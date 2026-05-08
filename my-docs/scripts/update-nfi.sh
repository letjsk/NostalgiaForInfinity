#!/bin/bash
# NFI 업데이트 스크립트 (VM/Linux Bash)
# 업데이트 소스:
#   1. upstream/main (공식 저장소)  -> origin/main -> origin/my-setup
#   2. origin/my-setup (수동 커밋한 변경)  -> 각 거래소 브랜치
# 전략(.py) 또는 설정(configs/*.json) 변경 시:
#   - 컨테이너 실행 중 → 자동 재시작
#   - 컨테이너 정지 상태 → 건드리지 않음
# 셋업 자동화:
#   - upstream 리모트 없으면 추가
#   - 로컬 main / my-setup 브랜치 없으면 origin에서 생성
# 폴더 감지:
#   - nfi-* 패턴 폴더 자동 감지 (nfi-binance, nfi-binance-x6, nfi-binance-x7, ...)
#   - 폴더명에 binance/okx/bybit 포함되면 해당 거래소 브랜치 사용

set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_URL="https://github.com/iterativv/NostalgiaForInfinity"

# 원래 위치 저장 (스크립트 종료 시 복귀)
ORIG_PWD="$(pwd)"
trap 'cd "$ORIG_PWD"' EXIT

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
RED='\033[0;31m'
NC='\033[0m'

ensure_upstream() {
    if ! git remote | grep -q "^upstream$"; then
        echo -e "${GRAY}  upstream 리모트 추가${NC}"
        git remote add upstream "$UPSTREAM_URL"
    fi
}

ensure_branch() {
    local BRANCH="$1"
    if ! git rev-parse --verify --quiet "$BRANCH" >/dev/null 2>&1; then
        echo -e "${GRAY}  로컬 $BRANCH 브랜치 생성${NC}"
        git branch "$BRANCH" "origin/$BRANCH"
    fi
}

# 거래소 추출 (binance/okx/bybit)
detect_branch() {
    local FOLDER="$1"
    case "$FOLDER" in
        *binance*) echo "my-setup-binance" ;;
        *okx*)     echo "my-setup-okx" ;;
        *bybit*)   echo "my-setup-bybit" ;;
        *)         echo "" ;;
    esac
}

# nfi-* 폴더 자동 감지
NFI_FOLDERS=()
for f in "$ROOT"/nfi-*; do
    [ -d "$f/.git" ] && NFI_FOLDERS+=("$(basename "$f")")
done

