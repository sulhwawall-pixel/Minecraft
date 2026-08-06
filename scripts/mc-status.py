#!/usr/bin/env python3
"""
mc-status.py — 마인크래프트 서버에 접속자 수를 물어본다.

서버 목록에 표시되는 정보를 가져오는 표준 프로토콜(Server List Ping)을 그대로 쓴다.
RCON을 켜거나 로그를 긁을 필요가 없고, 서버가 살아있는지도 함께 확인된다.

사용법:
    mc-status.py [host] [port]          사람이 읽는 형태로 출력
    mc-status.py --players-only         접속자 수만 출력 (스크립트용)
    mc-status.py --json                 원본 JSON 출력

종료 코드:
    0  서버 응답함
    1  서버가 응답하지 않음 (꺼져 있거나 아직 로딩 중)
"""
import json
import socket
import struct
import sys

TIMEOUT = 5.0
# 상태 조회는 프로토콜 버전을 검사하지 않으므로 어떤 값이든 통한다.
PROTOCOL_VERSION = 763  # 1.20.1


def encode_varint(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def read_varint(sock: socket.socket) -> int:
    result = 0
    for shift in range(0, 35, 7):
        chunk = sock.recv(1)
        if not chunk:
            raise EOFError("연결이 끊겼습니다")
        byte = chunk[0]
        result |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return result
    raise ValueError("varint가 너무 깁니다")


def read_exactly(sock: socket.socket, count: int) -> bytes:
    buf = bytearray()
    while len(buf) < count:
        chunk = sock.recv(count - len(buf))
        if not chunk:
            raise EOFError("응답이 중간에 끊겼습니다")
        buf += chunk
    return bytes(buf)


def query(host: str, port: int) -> dict:
    with socket.create_connection((host, port), TIMEOUT) as sock:
        sock.settimeout(TIMEOUT)

        addr = host.encode("utf-8")
        handshake = (
            b"\x00"
            + encode_varint(PROTOCOL_VERSION)
            + encode_varint(len(addr))
            + addr
            + struct.pack(">H", port)
            + encode_varint(1)          # next state: status
        )
        sock.sendall(encode_varint(len(handshake)) + handshake)
        sock.sendall(encode_varint(1) + b"\x00")   # status request

        read_varint(sock)               # 패킷 전체 길이 (쓰지 않음)
        if read_varint(sock) != 0:
            raise ValueError("예상과 다른 패킷 ID")
        payload = read_exactly(sock, read_varint(sock))
        return json.loads(payload.decode("utf-8", errors="replace"))


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}

    host = args[0] if args else "127.0.0.1"
    port = int(args[1]) if len(args) > 1 else 25565

    try:
        data = query(host, port)
    except Exception as exc:
        if "--players-only" in flags:
            print("-1")
        else:
            print(f"서버가 응답하지 않습니다: {exc}", file=sys.stderr)
        return 1

    players = data.get("players", {})
    online = players.get("online", 0)

    if "--json" in flags:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    elif "--players-only" in flags:
        print(online)
    else:
        version = data.get("version", {}).get("name", "?")
        print(f"버전     : {version}")
        print(f"접속자   : {online} / {players.get('max', '?')}")
        for entry in players.get("sample", []) or []:
            print(f"  - {entry.get('name')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
