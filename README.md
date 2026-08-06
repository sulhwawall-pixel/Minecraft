# 선릿밸리 모드팩 서버 — Oracle Cloud 무료 티어 구축 가이드

**Society: Sunlit Valley** (한국에서 흔히 "선셋밸리"라고 불리는 그 모드팩) 서버를
Oracle Cloud Infrastructure(OCI) **평생 무료** 인스턴스에 올리는 전체 가이드입니다.

리눅스도 클라우드도 처음이라는 가정으로 썼습니다. 순서대로만 따라오시면 됩니다.

---

## 먼저 알아야 할 두 가지

### 1. OCI 무료 티어가 2026년 6월에 절반으로 줄었습니다

| 항목 | 예전 | **지금 (2026-06-15~)** |
|---|---|---|
| ARM CPU | 4 OCPU | **2 OCPU** |
| ARM RAM | 24 GB | **12 GB** |

오라클이 공지 없이 문서만 바꿔서 모르는 분이 많습니다. 인터넷의 "24GB 무료" 가이드는
이제 맞지 않습니다. 이 저장소의 설정은 전부 **2 OCPU / 12 GB 기준**입니다.

### 2. 그래도 2~4명이 하기엔 충분합니다

선릿밸리 서버 권장 RAM이 6~7GB인데, 12GB 중 **약 8.5GB를 힙으로** 줄 수 있습니다.
CPU 2코어가 빠듯한 편이라 시야거리를 8로 낮춰뒀고, 이 상태로 2~4명은 무난합니다.

| 인원 | 현실적인 평가 |
|---|---|
| 2~4명 | 쾌적. 이 가이드의 기준 |
| 5~8명 | 가능하지만 Create 대형 공장 돌리면 렉 체감 |
| 9명+ | 무료 티어로는 권장하지 않음 |

---

## 모드팩 정보

| 항목 | 값 |
|---|---|
| 이름 | Society: Sunlit Valley |
| 마인크래프트 | **1.20.1** |
| 모드로더 | **Forge** |
| Java | **17** (21로 올리면 일부 모드가 깨집니다) |
| 서버 팩 | 공식 제공 (`SERVER-PACK-Society-Sunlit-Valley-*.zip`) |

> 혹시 Modrinth의 **Sunset Valley**(코티지코어 바닐라+ 경량 팩)를 찾으신 거라면
> 완전히 다른 모드팩입니다. 그건 훨씬 가벼워서 이 가이드보다 쉽게 됩니다 —
> 스크립트의 서버 팩 zip만 바꿔 끼우면 그대로 동작합니다.

---

## 전체 순서

| 단계 | 문서 | 예상 시간 |
|---|---|---|
| 1 | [OCI 계정 만들기](docs/01-oci-account.md) | 20분 |
| 2 | [인스턴스(서버 컴퓨터) 생성](docs/02-create-instance.md) | 20분 ~ 며칠※ |
| 3 | [네트워크 열기](docs/03-network.md) | 10분 |
| 4 | [모드팩 서버 설치](docs/04-install-server.md) | 30분 |
| 5 | [접속하고 운영하기](docs/05-operate.md) | — |
| ? | [문제 해결](docs/06-troubleshooting.md) | — |

※ 2단계에서 **"Out of host capacity"** 가 뜨는 일이 흔합니다. 무료 ARM 서버는 인기가
많아서 자리가 없을 때가 많습니다. 대처법은 2단계 문서에 정리해뒀습니다.

---

## 빠른 시작 (인스턴스 만든 다음부터)

SSH로 서버에 접속한 뒤:

```bash
# 1. 이 저장소 받기
sudo apt update && sudo apt install -y git
git clone https://github.com/sulhwawall-pixel/minecraft.git
cd minecraft

# 2. VM 준비 (Java, 방화벽, 스왑, systemd)
sudo bash scripts/01-setup-vm.sh

# 3. 서버 팩 zip 을 /opt/minecraft/downloads 에 올린 뒤
sudo bash scripts/02-install-modpack.sh

# 4. 시작
sudo mcctl start
sudo mcctl log      # "Done" 이 뜨면 완료
sudo mcctl ip       # 친구에게 알려줄 주소
```

---

## 서버 관리 명령 (`mcctl`)

```
sudo mcctl start          서버 시작
sudo mcctl stop           안전하게 정지 (월드 저장 후 종료)
sudo mcctl restart        재시작
sudo mcctl status         상태 / 메모리 / 백업 현황
sudo mcctl console        서버 콘솔 접속 (나올 때 Ctrl+B 누른 뒤 D)
sudo mcctl log            실시간 로그
sudo mcctl cmd "op 닉네임"  콘솔 명령 전송
sudo mcctl players        접속자 목록
sudo mcctl backup         즉시 백업
sudo mcctl ip             접속 주소 확인
sudo mcctl update         모드팩 업데이트 방법
```

백업은 **매일 새벽 4시에 자동**으로 돌고 7일치를 보관합니다.

---

## 저장소 구성

```
scripts/
  01-setup-vm.sh        VM 초기 세팅 (Java 17, 방화벽, 스왑, systemd)
  02-install-modpack.sh 서버 팩 설치 + Forge 설치 + 힙 자동 계산
  mcctl                 서버 관리 명령
  backup.sh             월드 백업 (save-off → 복사 → save-on)
config/
  minecraft.service          systemd 유닛 (tmux 기반, 안전 종료)
  minecraft-backup.{service,timer}  자동 백업
  server.properties          저사양 서버용 기본 설정
docs/                   단계별 한국어 가이드
```

---

## 비용에 대해

이 구성은 **Always Free 범위 안에만** 머무르도록 되어 있습니다 (2 OCPU / 12GB ARM,
부트 볼륨 200GB 이내, 아웃바운드 10TB/월). 가입 시 신용카드가 필요하지만 실제 청구는
없습니다. 다만 **가입 후 30일간의 $300 무료 크레딧 기간에는 유료 리소스도 만들어지므로**,
인스턴스 생성 화면에서 **"Always Free eligible"** 라벨이 붙어 있는지 꼭 확인하세요.
자세한 내용은 [1단계 문서](docs/01-oci-account.md)에 있습니다.
