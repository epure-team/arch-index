# Investigation — transient polyglot QA stall

**Date:** 2026-09-15
**Status:** HYPOTHESES IN PROGRESS
**Scope:** read-only diagnosis of the unchanged multilang test; no LSP fix.

QA round1 hung in `index: one polyglot repository, one database` after
TypeScript5.9.3 returned `No Project.`. The owned CLI waited with a zombie Node
child; targeted SIGTERM of CLI2903607 yielded exit143 and Tezt exit1. Logs are
retained in attempt4-main-qa-2FxqyG. This was not an OCaml product assertion RED.

An unchanged focused reproduction ran `opam exec -- dune exec
tezt/tests/main.exe -- --no-color --file tezt/tests/multilang.ml`: exit0 in10105ms,
source_state_unchanged=true, actual test SUCCESS. Evidence:
`improvement/2026-09-14-tezos-resolution/attempt4-lsp-repro-zQOQbx/`.
Three preceding reviewer full340 runs also passed. The stall is intermittent;
its exact cause and introduction are not established and no fix is claimed.

| Hypothesis | Result | Evidence |
|---|---|---|
| Deterministic new recursive-target failure | Not reproduced; unchanged targeted Go/TS case passes | focused.log; runner/client/extractor/JSONRPC/multilang diff vs PR107 exits0 |
| Server readiness/project race | Open | failed workspace/symbol `No Project`; lsp_client.ml:173 readiness path, runner.ml:312 symbol extraction |
| Shutdown/child lifetime stalls after server exit | Open | live CLI waited with zombie child; lsp_client.ml:583 shutdown ends with await_proc; exact blocked stack not captured |

No code change or proposed patch without a proven root cause. A future bounded
LSP investigation should capture readiness/protocol/process-lifetime evidence
on both sides of the race and add an authentic regression before fixing it.
That is outside this local-recursion iteration.

A fresh full QA round on the unchanged reviewed implementation may run once;
all gates must pass, no filter or timeout/threshold relaxation. Preserve round1
NO-GO in the audit. If the stall recurs, stop instead of retrying until green.
No new product iteration or new review claim is created by this verification retry.
