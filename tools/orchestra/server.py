"""Loopback HTTP API; POST requires token and all requests enforce same origin."""
from __future__ import annotations

import argparse
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import threading
from urllib.parse import urlsplit

from engine import Engine

WEB = Path(__file__).resolve().parent / "web"
STATIC = {"/": ("index.html", "text/html; charset=utf-8"), "/index.html": ("index.html", "text/html; charset=utf-8"),
          "/app.js": ("app.js", "text/javascript; charset=utf-8"), "/style.css": ("style.css", "text/css; charset=utf-8"),
          "/styles.css": ("styles.css", "text/css; charset=utf-8")}


class DataDirectoryLock:
    """OS-owned lifetime lock; file stays after release, lock does not."""
    def __init__(self, data_dir):
        directory = Path(data_dir).resolve()
        directory.mkdir(parents=True, exist_ok=True)
        self.file = (directory / "server.lock").open("a+b")
        try:
            self.file.seek(0, os.SEEK_END)
            if self.file.tell() == 0:
                self.file.write(b"0")
                self.file.flush()
            self.file.seek(0)
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(self.file.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            self.file.close()
            raise RuntimeError("Another Orchestra server owns this data directory") from exc

    def close(self):
        if self.file.closed:
            return
        try:
            self.file.seek(0)
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(self.file.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.file.fileno(), fcntl.LOCK_UN)
        finally:
            self.file.close()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # No tokens/prompts in HTTP access logs.

    def _send(self, status, value, content_type="application/json; charset=utf-8"):
        data = value if isinstance(value, bytes) else json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'")
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _allowed(self, post=False):
        host = self.headers.get("Host", "")
        port = self.server.server_address[1]
        valid_hosts = {f"127.0.0.1:{port}", f"localhost:{port}"}
        origin = self.headers.get("Origin")
        if (host not in valid_hosts or (origin is not None and origin != f"http://{host}")
                or self.headers.get("Sec-Fetch-Site", "") == "cross-site"):
            self._send(403, {"error": "Foreign Host/Origin rejected"})
            return False
        if post and not hmac.compare_digest(self.headers.get("X-Orchestra-Token", "").encode("utf-8"), self.server.token.encode("utf-8")):
            self._send(403, {"error": "Missing or invalid token"})
            return False
        return True

    def do_GET(self):
        if not self._allowed():
            return
        path = urlsplit(self.path).path
        if path == "/api/health":
            self._send(200, {"ok": True, "pid": os.getpid(), "mode": self.server.engine.state()["server"]["mode"]})
        elif path == "/api/token":
            self._send(200, {"token": self.server.token})
        elif path == "/api/state":
            if not hmac.compare_digest(self.headers.get("X-Orchestra-Token", "").encode("utf-8"), self.server.token.encode("utf-8")):
                self._send(403, {"error": "Missing or invalid token"})
                return
            self._send(200, self.server.engine.state())
        elif path in STATIC:
            name, mime = STATIC[path]
            target = WEB / name
            if target.is_file():
                self._send(200, target.read_bytes(), mime)
            else:
                self._send(404, {"error": "Dashboard file not found"})
        else:
            self._send(404, {"error": "Not found"})

    def do_POST(self):
        if not self._allowed(post=True):
            return
        try:
            if self.headers.get("Transfer-Encoding"):
                raise ValueError("Transfer encoding is unsupported")
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 65536:
                raise ValueError("Body must be 1–65536 bytes")
            if self.headers.get("Content-Type", "").split(";")[0].strip() != "application/json":
                raise ValueError("Content-Type must be application/json")
            self.connection.settimeout(5)
            data = json.loads(self.rfile.read(length))
            if not isinstance(data, dict):
                raise ValueError("Expected JSON object")
            path = urlsplit(self.path).path
            if path == "/api/messages":
                if set(data) - {"from", "to", "body", "kind"}:
                    raise ValueError("Unknown message field")
                result = self.server.engine.submit(data.get("from", "user"), data.get("to"), data.get("body"), data.get("kind", "task"))
                self._send(201, result)
            elif path.startswith("/api/tasks/") and path.endswith("/cancel"):
                task_id = path[len("/api/tasks/"):-len("/cancel")]
                self._send(200, {"task": self.server.engine.cancel(task_id)})
            elif path == "/api/shutdown":
                self._send(200, {"ok": True})
                threading.Thread(target=self.server.shutdown, daemon=True).start()
            else:
                self._send(404, {"error": "Not found"})
        except KeyError as exc:
            self._send(404, {"error": str(exc)})
        except (ValueError, TypeError, TimeoutError) as exc:
            self._send(400, {"error": str(exc)})

    def do_OPTIONS(self):
        self._send(403, {"error": "Cross-origin requests are not supported"})


def make_server(engine, port=0, token=None):
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.engine = engine
    server.token = token or secrets.token_urlsafe(32)
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--data-dir", type=Path)
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--sandbox", choices=("read-only", "workspace-write"), default="read-only")
    args = parser.parse_args()
    if not 1 <= args.port <= 65535 or args.timeout < 1:
        parser.error("port must be 1..65535 and timeout must be positive")
    project = args.project.resolve()
    data_dir = (args.data_dir or project / ".orchestra").resolve()
    # Bind before opening/recovering DB, preventing accidental recovery by duplicate launch.
    server = make_server(None, args.port)
    directory_lock = None
    try:
        directory_lock = DataDirectoryLock(data_dir)
        engine = Engine(project, data_dir, timeout=args.timeout, sandbox=args.sandbox)
    except Exception:
        server.server_close()
        if directory_lock:
            directory_lock.close()
        raise
    server.engine = engine
    connection = data_dir / "connection.json"
    try:
        connection.write_text(json.dumps({"url": f"http://127.0.0.1:{args.port}", "token": server.token, "pid": os.getpid()}), encoding="utf-8")
        engine.start()
        print(f"POINT Orchestra http://127.0.0.1:{args.port} ({args.sandbox}, real CLI)", flush=True)
        server.serve_forever(poll_interval=0.2)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        engine.close()
        try:
            if json.loads(connection.read_text(encoding="utf-8")).get("pid") == os.getpid():
                connection.unlink()
        except (OSError, ValueError):
            pass
        directory_lock.close()


if __name__ == "__main__":
    main()
