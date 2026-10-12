"""An interactive, role-specific view of the local Orchestra message broker."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import queue
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
ROLES = ("coordinator", "ui", "developer", "reviewer")
NAMES = dict(zip(ROLES, ("총괄", "UI", "개발", "리뷰/테스트")))

class Client:
    def __init__(self, connection: Path):
        self.connection = connection
        data = json.loads(connection.read_text(encoding="utf-8-sig"))
        self.url = data["url"].rstrip("/")
        parsed = urllib.parse.urlparse(self.url)
        if parsed.scheme != "http" or parsed.hostname != "127.0.0.1" or parsed.path or parsed.query or parsed.fragment or parsed.username:
            raise ValueError("Connection must use a local 127.0.0.1 HTTP server")
        self.token = data["token"]
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

    def request(self, path, body=None):
        headers = {"X-Orchestra-Token": self.token}
        payload = None
        if body is not None:
            payload = json.dumps(body, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(self.url + path, data=payload, headers=headers)
        try:
            with self.opener.open(request, timeout=5) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            raise RuntimeError(f"HTTP {error.code}: {error.read().decode('utf-8', errors='replace')}") from error

def dispatch(client, role, line):
    """Returns False to close this view; never interprets input as a shell command."""
    line = line.strip()
    if not line:
        return True
    if line == "/quit":
        return False
    if line == "/help":
        print("일반 입력: 이 역할에게 작업 요청\n/to ROLE 내용: 다른 역할에게 작업 전달\n/report ROLE 내용: 실행 없이 보고 전달\n/status: 전체 상태\n/cancel TASK_ID: 작업 취소\n/quit: 이 터미널 보기 닫기 (서버는 유지)")
        print("ROLE: " + ", ".join(ROLES))
    elif line == "/status":
        state = client.request("/api/state")
        for agent in state["agents"]:
            print(f"{agent['id']}: {agent['status']} | {agent.get('taskId') or '-'}")
    elif line.startswith("/cancel "):
        task_id = line.split(maxsplit=1)[1].strip()
        print(client.request("/api/tasks/" + urllib.parse.quote(task_id, safe="") + "/cancel", {}))
    else:
        target, sender, kind, body = role, "user", "task", line
        if line.startswith(("/to ", "/report ")):
            parts = line.split(maxsplit=2)
            if len(parts) != 3 or parts[1] not in ROLES:
                raise ValueError("사용법: /to 또는 /report ROLE 내용")
            command, target, body = parts
            sender = role
            kind = "report" if command == "/report" else "task"
        elif line.startswith("/"):
            raise ValueError("알 수 없는 명령입니다. /help를 입력하세요.")
        response = client.request("/api/messages", {"from": sender, "to": target, "body": body, "kind": kind})
        print("전달됨: " + json.dumps(response, ensure_ascii=False))
    return True

def run(role, client):
    print(f"POINT ORCHESTRA | {NAMES[role]} 작업실")
    print("실제 Codex 실행과 메시지 이력을 표시합니다. 입력하지 않으면 새 작업을 실행하지 않습니다.")
    dispatch(client, role, "/help")
    lines = queue.Queue()
    def read_input():
        while True:
            try:
                line = input()
            except EOFError:
                lines.put(None)
                break
            lines.put(line)
    threading.Thread(target=read_input, daemon=True).start()
    seen = set()
    initialized = False
    last_status = None
    failures = 0
    while True:
        try:
            state = client.request("/api/state")
            failures = 0
            agent = next((a for a in state["agents"] if a["id"] == role), {})
            status = (agent.get("status"), agent.get("taskId"))
            if status != last_status:
                print(f"\n[상태] {status[0]} | 작업: {status[1] or '-'}", flush=True)
                last_status = status
            records = []
            for category in ("messages", "events"):
                for item in state.get(category, []):
                    key = (category, str(item["id"]))
                    relevant = role in (item.get("from"), item.get("to"), item.get("role"))
                    if key not in seen and relevant:
                        records.append((key, item))
                    seen.add(key)
            for key, item in (records if initialized else records[-10:]):
                text = item.get("body", item.get("text", ""))
                origin = item.get("from", item.get("role", "server"))
                target = item.get("to", role)
                print(f"[{item.get('createdAt', '')}] {origin} → {target} ({item.get('kind', '')})\n{text}", flush=True)
            initialized = True
            if len(seen) > 10000:
                seen = {(c, str(x["id"])) for c in ("messages", "events") for x in state.get(c, [])}
        except (OSError, ValueError, RuntimeError) as error:
            failures += 1
            if failures == 1:
                print(f"[연결 끊김] {error}", flush=True)
            try:
                client = Client(client.connection)
            except (OSError, ValueError, KeyError):
                pass
            if failures >= 5:
                print("서버 연결이 종료되어 터미널 보기를 닫습니다.")
                return
        try:
            line = lines.get(timeout=1)
            if line is None or not dispatch(client, role, line):
                return
        except queue.Empty:
            pass
        except (ValueError, RuntimeError, OSError) as error:
            print(f"[전송 실패] {error}", flush=True)

def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--role", choices=ROLES, required=True)
    parser.add_argument("--connection", type=Path, default=ROOT / ".orchestra" / "connection.json")
    args = parser.parse_args()
    try:
        run(args.role, Client(args.connection))
    except KeyboardInterrupt:
        pass
    except (OSError, ValueError, KeyError) as error:
        print(f"작업실을 열 수 없습니다: {error}", file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
