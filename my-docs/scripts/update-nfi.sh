#!/bin/bash
# NFI 업데이트 스크립트 (VM/Linux Bash)
# 공식 저장소 변경사항 확인 -> main/my-setup 동기화 -> 3개 거래소 브랜치 merge
# 전략 파일(.py) 변경 시 재시작 필요한 봇 목록만 출력 (자동 재시작 안 함)

set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EXCHANGES=(
    "NFI-Binance:my-setup-binance"
    "NFI-OKX:my-setup-okx"
    "NFI-Bybit:my-setup-bybit"
)

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

cd "$ROOT/NFI-OKX"

# 1. upstream 업데이트 확인
echo -e "\n${CYAN}=== 공식 저장소 업데이트 확인 ===${NC}"
git fetch upstream >/dev/null 2>&1

NEW_COMMITS=$(git rev-list --count origin/main..upstream/main)
if [ "$NEW_COMMITS" -eq 0 ]; then
    echo -e "${GREEN}업데이트 없음. 종료.${NC}"
    exit 0
fi
echo -e "${YELLOW}새 커밋 ${NEW_COMMITS} 개 발견${NC}"

# 2. main 동기화
echo -e "\n${CYAN}=== main 동기화 ===${NC}"
git checkout main >/dev/null 2>&1
git merge upstream/main --no-edit
git push origin main

# 3. my-setup 업데이트
echo -e "\n${CYAN}=== my-setup 업데이트 ===${NC}"
git checkout my-setup >/dev/null 2>&1
git merge main --no-edit
git push origin my-setup

# 4. 각 거래소 브랜치 업데이트
RESTART_NEEDED=()

for entry in "${EXCHANGES[@]}"; do
    FOLDER="${entry%%:*}"
    BRANCH="${entry##*:}"

    echo -e "\n${CYAN}=== [${FOLDER}] 업데이트 ===${NC}"
    cd "$ROOT/$FOLDER"

    git checkout "$BRANCH" >/dev/null 2>&1

    BEFORE=$(git rev-parse HEAD)

    git fetch origin my-setup >/dev/null 2>&1
    git merge origin/my-setup --no-edit

    AFTER=$(git rev-parse HEAD)

    if [ "$BEFORE" = "$AFTER" ]; then
        echo "  변경 없음"
        continue
    fi

    git push origin "$BRANCH"

    # 전략 파일(.py) 변경 여부 확인
    CHANGED=$(git diff --name-only "$BEFORE" "$AFTER")
    PY_CHANGED=$(echo "$CHANGED" | grep -E "^NostalgiaForInfinity.*\.py$" || true)

    if [ -n "$PY_CHANGED" ]; then
        echo -e "${YELLOW}  전략 파일 변경됨${NC}"
        echo "$PY_CHANGED" | sed 's/^/    - /'
        RESTART_NEEDED+=("$FOLDER")
    else
        echo "  설정/문서만 변경"
    fi
done

# 5. 요약
echo -e "\n${GREEN}=== 완료 ===${NC}"

if [ ${#RESTART_NEEDED[@]} -eq 0 ]; then
    echo "재시작 불필요"
else
    echo -e "\n${YELLOW}재시작 필요:${NC}"
    for f in "${RESTART_NEEDED[@]}"; do
        echo "  cd $ROOT/$f && docker compose restart"
    done
fi
