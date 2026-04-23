# NFI 업데이트 스크립트 (PC/Windows PowerShell)
# 공식 저장소 변경사항 확인 -> main/my-setup 동기화 -> 3개 거래소 브랜치 merge
# 전략 파일(.py) 변경 시:
#   - 컨테이너 실행 중 → 자동 재시작
#   - 컨테이너 정지 상태 → 건드리지 않음

$ErrorActionPreference = "Stop"
$ROOT = $PSScriptRoot

$EXCHANGES = @(
    @{Folder = "NFI-Binance"; Branch = "my-setup-binance"},
    @{Folder = "NFI-OKX";     Branch = "my-setup-okx"},
    @{Folder = "NFI-Bybit";   Branch = "my-setup-bybit"}
)

Set-Location "$ROOT\NFI-OKX"

# 1. upstream 업데이트 확인
Write-Host "`n=== 공식 저장소 업데이트 확인 ===" -ForegroundColor Cyan
git fetch upstream 2>&1 | Out-Null

$newCommits = (git rev-list --count origin/main..upstream/main).Trim()
if ([int]$newCommits -eq 0) {
    Write-Host "업데이트 없음. 종료." -ForegroundColor Green
    exit 0
}
Write-Host "새 커밋 $newCommits 개 발견" -ForegroundColor Yellow

# 2. main 동기화
Write-Host "`n=== main 동기화 ===" -ForegroundColor Cyan
git checkout main 2>&1 | Out-Null
git merge upstream/main --no-edit
git push origin main

# 3. my-setup 업데이트
Write-Host "`n=== my-setup 업데이트 ===" -ForegroundColor Cyan
git checkout my-setup 2>&1 | Out-Null
git merge main --no-edit
git push origin my-setup

# 4. 각 거래소 브랜치 업데이트 + 재시작 판단
$restarted = @()
$skipped = @()

foreach ($ex in $EXCHANGES) {
    Write-Host "`n=== [$($ex.Folder)] ===" -ForegroundColor Cyan
    Set-Location "$ROOT\$($ex.Folder)"

    git checkout $ex.Branch 2>&1 | Out-Null

    $before = (git rev-parse HEAD).Trim()

    git fetch origin my-setup 2>&1 | Out-Null
    git merge origin/my-setup --no-edit

    $after = (git rev-parse HEAD).Trim()

    if ($before -eq $after) {
        Write-Host "  변경 없음"
        continue
    }

    git push origin $ex.Branch

    # 전략 파일(.py) 변경 확인
    $changed = git diff --name-only $before $after
    $pyChanged = $changed | Where-Object { $_ -match "^NostalgiaForInfinity.*\.py$" }

    if (-not $pyChanged) {
        Write-Host "  설정/문서만 변경 → 재시작 불필요"
        continue
    }

    Write-Host "  전략 파일 변경됨:" -ForegroundColor Yellow
    $pyChanged | ForEach-Object { Write-Host "    - $_" }

    # 컨테이너 실행 여부 확인
    $running = docker compose ps --status running -q 2>$null

    if ($running) {
        Write-Host "  컨테이너 실행 중 → 재시작" -ForegroundColor Yellow
        docker compose restart
        $restarted += $ex.Folder
    }
    else {
        Write-Host "  컨테이너 정지 상태 → 재시작 건너뜀"
        $skipped += $ex.Folder
    }
}

# 5. 요약
Write-Host "`n=== 완료 ===" -ForegroundColor Green

if ($restarted.Count -gt 0) {
    Write-Host "재시작됨:" -ForegroundColor Yellow
    $restarted | ForEach-Object { Write-Host "  - $_" }
}

if ($skipped.Count -gt 0) {
    Write-Host "`n전략 변경됐지만 정지 상태 (수동 시작 필요):" -ForegroundColor Gray
    foreach ($f in $skipped) {
        Write-Host "  cd `"$ROOT\$f`"; docker compose up -d"
    }
}

if ($restarted.Count -eq 0 -and $skipped.Count -eq 0) {
    Write-Host "재시작 불필요"
}
