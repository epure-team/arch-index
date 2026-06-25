# QA Brief — arch-serve

**Date:** 2026-06-25
**Status:** GO ✅

## Quality Gates

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build | `opam exec -- dune build` | ✅ PASS | 0.6s |
| Tests | `opam exec -- dune test` | ✅ PASS | 0.2s |
| Format | `opam exec -- dune fmt --preview` | ⚠️ PRE-EXISTING (ocamlformat absent from project switch) | n/a |

**Format gate note:** `ocamlformat` is installed in `octez-setup` switch but not in the project's local switch. `dune fmt` fails identically on unmodified main — not caused by arch_serve. Not counted as a regression.

## Tests: detail

- New tests added: 0 (arch_serve is a binary; no unit tests)
- Existing tests: all pass (53 inline + alcotest for arch_index library)
- Regression detected: NO

## Spec Runnable Checks

| Check | Description | Result |
|---|---|---|
| CHECK-1 | `GET /` returns HTML with `<title>arch-serve` | ✅ PASS |
| CHECK-2 | Missing DB → exit 1, stderr has "cannot open database" + path | ❌ FAIL |
| CHECK-3 | `/api/modules` — `has_mli` is boolean | ✅ PASS |
| CHECK-4 | `/api/functions?exposed=1&min_score=40` — only matching rows | ✅ PASS |
| CHECK-5 | `/api/graph/neighborhood` — `{nodes, edges, truncated}`, `module_id` present | ✅ PASS |
| CHECK-6 | `/api/reaches` — returns `PATH_EXISTS` or `NO_MUST_PATH` | ✅ PASS |
| CHECK-7 | `/api/reaches?from=nonexistent_fn` — returns error JSON | ✅ PASS |
| CHECK-8 | `kill -INT <pid>` → exit 0 | ✅ PASS |

## NO-GO issues

### CHECK-2 FAIL — Missing DB message and exit code wrong

**Command:** `_build/default/bin/arch_serve/arch_serve.exe /nonexistent.db 2>&1; echo "exit:$?"`

**Expected:** exit:1, stderr contains "cannot open database" and the file path.

**Actual output:**
```
Usage: arch-serve [--help] [--port=PORT] [OPTION]… DB
arch-serve: DB argument: no /nonexistent.db file
exit:124
```

**Root cause:** `db_arg` uses `Arg.(some non_dir_file)` (arch_serve.ml:401–403). Cmdliner's `non_dir_file` converter validates that the path exists before `serve()` is called. The custom "cannot open database" handler at lines 376–381 never runs. Cmdliner exits with code 124 (`Cmd.Exit.cli_error`) and its own message format.

**Fix:** Change `Arg.(some non_dir_file)` to `Arg.(some string)` so any path is accepted, and let `serve()` handle the missing-file case (the code there already produces the correct message and calls `exit 1`).

**Spec reference:** FR-002 / AC-2 — "When the database file cannot be opened, the server MUST exit with code 1 and emit a message to stderr including the file path and a reason string."

## Verdict

**NO-GO ❌** — return to `/roster-implement` for:

`arch_serve.ml:401` — change `Arg.(required & pos 0 (some non_dir_file) None & ...)` to `Arg.(required & pos 0 (some string) None & ...)` so Cmdliner accepts any path string and the custom "cannot open database" handler in `serve()` runs for missing files.
