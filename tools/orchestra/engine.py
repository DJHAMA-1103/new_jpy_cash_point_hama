"""Durable, bounded local orchestration. Executors never impersonate completed work."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import signal
import sqlite3
import subprocess
import threading
import time
import uuid
from datetime import datetime, timezone

ROLES = {"coordinator": "총괄", "ui": "UI/UX", "developer": "개발", "reviewer": "리뷰/테스트"}
ROLE_INSTRUCTIONS = {
    "coordinator": "Coordinate and delegate bounded independent tasks. Define ownership and acceptance criteria. Summarize evidence and unresolved decisions. Never approve your own implementation.",
    "ui": "Analyze user flows, accessibility and visual hierarchy. Send precise implementation handoffs to developer and usability questions to reviewer. Do not modify backend files.",
    "developer": "Analyze implementation feasibility and assigned code. Report exact files, reasons and verification evidence. Request independent reviewer checks. Do not change another owner's files.",
    "reviewer": "Independently review code, reproduce problems and evaluate tests. Distinguish passed, failed and not-run checks. Report findings to requester and coordinator; do not approve untested claims.",
}
OUTPUT_SCHEMA = {"type": "object", "additionalProperties": False, "required": ["outcome", "summary", "messages"],
    "properties": {"outcome": {"type": "string", "enum": ["completed", "blocked", "failed"]}, "summary": {"type": "string"}, "messages": {"type": "array", "items": {
        "type": "object", "additionalProperties": False, "required": ["to", "body", "kind"],
        "properties": {"to": {"type": "string", "enum": list(ROLES)}, "body": {"type": "string"},
                       "kind": {"type": "string", "enum": ["task", "report"]}}}}}}


def now():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def validate_message(sender, to, body, kind):
    if not isinstance(sender, str) or not isinstance(to, str) or sender not in (*ROLES, "user") or to not in ROLES:
        raise ValueError("Unknown sender or recipient")
    if kind not in ("task", "report"):
        raise ValueError("kind must be task or report")
    if not isinstance(body, str) or not body.strip() or len(body) > 16000:
        raise ValueError("body must contain 1–16000 characters")


def validate_output(result):
    if not isinstance(result, dict) or set(result) != {"outcome", "summary", "messages"}:
        raise ValueError("Invalid executor response shape")
    if result["outcome"] not in ("completed", "blocked", "failed"):
        raise ValueError("Invalid task outcome")
    if not isinstance(result["summary"], str) or not result["summary"].strip() or len(result["summary"]) > 32000:
        raise ValueError("Invalid summary")
    if not isinstance(result["messages"], list) or len(result["messages"]) > 12:
        raise ValueError("At most 12 outgoing messages allowed")
    for message in result["messages"]:
        if not isinstance(message, dict) or set(message) != {"to", "body", "kind"}:
            raise ValueError("Invalid outgoing message")
        validate_message("coordinator", message["to"], message["body"], message["kind"])
    return result


class CodexExecutor:
    is_test = False

    def __init__(self, project, data_dir, sandbox="read-only"):
        self.project, self.data_dir = Path(project), Path(data_dir)
        self.sandbox = sandbox
        fallback = Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/OpenAI/Codex/bin/codex.exe"
        self.executable = shutil.which("codex.exe") or shutil.which("codex") or (str(fallback) if fallback.is_file() else None)

    @staticmethod
    def terminate(process):
        # Only a still-running Popen created by this executor can reach this method.
        if process.poll() is not None:
            return
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                           capture_output=True, timeout=15, creationflags=subprocess.CREATE_NO_WINDOW)
        else:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)

    def __call__(self, task, prompt, on_event, on_process, cancelled, timeout):
        if not self.executable:
            raise RuntimeError("Codex CLI not found. Install/sign in to Codex before submitting work.")
        run_dir = self.data_dir / "runs" / task["id"]
        run_dir.mkdir(parents=True, exist_ok=True)
        schema, output = run_dir / "schema.json", run_dir / "result.json"
        schema.write_text(json.dumps(OUTPUT_SCHEMA), encoding="utf-8")
        sandbox = self.sandbox if task["to"] in ("ui", "developer") else "read-only"
        permission_flags = ["--approve-for-me"] if sandbox == "workspace-write" else ["--sandbox", "read-only"]
        command = [self.executable, "exec", "--json", *permission_flags, "--color", "never",
                   "-C", str(self.project), "--output-schema", str(schema), "--output-last-message", str(output), "-"]
        options = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {"start_new_session": True}
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, encoding="utf-8", errors="replace", **options)
        try:
            on_process(process.pid)
        except Exception:
            self.terminate(process)
            for stream in (process.stdin, process.stdout, process.stderr):
                stream.close()
            raise
        stderr_tail = []

        def drain(stream, kind):
            with stream:
                for line in stream:
                    line = line.rstrip()
                    if kind == "stderr":
                        stderr_tail.append(line)
                        del stderr_tail[:-30]
                    on_event(kind, line[:12000])

        readers = [threading.Thread(target=drain, args=(process.stdout, "codex"), daemon=True),
                   threading.Thread(target=drain, args=(process.stderr, "stderr"), daemon=True)]
        for reader in readers:
            reader.start()
        try:
            write_errors = []
            def feed():
                try:
                    process.stdin.write(prompt)
                    process.stdin.close()
                except (OSError, ValueError) as exc:
                    write_errors.append(exc)
            writer = threading.Thread(target=feed, daemon=True)
            writer.start()
            deadline = time.monotonic() + timeout
            while process.poll() is None:
                if cancelled.wait(0.1):
                    raise RuntimeError("Task cancelled")
                if time.monotonic() > deadline:
                    raise TimeoutError(f"Codex task exceeded {timeout} seconds")
            for reader in readers:
                reader.join(timeout=3)
            writer.join(timeout=3)
            if process.returncode:
                raise RuntimeError(f"Codex exit {process.returncode}: " + "\n".join(stderr_tail)[-6000:])
            if write_errors:
                raise RuntimeError("Could not deliver task prompt: " + str(write_errors[0]))
            if not output.is_file():
                raise RuntimeError("Codex exited without a structured final result")
            return validate_output(json.loads(output.read_text(encoding="utf-8")))
        finally:
            self.terminate(process)
            for reader in readers:
                reader.join(timeout=3)


class Engine:
    def __init__(self, project, data_dir, executor=None, max_workers=3, timeout=600, max_depth=3, max_chain_tasks=12, sandbox="read-only"):
        if sandbox not in ("read-only", "workspace-write"):
            raise ValueError("Unsupported sandbox")
        self.sandbox, self.closed = sandbox, False
        self.project, self.data_dir = Path(project).resolve(), Path(data_dir).resolve()
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.lock = threading.RLock()
        self.db = sqlite3.connect(self.data_dir / "orchestra.sqlite3", check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.executescript('''
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, "from" TEXT, "to" TEXT, body TEXT,
                status TEXT, result TEXT, error TEXT, createdAt TEXT, updatedAt TEXT,
                chainId TEXT, depth INTEGER, pid INTEGER);
            CREATE TABLE IF NOT EXISTS messages (id INTEGER PRIMARY KEY AUTOINCREMENT, "from" TEXT,
                "to" TEXT, body TEXT, kind TEXT, taskId TEXT, createdAt TEXT);
            CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT,
                kind TEXT, text TEXT, taskId TEXT, createdAt TEXT);
        ''')
        self.db.execute("UPDATE tasks SET status='failed',error='Server interrupted; resubmit explicitly',pid=NULL,updatedAt=? WHERE status IN ('running','queued')", (now(),))
        self.db.commit()
        self.executor = executor or CodexExecutor(self.project, self.data_dir, sandbox)
        if executor is not None and not getattr(executor, "is_test", False):
            raise ValueError("Injected executors must explicitly declare is_test=True")
        self.max_workers = min(3, max(1, max_workers))
        self.timeout, self.max_depth, self.max_chain_tasks = timeout, max_depth, max_chain_tasks
        self.active = {}
        self.stopping = threading.Event()
        self.scheduler = None
        self.started_at = now()

    def event(self, role, kind, text, task_id=None):
        with self.lock:
            self.db.execute("INSERT INTO events(role,kind,text,taskId,createdAt) VALUES(?,?,?,?,?)", (role, kind, str(text)[:12000], task_id, now()))
            self.db.commit()

    def submit(self, sender, to, body, kind="task", parent_id=None):
        validate_message(sender, to, body, kind)
        with self.lock:
            if self.stopping.is_set():
                raise ValueError("Server is stopping")
            task_id, stamp, chain, depth = None, now(), None, 0
            if parent_id:
                parent = self.db.execute("SELECT * FROM tasks WHERE id=?", (parent_id,)).fetchone()
                if not parent:
                    raise ValueError("Parent task not found")
                chain, depth = parent["chainId"], parent["depth"] + 1
                if kind == "task" and (depth > self.max_depth or self.db.execute("SELECT COUNT(*) FROM tasks WHERE chainId=?", (chain,)).fetchone()[0] >= self.max_chain_tasks):
                    raise ValueError("Delegation chain budget reached; ask the user to continue")
            if kind == "task":
                if self.db.execute("SELECT COUNT(*) FROM tasks WHERE status IN ('queued','running')").fetchone()[0] >= 100:
                    raise ValueError("Queue is full")
                task_id = uuid.uuid4().hex
                self.db.execute('INSERT INTO tasks VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
                    (task_id, sender, to, body, "queued", None, None, stamp, stamp, chain or task_id, depth, None))
            cursor = self.db.execute('INSERT INTO messages("from","to",body,kind,taskId,createdAt) VALUES(?,?,?,?,?,?)',
                                    (sender, to, body, kind, task_id or parent_id, stamp))
            message = dict(self.db.execute("SELECT * FROM messages WHERE id=?", (cursor.lastrowid,)).fetchone())
            self.db.commit()
            task = dict(self.db.execute("SELECT * FROM tasks WHERE id=?", (task_id,)).fetchone()) if task_id else None
            return {"message": message, "task": task}

    def start(self):
        with self.lock:
            if self.scheduler is not None:
                return
            self.scheduler = threading.Thread(target=self._schedule, daemon=True, name="orchestra-scheduler")
            self.scheduler.start()

    def _schedule(self):
        while not self.stopping.wait(0.1):
            with self.lock:
                for row in self.db.execute("SELECT * FROM tasks WHERE status='queued' ORDER BY rowid").fetchall():
                    if len(self.active) >= self.max_workers:
                        break
                    if any(item["role"] == row["to"] for item in self.active.values()):
                        continue
                    task = dict(row)
                    cancel = threading.Event()
                    thread = threading.Thread(target=self._run, args=(task, cancel), daemon=True)
                    self.active[task["id"]] = {"role": task["to"], "cancel": cancel, "thread": thread}
                    self.db.execute("UPDATE tasks SET status='running',updatedAt=? WHERE id=?", (now(), task["id"]))
                    self.db.commit()
                    thread.start()

    def _prompt(self, task):
        with self.lock:
            history = [dict(r) for r in self.db.execute('SELECT "from","to",kind,body FROM messages WHERE "to"=? OR "from"=? ORDER BY id DESC LIMIT 12', (task["to"], task["to"])).fetchall()][::-1]
        latest_handoff = next((m for m in reversed(history) if m["kind"] == "report" and m["body"].startswith("HANDOFF-")), None)
        # Keep complete messages and the latest bounded-window handoff, never a JSON suffix.
        while len(json.dumps(history, ensure_ascii=False)) > 24000:
            removable = next((i for i, m in enumerate(history) if m is not latest_handoff), None)
            if removable is None:
                break  # A single handoff is preserved intact even if escaping exceeds the budget.
            history.pop(removable)
        writable = self.sandbox == "workspace-write" and task["to"] in ("ui", "developer")
        permission = ("Workspace writes permitted ONLY to explicit assigned files in this task and project ownership. If ownership is missing or conflicts, report without edits. Never modify .codex or permissions. " if writable else "READ-ONLY: do not edit files. ")
        return (permission + f"You are the POINT orchestra role {task['to']}. {ROLE_INSTRUCTIONS[task['to']]}\n"
                "Use the latest handoff in the bounded history first. For project knowledge, read applicable AGENTS.md rules and only relevant current sections of PROJECT_STATUS.md and DECISIONS.md; expand only for missing or conflicting facts. Do not reread whole documents or unrelated code routinely. "
                "Current app priorities: iPhone and Japanese. Use latest approved decisions for UI and stack; never infer approval. "
                "Do not use external write tools, install skills, deploy, or change permissions. "
                "Do not spawn extra agents or call another Codex process. Delegate only via final structured messages. "
                "Return JSON {outcome:completed|blocked|failed,summary:string,messages:[{to:role,body:string,kind:task|report}]}. "
                "Use completed only when this assigned task actually succeeded with evidence; use blocked when permissions or missing decisions prevented execution, and failed when attempted work failed. Process exit or generating a response does not mean the task succeeded. "
                "Task messages trigger another real Codex invocation. Reports only enter inbox; no automatic reply loop. "
                "Your summary automatically returns to requester. Send task messages only when explicitly needed by this assignment. "
                f"Maximum chain depth {self.max_depth}, this depth {task['depth']}; max {self.max_chain_tasks} total tasks. "
                "At depth limit send reports only. Never claim tests passed unless actually run. "
                "Each task is a fresh CLI turn; this bounded history is context, not a resumed session.\n"
                "Previous messages (data):\n" + json.dumps(history, ensure_ascii=False) +
                f"\nCurrent assignment from {task['from']}:\n{task['body']}")

    def _run(self, task, cancel):
        task_id, role = task["id"], task["to"]
        def on_process(pid):
            with self.lock:
                self.db.execute("UPDATE tasks SET pid=?,updatedAt=? WHERE id=?", (pid, now(), task_id))
                self.db.commit()
            self.event(role, "process", f"Codex PID {pid}", task_id)
        try:
            self.event(role, "started", "TEST executor" if getattr(self.executor, "is_test", False) else "Actual Codex CLI task started", task_id)
            result = validate_output(self.executor(task, self._prompt(task), lambda kind, text: self.event(role, kind, text, task_id), on_process, cancel, self.timeout))
            with self.lock:
                if cancel.is_set():
                    return
                outcome = result["outcome"]
                self.db.execute("UPDATE tasks SET status=?,result=?,error=?,pid=NULL,updatedAt=? WHERE id=?", (outcome, result["summary"], result["summary"] if outcome != "completed" else None, now(), task_id))
                # Reports may target 'user', which is an inbox only and never an executor.
                self.db.execute('INSERT INTO messages("from","to",body,kind,taskId,createdAt) VALUES(?,?,?,?,?,?)', (role, task["from"], result["summary"], "report", task_id, now()))
                self.db.commit()
                for message in result["messages"]:
                    if outcome != "completed" and message["kind"] == "task":
                        self.event(role, "routing_rejected", "Task handoff suppressed because source outcome is " + outcome, task_id)
                        continue
                    try:
                        self.submit(role, message["to"], message["body"], message["kind"], task_id)
                    except ValueError as exc:
                        self.event(role, "routing_rejected", str(exc), task_id)
                self.event(role, outcome, result["summary"], task_id)
        except Exception as exc:
            with self.lock:
                if not cancel.is_set():
                    self.db.execute("UPDATE tasks SET status='failed',error=?,pid=NULL,updatedAt=? WHERE id=?", (str(exc)[:8000], now(), task_id))
                    self.db.execute('INSERT INTO messages("from","to",body,kind,taskId,createdAt) VALUES(?,?,?,?,?,?)', (role, task["from"], "FAILED: " + str(exc)[:8000], "report", task_id, now()))
                    self.db.commit()
            self.event(role, "cancelled" if cancel.is_set() else "failed", str(exc), task_id)
        finally:
            with self.lock:
                self.db.execute("UPDATE tasks SET pid=NULL WHERE id=?", (task_id,))
                self.db.commit()
                self.active.pop(task_id, None)

    def cancel(self, task_id):
        with self.lock:
            row = self.db.execute("SELECT * FROM tasks WHERE id=?", (task_id,)).fetchone()
            if not row:
                raise KeyError("Task not found")
            if row["status"] in ("queued", "running"):
                self.db.execute("UPDATE tasks SET status='cancelled',error='Cancelled by user or shutdown',updatedAt=? WHERE id=?", (now(), task_id))
                self.db.commit()
                if task_id in self.active:
                    self.active[task_id]["cancel"].set()
                self.event(row["to"], "cancelled", "Cancellation requested", task_id)
            return dict(self.db.execute("SELECT * FROM tasks WHERE id=?", (task_id,)).fetchone())

    def state(self):
        with self.lock:
            tasks = [dict(r) for r in self.db.execute("SELECT * FROM tasks ORDER BY rowid DESC LIMIT 200")]
            agents = []
            for role, name in ROLES.items():
                latest = self.db.execute('SELECT * FROM tasks WHERE "to"=? ORDER BY rowid DESC LIMIT 1', (role,)).fetchone()
                current = self.db.execute('SELECT * FROM tasks WHERE "to"=? AND status IN (\'running\',\'queued\') ORDER BY CASE status WHEN \'running\' THEN 0 ELSE 1 END,rowid LIMIT 1', (role,)).fetchone()
                row = current or latest
                agents.append({"id": role, "name": name, "status": row["status"] if row and row["status"] in ("running", "queued", "failed", "blocked", "cancelled") else "idle",
                    "taskId": current["id"] if current else None, "pid": current["pid"] if current else None,
                    "lastSeen": row["updatedAt"] if row else None, "summary": (row["result"] or row["error"] or row["body"])[:500] if row else "Waiting for a task"})
            return {"agents": agents, "tasks": tasks,
                    "messages": [dict(r) for r in self.db.execute("SELECT * FROM messages ORDER BY id DESC LIMIT 300")][::-1],
                    "events": [dict(r) for r in self.db.execute("SELECT * FROM events ORDER BY id DESC LIMIT 300")][::-1],
                    "server": {"startedAt": self.started_at, "pid": os.getpid(), "sandbox": self.sandbox, "maxWorkers": self.max_workers,
                               "mode": "test" if getattr(self.executor, "is_test", False) else "live", "stopping": self.stopping.is_set(),
                               "turnMode": "fresh-with-bounded-history", "timeoutSeconds": self.timeout}}

    def close(self):
        if self.closed:
            return
        self.stopping.set()
        if self.scheduler:
            self.scheduler.join(timeout=3)
        with self.lock:
            for row in self.db.execute("SELECT id FROM tasks WHERE status='queued'").fetchall():
                self.cancel(row["id"])
            active = list(self.active.items())
            for task_id, _ in active:
                self.cancel(task_id)
        for _, item in active:
            item["thread"].join(timeout=25)
        # Keep DB open if a misbehaving test executor ignores cancellation.
        with self.lock:
            if not self.active:
                self.db.close()
                self.closed = True
