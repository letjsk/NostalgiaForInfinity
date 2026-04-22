# NFI OKX 전환 가이드

바이낸스에서 운영 중인 NFI 봇을 OKX로 전환하는 절차입니다. API rate limit 밴 회피, 거래소 지갑 완전 분리를 목적으로 합니다.

## OKX 특징 요약

| 항목 | 값 |
|------|-----|
| 선물 유동성 | 3위권 |
| API Rate Limit | Private 60/2초 (관대함) |
| Taker 수수료 | 0.05% (기본) / VIP 할인 큼 |
| 한국 접근 | 부분 제한 (KYC 강화 추세) |
| NFI 지원 | 공식 (`pairlist-volume-okx-usdt.json` 포함) |
| Passphrase | **필수** (Binance/Bybit과 차이점) |

## 사전 준비

- OKX 계정
- KYC 인증 완료
- 현재 PC/VM에서 NFI가 Binance로 동작 중

---

## 1단계: OKX 계정 + KYC

### 1.1 가입
1. https://www.okx.com 접속
2. 이메일/비번으로 가입
3. 구글 OTP 2FA 활성화 (필수)

### 1.2 KYC 인증
- Identity Verification → **Level 2 이상** 진행 권장
- 여권 또는 신분증 + 셀피 + 거주지 증명 (Level 2)
- Level 1은 파생상품 제한적 → Level 2 권장

### 1.3 한국 거주자 주의

OKX는 한국 유저에 대한 제한이 점진적으로 강화되는 추세입니다:
- 거주지 증명 요구
- 일부 기간 신규 가입 제한 경험 있음
- 가입 전 현재 상태 확인 필요

---

## 2단계: Account Mode 설정

OKX는 4가지 계정 모드가 있습니다:

| 모드 | 특징 | NFI 선물 호환 |
|------|------|---------------|
| Spot Mode | 현물만 | ❌ |
| Spot and Futures Mode | 지갑 분리 | ✅ |
| Single-currency Margin | USDT 기반 마진 | ✅ (권장) |
| Multi-currency Margin | 다중 자산 담보 | ⚠️ (복잡) |
| Portfolio Margin | 고급 통합 마진 | ⚠️ (VIP) |

**권장**: **Single-currency Margin Mode** (선물 USDT 기준)

설정: Account → Account Settings → Account Mode

---

## 3단계: API 키 발급

### 3.1 API 관리 페이지

1. 우상단 프로필 → **API**
2. **Create V5 API Key** 클릭

### 3.2 권한 설정

| 항목 | 값 |
|------|-----|
| API Name | `NFI_DryRun_OKX` |
| **Passphrase** | 본인이 정하는 비밀 문구 (기억 필수!) |
| **Permissions** | `Read` + `Trade` |
| **Withdraw** | ❌ **절대 금지** |
| **IP 제한** | VM 공인 IP 또는 Tailscale IP 등록 (권장) |

### 3.3 키 저장

생성 직후 3가지 값이 한 번만 표시됨:
- **API Key**
- **Secret Key**
- **Passphrase** (본인이 설정한 값)

→ 안전한 곳에 모두 복사.

> Passphrase 분실 시 **API 키 재발급 필요** (복구 불가). Binance/Bybit과 가장 큰 차이.

---

## 4단계: .env 수정

```env
# 봇 이름 변경 (기존 sqlite와 구분)
FREQTRADE__BOT_NAME=NFI_DryRun_OKX

# 거래소 설정 (Passphrase 추가!)
FREQTRADE__EXCHANGE__NAME=okx
FREQTRADE__EXCHANGE__KEY=<OKX_API_KEY>
FREQTRADE__EXCHANGE__SECRET=<OKX_SECRET>
FREQTRADE__EXCHANGE__PASSWORD=<OKX_PASSPHRASE>

# 선물 모드
FREQTRADE__TRADING_MODE=futures
FREQTRADE__MARGIN_MODE=isolated

# 기타 API 서버 설정은 그대로
FREQTRADE__API_SERVER__ENABLED=true
FREQTRADE__API_SERVER__LISTEN_PORT=9044
# ...
```

> `FREQTRADE__EXCHANGE__PASSWORD` 설정 빠지면 인증 실패합니다.

---

## 5단계: 페어리스트/블랙리스트 변경

### 5.1 `user_data/config.json` 편집

기존 Binance 참조를 OKX로:

```json
{
  "add_config_files": [
    "../configs/trading_mode-futures.json",
    "../configs/pairlist-volume-okx-usdt.json",
    "../configs/blacklist-okx.json",
    "../configs/exampleconfig.json"
  ]
}
```

> 프로젝트에 이미 `pairlist-volume-okx-usdt.json`, `blacklist-okx.json` 파일이 존재합니다.

### 5.2 페어 수 조정 (선택)

`configs/pairlist-volume-okx-usdt.json` 편집 → `number_assets: 60` (권장).

---

## 6단계: 기존 sqlite 분리

거래소가 바뀌면 드라이런 히스토리는 의미 없음.

```bash
cd ~/projects/NostalgiaForInfinity/user_data

# 기존 Binance DB 백업 보관
mv NFI_DryRun_binance_futures-tradesv3.sqlite backup-binance-$(date +%Y%m%d).sqlite
```

