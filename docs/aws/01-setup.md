# AWS로 선릿밸리 서버 만들기

$100~200 크레딧으로 **최대 6개월** 돌리는 구성입니다.
놀 때만 켜지도록 만들어서 크레딧이 기간을 다 채우게 합니다.

> 시작하기 전에 **[AWS 무료 정책 정리](00-free-tier-policy.md)** 를 먼저 읽어보세요.
> 공식 문서로 확인한 내용만 담았습니다. **특히 6개월 뒤 계정이 닫히고
> 90일 후 데이터가 영구 삭제되는 점**이 중요합니다.

---

## 1. AWS 계정 만들기

https://aws.amazon.com/free 에서 가입합니다.

- 신용카드 필요 (본인 확인용 $1 정도가 잠시 잡힙니다)
- 가입 마지막에 **플랜 선택**이 나옵니다 → **Free plan(무료 플랜)** 을 고르세요
  - Free plan: 크레딧이 떨어지면 **계정이 만료됩니다.** 요금이 청구되지 않습니다
  - Paid plan: 크레딧이 떨어지면 **그대로 과금이 시작됩니다**
- 가입 후 콘솔의 온보딩 활동을 하면 크레딧이 $100 → 최대 $200이 됩니다

> 무료 정책 전체는 **[무료 정책 정리](00-free-tier-policy.md)** 에 공식 문서 출처와
> 함께 정리해뒀습니다. 시작 전에 한 번 읽어보시길 권합니다.
> 특히 **Free plan이 저절로 Paid plan으로 바뀌는 조건**이 있으니 확인하세요.

### 리전 선택

AWS는 OCI와 달리 **리전을 나중에 바꿔도 됩니다.** 부담 없이 고르세요.

**서울(`ap-northeast-2`)** 을 추천합니다. 핑이 가장 좋고, 요금은 us-east-1보다
10~15% 비싸지만 이 규모에서는 월 몇 달러 차이입니다.

---

## 2. EC2 인스턴스 만들기

**콘솔 → EC2 → 인스턴스 시작(Launch instance)**

### 이름 및 태그
- 이름: `minecraft-sunlit`

### 애플리케이션 및 OS 이미지
- **Ubuntu** 선택
- **Ubuntu Server 24.04 LTS** 선택
- 아키텍처는 **`64비트(x86)`** ← 기본값입니다. **Arm으로 바꾸지 마세요**

> ⚠️ **여기가 함정입니다.** 아키텍처를 Arm으로 바꾸면 인스턴스 유형 목록이
> Graviton 전용으로 걸러지고, 무료 플랜에서 쓸 수 있는 ARM 유형은
> `t4g.micro`(1GB)와 `t4g.small`(2GB)뿐이라 **8GB짜리를 고를 수 없게 됩니다.**
> x86으로 둬야 다음 단계의 `m7i-flex.large`가 목록에 나옵니다.

### 인스턴스 유형

**`m7i-flex.large`** (2 vCPU / **8 GiB**, Intel)

무료 플랜(2025년 7월 15일 이후 가입 계정)에서 **쓸 수 있는 EC2 유형은
아래 6개로 제한**되어 있습니다:

| 유형 | RAM | 선릿밸리 |
|---|---|---|
| t3.micro / t4g.micro | 1 GB | ❌ |
| t3.small / t4g.small | 2 GB | ❌ |
| c7i-flex.large | 4 GB | ❌ |
| **m7i-flex.large** | **8 GB** | **✅ 유일한 선택지** |

`m7i-flex`는 `t` 계열과 달리 **CPU 크레딧이 없습니다.** AWS가
"24시간 평균으로 95%의 시간 동안 전체 CPU 성능, 나머지 5%도 최소 40%"를
보장하는 방식이라 마인크래프트 서버처럼 꾸준히 도는 워크로드에 잘 맞습니다.

> `m7i-flex.large`가 목록에 안 보이면 ① 아키텍처가 x86인지, ② 리전을
> 확인하세요. 일부 리전에는 아직 없을 수 있습니다.

### 8GB로 충분한가요?

선릿밸리 권장은 힙 6~7GB인데, 8GB 인스턴스에서는 **힙 5.5GB**가 한계입니다.
설치 스크립트가 이걸 감지해서 **시야거리 6, 최대 4명**으로 자동 조정합니다.

**2~4명이면 충분히 돌아갑니다.** 다만 OCI 12GB보다는 빠듯해서, Create 대형
공장을 여러 개 돌리면 렉이 느껴질 수 있습니다.

### 키 페어 — 서버에 들어가는 열쇠입니다

1. **새 키 페어 생성** 클릭
2. **키 페어 이름**: `minecraft-key` ← 이 이름을 그대로 쓰시면 아래 명령을
   복사해서 붙여넣기만 하면 됩니다
