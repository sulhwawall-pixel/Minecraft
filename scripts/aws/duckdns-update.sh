#!/usr/bin/env bash
#
# duckdns-update.sh — 현재 공인 IP를 DuckDNS에 등록한다.
#
# EC2 인스턴스를 정지했다 켜면 공인 IP가 매번 바뀐다. 탄력적 IP(Elastic IP)를
# 잡아두면 고정되지만 꺼둔 시간에도 요금이 나가므로, 무료인 DuckDNS로
# 주소를 고정하는 편이 낫다.
#
# 부팅할 때 한 번, 그리고 5분마다 실행된다.
#
set -euo pipefail

CONF="/etc/duckdns.conf"
[[ -f "$CONF" ]] || { echo "설정 파일이 없습니다: $CONF" >&2; exit 1; }
# shellcheck disable=SC1090
source "$CONF"   # DUCKDNS_DOMAIN, DUCKDNS_TOKEN

: "${DUCKDNS_DOMAIN:?DUCKDNS_DOMAIN 이 설정되지 않았습니다}"
: "${DUCKDNS_TOKEN:?DUCKDNS_TOKEN 이 설정되지 않았습니다}"

log() { logger -t duckdns "$*"; echo "$*"; }

# EC2 인스턴스 메타데이터(IMDSv2)에서 공인 IP를 읽는다. 외부 사이트에 묻는 것보다
# 빠르고 확실하다. 실패하면 외부 조회로 넘어간다.
IP=""
TOKEN="$(curl -sS --max-time 3 -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)"
if [[ -n "$TOKEN" ]]; then
  IP="$(curl -sS --max-time 3 -H "X-aws-ec2-metadata-token: $TOKEN" \
    "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || true)"
fi
[[ -z "$IP" ]] && IP="$(curl -sS --max-time 5 https://ifconfig.me 2>/dev/null || true)"
[[ -n "$IP" ]] || { log "공인 IP를 확인하지 못했습니다."; exit 1; }

RESULT="$(curl -sS --max-time 10 \
  "https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip=${IP}")"

if [[ "$RESULT" == "OK" ]]; then
  log "${DUCKDNS_DOMAIN}.duckdns.org -> ${IP} 갱신 완료"
else
  log "갱신 실패 (응답: ${RESULT}). 도메인과 토큰을 확인하세요."
  exit 1
fi
