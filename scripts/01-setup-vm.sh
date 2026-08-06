#!/usr/bin/env bash
#
# 01-setup-vm.sh — OCI Ampere A1(ARM64) 우분투 인스턴스를 마인크래프트 서버용으로 준비한다.
#
# 하는 일:
#   1. 패키지 업데이트 + Java 17 / tmux / unzip 설치
#   2. minecraft 전용 사용자 + /opt/minecraft 디렉터리 생성
#   3. 스왑 파일 생성 (RAM 부족 시 OOM Kill 방지용 안전망)
#   4. 방화벽 25565 개방 (OCI 우분투 이미지의 iptables DROP 정책이 최대 함정)
#   5. 파일 디스크립터 상한 상향
#   6. systemd 유닛 + 백업 타이머 설치
#
# 사용법:  sudo bash 01-setup-vm.sh
#
set -euo pipefail

MC_USER="minecraft"
MC_HOME="/opt/minecraft"
MC_PORT="${MC_PORT:-25565}"
SWAP_SIZE="${SWAP_SIZE:-4G}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log()  { printf '\033[1;36m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "root로 실행해야 합니다:  sudo bash $0"

# ---------------------------------------------------------------- 0. 환경 점검
log "환경을 확인합니다."
ARCH="$(uname -m)"
TOTAL_MB="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
CPUS="$(nproc)"
echo "    아키텍처 : $ARCH"
echo "    CPU      : ${CPUS} 코어"
echo "    RAM      : ${TOTAL_MB} MB"

if [[ "$ARCH" != "aarch64" && "$ARCH" != "x86_64" ]]; then
  die "지원하지 않는 아키텍처입니다: $ARCH"
fi
if (( TOTAL_MB < 10000 )); then
  # 선릿밸리는 힙만 6~7GB를 요구하고, 대형 모드팩은 힙 바깥에서만 1.5~2.5GB를 더 쓴다.
  # 여기에 OS 몫까지 더하면 실질적으로 10GB 미만에서는 안정적으로 돌지 않는다.
  warn "RAM이 ${TOTAL_MB}MB 입니다. 선릿밸리는 12GB를 권장합니다."
  warn "(힙 6~7GB + JVM 오프힙 1.5~2.5GB + OS 1GB)"
  warn "OCI 무료 티어 최대치인 2 OCPU / 12GB 로 다시 만드는 것을 권합니다."
  read -rp "    그래도 계속할까요? [y/N] " ans
  [[ "${ans,,}" == "y" ]] || exit 1
fi
if (( CPUS < 2 )); then
  warn "CPU가 ${CPUS}코어입니다. 대형 모드팩에는 최소 2코어가 필요합니다."
fi

command -v apt-get >/dev/null || die "이 스크립트는 우분투(Ubuntu) 전용입니다. OCI 인스턴스 생성 시 이미지를 Ubuntu로 선택하세요."

# ------------------------------------------------------------- 1. 패키지 설치
log "패키지를 설치합니다. (2~3분 걸립니다)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# 마인크래프트 1.20.1 은 Java 17 이 정확한 요구사항이다. 21로 올리면 일부 모드가 깨진다.
apt-get install -y -qq \
  openjdk-17-jre-headless \
  tmux unzip curl jq rsync ca-certificates iptables-persistent >/dev/null

JAVA_BIN="$(readlink -f /usr/bin/java)"
log "Java 설치 완료: $(java -version 2>&1 | head -1)"

# ------------------------------------------------------------ 2. 사용자/디렉터리
if ! id -u "$MC_USER" >/dev/null 2>&1; then
  log "'$MC_USER' 사용자를 만듭니다."
  useradd -r -m -d "$MC_HOME" -s /bin/bash "$MC_USER"
else
  log "'$MC_USER' 사용자가 이미 있습니다."
fi
mkdir -p "$MC_HOME/server" "$MC_HOME/backups" "$MC_HOME/downloads"
chown -R "$MC_USER:$MC_USER" "$MC_HOME"

