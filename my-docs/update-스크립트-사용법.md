# NFI 업데이트 스크립트 사용법

공식 NostalgiaForInfinity 저장소 및 내 fork의 `my-setup` 브랜치 변경사항을 3개 거래소 브랜치(Binance/OKX/Bybit)에 자동 전파하는 스크립트입니다.

## 스크립트 위치

| 환경 | 파일 | 실행 방법 |
|------|------|----------|
| PC (Windows) | `update-nfi.ps1` | PowerShell에서 실행 |
| VM (Linux) | `update-nfi.sh` | bash에서 실행 |

두 위치에 동일한 파일이 있습니다:

- **부모 폴더 (git 외부)**: `nostalgia-for-infinity/update-nfi.ps1` / `.sh` → 바로 실행용
- **git 관리**: 각 클론의 `my-docs/scripts/update-nfi.ps1` / `.sh` → 버전 관리 및 배포용

## 무엇을 하나

```
1. upstream/main (공식 NFI) → 새 커밋 있는지 확인
     있으면: origin/main 동기화 → origin/my-setup 업데이트

2. 각 거래소 브랜치마다:
     origin/my-setup에 새 커밋 있으면 merge + push
       + 전략 파일(NostalgiaForInfinityX*.py) 변경됐고 컨테이너 실행 중 → 자동 재시작
       + 전략 변경 없음 → 재시작 안 함
       + 전략 변경 + 컨테이너 정지 → 수동 시작 명령만 출력
```

## 실행 방법

### PC (PowerShell)

```powershell
D:\OneDrive\Project\nostalgia-for-infinity\update-nfi.ps1
```

처음 실행 시 PowerShell 실행 정책 제한 걸릴 수 있음:
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### VM (Linux)

```bash
bash ~/projects/nostalgia-for-infinity/update-nfi.sh
```

또는 실행 권한 주고 직접:
```bash
chmod +x ~/projects/nostalgia-for-infinity/update-nfi.sh
~/projects/nostalgia-for-infinity/update-nfi.sh
```

## 출력 해석

### 공식 저장소 업데이트 없음 + 내 변경 없음
```
=== 공식 저장소 확인 ===
공식 저장소 변경 없음

=== [nfi-binance] ===
  변경 없음
=== [nfi-okx] ===
  변경 없음
=== [nfi-bybit] ===
  변경 없음

=== 완료 ===
모든 거래소 브랜치 최신 상태
```
→ 아무것도 할 게 없음. 종료.

### 공식 업데이트 + 전략 변경 + 컨테이너 실행 중
```
공식 저장소 새 커밋 5 개

=== main 동기화 ===
=== my-setup 업데이트 ===

=== [nfi-binance] ===
  my-setup에 6 커밋 앞서있음
  전략 파일 변경됨:
    - NostalgiaForInfinityX7.py
  컨테이너 실행 중 → 재시작

=== 완료 ===
재시작됨:
  - nfi-binance
```
→ 자동 재시작 완료.

### 전략 변경됐지만 컨테이너 정지 상태
```
=== [nfi-okx] ===
  my-setup에 3 커밋 앞서있음
  전략 파일 변경됨:
    - NostalgiaForInfinityX7.py
  컨테이너 정지 상태 → 재시작 건너뜀

=== 완료 ===
전략 변경됐지만 정지 상태 (수동 시작 필요):
  cd D:\OneDrive\Project\nostalgia-for-infinity\nfi-okx; docker compose up -d
```
→ 의도적으로 정지시켰을 수 있으므로 스크립트가 건드리지 않음. 직접 시작.

### 설정/문서만 변경
```
=== [nfi-bybit] ===
  my-setup에 2 커밋 앞서있음
  설정/문서만 변경 → 재시작 불필요

업데이트됨 (재시작 불필요):
  - nfi-bybit
```
→ 전략 .py 변경 없으면 재시작 안 함.

