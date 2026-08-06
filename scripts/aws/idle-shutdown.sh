#!/usr/bin/env bash
#
# idle-shutdown.sh — 접속자가 일정 시간 없으면 인스턴스를 자동으로 정지시킨다.
#
# AWS 크레딧을 아끼는 핵심 장치다. 이게 없으면 자고 있는 동안에도 요금이 나간다.
# 5분마다 타이머가 이 스크립트를 실행한다.
#
# 동작:
#   1. 부팅 직후 GRACE_MINUTES 동안은 아무것도 하지 않는다 (서버 로딩 시간 확보)
#   2. 서버에 접속자 수를 물어본다
#   3. 0명인 상태가 IDLE_CHECKS 번 연속되면 월드를 저장하고 인스턴스를 정지한다
#
# 설정은 /etc/minecraft-idle.conf 에서 바꿀 수 있다.
#
set -euo pipefail

CONF="/etc/minecraft-idle.conf"
# shellcheck disable=SC1090
[[ -f "$CONF" ]] && source "$CONF"

GRACE_MINUTES="${GRACE_MINUTES:-20}"      # 부팅 후 유예 시간
IDLE_CHECKS="${IDLE_CHECKS:-6}"           # 5분 × 6 = 30분간 비어 있으면 종료
PORT="${PORT:-25565}"
STATE="/run/minecraft-idle.count"
STATUS_BIN="/opt/minecraft/mc-status.py"

log() { logger -t mc-idle "$*"; echo "$*"; }

# ── 1. 부팅 직후에는 건드리지 않는다 ────────────────────────────────────
UPTIME_MIN=$(awk '{print int($1/60)}' /proc/uptime)
if (( UPTIME_MIN < GRACE_MINUTES )); then
  log "부팅 후 ${UPTIME_MIN}분 경과. ${GRACE_MINUTES}분까지는 대기합니다."
  exit 0
fi

# ── 2. 접속자 수 조회 ──────────────────────────────────────────────────
# -1 은 서버가 응답하지 않는다는 뜻. 유예 시간이 지났는데도 응답이 없으면
# 서버가 죽은 것이므로, 요금이 새지 않게 그대로 종료 대상으로 센다.
PLAYERS="$("$STATUS_BIN" 127.0.0.1 "$PORT" --players-only 2>/dev/null || echo -1)"

if [[ "$PLAYERS" =~ ^[0-9]+$ ]] && (( PLAYERS > 0 )); then
  [[ -f "$STATE" ]] && rm -f "$STATE"
  log "접속자 ${PLAYERS}명. 계속 실행합니다."
  exit 0
fi

# ── 3. 비어 있는 횟수를 센다 ───────────────────────────────────────────
COUNT=$(( $(cat "$STATE" 2>/dev/null || echo 0) + 1 ))
echo "$COUNT" > "$STATE"

if (( PLAYERS == -1 )); then
  log "서버가 응답하지 않습니다 (${COUNT}/${IDLE_CHECKS})."
else
  log "접속자 없음 (${COUNT}/${IDLE_CHECKS})."
fi

if (( COUNT < IDLE_CHECKS )); then
  exit 0
fi

# ── 4. 안전하게 정지 ───────────────────────────────────────────────────
log "유휴 상태가 이어져 인스턴스를 정지합니다."
rm -f "$STATE"

# 월드를 확실히 저장한 뒤 내린다. systemd 종료 순서에 맡기지 않고 직접 부른다.
if systemctl is-active --quiet minecraft; then
  log "마인크래프트 서버를 정지하는 중..."
  systemctl stop minecraft || log "서버 정지에 실패했습니다. 그래도 종료를 진행합니다."
fi

# EC2 인스턴스의 '종료 동작(Shutdown behavior)'이 Stop 이어야 여기서 인스턴스가
# 정지된다. Terminate 로 되어 있으면 인스턴스가 삭제되므로 반드시 확인할 것.
log "시스템을 종료합니다."
/sbin/shutdown -h now "유휴 상태로 인한 자동 종료"
