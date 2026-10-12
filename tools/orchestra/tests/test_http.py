"""HTTP security/routing tests use a local ephemeral server, no model/network service."""
import http.client
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from engine import Engine
from server import make_server
from test_engine import FakeExecutor


class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.engine = Engine(Path(self.temp.name), Path(self.temp.name) / "data", executor=FakeExecutor())
        self.addCleanup(self.engine.close)
        self.server = make_server(self.engine, token="offline-test-token")
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop_server)
        self.port = self.server.server_address[1]
    def stop_server(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(3)
    def request(self, path="/api/state", payload=None, token=True, extra=None, method=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=3)
        headers = {"Content-Type": "application/json"}
        if token:
            headers["X-Orchestra-Token"] = self.server.token
        headers.update(extra or {})
        try:
            connection.request(method or ("POST" if payload is not None else "GET"), path, body=json.dumps(payload) if payload is not None else None, headers=headers)
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()
    def test_authenticated_state_and_no_token_denied(self):
        self.assertEqual(self.request()[0], 200)
        self.assertIn(self.request(token=False)[0], (401, 403))
    def test_unauthenticated_post_denied(self):
        self.assertIn(self.request("/api/messages", {"to": "ui", "body": "test"}, token=False)[0], (401, 403))
        self.assertFalse(self.engine.state()["tasks"])
    def test_foreign_origin_host_and_cross_site_denied(self):
        for headers in ({"Origin": "https://evil.example"}, {"Host": "evil.example"}, {"Sec-Fetch-Site": "cross-site"}):
            with self.subTest(headers=headers):
                self.assertEqual(self.request(extra=headers)[0], 403)
                self.assertEqual(self.request("/api/token", extra=headers)[0], 403)
    def test_invalid_json_shape_and_unknown_fields_rejected(self):
        for payload in ([], {"to": "ui", "body": "x", "unexpected": True}, {"to": ["ui"], "body": "x"}, {"to": "ui", "body": 1}):
            with self.subTest(payload=payload):
                self.assertEqual(self.request("/api/messages", payload)[0], 400)
        self.assertFalse(self.engine.state()["tasks"])
    def test_report_persists_without_task(self):
        status, body = self.request("/api/messages", {"from": "ui", "to": "coordinator", "body": "offline report", "kind": "report"})
        self.assertEqual(status, 201)
        self.assertIsNone(json.loads(body)["task"])
        self.assertFalse(self.engine.state()["tasks"])
    def test_traversal_is_not_served(self):
        for path in ("/../engine.py", "/%2e%2e/engine.py", "/.orchestra/connection.json", "/web/../../AGENTS.md"):
            with self.subTest(path=path):
                self.assertEqual(self.request(path)[0], 404)
    def test_terminal_recovers_rotated_token_without_resubmitting_work(self):
        import contextlib
        import io
        from unittest.mock import patch
        from terminal import Client, run
        connection = Path(self.temp.name) / "connection.json"
        url = f"http://127.0.0.1:{self.port}"
        connection.write_text(json.dumps({"url": url, "token": "expired-token"}), encoding="utf-8")
        client = Client(connection)
        connection.write_text(json.dumps({"url": url, "token": self.server.token}), encoding="utf-8")
        recovered = threading.Event()
        observed_tokens = []
        original_request = Client.request
        def observe_request(current, path, body=None):
            observed_tokens.append(current.token)
            result = original_request(current, path, body)
            if path == "/api/state":
                recovered.set()
            return result
        def input_after_recovery():
            recovered.wait(4)
            return "/quit"
        with patch.object(Client, "request", observe_request), patch("builtins.input", side_effect=input_after_recovery), contextlib.redirect_stdout(io.StringIO()):
            run("ui", client)
        self.assertTrue(recovered.is_set(), "terminal never recovered after token rotation")
        self.assertEqual(observed_tokens[:2], ["expired-token", self.server.token])
        self.assertFalse(self.engine.state()["tasks"])

    def test_oversized_message_rejected(self):
        self.assertEqual(self.request("/api/messages", {"to": "ui", "body": "x" * 17000})[0], 400)


if __name__ == "__main__":
    unittest.main()
