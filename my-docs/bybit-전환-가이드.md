# NFI Bybit 전환 가이드

바이낸스에서 운영 중인 NFI 봇을 Bybit으로 전환하는 절차입니다. API rate limit 밴 회피, 거래소 지갑 완전 분리를 목적으로 합니다.

## Bybit 특징 요약

| 항목 | 값 |
|------|-----|
| 선물 유동성 | 2위 (Binance 다음) |
| API Rate Limit | 120/5초 (관대함) |
| Taker 수수료 | 0.055% (기본) / 할인 가능 |
| 한국 접근 | 양호 |
| NFI 지원 | 공식 (`pairlist-volume-bybit-usdt.json` 포함) |
| Passphrase | 불필요 |

## 사전 준비

- Bybit 계정
- KYC Level 1 완료 (파생상품 거래 필수)
- 현재 PC/VM에서 NFI가 Binance로 동작 중

---

## 1단계: Bybit 계정 + KYC

### 1.1 가입
1. https://www.bybit.com 접속
2. 이메일/비번으로 가입
3. 구글 OTP 2FA 활성화 (필수)

### 1.2 KYC 인증
- Identity Verification → **Standard** (Level 1) 진행
- 여권 또는 신분증 + 셀피
- 보통 10~30분 내 승인

> KYC 미완료 시 파생상품 거래 자체가 불가능합니다.

---

## 2단계: 계정 타입 확인

Bybit은 두 가지 계정 모드가 있습니다:

| 모드 | 특징 | NFI 호환 |
|------|------|---------|
| **Unified Trading Account (UTA)** | 최신, 통합 지갑 | ✅ (최근 지원됨) |
| **Classic Account** | 레거시, 지갑 분리 | ✅ (안정적) |

**권장**: UTA (신규 계정 기본값)

Account → Account Mode에서 확인.

---

## 3단계: API 키 발급

### 3.1 API 관리 페이지

1. 우상단 프로필 → **API**
2. **Create New Key** 클릭
3. **System-generated API Keys** 선택

### 3.2 권한 설정

| 항목 | 값 |
|------|-----|
| Name | `NFI_DryRun_Bybit` |
| **Read-Write** | ✅ |
| **Unified Trading** → Orders & Positions | ✅ |
| **Contract** → Orders & Positions | ✅ (Classic 계정) |
| **Spot** → Trade | ✅ (필요 시) |
| **Withdraw** | ❌ **절대 금지** |
| **IP 제한** | VM 공인 IP 또는 Tailscale IP 등록 |

### 3.3 키 저장

생성 직후 **API Key**와 **Secret**이 한 번만 표시됨 → 안전한 곳에 복사.

> Passphrase는 없습니다 (Binance와 동일 구조).

---

## 4단계: .env 수정

```env
# 봇 이름 변경 (기존 sqlite와 구분)
FREQTRADE__BOT_NAME=NFI_DryRun_Bybit

# 거래소 설정
FREQTRADE__EXCHANGE__NAME=bybit
FREQTRADE__EXCHANGE__KEY=<BYBIT_API_KEY>
FREQTRADE__EXCHANGE__SECRET=<BYBIT_SECRET>

# 선물 모드 (필요 시)
FREQTRADE__TRADING_MODE=futures
FREQTRADE__MARGIN_MODE=isolated

# 기타 API 서버 설정은 그대로
FREQTRADE__API_SERVER__ENABLED=true
FREQTRADE__API_SERVER__LISTEN_PORT=9044
# ...
```

---

## 5단계: 페어리스트/블랙리스트 변경

### 5.1 `user_data/config.json` 편집

기존 Binance 참조를 Bybit으로:

```json
{
  "add_config_files": [
    "../configs/trading_mode-futures.json",
    "../configs/pairlist-volume-bybit-usdt.json",
    "../configs/blacklist-bybit.json",
    "../configs/exampleconfig.json"
  ]
}
```

> 프로젝트에 이미 `pairlist-volume-bybit-usdt.json`, `blacklist-bybit.json` 파일이 존재합니다.

### 5.2 페어 수 조정 (선택)

`configs/pairlist-volume-bybit-usdt.json` 편집 → `number_assets: 60` (권장).

---

## 6단계: 기존 sqlite 분리

