"""
start_server.py — 마인크래프트 서버를 켜는 Lambda 함수.

Lambda 함수 URL로 만들어두면 폰 브라우저에서 링크만 눌러 서버를 켤 수 있다.
PC를 켤 필요도, AWS 콘솔에 로그인할 필요도 없다. 친구들에게 링크를 공유하면
누구나 서버를 켤 수 있다.

환경 변수:
    INSTANCE_ID   시작할 EC2 인스턴스 ID (예: i-0abc123...)   [필수]
    SECRET        URL에 ?key=... 로 넘길 공유 암호            [필수]
    HOSTNAME      안내에 표시할 접속 주소 (예: myserver.duckdns.org)  [선택]

Lambda는 상시 무료 사용량(월 100만 요청)에 들어가므로 사실상 요금이 없다.
"""
import json
import os

import boto3

ec2 = boto3.client("ec2")

INSTANCE_ID = os.environ["INSTANCE_ID"]
SECRET = os.environ["SECRET"]
HOSTNAME = os.environ.get("HOSTNAME", "")

# 서버 시작 후 모드팩 로딩까지 걸리는 대략적인 시간
BOOT_HINT = "모드가 많아 접속까지 3~5분 정도 걸립니다."


def _page(title: str, body: str, status: int = 200) -> dict:
    """폰에서 보기 좋은 아주 단순한 HTML 응답."""
    address = f"<p class='addr'>{HOSTNAME}</p>" if HOSTNAME else ""
    html = f"""<!doctype html>
<html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>마인크래프트 서버</title>
<style>
  body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
         max-width: 30rem; margin: 3rem auto; padding: 0 1.5rem; line-height: 1.7;
         background: #12151a; color: #e6e6e6; }}
  h1 {{ font-size: 1.4rem; }}
  .addr {{ background: #1e2530; padding: .8rem 1rem; border-radius: .5rem;
          font-family: ui-monospace, monospace; font-size: 1.1rem; }}
  .muted {{ color: #9aa4b2; font-size: .95rem; }}
</style></head>
<body><h1>{title}</h1><p>{body}</p>{address}
<p class="muted">{BOOT_HINT}</p></body></html>"""
    return {
        "statusCode": status,
        "headers": {"Content-Type": "text/html; charset=utf-8"},
        "body": html,
    }


def lambda_handler(event, context):
    # 함수 URL은 인증 없이 공개되므로, 최소한의 보호로 공유 암호를 확인한다.
    params = (event.get("queryStringParameters") or {})
    if params.get("key") != SECRET:
        return _page("접근할 수 없습니다", "링크가 올바르지 않습니다.", 403)

    state = ec2.describe_instances(InstanceIds=[INSTANCE_ID])
    instance = state["Reservations"][0]["Instances"][0]
    name = instance["State"]["Name"]

    if name == "running":
        return _page("이미 켜져 있습니다", "바로 접속하시면 됩니다.")

    if name in ("pending", "stopping"):
        return _page("처리 중입니다", f"현재 상태: {name}. 잠시 후 다시 확인해 주세요.")

    if name != "stopped":
        return _page("지금은 켤 수 없습니다", f"현재 상태: {name}", 409)

    ec2.start_instances(InstanceIds=[INSTANCE_ID])
    return _page("서버를 켰습니다", "곧 접속할 수 있습니다.")
