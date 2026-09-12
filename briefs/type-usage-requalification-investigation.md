# Investigation — type-usage-requalification

**Date:** 2026-09-12
**Symptom:** issue #29 reported more type usages than stored rows; its final correction identified deferred FK-rejected usages after duplicate function identities, with same-level shadowing as the residual source.
**Status:** ROOT CAUSE IDENTIFIED — known defects already fixed
**Scope:** read-only requalification of current main `932211be1ecd2b950d7cee6ef8dbbdd7bbed0460`; no original épure corpus rerun or production change.

## Root cause and current disposition

The issue's final correction supersedes its earlier cascade diagnosis: deferred usages held
function ids invalidated by replacement, then failed FK validation when flushed. Do not revive
the obsolete claim that the usages were successfully written and silently cascaded away.

The reported-versus-stored defect is fixed by PR #66 (`2e8eaa71881cbe93fce17d135653b0ae19ed0107`,
merged 2026-09-04). Current `lib/arch_index/arch_index.ml:1717` reads
`count_rows db "SELECT COUNT(*) FROM type_usage"`; line 1719 restricts the resolved count
to stored non-NULL `type_id` rows. These values are printed and returned at lines 1736 and 1764.

Same-level shadowing, the known residual mentioned in the issue, was fixed by PR #50
(`245d8b4fb510ae18e2b413e102269e31d2ee5333`, merged 2026-09-02).
`lib/arch_index/arch_index_cmt.ml:900` assigns distinct `#N` identities while preserving the
bare name for the live binding. The `UNIQUE(module_id,name)` replacement collision is thus
avoided for these bindings. Wildcard bindings are separately excluded and tested.

Failed writes are not successful extraction: `lib/arch_index/arch_index_db.ml:269` records
statement failures, and `bin/arch_callgraph_ocaml/arch_callgraph_ocaml.ml:19` makes them a
nonzero CLI result. Pending type usages are collected only after a successful function insert
(`arch_index_cmt.ml:3189`) and flushed later (`arch_index.ml:1658`).

**Disposition:** close #29 as fixed by already-merged changes. No new known production
data-loss mechanism was found in this bounded requalification.

## Tested hypotheses

| Hypothesis | Result | Evidence |
|---|---|---|
| Current result counts still include refused insert attempts | REFUTED for the covered counters | Post-commit SQL counts at `arch_index.ml:1717`; end-to-end rejection test below. |
| Same-level shadowed functions still share one replacement identity | REFUTED for the covered binding shapes | `arch_index_cmt.ml:900`; `tezt/tests/shadowed_definitions.ml:95` asserts distinct rows and correct call attribution. |
| Original issue was a silent post-insert cascade of type usages | WITHDRAWN historical diagnosis, not reused | Final correction in issue #29; current deferred flush and FK shape (`architecture-schema.sql:311`). |
| Original épure corpus is now complete | NOT MEASURED | That corpus was not rerun; closure is not a blanket completeness guarantee. |

## Observed verification

CI run https://github.com/epure-team/arch-index/actions/runs/34700676526 passed the full
231-test suite. The root independently read the actual log: six shadowed-definition cases
(83–88), wildcard regression (89), and reported-versus-stored regression (90) all succeeded.
This is observed CI evidence; the causal statements above are static code evidence.

The count regression is non-vacuous: `tezt/tests/reported_counts_are_row_counts.ml:92`
injects real insert refusals, line 223 requires the CLI failure gate, line 251 checks the
rejection categories, and line 306 compares all eleven reported counts to database counts.
Resolved counts also have positive gaps from totals, so removing their SQL filter is detected.

## Residual test/documentation debt

`tezt/tests/reported_equals_stored.ml:8` still contains the withdrawn cascade narrative.
Its `type_usage >= 0` assertion at line 109 cannot detect loss. Those are stale explanation
and test-quality debt, not evidence of a remaining #29 production defect. The newer count
regression above owns the actual accounting check.

A bounded follow-up may correct that narrative and positively assert type usages for both
shadowed/live bindings with distinct signature types. Existing shadowing tests cover rows
and call attribution, not an explicit positive type-usage-survival assertion. Do not delay
the next impact slice to reimplement fixes that already shipped.

## Recovery and limits

Historical databases created by affected versions do not repair themselves. Reindex with a
current producer; `lib/arch_index/arch_index.ml:391` drops/recreates its producer tables.
Other identity/extraction gaps remain separately tracked; this report does not close them.

Investigation used a Terra-model read-only subagent plus root review. No new worktree or
build was created for it; no KB is installed. The user's standing autonomous authorization
covered issue triage, without authorizing unrelated code changes.