거래소가 바뀌면 드라이런 히스토리는 의미 없음 (페어 구성, 가격 기준 등 다름).

```bash
cd ~/projects/nostalgia-for-infinity/user_data

# 기존 Binance DB 백업 보관 (혹시 나중에 복원용)
mv NFI_DryRun_binance_futures-tradesv3.sqlite backup-binance-$(date +%Y%m%d).sqlite
```

`BOT_NAME` 바꿨으니 새 sqlite(`NFI_DryRun_Bybit_bybit_futures-tradesv3.sqlite`)가 자동 생성됩니다.

---

## 7단계: 레버리지 설정 확인

`configs/trading_mode-futures.json`에서 기본 레버리지 설정:

```json
{
  "trading_mode": "futures",
  "margin_mode": "isolated",
  "exchange": {
    "name": "bybit"
  }
}
```

Bybit UI에서 초기 레버리지 설정:
- Derivatives → USDT Perpetual → 각 페어마다 수동 설정 필요
- NFI가 API로 자동 조정하므로 보통 건드릴 필요 없음

---

## 8단계: 봇 재시작

```bash
cd ~/projects/nostalgia-for-infinity

# 컨테이너 정지
docker compose down

# 새 설정으로 재시작
docker compose up -d

# 로그 확인
docker compose logs -f
```

### 정상 신호

```
freqtrade.exchange.exchange - INFO - Using Exchange "Bybit"
freqtrade.configuration.configuration - INFO - Dry run is enabled
freqtrade.worker - INFO - Changing state to: RUNNING
```

### 웹 UI 접속

```
http://<VM_IP>:9044
```

---

## 9단계: 텔레그램 알림 재활성화

`.env`에서:
```env
FREQTRADE__TELEGRAM__ENABLED=true
FREQTRADE__TELEGRAM__TOKEN=<기존_토큰>
FREQTRADE__TELEGRAM__CHAT_ID=<기존_ID>
```

기존 텔레그램 봇 그대로 재사용 가능. 재시작 후 `/status` 명령으로 연결 확인.

---

## 트러블슈팅

### "Invalid API Key"

- API 키 복사 시 공백 포함되지 않았는지 확인
- IP 제한 설정 시 현재 VM IP가 맞는지 확인
- API 키 활성화까지 몇 분 걸릴 수 있음

### "Signature verification failed"

- Secret 키 오타
- 시스템 시간 불일치 (VM: `sudo timedatectl` 확인)

### "Account mode mismatch"

- UTA와 Classic 간 혼동
- Bybit 웹 → Account → Account Mode에서 현재 모드 확인
- NFI는 두 모드 다 지원하지만, 페어 설정이 달라질 수 있음

### Pair not found

- Bybit USDT Perpetual은 `BTC/USDT:USDT` 형식
- NFI의 `pairlist-volume-bybit-usdt.json`이 맞는 형식 사용 중인지 확인

---

## 운영 팁

### 수수료 최적화
- BYB 토큰 보유 시 수수료 할인
- VIP 레벨 상승으로 0.045% → 0.040% 수준까지 인하 가능

### 펀딩비 모니터링
- Bybit 펀딩비 보통 8시간 간격
- 극단적 펀딩비 시기는 NFI 자체 필터링 있음

### 레버리지 조절
- 드라이런은 leverage 영향 없음
- 라이브 전환 시 `configs/trading_mode-futures.json`에 leverage 명시 권장

---

## 전환 체크리스트

- [ ] Bybit 가입 + KYC Level 1
- [ ] API 키 발급 (Read-Write, Withdraw 제외)
- [ ] IP 화이트리스트 등록
- [ ] `.env` 수정 (EXCHANGE__NAME, KEY, SECRET, BOT_NAME)
- [ ] `user_data/config.json` 페어리스트 경로 변경
- [ ] 기존 Binance sqlite 백업 이동
- [ ] `docker compose up -d` 정상 시작
- [ ] 로그에 "Using Exchange Bybit" 확인
- [ ] 웹 UI 접속
- [ ] 텔레그램 알림 수신 확인
- [ ] 24시간 후 페어리스트/거래 로그 확인

---

## 참고

- Bybit API 문서: https://bybit-exchange.github.io/docs/v5/intro
- NFI Bybit 커뮤니티: Discord #bybit 채널
