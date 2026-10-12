# Independent QA report — 2026-09-17

Reviewer: orchestra_quality. Owned paths: tools/orchestra/tests/ only.

## Result

`python -m unittest discover -s tools/orchestra/tests -v` completed with **35 tests passed**, exit code 0, 8.240 seconds on Windows / Python 3.12. This verifies the local orchestration infrastructure with explicitly fake model executors and mocked Codex processes. HTTP, SQLite, scheduler threads, Windows file locks and the rejected duplicate Python-server startup are real local operations.

## Covered behavior

- Report persistence across restart without a model invocation.
- Successful execution versus exceptions, invalid/missing JSON, nonzero exit and invalid handoffs.
- Concurrent roles, serialization within one role, FIFO scheduling, queued and active cancellation.
- Restart converts interrupted queued/running rows to failed; graceful shutdown cancels queued work.
- Automatic delegation is bounded by depth and chain count; malformed final output never partially routes valid-looking handoffs.
- Mock process cleanup on cancellation, timeout and PID callback failure.
- Default read-only mode; optional workspace-write applies only to UI/developer, with reviewer/coordinator remaining read-only. No sandbox-bypass command flags or shell=True in the adapter.
- HTTP state/POST authentication, foreign Origin/Host/cross-site rejection, malformed body rejection, oversized message rejection, static path allowlist.
- Real OS lock prevents a second owner and rejects a server using another port before opening the owned database. Lock can be reacquired after release.
- Terminal target/sender routing, report versus task distinction, invalid command rejection, quit behavior, shell text treated as message data and external connection URL rejection. A real local HTTP regression also verifies recovery from a rotated connection token without resubmitting work.

## Findings and resolution

Initial review found an unclosed schema literal (import failure), non-idempotent engine close, automatic restart of queued work, unauthenticated state reads, random UUID ordering for same-millisecond submissions, and absent cross-port data-directory locking. Implementation owners corrected these; applicable regression tests pass.

The first new restart regression test leaked its own SQLite connection because the sqlite context manager does not close connections. The test now closes it explicitly; this was a test-harness fault, not an app failure.

Root launcher review identified PowerShell 7 network exception handling and URL fragment validation. Root corrected these. UI review requested preservation of user edits made while submission is in flight; UI owner implemented it.

## Static UI / documentation review

The dashboard renders model text using textContent, polls real state, stops animation and disables sending/cancellation on disconnect, distinguishes test/live and read/write modes, and states that execution completion is not independent-review approval. Reports do not claim to trigger a reply. The README documents fresh CLI turns, bounded history, explicit follow-up for report synthesis, and the distinction between role instruction ownership and OS file isolation. Runtime records and tokens are excluded by .gitignore.

## Root-executed live evidence, independently inspected

The following checks were executed by root, not this reviewer. This reviewer read the saved evidence and checked that the stated conclusions match the records:

- `.orchestra/live-verification.json`: five successful actual Codex invocations. The delegation chain is coordinator → UI → developer → reviewer, followed by a reviewer report saved to the coordinator inbox. A separate reviewer task ran concurrently. The coordinator interval is 2026-09-17 13:55:54.859–13:56:09.078 UTC; reviewer overlap is 13:55:54.993–13:56:04.907 UTC. This proves message transport and actual execution overlap, not application implementation or code-review quality.
- `.orchestra/cancellation-verification.json`: active task cancelled, owned PID 20536 exited, and queued cancellation never spawned a process. This establishes the observed owned process exit; complete descendant enumeration was not independently performed by this reviewer.
- `.orchestra/browser-verification.json`: 11 checks passed with no page errors, including actual connection, four roles, template without execution, report persistence without a task, text-safe XSS payload, task detail, draft/focus preservation during polling, desktop capture, 390px overflow check, disconnect behavior and reconnect. Root used isolated Chrome because the native browser tool could not bootstrap. Root reports that a discovered overflow was corrected before the passing rerun.

Root also reported opening four role terminal clients. This reviewer did not directly observe those windows. The terminal connection-refresh change and stop-script process-exit wait were independently read; the token-rotation regression above was independently executed.

## Remaining limits

- Model output quality and application development success. Root live logs establish successful Codex responses and routing, but the smoke tasks deliberately prohibited tool/file access, so actual shell sandbox behavior is not established.
- Complete Windows descendant-tree termination after a task with spawned tool children; the inspected root cancellation evidence establishes the directly owned CLI PID exit.
- Direct reviewer observation of terminal windows, comprehensive keyboard/screen-reader accessibility, and layouts beyond the inspected root browser checks.
- Successful workspace-write modification of a real assigned file.
- Persistent resumed model sessions, automatic coordinator report synthesis, OS-enforced per-role file isolation, or orphan cleanup after an ungraceful server kill; these are not features verified here.

Root owns the live CLI, launcher and browser smoke checks and the final acceptance decision. No external Codex jobs were started by this reviewer.

## Reopened acceptance after real write probe

Root subsequently reported a real assigned-file write probe that exited normally but did not create the file. The previous adapter treated valid final JSON as completion even when its summary described inability to finish. The earlier 35-test result predates the explicit `outcome` contract and does not establish successful writes. Backend and tests are being updated to require `completed`, `blocked`, or `failed`; non-success outcomes must not dispatch follow-on tasks. Final acceptance remains open pending the regression rerun and root's reviewed write-path retest.