# ------------------------------------------------------------------- 3. 스왑
if swapon --show | grep -q '/swapfile'; then
  log "스왑이 이미 설정되어 있습니다."
else
  log "${SWAP_SIZE} 스왑 파일을 만듭니다. (RAM이 순간적으로 넘칠 때 서버가 죽는 걸 막아줍니다)"
  fallocate -l "$SWAP_SIZE" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096 status=none
  chmod 600 /swapfile
  mkswap -q /swapfile
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
# 스왑은 어디까지나 비상용이다. 평소에 스왑을 쓰면 TPS가 바닥나므로 최대한 늦게 쓰게 만든다.
sysctl -qw vm.swappiness=10
grep -q '^vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf

# ----------------------------------------------------------------- 4. 방화벽
# OCI 우분투 이미지는 INPUT 체인 기본 정책이 사실상 DROP 이다.
# 클라우드 콘솔의 '보안 목록'만 열고 여기를 안 열어서 접속이 안 되는 경우가 압도적으로 많다.
log "인스턴스 내부 방화벽에서 ${MC_PORT} 포트를 엽니다."
open_port() {
  local proto="$1"
  if ! iptables -C INPUT -p "$proto" --dport "$MC_PORT" -j ACCEPT 2>/dev/null; then
    # REJECT 규칙보다 반드시 앞에 와야 하므로 INPUT 체인 맨 앞에 삽입한다.
    iptables -I INPUT 1 -p "$proto" --dport "$MC_PORT" -m comment --comment "minecraft" -j ACCEPT
  fi
}
open_port tcp
open_port udp   # Bedrock 연동이나 LAN 검색용. 열어둬도 손해 없다.
netfilter-persistent save >/dev/null 2>&1 || iptables-save > /etc/iptables/rules.v4

if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q '^Status: active'; then
  log "ufw가 활성 상태라 여기도 함께 엽니다."
  ufw allow "${MC_PORT}/tcp" >/dev/null
  ufw allow "${MC_PORT}/udp" >/dev/null
fi

# ------------------------------------------------------------- 5. 파일 핸들 상한
if [[ ! -f /etc/security/limits.d/minecraft.conf ]]; then
  log "파일 디스크립터 상한을 올립니다."
  cat > /etc/security/limits.d/minecraft.conf <<EOF
${MC_USER} soft nofile 65536
${MC_USER} hard nofile 65536
EOF
fi

# --------------------------------------------------------- 6. systemd 유닛 설치
log "systemd 서비스와 백업 타이머를 설치합니다."
install -m 0644 "$REPO_DIR/config/minecraft.service"      /etc/systemd/system/minecraft.service
install -m 0644 "$REPO_DIR/config/minecraft-backup.service" /etc/systemd/system/minecraft-backup.service
install -m 0644 "$REPO_DIR/config/minecraft-backup.timer"   /etc/systemd/system/minecraft-backup.timer

install -m 0755 "$REPO_DIR/scripts/backup.sh"          "$MC_HOME/backup.sh"
install -m 0755 "$REPO_DIR/scripts/mcctl"              /usr/local/bin/mcctl
chown "$MC_USER:$MC_USER" "$MC_HOME/backup.sh"

systemctl daemon-reload
systemctl enable minecraft-backup.timer >/dev/null 2>&1 || true
systemctl start  minecraft-backup.timer >/dev/null 2>&1 || true

# ------------------------------------------------------------------- 마무리
PUBLIC_IP="$(curl -s --max-time 5 https://ifconfig.me || echo '(확인 실패)')"
printf '
\033[1;32m==================== VM 준비 완료 ====================\033[0m

  공인 IP     : %s
  서버 경로   : %s/server
  포트        : %s (인스턴스 방화벽 개방 완료)

  \033[1;33m아직 OCI 웹 콘솔의 "보안 목록"은 열리지 않았습니다.\033[0m
  docs/03-network.md 를 보고 인그레스 규칙을 추가하세요. 둘 다 열려야 접속됩니다.

  다음 단계:
      sudo bash scripts/02-install-modpack.sh

' "$PUBLIC_IP" "$MC_HOME" "$MC_PORT"