## 내가 my-setup에 수동 변경했을 때

예: pairlist 페어 수를 60 → 40으로 바꾸고 싶을 때.

```powershell
# nfi-okx (또는 아무 폴더)에서
cd D:\OneDrive\Project\nostalgia-for-infinity\nfi-okx
git checkout my-setup
# 파일 편집
git add configs/pairlist-volume-binance-usdt.json
git commit -m "config: pair count 60 -> 40"
git push origin my-setup

# 다시 원래 브랜치로 (nfi-okx는 my-setup-okx)
git checkout my-setup-okx
```

이후 아무 때나 스크립트 실행:
```powershell
D:\OneDrive\Project\nostalgia-for-infinity\update-nfi.ps1
```

스크립트가 3개 거래소 브랜치에 변경사항 자동 전파.

## 실행 전 확인사항

### 1. 미커밋 변경 없어야 함
```bash
cd nfi-okx && git status
cd ../nfi-binance && git status
cd ../nfi-bybit && git status
```
모두 `nothing to commit, working tree clean`이어야 함.

변경사항 있으면 먼저 커밋 or stash:
```bash
git stash   # 임시 보관
# 스크립트 실행
git stash pop   # 나중에 복원
```

### 2. Docker Desktop 실행 중 (PC)
Windows 트레이에 Docker Desktop 아이콘 녹색인지 확인.

### 3. SSH 키 로드됨 (깃 원격이 SSH인 경우)
```bash
ssh -T git@github.com
```
`Hi letjsk!` 나오면 OK.

## 트러블슈팅

### merge conflict 발생
```
CONFLICT (content): Merge conflict in ...
```
→ 스크립트 중단. 해당 폴더에서 수동 해결:
```bash
cd <충돌난 폴더>
# 파일 열어 <<<<< ===== >>>>> 표시 수정
git add <해결한 파일>
git commit
git push origin <브랜치명>
```
그 후 스크립트 재실행.

### `git fetch upstream` 실패
upstream이 설정 안 됨. 각 폴더에서 확인:
```bash
git remote -v
```
`upstream` 라인 없으면 추가:
```bash
git remote add upstream https://github.com/iterativv/NostalgiaForInfinity
```

### `docker compose restart` 실패
Docker 실행 여부 확인:
```bash
docker ps
```
Docker Desktop이 꺼져있거나 느리게 시작 중이면 잠깐 기다린 후 재시도.

### `permission denied (publickey)` 
SSH 에이전트에 키 등록 안 됨:
```powershell
# PC
Start-Service ssh-agent
ssh-add $env:USERPROFILE\.ssh\id_ed25519
```
```bash
# VM
eval $(ssh-agent)
ssh-add ~/.ssh/id_ed25519
```

## 예상 실행 시간

- upstream 업데이트 없음: **5~10초** (네트워크 fetch만)
- upstream 업데이트 있음 + 3개 폴더 업데이트: **30초~2분** (대용량 .py merge)
- 컨테이너 재시작 포함: **+1~3분** (freqtrade 재초기화)

## 자동 실행 (선택)

### VM: cron으로 주기적 실행

```bash
crontab -e
```
추가:
```
# 매일 오전 3시 NFI 업데이트 확인
0 3 * * * /bin/bash /home/ubuntu/projects/nostalgia-for-infinity/update-nfi.sh >> /var/log/nfi-update.log 2>&1
```

### PC: Windows Task Scheduler

- Task Scheduler → Create Task
- Trigger: Daily 3:00 AM
- Action: `powershell.exe -File D:\OneDrive\Project\nostalgia-for-infinity\update-nfi.ps1`

## 주의

- **force-push 안 함**: 로컬이 origin과 diverge했으면 수동 처리 필요
- **거래소 브랜치에 쌓인 로컬 커밋은 보존**: merge commit으로 처리됨
- **.env나 user_data는 건드리지 않음**: gitignore 대상이라 스크립트와 무관