3. 키 페어 유형: **RSA**
4. 프라이빗 키 파일 형식: **`.pem`**
5. **키 페어 생성** → `minecraft-key.pem` 파일이 자동으로 다운로드됩니다

> ⚠️ 이 파일은 **다시 받을 수 없습니다.** 잃어버리면 인스턴스를 새로 만들어야 합니다.
> 보통 `다운로드` 폴더에 저장되니, 안전한 곳으로 옮겨두고 경로를 기억해두세요.

### 네트워크 설정 — 보안 그룹

**편집**을 눌러 규칙을 추가합니다.

| 유형 | 프로토콜 | 포트 | 소스 | 설명 |
|---|---|---|---|---|
| SSH | TCP | 22 | 내 IP | 관리용 |
| **사용자 지정 TCP** | TCP | **25565** | `0.0.0.0/0` | Minecraft |
| 사용자 지정 UDP | UDP | 25565 | `0.0.0.0/0` | (선택) 음성 모드용 |

> OCI와 달리 **인스턴스 내부 방화벽은 신경 쓸 필요가 없습니다.**
> AWS의 우분투 AMI는 iptables가 기본 개방이라 보안 그룹만 열면 끝입니다.

### 스토리지 구성

- **50 GiB**, `gp3`

> **인스턴스를 꺼도 EBS 요금은 계속 나갑니다.** 크게 잡을수록 손해이니
> 50GB면 충분합니다. (모드팩 ~5GB + 월드 + 백업)

### 고급 세부 정보 — 꼭 확인

아래로 스크롤해서 **종료 동작(Shutdown behavior)** 을 찾으세요.

- **반드시 `중지(Stop)`** 여야 합니다
- `종료(Terminate)`면 자동 종료가 걸릴 때 **인스턴스가 삭제되고 월드가 사라집니다**

기본값이 `Stop`이지만 직접 확인하세요.

### 인스턴스 시작

**인스턴스 시작** 클릭.

---

## 3. 접속하기

인스턴스 상세에서 **퍼블릭 IPv4 주소**를 복사합니다.

아래 명령의 `minecraft-key.pem`은 **키 페어를 만들 때 정한 이름**입니다.
다른 이름으로 만드셨다면 그 이름으로 바꿔서 쓰세요.

**맥 / 리눅스:**
```bash
cd ~/Downloads
chmod 400 minecraft-key.pem          # 권한을 안 조이면 SSH가 키를 거부합니다
ssh -i minecraft-key.pem ubuntu@퍼블릭IP
```

**윈도우 PowerShell:**
```powershell
cd $HOME\Downloads
icacls .\minecraft-key.pem /inheritance:r
icacls .\minecraft-key.pem /grant:r "$($env:USERNAME):(R)"
ssh -i .\minecraft-key.pem ubuntu@퍼블릭IP
```

`ubuntu@ip-172-31-...:~$` 같은 프롬프트가 뜨면 접속 성공입니다.

### 키 이름이 기억나지 않는다면

EC2 콘솔 → 인스턴스 선택 → **세부 정보** 탭 → **키 페어 이름** 항목에 있습니다.
실제 파일은 보통 `다운로드` 폴더에 그 이름 + `.pem` 으로 저장돼 있습니다.

파일을 찾는 명령:

```bash
# 맥 / 리눅스
ls ~/Downloads/*.pem
```
```powershell
# 윈도우
Get-ChildItem -Path $HOME -Filter *.pem -Recurse -ErrorAction SilentlyContinue
```

### 자주 막히는 부분

| 증상 | 원인 |
|---|---|
| `Permission denied (publickey)` | 사용자 이름이 틀림. 우분투는 **`ubuntu`** (`root`·`ec2-user` 아님) |
| `UNPROTECTED PRIVATE KEY FILE` | `chmod 400` / `icacls` 를 안 함 |
| `No such file or directory` | `.pem` 파일 경로가 틀림. 위 명령으로 파일을 먼저 찾으세요 |
| `Connection timed out` | 보안 그룹에 SSH(22) 규칙이 없거나, 내 IP가 바뀜 |

---

## 4. 서버 설치

### 먼저 — 터미널에 붙여넣는 방법

SSH로 접속한 창에서는 **`Ctrl+V`가 안 먹는 경우가 많습니다.**

| 터미널 | 붙여넣기 |
|---|---|
| **Windows Terminal / PowerShell** | **마우스 우클릭** (또는 `Ctrl+Shift+V`) |
| PuTTY | **마우스 우클릭** |
| 맥 터미널 | `Cmd+V` |

명령을 복사한 뒤 **터미널 창에서 마우스 오른쪽 버튼을 한 번 클릭**하면 붙습니다.
붙여넣은 뒤 **Enter** 를 눌러야 실행됩니다.

