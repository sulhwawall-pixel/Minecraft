#!/usr/bin/env bash
#
# install-cost-savers.sh — AWS에서 크레딧을 아끼기 위한 장치를 설치한다.
#
#   1. 유휴 자동 종료 — 아무도 없으면 인스턴스를 스스로 정지시킨다
#   2. DuckDNS 자동 갱신 — 켤 때마다 바뀌는 공인 IP를 고정 주소로 덮어준다
#
# 사용법:  sudo bash install-cost-savers.sh
#
set -euo pipefail

MC_HOME="/opt/minecraft"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log()  { printf '\033[1;36m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "root로 실행해야 합니다:  sudo bash $0"
[[ -d "$MC_HOME" ]] || die "먼저 scripts/01-setup-vm.sh 를 실행하세요."

# ─────────────────────────────────────────── 1. 유휴 자동 종료
log "유휴 자동 종료를 설치합니다."
install -m 0755 "$REPO_DIR/scripts/mc-status.py"          "$MC_HOME/mc-status.py"
install -m 0755 "$REPO_DIR/scripts/aws/idle-shutdown.sh"  "$MC_HOME/idle-shutdown.sh"
install -m 0644 "$REPO_DIR/config/aws/minecraft-idle-shutdown.service" /etc/systemd/system/
install -m 0644 "$REPO_DIR/config/aws/minecraft-idle-shutdown.timer"   /etc/systemd/system/

if [[ ! -f /etc/minecraft-idle.conf ]]; then
  cat > /etc/minecraft-idle.conf <<'EOF'
# 유휴 자동 종료 설정
# 부팅 후 이 시간(분) 동안은 종료하지 않는다. 모드팩 로딩 시간을 감안한 값.
GRACE_MINUTES=20
# 5분마다 검사한다. 6 = 30분간 아무도 없으면 종료.
IDLE_CHECKS=6
PORT=25565
EOF
  log "설정 파일 생성: /etc/minecraft-idle.conf"
fi

systemctl daemon-reload
systemctl enable --now minecraft-idle-shutdown.timer >/dev/null
log "유휴 종료 타이머가 켜졌습니다. (30분간 접속자 없으면 인스턴스 정지)"

# ─────────────────────────────────────────── 2. DuckDNS
echo
log "DuckDNS로 접속 주소를 고정하면 IP가 바뀌어도 친구들이 같은 주소로 들어옵니다."
echo "    https://www.duckdns.org 에서 구글 로그인 후 도메인을 하나 만드세요."
echo "    (건너뛰려면 그냥 Enter)"
echo
read -rp "    도메인 이름 (예: my-sunlit  ← .duckdns.org 앞부분만): " DOMAIN

if [[ -n "$DOMAIN" ]]; then
  # DuckDNS API 는 .duckdns.org 앞부분만 받는다. 전체 주소를 붙여넣는 실수가
  # 잦아서 프로토콜과 도메인 꼬리를 여기서 정리한다.
  ORIG_DOMAIN="$DOMAIN"
  DOMAIN="${DOMAIN#http://}"
  DOMAIN="${DOMAIN#https://}"
  DOMAIN="${DOMAIN%%/*}"
  DOMAIN="${DOMAIN%%.duckdns.org*}"
  [[ "$DOMAIN" == "$ORIG_DOMAIN" ]] || warn "'${ORIG_DOMAIN}' 를 '${DOMAIN}' 로 정리했습니다."
  [[ -n "$DOMAIN" ]] || die "도메인 이름을 알아보지 못했습니다: $ORIG_DOMAIN"
  read -rp "    토큰 (DuckDNS 페이지 상단의 token): " TOKEN
  [[ -n "$TOKEN" ]] || die "토큰이 필요합니다."

  # 토큰이 들어 있으므로 소유자만 읽을 수 있게 잠근다.
  umask 077
  cat > /etc/duckdns.conf <<EOF
DUCKDNS_DOMAIN=${DOMAIN}
DUCKDNS_TOKEN=${TOKEN}
EOF
  umask 022
  chmod 600 /etc/duckdns.conf

  install -m 0755 "$REPO_DIR/scripts/aws/duckdns-update.sh" "$MC_HOME/duckdns-update.sh"
  install -m 0644 "$REPO_DIR/config/aws/duckdns.service" /etc/systemd/system/
  install -m 0644 "$REPO_DIR/config/aws/duckdns.timer"   /etc/systemd/system/

  systemctl daemon-reload
  systemctl enable duckdns.service >/dev/null
  systemctl enable --now duckdns.timer >/dev/null

  log "첫 갱신을 시도합니다..."
  if "$MC_HOME/duckdns-update.sh"; then
    log "접속 주소: ${DOMAIN}.duckdns.org"
  else
    warn "갱신에 실패했습니다. 도메인과 토큰을 다시 확인하세요."
    warn "설정 파일: /etc/duckdns.conf"
  fi
else
  warn "DuckDNS를 건너뛰었습니다. 인스턴스를 껐다 켤 때마다 IP가 바뀝니다."
fi

# ─────────────────────────────────────────── 마무리
printf '
\033[1;32m==================== 설치 완료 ====================\033[0m

  유휴 자동 종료 : 30분간 접속자가 없으면 인스턴스가 스스로 정지합니다
  상태 확인      : systemctl list-timers minecraft-idle-shutdown.timer
  동작 로그      : journalctl -t mc-idle -n 30
  설정 변경      : sudo nano /etc/minecraft-idle.conf

  \033[1;33m⚠ EC2 인스턴스의 "종료 동작(Shutdown behavior)"이 반드시\033[0m
  \033[1;33m  "중지(Stop)" 여야 합니다. "종료(Terminate)" 면 인스턴스가 삭제됩니다.\033[0m
  확인: EC2 콘솔 → 인스턴스 선택 → 작업 → 인스턴스 설정 → 종료 동작 변경

  서버를 다시 켜는 방법은 docs/aws/02-auto-onoff.md 를 보세요.

'
