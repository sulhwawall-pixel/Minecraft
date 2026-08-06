# AWS로 선릿밸리 서버 만들기

$100~200 크레딧으로 **최대 6개월** 돌리는 구성입니다.
놀 때만 켜지도록 만들어서 크레딧이 기간을 다 채우게 합니다.

> 비용 계산과 6개월 뒤 벌어지는 일은 [대안 비교 문서](../07-alternatives.md#aws는-왜-안-되나)를
> 먼저 읽어보세요. **특히 6개월 뒤 계정이 닫히고 90일 후 데이터가 영구 삭제되는 점**이 중요합니다.

---

## 1. AWS 계정 만들기

https://aws.amazon.com/free 에서 가입합니다.

- 신용카드 필요 (본인 확인용 $1 정도가 잠시 잡힙니다)
- 가입 마지막에 **플랜 선택**이 나옵니다 → **Free plan(무료 플랜)** 을 고르세요
  - Free plan: 크레딧이 떨어지면 **계정이 멈춥니다.** 요금이 청구되지 않습니다
  - Paid plan: 크레딧이 떨어지면 **그대로 과금이 시작됩니다**
- 가입 후 온보딩 과제 5개(각 $20)를 하면 크레딧이 $100 → 최대 $200이 됩니다

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
- **아키텍처를 `64비트(Arm)` 으로 변경** ← 꼭 확인하세요

### 인스턴스 유형

**`m7g.large`** (2 vCPU / 8GB, Graviton3)

> **`t4g`·`t3` 계열은 피하세요.** 버스터블이라 CPU 크레딧을 소진하면 성능이
> 제한되거나 추가 요금이 붙습니다. 마인크래프트 서버는 켜져 있는 내내 CPU를
> 꾸준히 쓰는 정반대 패턴이라 잘 안 맞습니다.

목록에 `m7g.large`가 없으면 `m6g.large`도 괜찮습니다.

### 키 페어
- **새 키 페어 생성** → 유형 `RSA`, 형식 `.pem`
- 다운로드된 `.pem` 파일을 잘 보관하세요. **다시 받을 수 없습니다.**

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

**맥 / 리눅스:**
```bash
chmod 400 ~/Downloads/키이름.pem
ssh -i ~/Downloads/키이름.pem ubuntu@퍼블릭IP
```

**윈도우 PowerShell:**
```powershell
icacls .\키이름.pem /inheritance:r
icacls .\키이름.pem /grant:r "$($env:USERNAME):(R)"
ssh -i .\키이름.pem ubuntu@퍼블릭IP
```

---

## 4. 서버 설치

여기서부터는 **OCI와 완전히 동일합니다.** 둘 다 Ubuntu ARM64라 스크립트가 그대로 돕니다.

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/sulhwawall-pixel/minecraft.git
cd minecraft

# VM 준비 (Java 17, 스왑, systemd, 자동 백업)
sudo bash scripts/01-setup-vm.sh

# 서버 팩 설치 — zip 구하는 법은 아래 문서 참고
sudo bash scripts/02-install-modpack.sh "<서버팩 직링크 또는 경로>"
```

서버 팩 zip을 구하는 방법은 [4단계 문서](../04-install-server.md#4-2-서버-팩-zip-구하기)에
그대로 나와 있습니다.

---

## 5. 비용 절감 장치 설치 — 이게 핵심입니다

```bash
sudo bash scripts/aws/install-cost-savers.sh
```

- **유휴 자동 종료**: 30분간 접속자가 없으면 인스턴스가 스스로 정지합니다
- **DuckDNS**: 켤 때마다 바뀌는 IP를 고정 주소로 덮어줍니다 (설치 중 입력)

DuckDNS 도메인은 https://www.duckdns.org 에서 구글 로그인만 하면 1분 만에
무료로 만들 수 있습니다. 스크립트가 도메인 이름과 토큰을 물어봅니다.

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
