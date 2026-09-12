# Intake Brief — origin-recurring-consumer

**Date:** 2026-09-12
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** yes

## Goal

Make arch-index itself a recurring, non-vacuous consumer of its shipped `forbid origin`
capability: review new escaping assertion/division sites in the existing bounded OCaml library
corpus on every CI run, retain gate/report/coverage evidence, and distinguish a policy gate
holding from a completeness proof. The reference is the owned `lib/arch_index` corpus at main
`d7112964df679fb44bc033e878059537208f58da`; current checkouts remain the live subject of the gate.
Pin reference revision, module inventory and observed coverage in versioned review data rather
than pretending future source revisions remain byte-identical to the reference.

Two independent values: (1) a real CI regression consumer on production library code; (2) a
bounded authentic-control harness demonstrating that it detects a new/increased origin and
rejects incomplete measurement. Synthetic controls validate the consumer, not its deployment
adoption. Reports expose concrete sites, coverage and limits; no reviewer-time saving is claimed
without measurement. This precedes the separate arch-guard value-analysis experiment.

## Scope Boundary

Included: dedicated self-origin rules/allow-list/reference metadata, a small repository-local
runner, authentic controls and Tezt registration, CI execution/artifact persistence, usage and
reference-update documentation. Reuse Arch_rule_eval through existing arch-rules/arch-report
CLIs. Preserve the existing four reachability rules and all existing CI gates unchanged.

Out of scope:

- Third-party targets, vulnerability hunting, exploitation or campaign automation.
- New abstract-value engine, division suppression, interprocedural summaries, array analysis.
- Changes to origin extraction, verdict policy, counted allow identity or public report schema.
- Automatic allow-list regeneration, automatically accepting a coverage drift, formal proof.
- Generic corpus discovery/download, new external corpus checkout or extra durable worktree.
- MCP, release/deploy, global tooling changes or vendor roster bundle changes.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `lib/arch_tools/arch_rule_eval.ml` | Reuse existing origin evaluation, no change planned | `Origin (s, forms, channel, allow)` |
| `bin/arch_rules/arch_rules.ml` | Gate JSON and exit policy | `computed`, `failing`, `results` |
| `bin/arch_report/arch_report.ml` | Publish evidence, not policy gate | optional `--rules` |
| `docs/fitness-functions.md` | Existing counted-exemption contract | no automatic `--regenerate` |
| `arch-rules.txt` | Existing reachability consumer, preserved | four `forbid reach` rules |
| `.github/workflows/ci.yml` | Add separate origin consumer and retained report artifacts | self-index at line 128, existing rules at 292 |
| `lib/arch_index/dune` | Existing production corpus build, no change planned | library with inline tests |
| `lib/arch_index/arch_index_cmt.ml:1374` | Review existing assertion allowance | nonempty `segs`, `split_last [] segs` |
| `tezt/tests/actionable_review_reports.ml` | Standalone checker/Tezt pattern | exact exit mapping controls |
| `tezt/tests/rules_origin.ml` | Existing authentic CMT and counted-origin tests | multiple sites and 201 caps |
| `tezt/tests/dune`, `tezt/tests/main.ml` | Wire new registered controls | CLI dependencies and registration |
| `docs/adr/001-self-index-golden.md` | Existing pinned measurement workflow, preserved | committed self-index counts |

New paths to freeze in plan: `scripts/origin-consumer.js`,
`checks/origin-recurring-consumer.js`, `tezt/tests/origin_recurring_consumer.ml`,
`test/fixtures/origin-consumer/` reference/rules/allow data, and `docs/origin-consumer.md`.
README/CHANGELOG may link and describe the consumer. Task briefs/spec/roster/friction artifacts
are in scope. No production library modification is needed by this brief.

## Architecture Notes

### Measured intake probe (not feature acceptance)

