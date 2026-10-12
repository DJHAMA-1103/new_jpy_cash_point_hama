# Independent verification

Run from repository root: `python -m unittest discover -s tools/orchestra/tests -v`.

The test executor is deliberately fake (`is_test = True`). These tests validate orchestration and HTTP behavior, not Codex authentication, model quality, real CLI execution, Windows child cleanup, or visual rendering. Real CLI smoke and interactive terminal/browser checks must be recorded separately.

Acceptance scenarios:

- Durable messages and tasks survive engine restart; interrupted work cannot appear completed.
- Different roles can overlap; two tasks for the same role cannot overlap; total concurrency is bounded.
- Reports and questions are delivered without automatically invoking another paid model turn.
- Explicit delegation is bounded by chain depth and task count; final output is validated before routing.
- Failed, cancelled, invalid, or missing model output cannot become successful completion.
- Queued and active cancellation are distinct; shutdown stops future dispatch.
- API requires a bearer token and rejects foreign browser origins, invalid payloads and path traversal.
- Runtime tokens/logs/database stay outside version control; command arguments never disable sandbox/approvals.
- Dashboard distinguishes saved messages, pending tasks, running tasks and failures; no simulated work is presented as real.