`BOT_NAME` 바꿨으니 새 sqlite(`NFI_DryRun_OKX_okx_futures-tradesv3.sqlite`)가 자동 생성됩니다.

---

## 7단계: OKX 선물 초기 설정

### 7.1 포지션 모드 확인

OKX → Trade → USDT-M Perpetual → Settings:
- **Position Mode**: `One-way Mode` (NFI 기본값)
- **Margin Mode**: `Isolated` (NFI 기본값)

### 7.2 레버리지 기본값

- 각 페어마다 기본 레버리지 설정 가능
- NFI가 API로 자동 조정하므로 보통 건드릴 필요 없음
- 걱정되면 모든 페어 레버리지 `1x`로 초기화

---

## 8단계: 봇 재시작

```bash
cd ~/projects/NostalgiaForInfinity

# 컨테이너 정지
docker compose down

# 새 설정으로 재시작
docker compose up -d

# 로그 확인
docker compose logs -f
```

### 정상 신호

```
freqtrade.exchange.exchange - INFO - Using Exchange "Okx"
freqtrade.configuration.configuration - INFO - Dry run is enabled
freqtrade.worker - INFO - Changing state to: RUNNING
```

### 웹 UI 접속

```
http://<VM_IP>:9044
```

---

## 9단계: 텔레그램 알림 재활성화

`.env`의 텔레그램 설정 유지:
```env
FREQTRADE__TELEGRAM__ENABLED=true
FREQTRADE__TELEGRAM__TOKEN=<기존_토큰>
FREQTRADE__TELEGRAM__CHAT_ID=<기존_ID>
```

재시작 후 `/status`로 연결 확인.

---

## 트러블슈팅

### "Invalid Sign" 또는 "Signature mismatch"

- Secret 키 오타
- **Passphrase 누락/오타** (OKX에서 가장 흔함)
- 시스템 시간 불일치: `sudo timedatectl` 확인

### "APIKey does not exist"

- API 키 활성화까지 최대 5분 소요
- IP 제한에 VM IP 누락

### "Account mode not supported"

- Account Mode가 Spot only
- Account Mode를 `Single-currency Margin` 또는 `Spot and Futures`로 변경

### "Insufficient permissions"

- API 키에 `Trade` 권한 누락
- 재발급 필요

### Pair not found / Symbol not supported

- OKX 선물 심볼은 `BTC-USDT-SWAP` 형식 (SWAP = 영구선물)
- NFI의 `pairlist-volume-okx-usdt.json`이 맞는 형식 사용 중인지 확인

### Passphrase 분실

- 복구 불가 → API 키 삭제 후 재발급
- 새 키로 .env 갱신 → 재시작

---

## 운영 팁

### 수수료 최적화
- OKB 토큰 보유 시 수수료 할인
- VIP 레벨 상승 시 할인 큼 (Tier별 큰 차이)
- 거래량 많아지면 Maker 수수료 0%까지 가능

### Rate Limit 활용
- OKX는 Private endpoint 60/2초 (매우 관대)
- NFI가 60페어 5분 갱신도 여유롭게 커버

### 포지션 모드 주의
- **One-way Mode**: 같은 페어 롱/숏 중 하나만
- **Hedge Mode**: 같은 페어 롱/숏 동시 가능
- NFI 기본은 One-way, 변경 시 코드 수정 필요

### 자산 이동
- OKX는 Funding Account ↔ Trading Account 간 자금 이동 필수
- 입금 시 Funding → Trading으로 먼저 옮겨야 거래 가능

---

## 전환 체크리스트

- [ ] OKX 가입 + KYC Level 2
- [ ] Account Mode: Single-currency Margin 설정
- [ ] API 키 발급 (Read-Write, Withdraw 제외)
- [ ] **Passphrase 별도 저장**
- [ ] IP 화이트리스트 등록
- [ ] `.env` 수정 (EXCHANGE__NAME, KEY, SECRET, **PASSWORD**, BOT_NAME)
- [ ] `user_data/config.json` 페어리스트 경로 변경
- [ ] 기존 Binance sqlite 백업 이동
- [ ] `docker compose up -d` 정상 시작
- [ ] 로그에 "Using Exchange Okx" 확인
- [ ] 웹 UI 접속
- [ ] 텔레그램 알림 수신 확인
- [ ] 24시간 후 페어리스트/거래 로그 확인

---

## Binance vs OKX 요약

| 항목 | Binance (현재) | OKX (전환 후) |
|------|---------------|-------------|
| Passphrase | 없음 | **필수** |
| Account Mode | 단일 | 4가지 (설정 필요) |
| Rate Limit | 1200 weight/분 | 60/2초 Private |
| 수수료 | 0.04% | 0.05% |
| 페어 수 | 300+ | 200+ |
| 한국 접근 | 제한 | 부분 제한 |

---

## 참고

- OKX API V5 문서: https://www.okx.com/docs-v5/
- CCXT OKX 예시: https://github.com/ccxt/ccxt/wiki/Manual#okx
- NFI OKX 커뮤니티: Discord #okx 채널
