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

if [[ ! -f "$SERVER_DIR/server.properties" ]]; then
  log "server.properties 를 2 OCPU 환경에 맞춰 생성합니다."
  cp "$(dirname "${BASH_SOURCE[0]}")/../config/server.properties" "$SERVER_DIR/server.properties"
else
  log "기존 server.properties 를 저사양 서버에 맞게 조정합니다."
  tune() {  # key value — 있으면 교체, 없으면 추가
    local k="$1" v="$2"
    if grep -q "^${k}=" "$SERVER_DIR/server.properties"; then
      sed -i "s|^${k}=.*|${k}=${v}|" "$SERVER_DIR/server.properties"
    else
      echo "${k}=${v}" >> "$SERVER_DIR/server.properties"
    fi
  }
  # 2코어 ARM에서 청크 생성이 가장 무겁다. 시야거리를 줄이는 게 체감 효과가 제일 크다.
  tune view-distance 8
  tune simulation-distance 6
  tune max-players 6
  tune network-compression-threshold 512
  tune sync-chunk-writes false
  tune spawn-protection 0
  tune motd "Sunlit Valley - OCI"
fi

# ------------------------------------------------------- 5. Forge 설치 여부 확인
cd "$SERVER_DIR"
if compgen -G "forge-*-installer.jar" >/dev/null && [[ ! -d "libraries/net/minecraftforge" ]]; then
  INSTALLER="$(ls forge-*-installer.jar | head -1)"
  log "Forge를 설치합니다: $INSTALLER (3~5분 걸립니다)"
  sudo -u "$MC_USER" java -jar "$INSTALLER" --installServer >/dev/null \
    || die "Forge 설치 실패. $SERVER_DIR/*.log 를 확인하세요."
  rm -f "$INSTALLER" "${INSTALLER}.log"
fi

# Forge 1.20.1 은 unix_args.txt 방식으로 실행한다. 이게 있어야 정상 설치된 것.
ARGS_FILE="$(find libraries/net/minecraftforge -name unix_args.txt 2>/dev/null | head -1)"
if [[ -z "$ARGS_FILE" ]]; then
  warn "unix_args.txt 를 못 찾았습니다. 서버 팩에 포함된 자체 실행 스크립트로 대체합니다."
fi

# ------------------------------------------------------------ 6. 시작 스크립트
# 힙 크기: 전체 RAM에서 OS + JVM 오프힙(메타스페이스/다이렉트 버퍼) 몫으로 3.5GB를 남긴다.
# 대형 모드팩은 오프힙만 1.5~2.5GB를 쓰기 때문에 이걸 안 빼면 OOM Kill이 난다.
TOTAL_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
HEAP_MB=$(( TOTAL_MB - 3584 ))
(( HEAP_MB > 10240 )) && HEAP_MB=10240
(( HEAP_MB < 4096 ))  && HEAP_MB=4096
HEAP="${HEAP_MB}M"
log "힙 크기를 ${HEAP} 로 정했습니다. (전체 RAM ${TOTAL_MB}MB)"
if (( HEAP_MB <= 4096 && TOTAL_MB < 10000 )); then
  warn "이 RAM으로는 힙이 권장치(6~7GB)에 못 미칩니다. 접속자가 늘면 불안정할 수 있습니다."
  warn "시야거리를 5 이하로 낮추고 인원을 2~3명으로 제한해서 쓰세요."
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

ARGS_FILE="\$(find libraries/net/minecraftforge -name unix_args.txt 2>/dev/null | head -1)"
if [[ -n "\$ARGS_FILE" ]]; then
  exec java "\${JVM_FLAGS[@]}" @"\$ARGS_FILE" nogui
else
  JAR="\$(ls minecraft_server*.jar forge-*.jar server.jar 2>/dev/null | grep -v installer | head -1)"
  [[ -n "\$JAR" ]] || { echo "실행할 jar를 찾지 못했습니다."; exit 1; }
  exec java "\${JVM_FLAGS[@]}" -jar "\$JAR" nogui
fi
EOF
chmod +x "$SERVER_DIR/start.sh"

# 서버 팩이 들고 온 자체 실행 스크립트는 힙 설정이 우리와 충돌하므로 비켜둔다.
for f in run.sh startserver.sh start-server.sh ServerStart.sh; do
  [[ -f "$SERVER_DIR/$f" ]] && mv "$SERVER_DIR/$f" "$SERVER_DIR/${f}.orig"
done

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
