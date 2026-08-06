#!/usr/bin/env bash
#
# 02-install-modpack.sh — Society: Sunlit Valley 서버 팩을 설치하고 실행 준비를 끝낸다.
#
# 사용법:
#   sudo bash 02-install-modpack.sh /경로/SERVER-PACK-Society-Sunlit-Valley-4.1.1.zip
#   sudo bash 02-install-modpack.sh https://mediafilez.forgecdn.net/files/.../SERVER-PACK-....zip
#
#   인자를 생략하면 /opt/minecraft/downloads 안에서 서버 팩 zip을 찾는다.
#
# 서버 팩 zip 구하는 법은 docs/04-install-server.md 참고.
#
set -euo pipefail

MC_USER="minecraft"
MC_HOME="/opt/minecraft"
SERVER_DIR="$MC_HOME/server"
DL_DIR="$MC_HOME/downloads"
SRC="${1:-}"

log()  { printf '\033[1;36m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "root로 실행해야 합니다:  sudo bash $0 $*"
[[ -d "$MC_HOME" ]] || die "먼저 01-setup-vm.sh 를 실행하세요."

# --------------------------------------------------------- 1. 서버 팩 zip 확보
mkdir -p "$DL_DIR"
ZIP=""

if [[ -z "$SRC" ]]; then
  ZIP="$(find "$DL_DIR" -maxdepth 1 -iname '*.zip' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
  [[ -n "$ZIP" ]] || die "서버 팩 zip을 못 찾았습니다. 경로나 URL을 인자로 주거나 $DL_DIR 에 올려주세요."
  log "가장 최근 zip을 사용합니다: $(basename "$ZIP")"
elif [[ "$SRC" =~ ^https?:// ]]; then
  ZIP="$DL_DIR/$(basename "${SRC%%\?*}")"
  log "서버 팩을 내려받습니다..."
  # CurseForge 웹페이지 링크는 403이 난다. mediafilez.forgecdn.net 직링크여야 한다.
  curl -fL --progress-bar -o "$ZIP" "$SRC" \
    || die "다운로드 실패. CurseForge 웹 링크가 아니라 mediafilez.forgecdn.net 직링크가 필요합니다 (docs/04-install-server.md 참고)."
else
  [[ -f "$SRC" ]] || die "파일이 없습니다: $SRC"
  ZIP="$SRC"
fi

file "$ZIP" | grep -qi zip || die "zip 파일이 아닙니다: $ZIP (HTML 에러 페이지를 받았을 가능성이 높습니다)"

# ------------------------------------------------------- 2. 기존 서버 백업 처리
if [[ -d "$SERVER_DIR" ]] && [[ -n "$(ls -A "$SERVER_DIR" 2>/dev/null)" ]]; then
  warn "$SERVER_DIR 에 기존 파일이 있습니다."
  if systemctl is-active --quiet minecraft; then
    log "실행 중인 서버를 정지합니다."
    systemctl stop minecraft
  fi
  if [[ -d "$SERVER_DIR/world" ]]; then
    STAMP="$(date +%Y%m%d-%H%M%S)"
    log "기존 월드를 백업합니다: $MC_HOME/backups/world-preinstall-$STAMP.tar.gz"
    tar -czf "$MC_HOME/backups/world-preinstall-$STAMP.tar.gz" -C "$SERVER_DIR" world 2>/dev/null || true
  fi
  read -rp "    $SERVER_DIR 위에 덮어씁니다. 계속할까요? [y/N] " ans
  [[ "${ans,,}" == "y" ]] || exit 1
fi

# ------------------------------------------------------------------ 3. 압축 해제
log "서버 팩을 풀고 있습니다. (모드가 많아 1~2분 걸립니다)"
mkdir -p "$SERVER_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unzip -q -o "$ZIP" -d "$TMP"

# 서버 팩마다 zip 최상위가 바로 내용물인 경우와 폴더 하나로 감싼 경우가 섞여 있다.
ROOT="$TMP"
if [[ "$(find "$TMP" -maxdepth 1 -mindepth 1 | wc -l)" -eq 1 ]] && [[ -d "$(find "$TMP" -maxdepth 1 -mindepth 1)" ]]; then
  ROOT="$(find "$TMP" -maxdepth 1 -mindepth 1)"
fi
[[ -d "$ROOT/mods" ]] || die "서버 팩 구조가 예상과 다릅니다 (mods 폴더 없음). 클라이언트 팩을 받으신 건 아닌지 확인하세요."

cp -a "$ROOT/." "$SERVER_DIR/"

# ------------------------------------------------------------- 4. EULA 및 설정
log "EULA에 동의 표시를 합니다. (https://aka.ms/MinecraftEULA)"
echo "eula=true" > "$SERVER_DIR/eula.txt"

TOTAL_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"

# RAM에 따라 부하 설정을 달리 잡는다. 2코어 서버에서 청크 생성이 가장 무겁기 때문에
# 시야거리를 줄이는 것이 체감 효과가 제일 크다.
if (( TOTAL_MB >= 10000 )); then
  VIEW=8; SIM=6; MAXP=6      # OCI 12GB 급
else
  VIEW=6; SIM=4; MAXP=4      # AWS m7i-flex.large 8GB 급
fi

if [[ ! -f "$SERVER_DIR/server.properties" ]]; then
  log "server.properties 를 생성합니다."
  cp "$(dirname "${BASH_SOURCE[0]}")/../config/server.properties" "$SERVER_DIR/server.properties"
fi

log "server.properties 를 이 서버 사양에 맞게 조정합니다. (시야거리 ${VIEW}, 최대 ${MAXP}명)"
tune() {  # key value — 있으면 교체, 없으면 추가
  local k="$1" v="$2"
  if grep -q "^${k}=" "$SERVER_DIR/server.properties"; then
    sed -i "s|^${k}=.*|${k}=${v}|" "$SERVER_DIR/server.properties"
  else
    echo "${k}=${v}" >> "$SERVER_DIR/server.properties"
  fi
}
tune view-distance "$VIEW"
tune simulation-distance "$SIM"
tune max-players "$MAXP"
tune network-compression-threshold 512
tune sync-chunk-writes false
tune spawn-protection 0
tune motd "Sunlit Valley"

# ------------------------------------------------------- 5. Forge 확보
cd "$SERVER_DIR"

# 서버 팩이 자체 실행 스크립트를 들고 오는 경우가 많다. 우리 start.sh 를 쓰기 전에
# 원본을 반드시 보존한다. (start.sh 를 목록에서 빠뜨려 원본을 날린 적이 있다)
for f in run.sh startserver.sh start-server.sh ServerStart.sh start.sh; do
  if [[ -f "$f" && ! -e "${f}.orig" ]]; then
    mv "$f" "${f}.orig"
    log "서버 팩의 ${f} 를 ${f}.orig 로 보존했습니다."
  fi
done

# Forge 설치 프로그램을 받아 서버를 구성한다.
#
# 설치 프로그램은 반드시 절대 경로로 다루고 root 로 실행한다. 상대 경로와
# 다른 계정(sudo -u)을 섞으면 작업 디렉터리나 권한 때문에 "Unable to access
# jarfile" 이 나는데, 그 메시지만으로는 원인을 가릴 수 없기 때문이다.
# 설치가 만들어낸 파일의 소유권은 스크립트 마지막의 chown -R 이 정리한다.
run_forge_installer() {   # $1 = 설치 프로그램 절대 경로
  local jar="$1"
  log "Forge를 설치합니다. 라이브러리를 여러 개 받으므로 3~10분 걸립니다."
  # headless 를 명시하지 않으면 화면 없는 서버에서 설치 프로그램이 창을 띄우려다 멈춘다.
  ( cd "$SERVER_DIR" && java -Djava.awt.headless=true -jar "$jar" --installServer ) || {
    warn "설치 프로그램 파일 상태:"
    ls -la "$jar" 2>&1 | sed 's/^/      /'
    file "$jar" 2>&1 | sed 's/^/      /'
    die "Forge 설치 실패. 위 출력을 확인하세요."
  }
  log "Forge 설치 완료."
}

fetch_forge() {   # $1 = 마인크래프트 버전, $2 = Forge 버전
  local mc="$1" fg="$2"
  local url="https://maven.minecraftforge.net/net/minecraftforge/forge/${mc}-${fg}/forge-${mc}-${fg}-installer.jar"
  local jar="$DL_DIR/forge-${mc}-${fg}-installer.jar"

  log "Forge ${mc}-${fg} 설치 프로그램을 내려받습니다."
  echo "      $url"
  curl -fL --progress-bar -o "$jar" "$url" \
    || die "Forge 설치 프로그램을 받지 못했습니다.
     주소: $url
     variables.txt 의 MODLOADER_VERSION(${fg}) 이 실제 존재하는 버전인지 확인하세요."

  # 받긴 받았는데 내용이 jar 가 아닌 경우(오류 페이지 등)를 여기서 걸러낸다.
  # jar 는 zip 이므로 목록을 읽을 수 있는지로 판정한다. file 의 설명 문구에
  # 의존하면 환경에 따라 표현이 달라져 멀쩡한 파일을 거부할 수 있다.
  [[ -s "$jar" ]] || die "받은 파일이 비어 있습니다: $jar"
  unzip -tq "$jar" >/dev/null 2>&1 \
    || die "받은 파일이 정상적인 jar 가 아닙니다: $(file -b "$jar")
     Forge 버전 ${fg} 이 존재하지 않아 오류 페이지를 받았을 수 있습니다."

  log "다운로드 완료: $(du -h "$jar" | cut -f1)"
  run_forge_installer "$jar"
}

if [[ -d libraries/net/minecraftforge ]]; then
  log "Forge가 이미 설치되어 있습니다."

elif compgen -G "forge-*-installer.jar" >/dev/null; then
  # 팩에 설치 프로그램이 동봉된 경우
  INSTALLER="$SERVER_DIR/$(ls forge-*-installer.jar | head -1)"
  log "동봉된 설치 프로그램을 사용합니다: $(basename "$INSTALLER")"
  run_forge_installer "$INSTALLER"

elif [[ -f variables.txt ]]; then
  # ServerPackCreator 로 만들어진 서버 팩. Forge 를 담지 않고 버전만 적어두고,
  # 팩의 실행 스크립트가 최초 구동 때 받아오는 구조다. 여기서 미리 설치해 둔다.
  # 윈도우 줄바꿈(CR)이 섞여 있는 경우가 많아 먼저 제거한다.
  getvar() { sed -n "s/\r\$//; s/^$1=//p" variables.txt | tr -d '"' | head -1; }
  MC_VER="$(getvar MINECRAFT_VERSION)"
  LOADER="$(getvar MODLOADER)"
  LOADER_VER="$(getvar MODLOADER_VERSION)"
  log "variables.txt 확인: 마인크래프트 ${MC_VER:-?}, ${LOADER:-?} ${LOADER_VER:-?}"

  if [[ "${LOADER,,}" == "forge" && -n "$MC_VER" && -n "$LOADER_VER" ]]; then
    fetch_forge "$MC_VER" "$LOADER_VER"
  else
    die "지원하지 않는 모드로더입니다: ${LOADER:-(없음)}. 이 스크립트는 Forge 전용입니다."
  fi

else
  die "Forge를 어떻게 설치해야 할지 판단하지 못했습니다.
     서버 폴더에 설치 프로그램도, variables.txt 도 없습니다.
     $SERVER_DIR 의 내용을 확인해 주세요."
fi

# Forge 1.20.1 은 unix_args.txt 방식으로 실행한다. 이게 있어야 정상 설치된 것.
#
# 주의: `set -e` + `pipefail` 아래에서 존재하지 않는 경로에 find 를 걸면 파이프라인이
# 실패 상태를 반환하고, 그 결과를 변수에 대입하는 순간 스크립트가 아무 메시지 없이
# 종료된다. 그래서 디렉터리 존재를 먼저 확인하고 `|| true` 로 막아둔다.
ARGS_FILE=""
if [[ -d libraries/net/minecraftforge ]]; then
  ARGS_FILE="$(find libraries/net/minecraftforge -name unix_args.txt 2>/dev/null | head -1 || true)"
fi

if [[ -n "$ARGS_FILE" ]]; then
  log "Forge 실행 파일을 확인했습니다: $ARGS_FILE"
else
  warn "Forge의 unix_args.txt 를 찾지 못했습니다."
  warn "서버 팩에 들어있는 jar 로 직접 실행하도록 설정합니다."
  # 무엇이 들어있는지 보여줘야 다음 조치를 판단할 수 있다.
  warn "현재 서버 폴더의 jar 목록:"
  ls -1 ./*.jar 2>/dev/null | sed 's/^/      /' || warn "      (jar 파일이 없습니다)"
fi

# ------------------------------------------------------------ 6. 시작 스크립트
# 힙 크기: 전체 RAM에서 OS + JVM 오프힙(메타스페이스/다이렉트 버퍼) 몫을 남긴다.
# 대형 모드팩은 오프힙만 1.5~2.5GB를 쓰기 때문에 이걸 안 빼면 OOM Kill이 난다.
# 여유분을 고정값으로 두면 8GB 서버에서 힙이 너무 작아지므로 사양별로 다르게 잡는다.
# 경계값은 실제 보고되는 값 기준이다. "12GB" 인스턴스는 펌웨어 예약분 때문에
# MemTotal 이 11,800MB 안팎으로 잡히므로 12000 이 아니라 10000 으로 나눈다.
if   (( TOTAL_MB >= 10000 )); then RESERVE=3584   # OCI 12GB 급
elif (( TOTAL_MB >= 7000  )); then RESERVE=2400   # AWS 8GB 급
else                               RESERVE=2048
fi
HEAP_MB=$(( TOTAL_MB - RESERVE ))
(( HEAP_MB > 10240 )) && HEAP_MB=10240
(( HEAP_MB < 3072 ))  && HEAP_MB=3072
HEAP="${HEAP_MB}M"
log "힙 크기를 ${HEAP} 로 정했습니다. (전체 RAM ${TOTAL_MB}MB)"
if (( HEAP_MB < 6144 )); then
  warn "힙이 권장치(6~7GB)보다 작습니다. 위에서 시야거리와 인원을 낮춰뒀습니다."
  warn "렉이 심하면 /etc/... 대신 server.properties 의 view-distance 를 5로 더 낮추세요."
fi

# Aikar's flags — 12GB 미만 힙용 파라미터 세트
cat > "$SERVER_DIR/start.sh" <<EOF
#!/usr/bin/env bash
set -e
cd "\$(dirname "\$0")"

HEAP="\${MC_HEAP:-${HEAP}}"

JVM_FLAGS=(
  -Xms"\$HEAP" -Xmx"\$HEAP"
  -XX:+UseG1GC
  -XX:+ParallelRefProcEnabled
  -XX:MaxGCPauseMillis=200
  -XX:+UnlockExperimentalVMOptions
  -XX:+DisableExplicitGC
  -XX:+AlwaysPreTouch
  -XX:G1NewSizePercent=30
  -XX:G1MaxNewSizePercent=40
  -XX:G1HeapRegionSize=8M
  -XX:G1ReservePercent=20
  -XX:G1HeapWastePercent=5
  -XX:G1MixedGCCountTarget=4
  -XX:InitiatingHeapOccupancyPercent=15
  -XX:G1MixedGCLiveThresholdPercent=90
  -XX:G1RSetUpdatingPauseTimePercent=5
  -XX:SurvivorRatio=32
  -XX:+PerfDisableSharedMem
  -XX:MaxTenuringThreshold=1
  -Dusing.aikars.flags=https://mcflags.emc.gs
  -Daikars.new.flags=true
  -Dfile.encoding=UTF-8
)

# set -e 아래에서는 find/ls 실패가 그대로 스크립트 종료로 이어지므로 || true 로 막는다.
ARGS_FILE=""
if [[ -d libraries/net/minecraftforge ]]; then
  ARGS_FILE="\$(find libraries/net/minecraftforge -name unix_args.txt 2>/dev/null | head -1 || true)"
fi

if [[ -n "\$ARGS_FILE" ]]; then
  exec java "\${JVM_FLAGS[@]}" @"\$ARGS_FILE" nogui
fi

JAR="\$(ls minecraft_server*.jar forge-*.jar server.jar 2>/dev/null | grep -v installer | head -1 || true)"
if [[ -z "\$JAR" ]]; then
  echo "실행할 jar를 찾지 못했습니다. 서버 폴더의 내용:" >&2
  ls -1 >&2
  exit 1
fi
exec java "\${JVM_FLAGS[@]}" -jar "\$JAR" nogui
EOF
chmod +x "$SERVER_DIR/start.sh"

# 팩의 실행 스크립트는 위 5단계에서 이미 .orig 로 보존해 두었다.

log "파일 소유권을 정리합니다. (파일이 많아 1~2분 걸릴 수 있습니다)"
chown -R "$MC_USER:$MC_USER" "$MC_HOME"

# ------------------------------------------------------------------- 마무리
systemctl daemon-reload
systemctl enable minecraft >/dev/null 2>&1 || true

PUBLIC_IP="$(curl -s --max-time 5 https://ifconfig.me || echo '서버IP')"
printf '
\033[1;32m==================== 설치 완료 ====================\033[0m

  서버 경로 : %s
  힙 크기   : %s

  서버 시작 :  sudo mcctl start
  콘솔 보기 :  sudo mcctl console      (빠져나올 때 Ctrl+B 누른 뒤 D)
  상태 확인 :  sudo mcctl status

  \033[1;33m첫 실행은 월드 생성 때문에 5~15분 걸립니다.\033[0m 콘솔에 "Done" 이 뜨면 완료입니다.

  마크 클라이언트에서 접속할 주소:
      %s:25565

' "$SERVER_DIR" "$HEAP" "$PUBLIC_IP"
