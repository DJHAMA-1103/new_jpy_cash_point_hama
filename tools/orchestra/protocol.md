# POINT Orchestra local protocol

Python 3.12 standard library. Bind only `127.0.0.1`. Default port 8765.
Roles: `coordinator`, `ui`, `developer`, `reviewer`; human sender `user`.
No tasks are generated on first startup. Queued and running tasks from an interrupted server become failed and require explicit resubmission.

## HTTP

- `GET /api/health`: `{ok,pid,mode}`.
- `GET /api/token`: `{token}`; same-origin browser bootstrap, trusted localhost clients only.
- `GET /api/state`: `{agents,tasks,messages,events,server}`. Tasks newest first (200), messages/events oldest first within latest 300. Poll once per second. Full durable history remains in SQLite.
- `POST /api/messages`: `{from,to,body,kind}`. `from` defaults `user`; kind defaults `task`. Returns HTTP201 `{message,task}`. A report creates no task (`task:null`). Task body max16000 characters. The role sender in a terminal is a human speaking through that role, not proof of model authorship; automatic model reports link to taskId.
- `POST /api/tasks/{id}/cancel`: `{}`. Returns `{task}`; idempotent for finished tasks.
- `POST /api/shutdown`: `{}`. Returns `{ok:true}` then stops server and owned running task processes. Queued tasks are cancelled on graceful shutdown.

`GET /api/state` requires `X-Orchestra-Token`. All POST require JSON, `X-Orchestra-Token`, body <=65536 bytes. Every request checks Host and optional Origin; foreign origins and cross-site browser requests rejected. No CORS. Static files are allowlisted only. API errors `{error}` with 400/403/404. Local clients with OS-user access are trusted; this is not a multi-user authentication boundary. Tokens, task text and logs remain local `.orchestra/` and must not be committed.

Agent fields: `id,name,status,taskId,pid,lastSeen,summary`. Idle means no current queued/running task, not a permanently running model. Task fields: `id,from,to,body,status,result,error,createdAt,updatedAt,chainId,depth,pid`. Status is queued/running/completed/blocked/failed/cancelled. Message fields: `id,from,to,body,kind,taskId,createdAt`. Event fields: `id,role,kind,text,taskId,createdAt`. Server identifies `mode:live|test`, `sandbox:read-only|workspace-write`, `maxWorkers`, `turnMode:fresh-with-bounded-history`, timeout, startedAt, pid, stopping. Times are UTC ISO strings.

## Actual execution and bounded delegation

Each task launches installed `codex exec --json --sandbox read-only --output-schema ... --output-last-message ... -` with prompt through stdin and inherited account/model settings. CLI event/stdout and stderr lines are actual process output, never simulated activity. No global config or permission bypass flags. Role-specific instructions live in engine.py and current project rules are referenced; stale initial-setup role instructions are not copied. Server `--sandbox workspace-write` explicitly enables controlled writes for UI/developer only; coordinator/reviewer remain read-only. The workspace-write adapter uses the installed `--approve-for-me` automatic approval-review option; it does not bypass review. UI/developer must have explicit file ownership in their current assignment or report without edits. Default remains read-only. CLI login/network/sandbox failures remain failed tasks with stderr evidence.

Final output JSON: `{outcome:"completed"|"blocked"|"failed",summary:string,messages:[{to:role,body:string,kind:"task"|"report"}]}`. The summary is automatically delivered as report to original requester, including `user`. Explicit reports enter inbox only. Explicit tasks create real queued invocations. At most three invocations run concurrently, one per role; max depth3, max12 tasks per chain, max100 pending globally, timeout600 seconds. Rejected routing is recorded as `routing_rejected` rather than executing beyond budget. The required outcome describes actual assignment success, a blocker, or failure. CLI exit0 alone never marks completion. Blocked/failed outcomes suppress outgoing task delegation but retain reports. Completed is a model-reported assignment outcome, not independent approval of downstream work or all app requirements.

These are fresh CLI turns with latest12 role messages (bounded prompt history), not persistent/resumed model sessions. Previous reports are read at the next explicit task. User must send a follow-up task to ask the coordinator to synthesize asynchronous results. Avoid claiming automatic report synthesis.

Running and queued tasks become failed after interrupted server restart and require explicit resubmission; no unfinished task automatically re-executes. Cancel stops only that owned Codex process tree, not downstream tasks already queued. Shutdown cancels queued and running tasks. After an ungraceful OS/process kill, orphan process cleanup is not inferred from stale PIDs (PID reuse risk); inspect manually. An OS lifetime lock on server.lock enforces one production server per data directory, even across different ports; stale lock files are harmless because OS locks release with the process.

## Test seam

`Engine(project,data_dir,executor=Fake(),max_workers=3,timeout=600,max_depth=3,max_chain_tasks=12)`. Fake must declare `is_test=True` and implement `__call__(task,prompt,on_event,on_process,cancel_event,timeout)` returning structured output. `submit(sender,to,body,kind='task',parent_id=None)`, `state()`, `start()`, `cancel(task_id)`, `close()`. Constructor does not start scheduling. `server.make_server(engine,port=0,token=None)` permits an ephemeral test listener. Test executors are explicitly shown as test mode and cannot be selected through production CLI arguments.