if [ ${#NFI_FOLDERS[@]} -eq 0 ]; then
    echo -e "${RED}nfi-* 폴더 없음. 종료.${NC}"
    exit 1
fi

echo -e "${GRAY}감지된 폴더 (${#NFI_FOLDERS[@]}개): ${NFI_FOLDERS[*]}${NC}"

# 첫 폴더를 main/my-setup 작업의 중앙 저장소로 사용
CENTRAL="${NFI_FOLDERS[0]}"
cd "$ROOT/$CENTRAL"

# 0. 셋업 (upstream 리모트 + 로컬 main/my-setup 브랜치)
echo -e "\n${CYAN}=== 셋업 확인 (in $CENTRAL) ===${NC}"
ensure_upstream
git fetch origin >/dev/null 2>&1
ensure_branch "main"
ensure_branch "my-setup"

# 1. upstream 변경 확인 및 적용
echo -e "\n${CYAN}=== 공식 저장소 확인 ===${NC}"
git fetch upstream >/dev/null 2>&1

UPSTREAM_NEW=$(git rev-list --count origin/main..upstream/main)

if [ "$UPSTREAM_NEW" -gt 0 ]; then
    echo -e "${YELLOW}공식 저장소 새 커밋 ${UPSTREAM_NEW} 개${NC}"

    echo -e "\n${CYAN}=== main 동기화 ===${NC}"
    git checkout main
    git merge --ff-only origin/main
    git merge upstream/main --no-edit
    git push origin main

    echo -e "\n${CYAN}=== my-setup 업데이트 ===${NC}"
    git checkout my-setup
    git merge --ff-only origin/my-setup
    git merge main --no-edit
    git push origin my-setup
else
    echo "공식 저장소 변경 없음"
fi

# 2. 각 거래소 폴더 업데이트
RESTARTED=()
SKIPPED=()
UPDATED=()

for FOLDER in "${NFI_FOLDERS[@]}"; do
    BRANCH=$(detect_branch "$FOLDER")
    if [ -z "$BRANCH" ]; then
        echo -e "\n${GRAY}=== [${FOLDER}] (브랜치 매칭 실패, 건너뜀) ===${NC}"
        continue
    fi

    echo -e "\n${CYAN}=== [${FOLDER}] (${BRANCH}) ===${NC}"
    cd "$ROOT/$FOLDER"

    git checkout "$BRANCH"
    git fetch origin >/dev/null 2>&1

    BEFORE=$(git rev-parse HEAD)
    git merge --ff-only "origin/$BRANCH" 2>/dev/null || true

    BEHIND=$(git rev-list --count HEAD..origin/my-setup)
    AFTER_SYNC=$(git rev-parse HEAD)

    if [ "$BEFORE" = "$AFTER_SYNC" ] && [ "$BEHIND" -eq 0 ]; then
        echo "  변경 없음"
        continue
    fi

    if [ "$BEHIND" -gt 0 ]; then
        echo -e "${YELLOW}  my-setup에 ${BEHIND} 커밋 앞서있음${NC}"
        git merge origin/my-setup --no-edit
        git push origin "$BRANCH"
    else
        echo -e "${YELLOW}  원격 $BRANCH 변경사항 반영됨${NC}"
    fi

    AFTER=$(git rev-parse HEAD)

    # 전략(.py) 또는 설정(configs/*.json) 변경 확인
    CHANGED=$(git diff --name-only "$BEFORE" "$AFTER")
    RESTART_WORTHY=$(echo "$CHANGED" | grep -E "^(NostalgiaForInfinity.*\.py|configs/.*\.json)$" || true)

    if [ -z "$RESTART_WORTHY" ]; then
        echo "  문서만 변경 → 재시작 불필요"
        UPDATED+=("$FOLDER")
        continue
    fi

    echo -e "${YELLOW}  재시작 필요한 변경:${NC}"
    echo "$RESTART_WORTHY" | sed 's/^/    - /'

    RUNNING=$(docker compose ps --status running -q 2>/dev/null || true)

    if [ -n "$RUNNING" ]; then
        echo -e "${YELLOW}  컨테이너 실행 중 → 재시작${NC}"
        if docker compose restart; then
            RESTARTED+=("$FOLDER")
        else
            echo -e "${RED}  재시작 실패${NC}"
        fi
    else
        echo "  컨테이너 정지 상태 → 재시작 건너뜀"
        SKIPPED+=("$FOLDER")
    fi
done

# 3. 요약
echo -e "\n${GREEN}=== 완료 ===${NC}"

if [ ${#RESTARTED[@]} -gt 0 ]; then
    echo -e "${YELLOW}재시작됨:${NC}"
    for f in "${RESTARTED[@]}"; do
        echo "  - $f"
    done
fi

if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo -e "\n${GRAY}변경 있지만 정지 상태 (수동 시작 필요):${NC}"
    for f in "${SKIPPED[@]}"; do
        echo "  cd $ROOT/$f && docker compose up -d"
    done
fi

if [ ${#UPDATED[@]} -gt 0 ]; then
    echo -e "\n${GRAY}업데이트됨 (재시작 불필요):${NC}"
    for f in "${UPDATED[@]}"; do
        echo "  - $f"
    done
fi

if [ ${#RESTARTED[@]} -eq 0 ] && [ ${#SKIPPED[@]} -eq 0 ] && [ ${#UPDATED[@]} -eq 0 ]; then
    echo "모든 폴더 최신 상태"
fi