> 여러 줄을 한꺼번에 붙여넣어도 되지만, 처음이시라면 **한 줄씩** 붙여넣고
> 각각 끝나는 걸 확인하면서 진행하는 편이 문제를 찾기 쉽습니다.

---

### 4-1. 저장소 받기

```bash
sudo apt update && sudo apt install -y git
```

```bash
git clone -b claude/minecraft-sunset-valley-oci-9pwbki https://github.com/sulhwawall-pixel/minecraft.git
```

```bash
cd minecraft
```

### 4-2. VM 준비

```bash
sudo bash scripts/01-setup-vm.sh
```

Java 17, 스왑, 방화벽, systemd, 자동 백업을 설치합니다. 2~3분 걸립니다.

RAM 8GB라서 중간에 **"RAM 7900MB — 돌아가지만 여유가 많지 않습니다"** 경고가
뜨는데 **정상입니다.** 그냥 진행됩니다.

### 4-3. 서버 팩 zip 링크 구하기 — 여기는 PC 브라우저에서 합니다

서버에 CurseForge 페이지 주소를 그대로 넣으면 **403 에러**가 납니다.
파일이 실제로 있는 CDN 주소가 따로 필요합니다.

1. PC 브라우저에서 파일 목록 열기
   https://www.curseforge.com/minecraft/modpacks/society-sunlit-valley/files/all
2. 이름에 **`SERVER-PACK`** 이 들어간 최신 파일을 클릭
   (예: `SERVER-PACK-Society-Sunlit-Valley-4.1.1.zip`)
   → **`SERVER PACK`이 아닌 파일은 클라이언트용이라 안 됩니다**
3. **Download** 버튼 클릭 → 다운로드가 시작됩니다
4. 브라우저에서 **`Ctrl+J`** (다운로드 목록 열기)
5. 방금 받은 항목에 **마우스 우클릭 → "다운로드 링크 복사"**

복사된 주소가 이렇게 생겼으면 정답입니다:

```
https://mediafilez.forgecdn.net/files/7650/600/SERVER-PACK-Society-Sunlit-Valley-4.1.1.zip
```

> ⚠️ 주소에 `curseforge.com` 이 들어 있으면 **잘못 복사한 것**입니다.
> 반드시 `mediafilez.forgecdn.net` 으로 시작해야 합니다.

### 4-4. 서버 팩 설치 — 반드시 `tmux` 안에서 하세요

설치는 10분 넘게 걸립니다. 그동안 **SSH 연결이 한 번이라도 끊기면 설치가
통째로 죽습니다.** (화면은 멈춘 것처럼 보이는데 실제로는 프로세스가 사라진 상태)

`tmux` 안에서 돌리면 **연결이 끊겨도 서버 쪽에서 계속 진행**되고,
다시 접속해서 이어보면 됩니다.

먼저 tmux 세션을 만듭니다:

```bash
tmux new -s install
```

화면 아래에 초록색 줄이 생기면 tmux 안에 들어온 겁니다.
**여기서** 설치 명령을 실행하세요. 따옴표 안에 4-3에서 복사한 주소를 붙여넣습니다:

```bash
sudo bash scripts/02-install-modpack.sh "여기에_복사한_주소_붙여넣기"
```

실제로는 이런 모양이 됩니다:

```bash
sudo bash scripts/02-install-modpack.sh "https://mediafilez.forgecdn.net/files/7650/600/SERVER-PACK-Society-Sunlit-Valley-4.1.1.zip"
```

**따옴표 `"` 를 빠뜨리지 마세요.** 주소에 특수문자가 들어 있으면 따옴표 없이는 깨집니다.

다운로드 + 압축 해제 + Forge 설치까지 **5~10분** 걸립니다.

> 마지막에 `힙 크기를 5500M 로 정했습니다` 같은 줄이 나오면 성공입니다.

### 4-5. 연결이 끊겼다면

당황하지 마세요. tmux 안에서 돌렸다면 **설치는 서버에서 계속 진행 중**입니다.

다시 SSH로 접속한 뒤:

```bash
tmux attach -t install
```

아까 그 화면이 그대로 나옵니다. 진행이 끝나 있을 수도 있습니다.

### tmux 기본 조작

| 하고 싶은 것 | 방법 |
|---|---|
| 나가되 계속 돌리기 | **`Ctrl+B`** 누른 뒤 **`D`** |
| 다시 들어가기 | `tmux attach -t install` |
| 세션 목록 보기 | `tmux ls` |

> **`Ctrl+C` 는 실행 중인 작업을 죽입니다.** 나갈 때는 반드시 `Ctrl+B` → `D`.

### 4-6. 진행이 멈춘 것 같을 때

진짜 멈춘 건지 확인하려면 **새 SSH 창**에서:

```bash
ps aux | grep -c "[j]ava"
```

