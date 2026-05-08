# NFI 업데이트 스크립트 (PC/Windows PowerShell)
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

$ErrorActionPreference = "Stop"
$ROOT = $PSScriptRoot
$UPSTREAM_URL = "https://github.com/iterativv/NostalgiaForInfinity"

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

function Detect-Branch {
    param([string]$Folder)
    switch -Wildcard ($Folder) {
        "*binance*" { return "my-setup-binance" }
        "*okx*"     { return "my-setup-okx" }
        "*bybit*"   { return "my-setup-bybit" }
        default     { return $null }
    }
}

try {
    # nfi-* 폴더 자동 감지
    $folders = Get-ChildItem -Path $ROOT -Directory -Filter "nfi-*" |
        Where-Object { Test-Path "$($_.FullName)\.git" } |
        Select-Object -ExpandProperty Name

    if ($folders.Count -eq 0) {
        Write-Host "nfi-* 폴더 없음. 종료." -ForegroundColor Red
        exit 1
    }

    Write-Host "감지된 폴더 ($($folders.Count)개): $($folders -join ', ')" -ForegroundColor Gray

    # 첫 폴더를 main/my-setup 작업의 중앙 저장소로 사용
    $central = $folders[0]
    Set-Location "$ROOT\$central"

    # 0. 셋업
    Write-Host "`n=== 셋업 확인 (in $central) ===" -ForegroundColor Cyan
    Ensure-Upstream
    & git fetch origin 2>&1 | Out-Null
    Ensure-Branch -Branch "main"
    Ensure-Branch -Branch "my-setup"

    # 1. upstream 변경 확인
    Write-Host "`n=== 공식 저장소 확인 ===" -ForegroundColor Cyan
    Run-Git fetch upstream

    $upstreamNew = & git rev-list --count origin/main..upstream/main
    if ($LASTEXITCODE -ne 0) { throw "rev-list 실패" }

    if ([int]$upstreamNew -gt 0) {
        Write-Host "공식 저장소 새 커밋 $upstreamNew 개" -ForegroundColor Yellow

        Write-Host "`n=== main 동기화 ===" -ForegroundColor Cyan
        Run-Git checkout main
        Run-Git merge --ff-only origin/main
        Run-Git merge upstream/main --no-edit
        Run-Git push origin main

        Write-Host "`n=== my-setup 업데이트 ===" -ForegroundColor Cyan
        Run-Git checkout my-setup
        Run-Git merge --ff-only origin/my-setup
        Run-Git merge main --no-edit
        Run-Git push origin my-setup
    }
    else {
        Write-Host "공식 저장소 변경 없음"
    }

    # 2. 각 폴더 처리
    $restarted = @()
    $skipped = @()
    $updated = @()

    foreach ($folder in $folders) {
        $branch = Detect-Branch -Folder $folder
        if (-not $branch) {
            Write-Host "`n=== [$folder] (브랜치 매칭 실패, 건너뜀) ===" -ForegroundColor Gray
            continue
        }

        Write-Host "`n=== [$folder] ($branch) ===" -ForegroundColor Cyan
        Set-Location "$ROOT\$folder"

        Run-Git checkout $branch
        & git fetch origin 2>&1 | Out-Null

        $before = & git rev-parse HEAD
        & git merge --ff-only "origin/$branch" 2>&1 | Out-Null

        $behind = & git rev-list --count "HEAD..origin/my-setup"
        if ($LASTEXITCODE -ne 0) { throw "rev-list 실패" }
        $afterSync = & git rev-parse HEAD

        if ($before -eq $afterSync -and [int]$behind -eq 0) {
            Write-Host "  변경 없음"
            continue
        }

        if ([int]$behind -gt 0) {
            Write-Host "  my-setup에 $behind 커밋 앞서있음" -ForegroundColor Yellow
            Run-Git merge origin/my-setup --no-edit
            Run-Git push origin $branch
        }
        else {
            Write-Host "  원격 $branch 변경사항 반영됨" -ForegroundColor Yellow
        }

        $after = & git rev-parse HEAD

        # 전략(.py) 또는 설정(configs/*.json) 변경 확인
        $changed = & git diff --name-only $before $after
        $restartWorthy = $changed | Where-Object { $_ -match "^(NostalgiaForInfinity.*\.py|configs/.*\.json)$" }

        if (-not $restartWorthy) {
            Write-Host "  문서만 변경 → 재시작 불필요"
            $updated += $folder
            continue
        }

        Write-Host "  재시작 필요한 변경:" -ForegroundColor Yellow
        $restartWorthy | ForEach-Object { Write-Host "    - $_" }

        $running = & docker compose ps --status running -q 2>$null

        if ($running) {
            Write-Host "  컨테이너 실행 중 → 재시작" -ForegroundColor Yellow
            & docker compose restart
            if ($LASTEXITCODE -eq 0) {
                $restarted += $folder
            }
            else {
                Write-Host "  재시작 실패 (exit $LASTEXITCODE)" -ForegroundColor Red
            }
        }
        else {
            Write-Host "  컨테이너 정지 상태 → 재시작 건너뜀"
            $skipped += $folder
        }
    }

    # 3. 요약
    Write-Host "`n=== 완료 ===" -ForegroundColor Green

    if ($restarted.Count -gt 0) {
        Write-Host "재시작됨:" -ForegroundColor Yellow
        $restarted | ForEach-Object { Write-Host "  - $_" }
    }

    if ($skipped.Count -gt 0) {
        Write-Host "`n변경 있지만 정지 상태 (수동 시작 필요):" -ForegroundColor Gray
        foreach ($f in $skipped) {
            Write-Host "  cd `"$ROOT\$f`"; docker compose up -d"
        }
    }

    if ($updated.Count -gt 0) {
        Write-Host "`n업데이트됨 (재시작 불필요):" -ForegroundColor Gray
        $updated | ForEach-Object { Write-Host "  - $_" }
    }

    if ($restarted.Count -eq 0 -and $skipped.Count -eq 0 -and $updated.Count -eq 0) {
        Write-Host "모든 폴더 최신 상태"
    }
}
finally {
    Set-Location $ORIG_LOCATION
}
