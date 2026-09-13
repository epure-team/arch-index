# Calibration attribution — functor catalogue

Date: 2026-09-13. No constant, reference, allowance or evaluator has been changed.

## Pristine measurement

Unmodified `scripts/recalibrate.sh --explain --base
89a15afb51fa89eb0da209a3f611b08b2df31ff3` ran under the existing OCaml5.3 opam switch
in a temporary, detached, unpublished snapshot clone. This reconciles the tool's
clean-HEAD requirement with not committing a failing feature branch. Snapshot
`50b4589e4006a302c794dc4332f850901cd9885c` contains the current implementation
sources. It is a measurement fixture, not a shipped/reviewed revision. Two pristine
worktrees were built and removed by the unchanged tool. Exit0 in explain mode
means a successful measurement, **not current pins**; both pins were reported stale.

| Measurement | A old/old | B new/old | C old/new | D new/new |
|---|---:|---:|---:|---:|
| Golden modules | 23 | 23 | 24 | 24 |
| Golden functions | 828 | 828 | 859 | 859 |
| Golden calls | 5223 | 5223 | 5440 | 5440 |
| Whole-build MUST/NULL, excluding Stdlib | 437 | 437 | 468 | 468 |
| Whole-build calls | 19826 | 19826 | 20525 | 20525 |
| MUST/NULL with indexed root | 141 | 141 | 159 | 159 |
| MUST/NULL with root outside index | 296 | 296 | 309 | 309 |
| Resolver misses by existing equality query | 0 | 0 | 0 | 0 |
| Positive resolved-name control | 4888 | 4888 | 5072 | 5072 |

All cells exceed the unchanged8000-call adequacy floor. Both marginal comparisons
A=B and C=D hold. `calibration.log` is the actual tool output.

All eight generated SQLite databases were retained through read-only open handles
until the tool finished, then copied after its cleanup trap. Each passed
`PRAGMA integrity_check`. Comparisons of15 existing graph/error tables, excluding
only producer_run_id/created_at/last_analyzed fields, were also exactly equal on
each same-corpus pair. Their SHA256 digests are in `calibration-rows.json`; this
rules out cancellation hidden by the aggregate count on these measured corpora.
It does not assert correctness for unmeasured programs.

## Row attribution

MUST/NULL row identity query:

```sql
SELECT m.path, f.name AS caller, c.call_site, c.callee_name
FROM calls c JOIN functions f ON f.id=c.caller_id
JOIN modules m ON m.id=f.module_id
WHERE c.kind='MUST' AND c.callee_id IS NULL
  AND c.callee_name NOT LIKE 'Stdlib.%'
ORDER BY m.path, f.name, c.call_site, c.callee_name;
```

The31 new rows are localized to four files:

| Source | Added rows | Cause |
|---|---:|---|
| lib/arch_index/arch_index.ml | 4 | Sqlite3.bind/finalize/step in outcome persistence |
| lib/arch_index/arch_index_functors.ml | 8 | SQLite, Yojson and compiler Path calls |
| lib/arch_tools/arch_functor_catalogue.ml | 14 | Caqti type combinators and Yojson parsing |
| tezt/tests/functor_catalogue.ml | 5 | Existing Arch_tezt.Check list/option combinators |

No `(source path, callee)` group loses rows, and every pre-existing group retains
its multiplicity (`calibration-groups.json`). Eight anonymous `process_cmt` caller
names initially appear removed at the stricter source-coordinate identity level:
the insertion moved them18 lines. All eight old rows match their new rows after
that exact18-line adjustment to both lambda coordinates and call site, verified
without dropping caller identity (`calibration-shifted-rows.json`). The first
attempt applied that adjustment to all anonymous functions in the file, including
unchanged earlier ones; it failed and was corrected to the eight affected
process_cmt rows. No failed diagnostic was counted as verification.

## Clean-build defect found during measurement

The first snapshot8656e4a failed ceiling C because the fixture's explicit
`(:standard -bin-annot)` generated both byte/catalogue.cmt and native/catalogue.cmt
for the same source. The incremental build had only the byte artifact and hid
this duplication. Root confirmed both paths in a separate pristine build.
Removing the redundant flag lets Dune provide its usual byte annotation without
the extra native artifact. The successful50b4589 measurement above validates the
fixture-only correction; the producer's rejection behavior was not weakened.

## Origin observation and proposed changes

The golden current corpus has495 origins, versus491 previously. Groups differ
only by exception/failwith +1, exception/reraise +2, option/raise +1; the new
source module is arch_index_functors.ml. The authentic production diagnostic
reported coverage-drift, with policy UNKNOWN/failed=false/gate_exit0, not PASS
and not a policy exemption. Reference update remains pending, separate from
unchanged self.allow and evaluator semantics.

Proposed descriptive golden:24modules/859functions/5440calls. Proposed origin
observation:24/859/5440/495, with the same unchanged allowance. Both need a durable
feature revision/rationale when implementation can complete.

**Human decision needed for the normative ratchet:** clean_measured430→468,
unchanged headroom25, hence effective ceiling455→493 (+38). The decomposition is
7 already present at the task's base plus31 from this source addition. The tool
expressly refuses automatic loosening even when source-only attribution holds.
No increase is installed without explicit acceptance of this exact change.
