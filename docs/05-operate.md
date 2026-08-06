# 5단계 — 운영하기

---

## 매일 쓰는 명령

```bash
sudo mcctl status      # 지금 상태
sudo mcctl start       # 켜기
sudo mcctl stop        # 끄기 (월드 저장 후 안전 종료)
sudo mcctl restart     # 재시작
sudo mcctl log         # 실시간 로그 (Ctrl+C 로 나감)
sudo mcctl players     # 누가 접속해 있나
sudo mcctl ip          # 접속 주소
```

### 콘솔에서 직접 명령 치기

```bash
sudo mcctl cmd "op 닉네임"
sudo mcctl cmd "whitelist add 닉네임"
sudo mcctl cmd "time set day"
sudo mcctl cmd "say 안녕하세요"
```

또는 콘솔에 아예 붙어서 작업할 수도 있습니다:

```bash
sudo mcctl console
```

> **⚠️ 콘솔에서 나올 때 반드시 `Ctrl+B` 를 누른 뒤 `D` 를 누르세요.**
> `Ctrl+C` 를 누르면 서버가 그대로 죽습니다.

---

## 백업

**자동으로 매일 새벽 4시**에 돌아가고 **7일치**를 보관합니다.
`save-off → 저장 확정 → 복사 → save-on` 순서로 진행해서, 저장 도중에
스냅샷이 찍혀 청크가 깨지는 일이 없습니다.

```bash
sudo mcctl backup                      # 지금 즉시 백업
ls -lh /opt/minecraft/backups/         # 백업 목록
sudo systemctl list-timers minecraft-backup.timer   # 다음 백업 시각
```

### 백업에서 복구하기

```bash
sudo mcctl stop
cd /opt/minecraft/server
sudo mv world world-망한거-$(date +%F)          # 기존 월드는 일단 살려둠
sudo -u minecraft tar -xzf /opt/minecraft/backups/world-20260806-040000.tar.gz
sudo mcctl start
```

### 내 PC로 백업 가져오기 (권장)

인스턴스가 통째로 날아가는 경우에 대비해 가끔 로컬로도 받아두세요.

```bash
scp -i ssh키 ubuntu@공인IP:/opt/minecraft/backups/world-*.tar.gz ./
```

---

## 화이트리스트 (아는 사람만 들어오게)

주소가 공개되면 모르는 사람이 들어올 수 있습니다. 친구들만 하는 서버라면
켜두는 걸 권합니다.

```bash
sudo mcctl cmd "whitelist add 친구닉네임1"
sudo mcctl cmd "whitelist add 친구닉네임2"
sudo mcctl cmd "whitelist on"
```

이미 접속해 있는 사람은 화이트리스트를 켜도 쫓겨나지 않으니, 먼저 전원 추가한 뒤
켜는 게 편합니다.

---

## 성능 관리

### 지금 얼마나 버거운지 보기

```bash
sudo mcctl status                              # 메모리, 부하
sudo mcctl cmd "forge tps"                     # TPS 확인
sudo mcctl log | grep -i "Can't keep up"       # 틱이 밀리는 중인지
```

**TPS 20이 정상**입니다. 15 아래로 떨어지면 눈에 띄게 렉이 걸립니다.

### 렉이 걸릴 때 (원인 순서대로)

**1. 엔티티가 너무 많은 경우 — 가장 흔합니다**
동물 목장, 아이템 드롭 더미, 몹 스포너가 주범입니다.

```bash
sudo mcctl cmd "forge entity list"     # 뭐가 몇 마리 있는지
sudo mcctl cmd "kill @e[type=item]"    # 바닥에 떨어진 아이템 정리
```

**2. Create 대형 공장**
2코어에서는 거대 기계 여러 개가 동시에 도는 걸 감당하기 어렵습니다.
공장을 여러 청크에 분산하거나, 안 쓸 때 클러치로 꺼두게 하세요.

**3. 시야거리 낮추기 — 효과가 가장 확실합니다**

```bash
sudo nano /opt/minecraft/server/server.properties
# view-distance=6
# simulation-distance=4
sudo mcctl restart
```

**4. 청크 프리로딩**
새 지역을 탐험할 때 렉이 심하다면, 미리 청크를 생성해두면 좋습니다.
Chunky 모드가 팩에 포함돼 있으면:

```bash
sudo mcctl cmd "chunky radius 1000"
sudo mcctl cmd "chunky start"
```

접속자가 없을 때 돌리세요. CPU를 다 씁니다.

---

## 모드팩 업데이트

```bash
sudo mcctl backup       # 반드시 먼저
sudo mcctl stop
# 새 SERVER-PACK zip 을 /opt/minecraft/downloads 에 올린 뒤
sudo bash ~/minecraft/scripts/02-install-modpack.sh
sudo mcctl start
```

월드(`world/`)는 유지되고 모드만 교체됩니다.

> **주의:** 메이저 버전(3.x → 4.x)이 바뀌면 기존 월드가 호환되지 않을 수 있습니다.
> 업데이트 전에 모드팩 배포처의 변경 내역을 확인하세요.
> 그리고 **서버와 모든 클라이언트의 팩 버전이 같아야** 합니다.

---

## 재부팅 후 자동 시작

`systemctl enable minecraft` 이 이미 걸려 있어서, 인스턴스를 재부팅하면
서버가 자동으로 켜집니다.

확인:
```bash
systemctl is-enabled minecraft
```

---

## 인스턴스 관리

**정지했다가 켜면 공인 IP가 바뀝니다** (예약 IP로 바꾸지 않았다면).
[2단계 문서의 "공인 IP를 고정하기"](02-create-instance.md#공인-ip를-고정하기-권장)를
참고하세요.

무료 티어라 계속 켜둬도 요금은 나오지 않습니다. 다만 오라클은 **완전히 유휴 상태인
무료 인스턴스를 회수**할 수 있는데, 마크 서버가 돌고 있으면 해당되지 않습니다.
