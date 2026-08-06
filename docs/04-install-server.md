# 4단계 — 선릿밸리 서버 설치

SSH로 서버에 접속한 상태에서 진행합니다.

---

## 4-1. 저장소 받고 VM 준비하기

```bash
sudo apt update && sudo apt install -y git
git clone -b claude/minecraft-sunset-valley-oci-9pwbki https://github.com/sulhwawall-pixel/minecraft.git
cd minecraft
sudo bash scripts/01-setup-vm.sh
```

이 스크립트가 하는 일:

- **Java 17** 설치 — 마크 1.20.1의 정확한 요구 버전입니다. Java 21을 쓰면 일부 모드가 깨집니다
- `minecraft` 전용 사용자와 `/opt/minecraft` 디렉터리 생성
- **4GB 스왑 파일** 생성 — 메모리가 순간적으로 튈 때 서버가 강제 종료되는 걸 막습니다
- **인스턴스 방화벽(iptables)에 25565 개방** — 3단계에서 말한 두 번째 방화벽
- 파일 디스크립터 상한 상향
- systemd 서비스 + 자동 백업 타이머 설치

2~3분이면 끝납니다.

---

## 4-2. 서버 팩 zip 구하기

**클라이언트 팩이 아니라 서버 팩(SERVER PACK)** 이어야 합니다. 이름에 `SERVER-PACK`이
들어간 파일입니다.

CurseForge 파일 목록:
https://www.curseforge.com/minecraft/modpacks/society-sunlit-valley/files/all

`SERVER-PACK-Society-Sunlit-Valley-4.1.1.zip` 같은 최신 파일을 찾으세요.

> **중요:** 서버 버전과 친구들이 CurseForge 런처에서 설치할 클라이언트 버전이
> **정확히 같아야** 합니다. 4.1.1 서버에 4.0.0 클라이언트로는 접속되지 않습니다.
> 먼저 어떤 버전을 쓸지 정하고 다 같이 맞추세요.

아래 두 방법 중 편한 쪽을 쓰시면 됩니다.

### 방법 A — 직링크로 서버에서 바로 받기 (추천)

CurseForge 페이지 주소를 서버에 그대로 넣으면 **403 에러**가 납니다.
실제 파일이 있는 CDN 주소가 따로 필요합니다.

1. 위 파일 목록에서 원하는 서버 팩을 클릭
2. **Download** 버튼을 누르면 다운로드가 시작됩니다
3. 브라우저의 **다운로드 목록(Ctrl+J)** 을 열고, 방금 받은 항목에서
   **우클릭 → "다운로드 링크 복사"**
4. `https://mediafilez.forgecdn.net/files/7650/600/SERVER-PACK-...zip` 형태면 정답입니다

이 링크를 그대로 넘기면 됩니다:

```bash
sudo bash scripts/02-install-modpack.sh "https://mediafilez.forgecdn.net/files/.../SERVER-PACK-....zip"
```

> 링크에 `curseforge.com` 이 들어 있으면 잘못 복사한 것입니다. 반드시
> `mediafilez.forgecdn.net` 이어야 합니다.

### 방법 B — 내 PC에서 받아서 업로드

이미 PC에 받아뒀다면 SSH 키를 써서 올리면 됩니다.

> 아래 `ssh-key-XXXX.key` 는 **OCI**가 만들어주는 키 파일 이름입니다.
> **AWS**라면 본인이 정한 이름의 `.pem` 파일(예: `minecraft-key.pem`)로 바꿔 쓰세요.

**윈도우 PowerShell:**
```powershell
scp -i .\ssh-key-XXXX.key ".\SERVER-PACK-Society-Sunlit-Valley-4.1.1.zip" ubuntu@공인IP:/tmp/
```

**맥 / 리눅스:**
```bash
scp -i ~/Downloads/ssh-key-XXXX.key ~/Downloads/SERVER-PACK-*.zip ubuntu@공인IP:/tmp/
```

파일이 1GB 가까이 되므로 몇 분 걸립니다. 업로드가 끝나면 서버에서:

```bash
sudo bash scripts/02-install-modpack.sh /tmp/SERVER-PACK-Society-Sunlit-Valley-4.1.1.zip
```

---

## 4-3. 설치 스크립트가 하는 일

```bash
sudo bash scripts/02-install-modpack.sh <zip 경로 또는 직링크>
```

- 서버 팩 압축 해제
- `eula.txt` 에 동의 표시 (마인크래프트 EULA: https://aka.ms/MinecraftEULA)
- `server.properties` 를 **서버 사양에 맞게 조정** — 12GB면 시야거리 8·최대 6명,
  8GB면 시야거리 6·최대 4명. 저사양에서는 시야거리를 줄이는 게 체감 효과가 제일 큽니다
- **Forge 서버 설치** (서버 팩에 인스톨러가 들어있는 경우)
- **힙 크기 자동 계산** — 전체 RAM에서 OS와 JVM 오프힙 몫을 남기고 나머지를 힙으로 줍니다.
  대형 모드팩은 힙 바깥(메타스페이스, 다이렉트 버퍼)에서만 1.5~2.5GB를 쓰기 때문에
  이걸 안 빼면 리눅스가 서버 프로세스를 강제 종료시킵니다.
  → **12GB 인스턴스에서는 힙 약 8GB.** 권장치 6~7GB보다 여유 있습니다.
  8GB 인스턴스(AWS)라면 힙 5.5GB로 잡고 시야거리와 인원을 함께 낮춥니다
- **Aikar's flags** 적용 — 마크 서버용으로 검증된 G1 GC 튜닝값
- 기존 월드가 있으면 자동 백업 후 진행

Forge 설치 때문에 3~5분 정도 걸립니다.

---

## 4-4. 서버 켜기

```bash
sudo mcctl start
sudo mcctl log
```

**첫 실행은 5~15분 걸립니다.** 모드 수백 개를 로딩하고 월드를 새로 만들기 때문입니다.
로그에 이런 줄이 뜨면 준비 완료입니다:

```
[Server thread/INFO]: Done (312.456s)! For help, type "help"
```

`mcctl log` 에서 빠져나올 때는 **Ctrl+C** (서버는 계속 돌아갑니다).

### 관리자 권한 주기

```bash
sudo mcctl cmd "op 내닉네임"
```

### 접속 주소 확인

```bash
sudo mcctl ip
```

---

## 4-5. 친구들 클라이언트 설정

각자 PC에서:

1. **CurseForge 앱** 설치 (https://www.curseforge.com/download/app)
2. Minecraft → **Browse Modpacks** → `Society: Sunlit Valley` 검색 → 설치
3. **서버와 같은 버전**인지 확인 (설치 후 팩 우측 ⋮ → Versions 에서 변경 가능)
4. 팩 설정에서 **할당 메모리를 6GB 이상**으로 (기본 4GB로는 부족합니다)
   - CurseForge 설정 → Minecraft → Java Settings → Allocated Memory
5. 게임 실행 → **멀티플레이 → 서버 추가** → 주소에 `공인IP:25565` 입력

> 클라이언트 PC의 RAM이 8GB뿐이라면 6GB 할당은 무리입니다. 최소 16GB를 권합니다.

---

## 다음

→ [5단계: 운영하기](05-operate.md)
→ 안 되는 게 있다면 [문제 해결](06-troubleshooting.md)
