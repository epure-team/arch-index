# Implementation Brief — functor-instance-resolution

**Date:** 2026-09-13
**Mode:** full
**Status:** COMPLETED

## Implemented scope

The syntax-only application catalogue is implemented end-to-end: additive
main-schema1.14 tables; per-selected-input accounting; closed Typedtree operand,
location and diagnostic data; transactional input persistence and independent
completion marker; read-only whole-snapshot query with strict limits/refusals.
No target substitution, 0CFA, call-edge promotion or Tezos precision claim.

| Files | Change |
|---|---|
| architecture-schema.sql, lib/arch_index/arch_index_db.ml, arch_index_support.ml | Catalogue schema, drop list, independent marker lifecycle |
| lib/arch_index/arch_index_functors.ml/.mli | Traversal, exact-string selection, atomic persistence, completion validation |
| lib/arch_index/arch_index.ml, arch_index_cmt.ml/.mli | Isolated callbacks and collection outcomes, preserving graph return tuple |
| lib/arch_tools/arch_functor_catalogue.ml, bin/arch_query/arch_query.ml | Read-only validated query and six-format CLI output |
| tezt/fixtures/functor_catalogue/, tezt/tests/functor_catalogue.ml, main.ml, dune | Native fixtures/probes and ten registered tests, including four independent groups |
| scripts/check-functor-catalogue.js | Owned inventory/lifecycle/crafted-query/legacy-compatibility oracles |
| README.md, docs/schema.md, docs/functor-catalogue.md | User-facing schema/reindex/query/limitations documentation |
| briefs/, roster/functor-instance-resolution/ | Plan collateral amendment and traceable execution/calibration evidence |

## Decisions and corrections

See integration-checkpoint.md and calibration-attribution.md in the task evidence
directory for genuine red/green cases, rejected premises, probe-source fixes,
full-suite cwd integration correction, six-format independent byte oracle,
provenance-marker fix, and pristine-build duplicate-CMT correction.
The accidental main-library public helper addition was removed; no manifest
widening was used to legitimize that out-of-scope file. CWR/template and a dedicated
OCaml specialist were absent; the recorded manual roster chain and user-authorized
Sol/Terra subagents were used. Root alone owned Dune integration.

## Quality gates at handoff (approval resumed)

- Build: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` — exit0.
- Full forced suite: corresponding `dune test --root . --force` — exit0,
  **266/266 Tezt and64/64 Alcotest pass**, including all ten catalogue cases.
  Evidence: roster/functor-instance-resolution/final-suite-after-calibration.log.
  The historical264/266 pre-calibration log remains preserved, not relabeled green.
- Four standalone Node groups inventory/lifecycle/query/compatibility — exit0.
- Unchanged pristine calibration script `--explain --base89a15af` — exit0;
  golden A=B23/828/5223,C=D24/859/5440; ceiling A=B437,C=D468. Explain0 is not a
  current-pin pass. All eight captured DBs integrity-checked;15 common tables equal
  for both same-corpus binary comparisons;31 source additions attributed by row.
- Bundle22SHA1.6.0 and manifest scope gate — exit0.
- `git diff --check` — exit0. No configured standalone formatter/linter.
- Origin standalone authentic/failures/package checks — exit0 each; authentic
  rerun after reference anchoring also exit0. Fresh consumer and package validator
  exit0; after-calibration package status held, evaluator still UNKNOWN, not PASS.
  The earlier coverage-drift package is retained as historical evidence.

## Authority and remaining pipeline

The user explicitly approved continuation after the exact calibration proposal.
Installed clean_measured430→468, effective ceiling455→493; margin25/floor8000,
self.allow and all evaluator semantics unchanged. Descriptive golden/origin pins
now reflect the independently attributed source population. Reference revision
c2a8add5e394c162eeef4d204a73e1058a436df2 names the actual product-source checkpoint.
The historical PARTIAL event is preserved; completion is appended, not rewritten.

Next: real roster-review, roster-QA, exact-head green PR, rebase merge, notes sync
and active-worktree cleanup. No review/QA GO or PR is claimed by this brief.
User additionally authorized bounded local protocol/Irmin catalogue measurement;
inventory records414 compatible CMTs and dirty-checkout caveats. This supplementary
measurement is not target substitution or a graph precision claim.
ACTIVE_TASK is deactivated at this completion; round artifacts are committed before review.

## Cleanup and residuals

Archived raw final-suite/calibration logs, same-corpus table digests, row/group
attribution and pre-calibration origin package. Removed six exact owned temporary
roots, including the unpublished snapshot clone/builds and obsolete baseline/probe
artifacts (about796MiB). They can be regenerated from the recorded source and
commands; deletion itself is not undoable. The active task worktree/build remains
needed and was preserved. Unrelated worktrees and unknown old Tezt scratch were
not touched. No external scan, held issue publication or cost telemetry staging.
