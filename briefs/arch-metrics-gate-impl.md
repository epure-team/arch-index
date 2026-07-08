# Implementation Brief — arch-metrics-gate

**Date:** 2026-07-08
**Mode:** full
**Status:** COMPLETED

## Modified files

| File | Type of change | Reason |
|---|---|---|
| `lib/arch_compare/arch_compare.ml` | addition | compare engine (port of octez arch_compare.ml + spec deltas) |
| `lib/arch_compare/arch_compare.mli` | addition | public API for CLI + tests |
| `lib/arch_compare/dune` | addition | library stanza (yojson) |
| `bin/arch_compare_cli/arch_compare_cli.ml` | addition | `arch-compare` CLI, exits {0,1,2} |
| `bin/arch_compare_cli/dune` | addition | executable stanza |
| `arch-compare` | addition | top-level wrapper script (repo convention) |
| `test/test_arch_compare.ml` | addition | 25 Alcotest cases (FR-006..017, EC-2..6) |
| `test/dune` | modification | wire new test |
| `arch-query` | modification | `metrics` subcommand + header doc; `-o FILE`; exit 2/3 paths |
| `.github/workflows/ci.yml` | modification | "Metrics regression gate" step reusing /tmp/self.db |
| `metrics-baseline.json` | addition | committed self-index baseline |
| `.metrics-accept` | addition | empty policy, format documented in header |
| `docs/adr/002-metrics-gate.md` | addition | regeneration, waiver workflow, C-5 semantics, consumer HEAD-pinned pattern |
| `README.md` | modification | use-case bullet |

## Decisions made

- Strict JSON parsing returns `result` (octez silently coerced bad input to empty maps — that would satisfy FR-009's exit-2 requirement only accidentally); CLI maps `Error` → exit 2 naming the file.
- Duplicate `.metrics-accept` entries → invalid (spec FR-014; stricter than octez).
- `json_object()` emission with printf fallback behind a runtime probe (plan decision); sqlite3 3.53 in dev has JSON, fallback untested on a real old sqlite (code path reviewed, shares per-metric SQL).
- Self-index reality (anticipated as C-10): the CMT producer's `functions` table lacks `line_count`, so `large_functions` is omitted from the self baseline; `kind` exists but is all-NULL, so `may_top_edges=0` is emitted. Both faithful to FR-002/003.

## Quality Gates

- [x] Build: `opam exec -- dune build` ✅
- [x] Tests: `opam exec -- dune test` ✅ (61 tests total across 4 suites; 26 new in test_arch_compare — 25 at implement time, +1 template-hazard case added during review) _(count corrected after cross-runtime QA dispute)_
- [x] `./selftest-contract.sh` ✅  `./selftest-load.sh` ✅
- [ ] `./selftest-effects.sh` ❌ **pre-existing failure at baseline** (verified via `git stash`: fails on clean tree too — "effects-of exported_entry missing FieldAccess/HashTbl"). Not in CI, not touched by this change. Reported, not hidden.
- [x] AC-7 dogfood: clean compare → exit 0; artificial `large_files+1` → exit 1.
- [x] CHECK-1..7 all verified manually (see QA scope for commands).

## Points of attention for review

- `arch-query` metrics branch under `set -euo pipefail`: `addpair`/`emit` helpers, probe + fallback path (fallback not exercised by tests on this machine).
- `-o` argument handling (uses positional `$A`/`$B` — `metrics -o` without FILE → exit 2, unknown arg → exit 2).
- CI step ordering: gate runs after the golden diff, reusing `/tmp/self.db`.
- Baseline contains informational metrics too (harmless — untracked by design, FR-008/FR-020).

## Identified out-of-scope

- Pre-existing `selftest-effects.sh` failure (should get its own fix task).
- `arch-callgraph-ocaml` writes NULL `kind` + no `comment_db_meta` in main-schema mode — worth a look under item 3+ (affects contract queries, not metrics).
- Friction: subagent budget exhausted mid-pipeline → spec/plan/implement sub-agent roles executed inline.
