# 문제 해결

---

## 접속이 안 됩니다

### 진단 순서

**① 서버가 켜져 있고 포트를 듣고 있나?**
```bash
sudo mcctl status
sudo ss -tlnp | grep 25565
```
`LISTEN` 이 안 보이면 → 서버가 안 켜졌거나 죽은 것. `sudo mcctl log` 로 원인 확인.

**② 인스턴스 방화벽이 열려 있나?**
```bash
sudo iptables -L INPUT -n --line-numbers | head -20
```
`ACCEPT tcp dpt:25565` 이 **REJECT/DROP 줄보다 위에** 있어야 합니다.
없거나 아래에 있으면:
```bash
sudo iptables -I INPUT 1 -p tcp --dport 25565 -j ACCEPT
sudo iptables -I INPUT 1 -p udp --dport 25565 -j ACCEPT
sudo netfilter-persistent save
```

**③ OCI 보안 목록이 열려 있나?**
[3단계 문서](03-network.md)를 다시 확인하세요. **이게 원인인 경우가 가장 많습니다.**
①②가 다 정상인데 밖에서 안 되면 거의 확실히 여기입니다.

**④ 바깥에서 실제로 열렸는지 확인**
https://mcsrvstat.us 에 `공인IP:25565` 입력.

### 증상별

| 증상 | 원인 |
|---|---|
| `Connection timed out` | 방화벽 문제. ②③ 확인 |
| `Connection refused` | 포트는 뚫렸는데 서버가 안 켜짐. ① 확인 |
| `Outdated server/client` | 서버와 클라이언트의 **팩 버전 불일치** |
| `Missing mods` / `Mod rejections` | 클라이언트 팩 버전이 다름. 같은 버전으로 재설치 |
| 나만 되고 친구는 안 됨 | 친구 쪽 네트워크 문제이거나, 화이트리스트가 켜져 있음 |
| 어제까진 됐는데 오늘 안 됨 | **공인 IP가 바뀜.** `sudo mcctl ip` 로 새 주소 확인 후 예약 IP로 전환 |

---

## 서버가 자꾸 죽습니다

### 메모리 부족 (가장 흔함)

```bash
# 리눅스가 강제 종료시켰는지 확인
sudo dmesg | grep -i "killed process"
sudo journalctl -u minecraft --since "1 hour ago" | tail -50
```

`Out of memory: Killed process ... java` 가 보이면 힙이 너무 큽니다.

```bash
sudo nano /opt/minecraft/server/start.sh
# HEAP="${MC_HEAP:-8704M}"  →  7680M 정도로 낮춤
sudo mcctl restart
```

로그에 `java.lang.OutOfMemoryError: Java heap space` 가 뜨는 건 **반대 경우**로,
힙이 부족한 겁니다. 이때는 힙을 늘리는 대신 **시야거리를 줄이고 엔티티를 정리**하는 게
맞습니다. 12GB 인스턴스에서 힙을 9GB 이상 주면 오프힙 공간이 모자라 다시 강제 종료됩니다.

### 특정 모드 크래시

```bash
grep -a -A 30 "Exception\|Crash" /opt/minecraft/server/logs/latest.log | head -60
ls -lt /opt/minecraft/server/crash-reports/ | head
```

크래시 리포트 상단의 `Description` 과 스택 첫 줄에 모드 이름이 나옵니다.

선릿밸리는 스크립트(KubeJS 등) 오타로 인한 에러가 알려져 있습니다.
`Caused by` 에 스크립트 파일 경로가 찍혀 있으면 해당 파일의 문법 문제입니다.
보통 다음 팩 버전에서 고쳐지니 업데이트가 가장 빠른 해결입니다.

---

## 렉이 심합니다

```bash
sudo mcctl cmd "forge tps"
```

TPS 20이 정상. 대처법은 [5단계 문서의 성능 관리](05-operate.md#성능-관리)를 보세요.
요약하면 **엔티티 정리 → 시야거리 축소 → Create 공장 분산** 순으로 효과가 큽니다.

2 OCPU에서는 CPU가 병목입니다. RAM을 더 준다고 TPS가 오르지는 않습니다.

---

## Java 버전 문제

```bash
java -version    # openjdk version "17.x.x" 여야 함
```

21이 잡혀 있다면:
```bash
sudo apt install -y openjdk-17-jre-headless
sudo update-alternatives --config java     # 17 선택
sudo mcctl restart
```

마크 1.20.1 + Forge 47.x 는 Java 17이 정식 조합입니다.
21에서도 뜨긴 하지만 일부 모드가 리플렉션 문제로 깨집니다.

---

## ARM(aarch64) 관련

마인크래프트 **서버**는 그래픽 라이브러리를 안 쓰기 때문에 ARM에서 잘 돌아갑니다.
다만 드물게 네이티브 라이브러리를 포함한 모드가 문제를 일으킬 수 있습니다.

증상: `UnsatisfiedLinkError` 또는 `no XXX in java.library.path`

```bash
grep -a "UnsatisfiedLinkError\|java.library.path" /opt/minecraft/server/logs/latest.log
```

이런 모드는 대개 클라이언트 전용(렌더링/셰이더 관련)이라 서버에서 빼도 됩니다.
`mods/` 에서 해당 jar를 `mods/disabled/` 로 옮기고 재시작해보세요.
단, 클라이언트에서도 같이 빼야 하는 모드인지 먼저 확인해야 합니다.

---

## 디스크가 찼습니다

```bash
df -h /
du -sh /opt/minecraft/* | sort -h
```

정리 대상:
```bash
# 오래된 백업
sudo find /opt/minecraft/backups -name 'world-*.tar.gz' -mtime +7 -delete

# 오래된 로그
sudo find /opt/minecraft/server/logs -name '*.log.gz' -mtime +14 -delete

# apt 캐시
sudo apt clean
```

부트 볼륨을 늘렸는데 `df` 에 반영이 안 됐다면 파티션 확장이 필요합니다:
```bash
sudo /usr/libexec/oci-growfs -y
```

---

## 인스턴스에 SSH가 안 됩니다

- **키 파일 권한**: 윈도우는 `icacls`, 맥/리눅스는 `chmod 600` ([2단계 참고](02-create-instance.md#ssh로-접속하기))
- **사용자 이름**: 우분투는 `ubuntu`, Oracle Linux는 `opc`. `root`는 안 됩니다
- **IP가 바뀌었을 수 있음**: OCI 콘솔에서 현재 공인 IP 확인
- **iptables를 잘못 건드려 22번을 막은 경우**: OCI 콘솔의
  **인스턴스 → 콘솔 연결(Console Connection)** 으로 들어가 복구할 수 있습니다

---

## 그래도 안 될 때 정보 모으기

```bash
{
  echo "=== 시스템 ==="; uname -a; free -h; df -h /
  echo "=== Java ==="; java -version 2>&1
  echo "=== 서비스 ==="; systemctl status minecraft --no-pager | head -20
  echo "=== 포트 ==="; sudo ss -tlnp | grep 25565
  echo "=== iptables ==="; sudo iptables -L INPUT -n --line-numbers | head -20
  echo "=== 로그 ==="; tail -80 /opt/minecraft/server/logs/latest.log
} > ~/mc-diag.txt

cat ~/mc-diag.txt
```

이 내용을 들고 물어보시면 원인을 훨씬 빨리 찾을 수 있습니다.
