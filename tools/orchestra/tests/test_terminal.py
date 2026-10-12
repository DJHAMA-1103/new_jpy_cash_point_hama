"""Client routing tests. No network or Codex execution occurs here."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from terminal import Client, dispatch


class RecordingClient:
    def __init__(self):
        self.calls = []
    def request(self, path, body=None):
        self.calls.append((path, body))
        return {"message": {"id": 1}}


class TerminalTests(unittest.TestCase):
    def setUp(self):
        self.client = RecordingClient()
        self.output = contextlib.redirect_stdout(io.StringIO())
        self.output.__enter__()
    def tearDown(self):
        self.output.__exit__(None, None, None)
    def test_plain_input_targets_current_role(self):
        self.assertTrue(dispatch(self.client, "ui", "design request"))
        self.assertEqual(self.client.calls, [("/api/messages", {"from": "user", "to": "ui", "body": "design request", "kind": "task"})])
    def test_handoff_preserves_sender_and_recipient(self):
        dispatch(self.client, "ui", "/to developer implement approved design")
        self.assertEqual(self.client.calls[0][1], {"from": "ui", "to": "developer", "body": "implement approved design", "kind": "task"})
    def test_report_is_not_task(self):
        dispatch(self.client, "reviewer", "/report coordinator results ready")
        self.assertEqual(self.client.calls[0][1]["kind"], "report")
    def test_invalid_command_and_role_make_no_request(self):
        for value in ("/to nowhere hello", "/to ui", "/unknown"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                dispatch(self.client, "ui", value)
        self.assertFalse(self.client.calls)
    def test_quit_and_blank_make_no_request(self):
        self.assertFalse(dispatch(self.client, "ui", "/quit"))
        self.assertTrue(dispatch(self.client, "ui", "  "))
        self.assertFalse(self.client.calls)
    def test_shell_text_is_data(self):
        payload = "$(whoami); Remove-Item anything"
        dispatch(self.client, "developer", payload)
        self.assertEqual(self.client.calls[0][1]["body"], payload)
    def test_connection_refuses_remote_credential_destination(self):
        with tempfile.TemporaryDirectory() as directory:
            connection = Path(directory) / "connection.json"
            for url in ("https://example.com", "http://localhost:1234", "http://127.0.0.1:1234/path", "http://attacker@127.0.0.1:1234", "http://127.0.0.1:1234?x=1"):
                connection.write_text(json.dumps({"url": url, "token": "test-only"}), encoding="utf-8")
                with self.subTest(url=url), self.assertRaises(ValueError):
                    Client(connection)


if __name__ == "__main__":
    unittest.main()