- **1 이상** → Forge 설치가 도는 중입니다. 기다리세요
- **0** → 프로세스가 죽었습니다. 대부분 SSH가 끊긴 경우이니
  위의 tmux 방식으로 다시 실행하세요

파일이 실제로 늘고 있는지 보는 방법:

```bash
sudo du -sh /opt/minecraft/server/libraries
```

30초 간격으로 두 번 쳐서 크기가 커지면 정상입니다.

### 4-7. 그 밖에 잘 안 될 때

| 증상 | 해결 |
|---|---|
| `zip 파일이 아닙니다` | CurseForge 웹 주소를 넣은 것. `mediafilez.forgecdn.net` 링크가 맞는지 확인 |
| `다운로드 실패` | 링크가 만료됨. 4-3을 다시 해서 새 링크를 받으세요 |
| `mods 폴더 없음` | 클라이언트 팩을 받은 것. 이름에 `SERVER-PACK` 이 있는 파일이어야 합니다 |
| 붙여넣기가 안 됨 | 터미널 창에서 **마우스 우클릭** |
| 자꾸 연결이 끊김 | 아래 "SSH 끊김 방지" 참고 |

### SSH 끊김 방지 (선택)

PC에서 SSH가 자주 끊긴다면, 접속할 때 keepalive 옵션을 붙이세요:

```powershell
ssh -o ServerAliveInterval=60 -i .\minecraft.pem ubuntu@퍼블릭IP
```

60초마다 신호를 보내서 공유기나 방화벽이 유휴 연결로 판단해 끊는 걸 막아줍니다.

---

## 5. 비용 절감 장치 설치 — 이게 핵심입니다

```bash
sudo bash scripts/aws/install-cost-savers.sh
```

- **유휴 자동 종료**: 30분간 접속자가 없으면 인스턴스가 스스로 정지합니다
- **DuckDNS**: 켤 때마다 바뀌는 IP를 고정 주소로 덮어줍니다 (설치 중 입력)

스크립트가 **도메인 이름**과 **토큰** 두 가지를 물어봅니다. 먼저 아래처럼 준비하세요.

### DuckDNS 도메인 만들기 (PC 브라우저에서, 1분)

1. https://www.duckdns.org 접속
2. 위쪽의 **Google / GitHub** 등으로 로그인 (가입 절차 따로 없음)
3. 로그인하면 나오는 화면 맨 위에 **`token`** 이 길게 적혀 있습니다 → **복사해두세요**
4. 아래 **domains** 칸에 원하는 이름을 입력 (예: `my-sunlit`) → **add domain** 클릭
5. 목록에 `my-sunlit.duckdns.org` 가 생기면 끝입니다

### ⚠️ "current ip" 칸은 건드리지 마세요

도메인을 만들면 **`current ip` 에 값이 자동으로 채워집니다.
그건 서버 IP가 아니라 지금 접속한 내 PC의 IP라서 틀린 값입니다.**

**손으로 고칠 필요 없습니다.** 서버에서 스크립트를 설치하면 곧바로 EC2의
실제 IP로 덮어쓰고, 이후 5분마다 자동으로 갱신합니다. 인스턴스를 껐다 켜서
IP가 바뀌어도 알아서 따라갑니다.

### 스크립트에 입력할 값

| 물어보는 것 | 넣을 값 | 예시 |
|---|---|---|
| 도메인 이름 | **`.duckdns.org` 앞부분만** | `my-sunlit` ← `my-sunlit.duckdns.org` (X) |
| 토큰 | 3번에서 복사한 문자열 | `a1b2c3d4-...` |

설치가 끝나면 `my-sunlit.duckdns.org -> 3.35.x.x 갱신 완료` 같은 줄이 나옵니다.
그러면 정상입니다.

DuckDNS를 안 쓰고 싶으면 도메인 이름을 묻는 곳에서 그냥 Enter를 누르면 건너뜁니다.
대신 인스턴스를 껐다 켤 때마다 친구들에게 새 IP를 알려줘야 합니다.

### 나중에 확인하고 싶을 때

```bash
sudo cat /etc/duckdns.conf          # 저장된 도메인·토큰
sudo /opt/minecraft/duckdns-update.sh   # 지금 즉시 갱신 시도
journalctl -t duckdns -n 20         # 갱신 기록
```

---

## 6. 서버 켜기

```bash
sudo mcctl start
sudo mcctl log      # "Done" 이 뜨면 완료 (첫 실행 5~15분)
```

접속 주소는 `내도메인.duckdns.org:25565` 입니다.

---

## 다음

→ **[서버를 자동으로 켜고 끄기](02-auto-onoff.md)** — PC 없이 폰으로 켜는 방법
→ [운영 가이드](../05-operate.md) (OCI와 동일)
→ [문제 해결](../06-troubleshooting.md)
