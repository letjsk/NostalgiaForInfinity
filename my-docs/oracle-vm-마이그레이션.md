# PC → Oracle Cloud VM 마이그레이션 가이드

PC에서 드라이런 중인 NostalgiaForInfinity 봇을 Oracle Cloud Free Tier VM으로 이관하는 절차입니다.

## 사전 준비

- Oracle Cloud 계정 + Free Tier VM 생성 완료
- VM 사양 권장: **A1.Flex (ARM64), 2 OCPU / 8GB RAM** (드라이런/소규모 라이브에 충분)
- OS: Ubuntu 22.04 LTS 또는 Oracle Linux
- PC와 VM 모두 [Tailscale](https://tailscale.com/) 설치 권장 (VPN으로 안전 접근)
- PC에서 봇이 Docker Compose로 동작 중

---

## 1단계: VM 환경 준비

### 1.1 SSH 접속 후 시스템 업데이트

```bash
sudo apt update && sudo apt upgrade -y
```

### 1.2 Docker 설치

```bash
# 공식 설치 스크립트 (Compose v2 포함)
curl -fsSL https://get.docker.com | sh

# sudo 없이 docker 명령 실행
sudo usermod -aG docker $USER
newgrp docker

# 부팅 시 자동 시작
sudo systemctl enable docker
sudo systemctl start docker
```

### 1.3 설치 확인

```bash
docker --version
docker compose version
docker run --rm hello-world
```

`Hello from Docker!` 메시지 나오면 정상.

### 1.4 Tailscale 설치 및 연결 (선택, 강력 권장)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh
```

VM의 Tailscale IP 확인:

```bash
tailscale ip -4
# 예: 100.110.80.53
```

> Tailscale을 사용하면 VCN/NSG/iptables 설정 없이 안전하게 접근 가능. `--ssh` 옵션으로 SSH 키 관리도 불필요.

---

## 2단계: PC 드라이런 정지

마이그레이션 전 반드시 PC 봇을 중지해야 SQLite DB 손상을 방지할 수 있습니다.

PC에서:

```bash
cd <NFI_프로젝트_경로>
docker compose down
docker ps   # 봇 컨테이너 안 보여야 정상
```

---

## 3단계: VM에 프로젝트 클론

VM에서:

```bash
mkdir -p ~/projects && cd ~/projects
git clone https://github.com/iterativv/NostalgiaForInfinity
cd NostalgiaForInfinity
```

---

## 4단계: PC → VM 핵심 파일 전송

다음 파일들을 PC에서 VM으로 복사합니다:

| 파일 | 용도 | 필수 여부 |
|------|------|----------|
| `.env` | API 키, 봇 설정, 텔레그램 토큰 | ✅ 필수 |
| `user_data/config.json` | 거래 설정 | ✅ 필수 |
| `configs/pairlist-volume-binance-usdt.json` | 페어 수 등 커스텀 페어리스트 설정 | ⚠️ 기본값 수정 시 필수 |
| `user_data/*.sqlite` | 드라이런 거래 히스토리 | ⏸️ **이어서 진행 시에만** 필요 |

> **sqlite 파일은 기존 드라이런을 이어서 돌릴 때만 복사하세요.** 새로 시작하는 경우(새 전략 테스트, 깨끗한 상태에서 재시작 등)에는 복사하지 않아야 합니다. 복사하지 않으면 VM에서 새 DB가 자동 생성됩니다.

### PC에서 실행 (PowerShell 기준)

```powershell
cd <NFI_프로젝트_경로>

# .env 전송 (필수)
scp .env ubuntu@<VM_IP>:/home/ubuntu/projects/nostalgia-for-infinity/

# config.json 전송 (필수)
scp user_data/config.json ubuntu@<VM_IP>:/home/ubuntu/projects/nostalgia-for-infinity/user_data/

# 페어리스트 커스텀 설정 전송 (기본값에서 수정한 경우만)
scp configs/pairlist-volume-binance-usdt.json ubuntu@<VM_IP>:/home/ubuntu/projects/nostalgia-for-infinity/configs/

# sqlite DB 전송 (이어서 진행 시에만, 새로 시작하면 생략)
scp user_data/*.sqlite ubuntu@<VM_IP>:/home/ubuntu/projects/nostalgia-for-infinity/user_data/
```

> Oracle Linux VM이면 사용자명을 `opc`로 변경: `opc@<VM_IP>`
> Tailscale SSH 사용 시 키 옵션(`-i`) 불필요.

### VM에서 도착 확인

```bash
cd ~/projects/nostalgia-for-infinity
ls -la .env user_data/config.json configs/pairlist-volume-binance-usdt.json
ls -la user_data/*.sqlite  # 이어서 진행 시에만
```

파일 모두 보이면 OK.

---

## 5단계: 디렉토리 권한 설정 (필수)

freqtrade 컨테이너는 UID 1000(`ftuser`)으로 동작합니다. 호스트의 `user_data/` 소유권을 맞춰주지 않으면 로그 파일 생성 시 `Permission denied` 에러가 발생합니다.

```bash
sudo chown -R 1000:1000 user_data/
sudo chmod -R u+rwX,g+rX,o+rX user_data/
```

확인:

```bash
ls -la user_data/
# owner가 1000:1000 (또는 opc:opc로 표시되어도 무방)
```

---

## 6단계: 봇 실행

```bash
cd ~/projects/nostalgia-for-infinity

# 첫 실행 시 빌드 포함 (ARM64 빌드는 5~10분 소요)
docker compose up -d --build

# 실시간 로그 확인 (Ctrl+C로 빠져나와도 컨테이너 계속 동작)
docker compose logs -f
```

### 정상 동작 신호

로그에서 다음 메시지가 보이면 성공:

```
freqtrade.worker - INFO - Starting worker
freqtrade.configuration.configuration - INFO - Dry run is enabled
freqtrade.exchange.exchange - INFO - Using Exchange "Binance"
freqtrade.rpc.api_server.webserver - INFO - Uvicorn running on http://0.0.0.0:<PORT>
freqtrade.worker - INFO - Changing state to: RUNNING
```

---

## 7단계: 웹 UI 접속

PC 브라우저에서:

```
http://<VM_TAILSCALE_IP>:<API_SERVER_LISTEN_PORT>
```

예시: `http://100.110.80.53:9044`

`.env`에 설정한 username/password로 로그인.

> 포트는 `.env`의 `FREQTRADE__API_SERVER__LISTEN_PORT` 값 사용.

---

## 운영 명령어

```bash
# 로그
docker compose logs -f             # 실시간
docker compose logs --tail 100     # 최근 100줄

# 컨테이너 관리
docker compose ps                  # 상태 확인
docker compose restart             # 재시작
docker compose down                # 정지
docker compose up -d               # 백그라운드 실행

# 업데이트
git pull                           # 전략 업데이트
docker compose pull                # 이미지 업데이트
docker compose up -d --build       # 재시작 + 재빌드

# 모니터링
docker stats --no-stream           # 자원 사용량
df -h                              # 디스크
free -h                            # 메모리
```

---

## 트러블슈팅

### 웹 UI 접속 불가

```bash
# 1. 포트 매핑 확인
docker compose ps
# → "0.0.0.0:<PORT>->8080/tcp" 형태로 보여야 함

# 2. VM 내부 응답 확인
curl -v http://localhost:<PORT>

# 3. 리스닝 상태 확인
sudo ss -tlnp | grep <PORT>
# → "0.0.0.0:<PORT>" 또는 "*:<PORT>" 이어야 외부 접근 가능
```

`.env`에 다음 설정 누락되지 않았는지 확인:

```env
FREQTRADE__API_SERVER__ENABLED=true
FREQTRADE__API_SERVER__LISTEN_IP_ADDRESS=0.0.0.0
FREQTRADE__API_SERVER__LISTEN_PORT=9044
```

### `Permission denied: '/freqtrade/user_data/logs/...'`

5단계 권한 설정 누락. 다음 실행:

```bash
docker compose down
sudo chown -R 1000:1000 user_data/
docker compose up -d
```

### Tailscale 미사용 시 (공인 IP로 접근)

VCN Security List 또는 Network Security Group에 인그레스 규칙 추가:

- Source CIDR: `0.0.0.0/0` (또는 본인 IP/32)
- Protocol: TCP
- Destination Port: API 서버 포트

Oracle Ubuntu 이미지는 iptables 기본 차단이므로 VM 내부에서도 개방 필요:

```bash
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport <PORT> -j ACCEPT
sudo netfilter-persistent save
```

### 컨테이너가 자동 시작 안 됨

`docker-compose.yml`의 `restart: unless-stopped` 옵션 확인 (NFI 기본값에 포함되어 있음).

```bash
docker inspect $(docker compose ps -q) | grep -i restart
```

---

## 마이그레이션 체크리스트

- [ ] VM 생성 + SSH 접속 성공
- [ ] Docker 설치 + Hello World 확인
- [ ] Tailscale 연결 (선택)
- [ ] PC 드라이런 정지 (`docker compose down`)
- [ ] VM에 프로젝트 클론
- [ ] `.env`, `config.json` 전송 완료 (페어리스트 커스텀 시 `pairlist-*.json`도)
- [ ] `*.sqlite` 전송 (이어서 진행 시에만, 새로 시작하면 생략)
- [ ] `user_data/` 권한 1000:1000으로 변경
- [ ] `docker compose up -d` 정상 실행
- [ ] 웹 UI 접속 + 로그인 성공
- [ ] 텔레그램 알림 수신 확인 (활성화 시)
- [ ] 24시간 후 정상 거래 로그 확인

---

## 참고 사항

### Oracle Cloud Free Tier 한도

- A1.Flex (ARM): 총 4 OCPU / 24GB RAM 무료
- AMD E2.1.Micro: 1/8 OCPU / 1GB RAM × 2개 무료
- 2 OCPU / 8GB RAM 정도면 NFI 라이브 운영도 충분

### 리사이징

A1.Flex는 OCPU/RAM을 언제든 조절 가능 (재부팅 발생). 단, 늘릴 때는 해당 가용 도메인 자원 부족으로 실패할 수 있으므로 잡은 자원은 가능하면 유지 권장.

### 데이터 백업

```bash
# sqlite DB와 설정 백업
tar czf nfi-backup-$(date +%Y%m%d).tar.gz \
  ~/projects/nostalgia-for-infinity/.env \
  ~/projects/nostalgia-for-infinity/user_data/config.json \
  ~/projects/nostalgia-for-infinity/user_data/*.sqlite

# PC로 다운로드
# (PC에서) scp ubuntu@<VM_IP>:~/nfi-backup-*.tar.gz ./
```
