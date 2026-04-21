# Windows에서 WSL로 백테스트 환경 구성하기

이 문서는 Windows에서 WSL을 사용해 이 저장소의 `.sh` 백테스트 스크립트를 실행할 때, OneDrive 경로, CRLF 줄바꿈, Linux 권한 문제 때문에 꼬이지 않도록 설정하는 방법을 정리한 문서입니다.

## 이 문서가 필요한 경우

다음 조건에 해당하면 이 문서를 따라가면 됩니다.

- Windows 환경에서 작업 중인 경우
- 이 저장소의 `.sh` 스크립트를 직접 실행하고 싶은 경우
- PowerShell만으로는 작업이 불편한 경우
- 프로젝트가 `D:\...` 또는 OneDrive 아래에 있는 경우

이 문서는 저장소가 이미 클론되어 있다고 가정합니다.

## 왜 WSL을 쓰는가

이 저장소의 백테스트 스크립트는 Bash 스크립트이며 다음 같은 도구를 직접 호출합니다.

- `bash`
- `freqtrade`
- `git`
- `du`

이 조합은 PowerShell이나 혼합 Windows 셸보다 WSL에서 훨씬 안정적으로 동작합니다.

## Windows에서 자주 발생하는 문제

저장소가 `/mnt/d/...` 같은 Windows 마운트 경로나 OneDrive 아래에 있으면 다음 문제가 자주 발생합니다.

- `CRLF` 줄바꿈 때문에 `bash` 스크립트가 깨짐
- `git clone` 중 권한 또는 lock 파일 오류 발생
- `sed -i` 실행 시 `Operation not permitted` 발생
- `git`에서 `dubious ownership` 경고 발생
- `/mnt/d/...` 경로 안에서 Python 가상환경 생성 실패

이 문제들은 전략 문제라기보다 환경과 파일시스템 문제입니다.

## 권장 디렉터리 구성

다음처럼 분리하는 것이 가장 안정적입니다.

- 저장소 소스코드: 현재처럼 `/mnt/d/...` 경로에 둬도 됨
- Python 가상환경: WSL 홈 디렉터리 아래에 생성
- 다운로드한 시장 데이터: WSL 홈 디렉터리 아래에 저장하고, 저장소에서는 링크로 연결

이렇게 하면 Windows에서도 프로젝트를 볼 수 있고, Linux 민감 작업은 WSL 파일시스템에서 안정적으로 처리할 수 있습니다.

## 1단계: WSL과 Ubuntu 설치

Windows PowerShell을 관리자 권한으로 열고 실행합니다.

```powershell
wsl --install -d Ubuntu
```

설치 후 Ubuntu 터미널을 열면 Linux 사용자 이름과 비밀번호를 생성하게 됩니다.

## 2단계: Ubuntu 패키지 설치

Ubuntu 안에서 실행합니다.

```bash
sudo apt update
sudo apt install -y python3-pip python3-venv python3-dev git build-essential libffi-dev libssl-dev
```

## 3단계: WSL 홈 디렉터리에 가상환경 생성

가상환경은 `/mnt/d/...` 안에 만들지 말고 WSL 홈 디렉터리에 만듭니다.

```bash
cd ~
python3 -m venv testenv
source ~/testenv/bin/activate
```

정상적으로 활성화되면 프롬프트가 대략 이렇게 바뀝니다.

```bash
(testenv) user@host:~$
```

## 4단계: Freqtrade 설치

가상환경이 활성화된 상태에서 실행합니다.

```bash
pip install --upgrade pip setuptools wheel
pip install freqtrade
```

설치 확인:

```bash
freqtrade --version
```

## 5단계: 저장소 폴더로 이동

```bash
cd /mnt/d/OneDrive/Project/NostalgiaForInfinity
```

저장소 위치가 다르면 경로를 맞게 바꿔서 이동하면 됩니다.

## 6단계: Git safe.directory 설정

WSL에서 Windows 드라이브 아래 Git 저장소를 다룰 때 `detected dubious ownership` 경고가 나올 수 있습니다.

그 경우 아래 명령을 실행합니다.

```bash
git config --global --add safe.directory /mnt/d/OneDrive/Project/NostalgiaForInfinity
```

## 7단계: 시장 데이터는 WSL 파일시스템에 저장

이 저장소의 다운로드 스크립트는 `user_data/data` 에 데이터를 저장합니다.  
하지만 OneDrive나 `/mnt/d/...` 경로에서는 `git clone`, 권한 변경, lock 파일 작업이 실패할 수 있습니다.

따라서 실제 데이터는 WSL 홈 디렉터리에 두고, 저장소에서는 심볼릭 링크로 연결하는 것이 안전합니다.

```bash
rm -rf ~/nfi-data
mkdir -p ~/nfi-data
rm -rf user_data/data
ln -s ~/nfi-data user_data/data
```

링크 확인:

```bash
ls -l user_data
```

`data -> /home/.../nfi-data` 형태로 보이면 정상입니다.

## 8단계: Bash 스크립트를 Linux 줄바꿈으로 변환

