# NFI 업데이트 스크립트 (PC/Windows PowerShell)
# 업데이트 소스:
#   1. upstream/main (공식 저장소)  -> origin/main -> origin/my-setup
#   2. origin/my-setup (수동 커밋한 변경)  -> 각 거래소 브랜치
# 전략 파일(.py) 변경 시:
#   - 컨테이너 실행 중 → 자동 재시작
#   - 컨테이너 정지 상태 → 건드리지 않음
# 셋업 자동화:
#   - upstream 리모트 없으면 추가
#   - 로컬 main / my-setup 브랜치 없으면 origin에서 생성

$ErrorActionPreference = "Stop"
$ROOT = $PSScriptRoot
$UPSTREAM_URL = "https://github.com/iterativv/NostalgiaForInfinity"

$EXCHANGES = @(
    @{Folder = "nfi-binance"; Branch = "my-setup-binance"},
    @{Folder = "nfi-okx";     Branch = "my-setup-okx"},
    @{Folder = "nfi-bybit";   Branch = "my-setup-bybit"}
)

# 원래 위치 저장 (스크립트 종료 시 복귀)
$ORIG_LOCATION = Get-Location

function Run-Git {
    & git @args
    if ($LASTEXITCODE -ne 0) {
        throw "git $($args -join ' ') 실패 (exit $LASTEXITCODE)"
    }
}

function Ensure-Upstream {
    $remotes = @(& git remote)
    if ($remotes -notcontains "upstream") {
        Write-Host "  upstream 리모트 추가" -ForegroundColor Gray
        Run-Git remote add upstream $UPSTREAM_URL
    }
}

function Ensure-Branch {
    param([string]$Branch)
    & git rev-parse --verify --quiet $Branch 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  로컬 $Branch 브랜치 생성" -ForegroundColor Gray
        Run-Git branch $Branch "origin/$Branch"
    }
}

try {
Set-Location "$ROOT\nfi-okx"

# 0. 셋업 (upstream 리모트 + 로컬 main/my-setup 브랜치)
Write-Host "=== 셋업 확인 ===" -ForegroundColor Cyan
Ensure-Upstream
& git fetch origin 2>&1 | Out-Null
Ensure-Branch -Branch "main"
Ensure-Branch -Branch "my-setup"

# 1. upstream 변경 확인 및 적용
Write-Host "`n=== 공식 저장소 확인 ===" -ForegroundColor Cyan
Run-Git fetch upstream

$upstreamNew = & git rev-list --count origin/main..upstream/main
if ($LASTEXITCODE -ne 0) { throw "rev-list 실패" }

if ([int]$upstreamNew -gt 0) {
    Write-Host "공식 저장소 새 커밋 $upstreamNew 개" -ForegroundColor Yellow

    Write-Host "`n=== main 동기화 ===" -ForegroundColor Cyan
    Run-Git checkout main
    Run-Git merge --ff-only origin/main   # 다른 기기에서 push한 origin 변경 반영
    Run-Git merge upstream/main --no-edit
    Run-Git push origin main

    Write-Host "`n=== my-setup 업데이트 ===" -ForegroundColor Cyan
    Run-Git checkout my-setup
    Run-Git merge --ff-only origin/my-setup   # 다른 기기 변경사항 반영
    Run-Git merge main --no-edit
    Run-Git push origin my-setup
}
else {
    Write-Host "공식 저장소 변경 없음"
}

# 2. 각 거래소 브랜치 업데이트
$restarted = @()
$skipped = @()
$updated = @()

foreach ($ex in $EXCHANGES) {
    Write-Host "`n=== [$($ex.Folder)] ===" -ForegroundColor Cyan
    Set-Location "$ROOT\$($ex.Folder)"

    Run-Git checkout $ex.Branch
    & git fetch origin 2>&1 | Out-Null

    $before = & git rev-parse HEAD   # 모든 merge 전 기준점
    & git merge --ff-only "origin/$($ex.Branch)" 2>&1 | Out-Null   # 다른 기기 변경 반영

    $behind = & git rev-list --count "HEAD..origin/my-setup"
    if ($LASTEXITCODE -ne 0) { throw "rev-list 실패" }
    $afterSync = & git rev-parse HEAD

    # ff-only merge도 없고 my-setup도 뒤쳐지지 않으면 완전 최신
    if ($before -eq $afterSync -and [int]$behind -eq 0) {
        Write-Host "  변경 없음"
        continue
    }

    if ([int]$behind -gt 0) {
        Write-Host "  my-setup에 $behind 커밋 앞서있음" -ForegroundColor Yellow
        Run-Git merge origin/my-setup --no-edit
        Run-Git push origin $ex.Branch
    }
    else {
        Write-Host "  원격 $($ex.Branch) 변경사항 반영됨" -ForegroundColor Yellow
    }

    $after = & git rev-parse HEAD

    # 전략(.py) 또는 설정(configs/*.json) 변경 확인
    $changed = & git diff --name-only $before $after
    $restartWorthy = $changed | Where-Object { $_ -match "^(NostalgiaForInfinity.*\.py|configs/.*\.json)$" }

    if (-not $restartWorthy) {
        Write-Host "  문서만 변경 → 재시작 불필요"
        $updated += $ex.Folder
        continue
    }

    Write-Host "  재시작 필요한 변경:" -ForegroundColor Yellow
    $restartWorthy | ForEach-Object { Write-Host "    - $_" }

    # 컨테이너 실행 여부 확인
    $running = & docker compose ps --status running -q 2>$null

    if ($running) {
        Write-Host "  컨테이너 실행 중 → 재시작" -ForegroundColor Yellow
        & docker compose restart
        if ($LASTEXITCODE -eq 0) {
            $restarted += $ex.Folder
        }
        else {
            Write-Host "  재시작 실패 (exit $LASTEXITCODE)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "  컨테이너 정지 상태 → 재시작 건너뜀"
        $skipped += $ex.Folder
    }
}

# 3. 요약
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

if ($updated.Count -gt 0) {
    Write-Host "`n업데이트됨 (재시작 불필요):" -ForegroundColor Gray
    $updated | ForEach-Object { Write-Host "  - $_" }
}

if ($restarted.Count -eq 0 -and $skipped.Count -eq 0 -and $updated.Count -eq 0) {
    Write-Host "모든 거래소 브랜치 최신 상태"
}
}
finally {
    Set-Location $ORIG_LOCATION
}