Fresh built CMT self-index from the current checkout: 23 modules, 828 functions, 5223 calls.
SQLite enumeration observed 491 origin rows across channels; exception assert=1, division=0.
Rule `file:lib/arch_index/** form:assert,division channel:exception` with an empty allow-list
returned VIOLATION, exit 1, exactly the existing assertion at arch_index_cmt.ml:1388.
With one manually authored x1 entry, the SAME indexed corpus returned UNKNOWN, gate exit 0:
coverage 1045 graph nodes (including external nodes), one selected origin/site, one matching
allow entry, 138 top-bearing nodes reported by the existing note. This is not 1045 source
functions or a proof that no fatal origin exists. Neither probe changed source or evaluator.

Existing assertion identity:
`collect_calls_from_expr.<fun:1374:21>.<fun:1385:36> | lib/arch_index/arch_index_cmt.ml:1388 | assert | Assert_failure | x1`.
Source review: split_last is called only with a nonempty segment list; its recursive multi-item
case reaches a singleton before the empty case. This justifies one explicit initial allowance
under delegated review, not a machine-checked invariant or an automatic exemption generator.
The spec/review must challenge it; source/identity changes require a deliberate reviewed edit.
Zero current division sites is a baseline observation, not proof that division detection works;
the authentic injected-division control must supply that separate evidence.

### Runner and reference contract

- Repository-local invocation: `node scripts/origin-consumer.js --out <new-output-directory>`
  after the documented build. It creates a fresh index from the bounded built library itself;
  no arbitrary preexisting DB input, no source mutation or internal Dune rebuild. Reindexing is
  cheap and avoids claiming an externally supplied DB belongs to the current corpus.
- Reference module paths and a reference observation are pinned to d711296. Each run records
  current revision, rule/allow/reference identity, schema/error configuration and actual input
  inventory/digests. This is provenance under a trusted local build assumption, not a source
  freshness certificate; CMT bytes can vary with compiler/build path and are not global pins.
- Missing/extra module population relative to the reviewed scope or an incomplete/empty index
  is an explicit coverage failure, never a clean result. Reference source revisions and counts
  are observations, not an excuse to suppress new sites. Existing golden/recalibration gates
  remain independent. Changes to scope require deliberate reference edits.
- Reuse arch-rules for policy and arch-report for artifacts. Unknown is permitted as UNKNOWN
  (as in the established gate policy); violation always fails, vacuity/NOT_COMPUTED/refused
  execution never pass. Report exit 0 alone is never gate evidence.
- Retain gate JSON, report JSON/SARIF/HTML and a machine-readable run/coverage record on success
  and policy failure. Record corpus-wide raw counts separately from the evaluator's opaque
  per-rule coverage note; do not parse prose into a claimed stable structured API or duplicate
  origin graph/allow evaluation. Failure artifacts must identify incomplete execution.
- Output directory must be newly created and owned; refuse preexisting output to avoid stale
  success artifacts or overwrites. Remove transient DB/build fixtures, retain only useful
  reports/diagnostics. On an I/O error, incomplete reports are not publishable as a successful run.
- Exact controls: authentic clean/allowed case, new division site, increased same-site count,
  empty/wrong/incomplete corpus, unavailable origin pass and tool/execution error. Assertions
  must inspect verdict/details and real exits; test runner errors are not expected violations.
- CI runs this consumer within the existing required build job and uploads compact reports
  even when the origin policy fails, with bounded retention. No database or build tree uploaded.

Claims reconciler, freshness authority, KB and hooks are absent. No authority projection is
claimed. Trust boundary yes reflects converting measured artifacts into a CI success signal;
Full feature route chosen under standing autonomy, not a formal-verification route.

## Quality Gates

Existing runnable gates:

```bash
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force
rtk proxy git diff --check
```

No separate formatter/full-linter configured; known opam metadata lint debt is not passing.
Existing CI golden, attributed recalibration, four architecture rules and impact smoke remain
mandatory. New consumer/control commands will be frozen as runnable CHECK-N contracts in spec;
the paths above do not yet exist and are not represented as passing. Local and remote CI gates
must both complete with real exits before the exact-head PR merge.

## Open Questions

None delegated to implementation as TBD. Corpus, reference/current distinction, initial
allowance, scope refusal, artifact retention and authentic controls are pinned here and subject
to adversarial specification. Any material direction change must be surfaced to the user.
Validation uses explicit standing autonomous authorization; no new human quiz is claimed.