Windows에서 수정된 파일은 `CRLF` 줄바꿈을 갖는 경우가 많고, 이 때문에 WSL의 `bash` 에서 스크립트가 깨질 수 있습니다.

`/mnt/d/...` 아래 원본 파일을 직접 수정하려 하지 말고, WSL 홈 디렉터리에 Linux용 복사본을 만들어 실행합니다.

```bash
mkdir -p ~/nfi-tmp
tr -d '\r' < tools/download-necessary-exchange-market-data-for-backtests.sh > ~/nfi-tmp/download-necessary-exchange-market-data-for-backtests.sh
chmod +x ~/nfi-tmp/download-necessary-exchange-market-data-for-backtests.sh
```

다른 스크립트도 같은 방식으로 처리할 수 있습니다.

```bash
tr -d '\r' < tests/backtests/backtesting-all-years-all-pairs.sh > ~/nfi-tmp/backtesting-all-years-all-pairs.sh
chmod +x ~/nfi-tmp/backtesting-all-years-all-pairs.sh
```

## 9단계: 다운로드 스크립트를 대상 시장에 맞게 조정

기본 다운로드 스크립트는 여러 거래소와 여러 거래 모드를 대상으로 되어 있을 수 있습니다.  
예를 들어 Binance futures만 받으려면 Linux용 복사본을 만들 때 값을 바꿔서 실행하면 됩니다.

```bash
tr -d '\r' < tools/download-necessary-exchange-market-data-for-backtests.sh \
  | sed 's/^TRADING_MODE=.*/TRADING_MODE="futures"/' \
  | sed 's/^EXCHANGE=.*/EXCHANGE="binance"/' \
  > ~/nfi-tmp/download-necessary-exchange-market-data-for-backtests.sh
chmod +x ~/nfi-tmp/download-necessary-exchange-market-data-for-backtests.sh
```

실행:

```bash
bash ~/nfi-tmp/download-necessary-exchange-market-data-for-backtests.sh
```

## 10단계: 백테스트 스크립트 실행

백테스트 스크립트도 Linux용 복사본을 만듭니다.

```bash
tr -d '\r' < tests/backtests/backtesting-all-years-all-pairs.sh > ~/nfi-tmp/backtesting-all-years-all-pairs.sh
chmod +x ~/nfi-tmp/backtesting-all-years-all-pairs.sh
```

필요한 환경변수를 설정합니다.

```bash
export EXCHANGE=binance
export TRADING_MODE=futures
export STRATEGY_NAME=NostalgiaForInfinityX7
```

실행:

```bash
bash ~/nfi-tmp/backtesting-all-years-all-pairs.sh
```

기간을 제한하고 싶으면:

```bash
export TIMERANGE=20240101-20241231
```

그 다음 다시 스크립트를 실행하면 됩니다.

## 권장 작업 흐름 요약

Windows에서 이 저장소를 다룰 때 가장 안정적인 방식은 다음과 같습니다.

1. WSL Ubuntu 사용
2. 저장소 소스코드는 `/mnt/d/...` 에 둬도 됨
3. Python 가상환경은 `~` 아래에 생성
4. 시장 데이터도 `~` 아래에 저장
5. `user_data/data` 는 WSL 데이터 디렉터리로 링크
6. `.sh` 스크립트는 `~/nfi-tmp` 아래 Linux용 복사본을 만들어 실행

## 문제 해결

### `bash: command not found`

PowerShell이나 Bash가 없는 환경일 가능성이 큽니다. WSL Ubuntu에서 실행합니다.

### `freqtrade: command not found`

현재 활성화된 WSL 가상환경에 `freqtrade`가 설치되지 않은 상태입니다.

```bash
source ~/testenv/bin/activate
pip install freqtrade
```

### `/mnt/d/...` 안에서 `python3 -m venv .venv` 실패

가상환경은 `/mnt/d/...` 안에 만들지 말고 WSL 홈 디렉터리에 만듭니다.

```bash
cd ~
python3 -m venv testenv
```

### `sed -i` 실행 시 `Operation not permitted`

`/mnt/d/...` 아래 원본을 직접 수정하지 말고 `~/nfi-tmp` 에 Linux용 복사본을 만듭니다.

### `git clone` 또는 `chmod` 실패

데이터를 OneDrive 기반 Windows 경로에 직접 저장하지 말고 WSL 디렉터리에 저장한 뒤 링크로 연결합니다.

### `detected dubious ownership`

아래 명령으로 저장소를 safe directory로 등록합니다.

```bash
git config --global --add safe.directory /mnt/d/OneDrive/Project/NostalgiaForInfinity
```

## 마지막 정리

핵심 원칙은 간단합니다.

- 소스코드는 Windows 드라이브에 있어도 됨
- 가상환경과 시장 데이터는 WSL 파일시스템에 두는 것이 안전함

이 원칙 하나만 지켜도 Windows에서 이 저장소의 백테스트 스크립트를 실행할 때 발생하는 대부분의 환경 문제를 피할 수 있습니다.
