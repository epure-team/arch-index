# QA Brief — schema-versioning

**Date:** 2026-09-03
**Status:** GO ✅
**Round:** 1 (qualifying 0/5)

## Round state

Fresh cycle, round 1. `qa_no_go_round: 0/5`.

## Quality Gates

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build | `dune build @all` (worktree) | ✅ PASS | 0.27s |
| Tests | `dune test --force` (worktree) | ✅ PASS — 89/89 tezt tests + 6 new inline tests (`arch_index_db.ml`) | 84.5s |

No documented lint/format gate beyond `dune build`'s own warnings-as-errors flags (per the intake
brief's Quality Gates section). Same `Statement error (CONSTRAINT): FOREIGN KEY constraint failed`
stderr lines as every prior round — confirmed (again) as the documented, intentional
rejection-attribution diagnostic (`lib/arch_index/arch_index_db.ml`), not a regression.

## Tests: detail

- New tests added: 6 inline tests (`arch_index_db.ml`) — well-formed version string,
  `schema_sql` defines the base tables, `schema_version_at_least` self-satisfaction and
  future-version rejection, main/flat version identities are distinct, flat version is
  well-formed
- Existing tests: 89 pass, 0 skip, 0 fail
- Regression detected: NO

## Code-intel gate

`kb/` absent — skipped (no `code-intel` block).

## Independent end-to-end reverification (not just trusting the test suite)

No `specs/schema-versioning.md` exists (fix-type task, formal spec skipped) — no `CHECK-N`
runnable checks to execute. Instead, independently reran both real production binaries against a
**fresh** fixture (not reused from implement or review rounds):

- `arch_callgraph_ocaml` (the CMT-based, main-schema path) against a real dune-built `.cmt`
  directory → `comment_db_meta`: `schema_version=1.2`, `callgraph_contract=v1`. ✅ matches
  `Arch_index_db.current_schema_version`.
- `arch_index_cli` (the LSP-based, flat-schema path — the actual `arch-index` CLI entry point) →
  `comment_db_meta`: `schema_version=1.0`, `language=ocaml`. ✅ matches
  `Arch_index_db.current_flat_schema_version`, confirmed DISTINCT from the main schema's `1.2` —
  this is the exact defect the review round's HIGH finding was about, reverified independently
  here rather than trusting that round's own verification.

## TUI

Not applicable — no TUI in scope.

## Verdict

**GO** — ready for `/roster-ship`
