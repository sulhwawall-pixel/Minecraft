#!/usr/bin/env bash
#
# backup.sh — 월드를 안전하게 tar.gz 로 백업하고 오래된 백업을 정리한다.
#
# 서버가 켜져 있으면 save-off → save-all 로 디스크에 확정시킨 뒤 복사하고,
# 복사가 끝나면 save-on 으로 되돌린다. 이 과정을 건너뛰면 저장 도중 스냅샷이
# 찍혀 청크가 깨진 백업이 만들어질 수 있다.
#
set -euo pipefail

SERVER_DIR="/opt/minecraft/server"
BACKUP_DIR="/opt/minecraft/backups"
KEEP_DAYS="${KEEP_DAYS:-7}"
TMUX="tmux -L minecraft"

mkdir -p "$BACKUP_DIR"
cd "$SERVER_DIR"

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$BACKUP_DIR/world-$STAMP.tar.gz"

server_running() { $TMUX has-session -t mc 2>/dev/null; }
send() { $TMUX send-keys -t mc "$1" Enter 2>/dev/null || true; }

WAS_RUNNING=0
if server_running; then
  WAS_RUNNING=1
  echo "[+] 서버가 실행 중입니다. 저장을 잠시 멈춥니다."
  send "save-off"
  send "save-all flush"
  sleep 15   # save-all flush 가 끝날 시간을 준다
fi

# 백업 대상: 월드 + 설정. mods/ 와 libraries/ 는 서버 팩에서 다시 받으면 되므로 제외한다.
TARGETS=()
for d in world world_nether world_the_end; do
  [[ -d "$d" ]] && TARGETS+=("$d")
done
for f in server.properties ops.json whitelist.json banned-players.json banned-ips.json; do
  [[ -f "$f" ]] && TARGETS+=("$f")
done
[[ -d config ]] && TARGETS+=("config")

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "[x] 백업할 대상이 없습니다." >&2
  (( WAS_RUNNING )) && send "save-on"
  exit 1
fi

echo "[+] 백업 생성: $OUT"
tar -czf "$OUT" "${TARGETS[@]}"

if (( WAS_RUNNING )); then
  send "save-on"
  send "say 백업 완료"
  echo "[+] 저장을 다시 켰습니다."
fi

echo "[+] ${KEEP_DAYS}일 지난 백업을 정리합니다."
find "$BACKUP_DIR" -name 'world-*.tar.gz' -mtime "+${KEEP_DAYS}" -delete

echo "[+] 완료: $(du -h "$OUT" | cut -f1)  (전체 $(du -sh "$BACKUP_DIR" | cut -f1))"
