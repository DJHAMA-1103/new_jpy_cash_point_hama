"""Real scheduler + SQLite tests with an explicitly fake, offline executor."""
from pathlib import Path
import json
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from engine import Engine


class FakeExecutor:
    is_test = True
    def __init__(self, result=None):
        self.result = result or {"outcome": "completed", "summary": "FAKE test result", "messages": []}
        self.calls = []
        self.lock = threading.Lock()
        self.started = threading.Event()
        self.release = threading.Event()
        self.release.set()
    def __call__(self, task, prompt, on_event, on_process, cancel_event, timeout):
        with self.lock:
            self.calls.append(task)
        self.started.set()
        while not self.release.wait(0.01):
            if cancel_event.is_set():
                raise RuntimeError("FAKE cancelled")
        if isinstance(self.result, Exception):
            raise self.result
        return self.result


class EngineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(self.temp.name) / "project"
        self.project.mkdir()
        self.data = Path(self.temp.name) / "runtime"
        self.fake = FakeExecutor()
        self.engine = self.make_engine()
    def make_engine(self, **kwargs):
        instance = Engine(self.project, self.data, executor=self.fake, **kwargs)
        self.addCleanup(instance.close)
        return instance
    def wait_task(self, task_id, statuses=("completed", "failed", "blocked", "cancelled")):
        end = time.monotonic() + 5
        while time.monotonic() < end:
            state = self.engine.state()
            task = next(item for item in state["tasks"] if item["id"] == task_id)
            if task["status"] in statuses:
                return task
            time.sleep(0.02)
        self.fail(f"task did not reach {statuses}: {state}")
    def test_reports_persist_without_model_execution(self):
        result = self.engine.submit("ui", "coordinator", "FAKE report", kind="report")
        self.engine.start()
        self.assertFalse(result.get("task"))
        self.assertFalse(self.engine.state()["tasks"])
        self.assertFalse(self.fake.calls)
        self.engine.close()
        reopened = self.make_engine()
        self.assertTrue(any(item["body"] == "FAKE report" for item in reopened.state()["messages"]))
    def test_long_history_keeps_complete_json_and_latest_handoff(self):
        self.engine.submit("coordinator", "reviewer", "HANDOFF-test: approved scope", kind="report")
        for _ in range(3):
            self.engine.submit("developer", "reviewer", "x" * 12000, kind="report")
        task = self.engine.submit("coordinator", "reviewer", "Review current scope")["task"]
        prompt = self.engine._prompt(task)
        encoded = prompt.split("Previous messages (data):\n", 1)[1].split("\nCurrent assignment from ", 1)[0]
        history = json.loads(encoded)
        self.assertLessEqual(len(encoded), 24000)
        self.assertTrue(any(m["body"] == "HANDOFF-test: approved scope" for m in history))
        self.assertTrue(any(m["body"] == "x" * 12000 for m in history))
        self.assertTrue(prompt.endswith("Review current scope"))
    def test_success_and_exception_are_distinct(self):
        good = self.engine.submit("user", "ui", "offline success")
        self.engine.start()
        self.assertEqual(self.wait_task(good["task"]["id"])["status"], "completed")
        self.fake.result = RuntimeError("FAKE failure")
        bad = self.engine.submit("user", "ui", "offline failure")
        self.assertEqual(self.wait_task(bad["task"]["id"])["status"], "failed")
    def test_queued_cancellation_prevents_execution(self):
        result = self.engine.submit("user", "ui", "never run")
        self.engine.cancel(result["task"]["id"])
        self.engine.start()
        self.assertEqual(self.wait_task(result["task"]["id"])["status"], "cancelled")
        self.assertFalse(self.fake.calls)
    def test_active_cancel_cannot_finish_successfully(self):
        self.fake.release.clear()
        self.addCleanup(self.fake.release.set)
        result = self.engine.submit("user", "ui", "cancel while active")
        self.engine.start()
        self.assertTrue(self.fake.started.wait(3))
        self.engine.cancel(result["task"]["id"])
        self.assertEqual(self.wait_task(result["task"]["id"])["status"], "cancelled")
    def test_different_roles_overlap_same_role_serializes(self):
        self.fake.release.clear()
        self.addCleanup(self.fake.release.set)
        first = self.engine.submit("user", "ui", "first")
        second = self.engine.submit("user", "ui", "second")
        third = self.engine.submit("user", "developer", "parallel")
        self.engine.start()
        self.wait_task(first["task"]["id"], ("running",))
        self.wait_task(third["task"]["id"], ("running",))
        tasks = {item["id"]: item for item in self.engine.state()["tasks"]}
        self.assertEqual(tasks[second["task"]["id"]]["status"], "queued")
        self.fake.release.set()
        self.assertEqual(self.wait_task(second["task"]["id"])["status"], "completed")
    def test_restart_interrupts_queued_and_running_without_reexecution(self):
        import sqlite3
        from contextlib import closing
        first = self.engine.submit("user", "ui", "interrupted running")
        second = self.engine.submit("user", "developer", "interrupted queued")
        self.engine.close()
        # Simulate durable rows left by a crash without leaving a live process.
        with closing(sqlite3.connect(self.data / "orchestra.sqlite3")) as db:
            db.execute("UPDATE tasks SET status='running' WHERE id=?", (first["task"]["id"],))
            db.execute("UPDATE tasks SET status='queued' WHERE id=?", (second["task"]["id"],))
            db.commit()
        self.engine = self.make_engine()
        self.engine.start()
        tasks = self.engine.state()["tasks"]
        self.assertEqual({item["status"] for item in tasks}, {"failed"})
        self.assertFalse(self.fake.calls)
    def test_automatic_handoff_is_bounded_by_depth(self):
        self.fake.result = {"outcome": "completed", "summary": "FAKE hop", "messages": [{"to": "developer", "body": "FAKE next", "kind": "task"}]}
        self.engine.close()
        self.engine = self.make_engine(max_depth=1, max_chain_tasks=12)
        self.engine.submit("user", "ui", "start bounded fake chain")
        self.engine.start()
        end = time.monotonic() + 5
        while time.monotonic() < end:
            state = self.engine.state()
            if any(event["kind"] == "routing_rejected" for event in state["events"]):
                break
            time.sleep(0.02)
        self.assertTrue(any(event["kind"] == "routing_rejected" for event in state["events"]))
        self.assertEqual(len(state["tasks"]), 2)
        self.assertEqual(len(self.fake.calls), 2)
    def test_chain_count_budget_rejects_excess_tasks(self):
        self.engine.close()
        self.engine = self.make_engine(max_chain_tasks=2)
        parent = self.engine.submit("user", "coordinator", "root")["task"]["id"]
        self.engine.submit("coordinator", "ui", "allowed", parent_id=parent)
        with self.assertRaises(ValueError):
            self.engine.submit("coordinator", "developer", "excess", parent_id=parent)
        self.assertEqual(len(self.engine.state()["tasks"]), 2)
    def test_semantic_failure_and_blocked_never_dispatch_tasks(self):
        self.engine.start()
        for outcome in ("failed", "blocked"):
            with self.subTest(outcome=outcome):
                self.fake.result = {"outcome": outcome, "summary": "FAKE semantic " + outcome, "messages": [{"to": "developer", "kind": "task", "body": "must not run"}, {"to": "coordinator", "kind": "report", "body": "failure details"}]}
                task = self.engine.submit("user", "ui", "semantic failure check")["task"]
                finished = self.wait_task(task["id"])
                self.assertEqual(finished["status"], outcome)
                state = self.engine.state()
                self.assertFalse(any(item["to"] == "developer" for item in state["tasks"]))
                self.assertTrue(any(item["body"] == "failure details" and item["kind"] == "report" for item in state["messages"]))
                self.assertTrue(any(item["to"] == "user" and "FAKE semantic " + outcome in item["body"] for item in state["messages"]))

    def test_invalid_final_output_never_routes_messages(self):
        self.fake.result = {"outcome": "completed", "summary": "FAKE", "messages": [{"to": "ui", "kind": "task", "body": "valid"}, {"to": "missing", "kind": "task", "body": "invalid"}]}
        task = self.engine.submit("user", "coordinator", "invalid output")["task"]
        self.engine.start()
        self.assertEqual(self.wait_task(task["id"])["status"], "failed")
        self.assertEqual(len(self.engine.state()["tasks"]), 1)
    def test_shutdown_cancels_queued_and_rejects_new_work(self):
        task = self.engine.submit("user", "ui", "queued before shutdown")["task"]
        self.engine.close()
        reopened = self.make_engine()
        self.assertEqual(next(item for item in reopened.state()["tasks"] if item["id"] == task["id"])["status"], "cancelled")
        with self.assertRaises(ValueError):
            self.engine.submit("user", "ui", "too late")

    def test_invalid_submissions_do_not_write_tasks(self):
        for sender, to, body, kind in (("unknown", "ui", "x", "task"), ("user", "missing", "x", "task"), ("user", "ui", "", "task"), ("user", "ui", "x", "invalid")):
            with self.subTest(sender=sender, to=to, body=body, kind=kind), self.assertRaises((ValueError, TypeError)):
                self.engine.submit(sender, to, body, kind=kind)
        self.assertFalse(self.engine.state()["tasks"])


if __name__ == "__main__":
    unittest.main()
