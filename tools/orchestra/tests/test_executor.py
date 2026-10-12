"""Mocked subprocess tests: NOT evidence that the real Codex CLI worked."""
import io
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from engine import CodexExecutor


class FakeProcess:
    pid = 99999999
    def __init__(self, returncode):
        self.returncode = returncode
        self.stdin = io.StringIO()
        self.stdout = io.StringIO('{"type":"test.only"}\n')
        self.stderr = io.StringIO("FAKE stderr\n")
    def poll(self):
        return self.returncode


class ExecutorTests(unittest.TestCase):
    def run_fake_cli(self, code=0, content=None, sandbox="read-only", role="reviewer"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executor = CodexExecutor(root, root / "runtime", sandbox=sandbox)
            executor.executable = "FAKE-CODEX-DO-NOT-RUN"
            captured = []
            def fake_popen(command, **kwargs):
                captured.append(command)
                self.assertNotIn("--dangerously-bypass-approvals-and-sandbox", command)
                self.assertNotIn("danger-full-access", command)
                if sandbox == "workspace-write" and role in ("ui", "developer"):
                    self.assertIn("--approve-for-me", command)
                else:
                    self.assertEqual(command[command.index("--sandbox") + 1], "read-only")
                    self.assertNotIn("--approve-for-me", command)
                self.assertFalse(kwargs.get("shell", False))
                if content is not None:
                    Path(command[command.index("--output-last-message") + 1]).write_text(content, encoding="utf-8")
                return FakeProcess(code)
            with patch("engine.subprocess.Popen", side_effect=fake_popen):
                result = executor({"id": "fake-test", "to": role}, "test prompt", lambda *args: None, lambda *args: None, threading.Event(), 1)
            self.assertTrue(captured)
            return result
    def test_writable_mode_preserves_read_only_review_and_coordinator(self):
        for role in ("ui", "developer", "reviewer", "coordinator"):
            with self.subTest(role=role):
                self.run_fake_cli(content=json.dumps({"outcome": "completed", "summary": "FAKE", "messages": []}), sandbox="workspace-write", role=role)
    def test_cancel_and_timeout_call_owned_process_cleanup(self):
        for reason in ("cancel", "timeout", "callback_error"):
            with self.subTest(reason=reason), tempfile.TemporaryDirectory() as directory:
                executor = CodexExecutor(Path(directory), Path(directory) / "runtime")
                executor.executable = "FAKE-CODEX-DO-NOT-RUN"
                process = FakeProcess(None)
                cancel = threading.Event()
                if reason == "cancel":
                    cancel.set()
                def on_process(pid):
                    if reason == "callback_error":
                        raise RuntimeError("FAKE callback failure")
                with patch("engine.subprocess.Popen", return_value=process), patch.object(executor, "terminate") as terminate:
                    with self.assertRaises((RuntimeError, TimeoutError)):
                        executor({"id": "fake", "to": "reviewer"}, "test", lambda *args: None, on_process, cancel, 0)
                    terminate.assert_called_once_with(process)

    def test_valid_final_json_accepted(self):
        result = self.run_fake_cli(content=json.dumps({"outcome": "completed", "summary": "FAKE success", "messages": []}))
        self.assertEqual(result["summary"], "FAKE success")
    def test_nonzero_exit_not_completed_even_with_result(self):
        with self.assertRaises(RuntimeError):
            self.run_fake_cli(code=1, content=json.dumps({"outcome": "completed", "summary": "FAKE", "messages": []}))
    def test_missing_result_not_completed(self):
        with self.assertRaises(RuntimeError):
            self.run_fake_cli()
    def test_invalid_json_not_completed(self):
        with self.assertRaises(ValueError):
            self.run_fake_cli(content="not valid json")
    def test_invalid_handoff_not_completed(self):
        with self.assertRaises(ValueError):
            self.run_fake_cli(content=json.dumps({"outcome": "completed", "summary": "FAKE", "messages": [{"to": "unknown", "kind": "task", "body": "x"}]}))


if __name__ == "__main__":
    unittest.main()
