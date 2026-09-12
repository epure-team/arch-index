# Implementer — actionable-review-reports

**Date:** 2026-09-12
**Status: VALIDATED**
**Mode:** full

## Assignment

Implement complete increments A then B from the plan, with actual RED→GREEN before production
changes and immediate tests/docs per increment. Read the validated spec for AC traceability.
Do not stop at a schema-only or report-only partial feature and claim completion. Baseline is
231/231 plus Alcotest (root run documented in preflight), no production code changed during
planning. Establish manifest/base/dirty before any implementation baseline commands.

## Files

Exact allowed candidate paths (modify/create only as needed, read existing files first):
- `bin/arch_rules/arch_rules.ml`
- `bin/arch_report/arch_report.ml`
- `lib/arch_tools/arch_rule_eval.ml`
- `lib/arch_tools/arch_rule_eval.mli`
- `lib/arch_tools/arch_report.ml`
- `lib/arch_tools/arch_sarif.ml`
- `lib/arch_tools/arch_origin_context.ml`
- `lib/arch_tools/arch_origin_context.mli`
- `lib/arch_tools/dune`
- `lib/arch_index/arch_index_exn.ml`
- `lib/arch_index/arch_index_exn.mli`
- `lib/arch_index/arch_index_cmt.ml`
- `lib/arch_index/arch_index_db.ml`
- `lib/arch_index/arch_index.ml`
- `architecture-schema.sql`
- `tezt/tests/report.ml`
- `tezt/tests/actionable_review_reports.ml`
- `tezt/tests/rules_origin.ml`
- `tezt/tests/exn_raise_sets.ml`
- `tezt/tests/sarif_out.ml`
- `tezt/tests/main.ml`
- `tezt/tests/dune`
- `tezt/lib/dune`
- `checks/actionable-review-reports.js`
- `test/fixtures/self-index-stats.txt`
- `docs/schema.md`
- `docs/fitness-functions.md`
- `docs/reporting.md`
- `README.md`
- `CHANGELOG.md`
- `specs/reporting-and-integration.md`
- `specs/actionable-review-reports.md`

Pipeline artifacts: briefs/, roster/actionable-review-reports/, skills-meta/friction.jsonl.
The roadmap in /home/mathias/notes is root-owned, not this implementer's concurrent write scope.
New helper candidates are not instructions to create redundant modules. If an additional
integration file is necessary, report the concrete dependency before widening the manifest.
Never widen to the whole repository or silently label new files pre-task dirty.

## Sequential implementation

1. **A — optional evaluated-rule report, end to end.** Start with authentic failing CLI
   tests/checks for rules/witnesses/order/compatibility. Mechanically share parser/evaluation,
   keep arch-rules gate policy local, and add --rules to report collection plus JSON/SARIF/HTML.
   Preserve unavailable no-rules behavior and all evaluator result semantics. Include exact
   census, ordinals, explanation, safe provenance and error-before-write handling. Update
   report documentation in this increment. Complete only when new focused tests, existing
   report/rules/SARIF regressions, build and whitespace checks pass.
2. **B — typed divisor context, end to end.** Start with failing authentic CMT fixture and
   query/report cases. Add nullable metadata and versioned schema documentation, capture
   original slot-2 syntax, read with capability guards and strict validation, attach bounded
   contexts without changing allow identities/counts, and render in all report artifacts.
   Include old/malformed metadata, both budgets, UTF-8 limits, changed source and unsupported
   producer cases. Complete only with its immediate green tests and docs.
3. **Integrated delivery.** Run the full checker/Tezt/build and self-analysis gates, explain
   any source-driven golden movement per ADR 001, then roster-review → roster-qa → roster-ship.
   Open one complete feature PR, correct failures, merge only exact-head green, resync main,
   update roadmap and remove this delivery worktree/build. No feature tests are deferred here.


## Exact gates

```bash
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune exec --root . tezt/tests/main.exe -- --file report.ml
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/actionable-review-reports.js rules
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/actionable-review-reports.js ordering
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/actionable-review-reports.js operands
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/actionable-review-reports.js compatibility
rtk proxy git diff --check
```

Also run the project CI self-index/golden, recalibration and architecture-rule checks. Inspect
their existing commands and ADR 001 before any changed golden. No passing MCP claim without
its required dependency/token. No concurrent Dune in this worktree; fixture Dune must name its
own explicit root. Capture real final exit codes, no timeout-as-pass. Keep compact evidence,
remove only owned disposable fixtures/DBs. No push or PR: root owns review/QA/ship orchestration.

## Risk controls and environment

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Extraction changes rule verdicts/diagnostics/exits | Medium | High | Characterization/parity before and after; keep policy at CLI boundary |
| Report/evaluator dependency cycle | Medium | High | Shared evaluator below report; one existing verdict vocabulary |
| Availability/provenance conflation | High | High | Mixed verdict and native/imported controls, explicit separate fields |
| Wrong optional argument slot or inferred value | Medium | High | Original-slot fixture and constant/identifier/other/missing controls |
| Site/context cap or exemption-count conflation | Medium | High | Independent limits and same-line multiplicity controls |
| Old DB query refusal hidden as empty success | Medium | High | Guard absent columns; strictly reject malformed present metadata |
| Artifact disagreement or fabricated SARIF locations | Medium | High | One report value, direct cross-format comparisons and schema validation |
| Partial I/O output mistaken as success | Medium | Medium | Nonzero write errors/no success summary; document non-atomic output |
| New indexer functions move golden | High | Medium | Measure; no guessed counts or gate weakening |
| Excess disk or Dune contention | Medium | High | Sole delivery worktree, serial Dune with explicit root; exact temporary cleanup |


Use /home/mathias/dev/agent-roster/agents/specialist/ocaml-dune-specialist.md when the project-local
agent definition is absent. Read roster-implement and tdd-workflow completely. Agent creation
currently hits thread limit; ask root to reuse finished agents if needed, not extra worktrees.
Shared-checkout single writer/build owner. Skill control-file Bash-only guidance conflicts
with the developer's apply_patch requirement: use apply_patch for file edits and record the
override (no installed freeze hook). Commit complete verified work, impl brief, friction and
final ledger event; leave clean tracked/untracked state, deactivate own ACTIVE_TASK on completion.

## Complete contractual context (intake copied for self-containment)

# Intake Brief — actionable-review-reports

**Date:** 2026-09-12
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** no

## Goal

Make arch-index's architecture review reports directly usable: carry existing rule verdicts,
ordered witnesses and explanations into the unified JSON/SARIF/HTML report; expose a documented
review order; retain syntax-level divisor operands as supporting context for `forbid origin`.
This is the approved report-usability roadmap slice, not a change to the roster's own review
finding schema. Success means a reviewer can follow the existing analysis and see its limits
without manually rerunning and reconciling separate commands.

Deliver `arch-report <db> --out <dir> [--rules <rules-file>]`. Optional rules are evaluated in
this invocation through the same implementation as `arch-rules`, against the report's open
read-only database. Without rules, the existing unavailable-verdict behavior remains intact.
The initial operand support covers integer division/remainder primitives only, providing the
bounded foundation for the separately queued abstract-analysis experiment.

## Scope Boundary

In scope:
- Shared rule parsing/evaluation, mechanically extracted rather than reimplemented; existing
  arch-rules exit policy, allow-list identity/count semantics and verdicts remain unchanged.
- Opt-in rule results in all three report artifacts, census over every evaluated rule, ordered
  witness steps, exact/uncertain status, notes, top reasons, detail totals and selector sizes.
- Explained report ordering: VIOLATION, POSSIBLE, uncertainty (UNKNOWN,
  UNKNOWN_NO_CONTRACT, NOT_COMPUTED), vacuity (NO_SOURCE, NO_TARGET), with declaration ordinal
  as stable tie-breaker within each tier. PASS remains in the census and rule-results contract
  but is not an alert. Existing unrelated sections retain their order.
- Syntax-only divisor context for recognized integer division/remainder primitives: second
  original argument slot, never the second present argument. Preserve primitive identity,
  slot number, typed-AST category, and a bounded representation for integer literals and
  identifiers. Categories are integer_literal, identifier, other, missing. Other expressions
  are explicitly not serialized as exact source; no current-source-file reads are required.
  Missing operands and old indexes are explicitly unavailable, never inferred values.
- Additive nullable origin metadata, schema version/documentation update, read compatibility
  for old main and flat indexes. Native CMT producer populates division metadata; other origin
  forms and value channels remain explicitly unsupported for operand context in this slice.
- Structured origin context reaches arch-rules JSON and unified reports as supporting data,
  associated with existing aggregate site identities; never changes allow-list matching.
  Bound displayed context to the existing result detail budget and expose omitted totals.
- Authentic CLI tests, old-schema/empty/error cases, cross-format parity, SARIF validation,
  documentation and roadmap updates, review/QA/green CI before merge, worktree/build cleanup.

Explicitly out of scope:
- Any abstract-value inference, constant propagation, intervals, path feasibility, suppression
  of nonzero literal origins, new proofs or changes to rule gating policy.
- General operand extraction, array-bound analysis, third-party vulnerability reproduction,
  autonomous offensive workflows, recurring external corpus execution (next roadmap slice).
- Importing detached rule JSON, storing rule-result runs in SQLite, background evaluation,
  new freshness certificates, source-file freshness verification or concurrent DB-writer support.
- Roster harness/vendor schema changes, new GUI/editor/MCP behavior, unrelated issues or PR #93.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `bin/arch_rules/arch_rules.ml` | Existing parser/evaluator, result contract and CLI | `List.map (eval t g ~sound:contract_ok) rules`; `witness : string list` |
| `lib/arch_tools/arch_report.ml` | Single collected value and three renderers | `let collect ~db_path`; currently `code_flow = []` |
| `bin/arch_report/arch_report.ml` | CLI arguments and artifact writes | `Arch_report.collect ~db_path t` |
| `lib/arch_tools/dune` | Shared read-model library | `(name arch_tools)` |
| `lib/arch_index/arch_index_exn.ml` | Typed primitive recognition and origin accumulator | `Some P_division -> add acc Division ...` |
| `lib/arch_index/arch_index_exn.mli` | Origin public record | `type origin = { o_form ...; o_col : int }` |
| `lib/arch_index/arch_index_cmt.ml` | Writes finalized origins | `insert_exn_origin ... ~channel:"exception"` |
| `lib/arch_index/arch_index_db.ml` | Origin writer and schema version | `insert_exn_origin`; `current_schema_version = "1.12"` |
| `lib/arch_index/arch_index.ml` | Prepared origin statement | `INSERT INTO exn_origins ... VALUES (?, ?, ?, ?, ?, ?, ?, ?)` |
| `architecture-schema.sql` | Additive origin storage | `CREATE TABLE IF NOT EXISTS exn_origins` |
| `tezt/tests/report.ml` | Actual report CLI and cross-format assertions | `run_report`; `check_verdict_absence` |
| `specs/reporting-and-integration.md` | Existing report obligations | FR-020, FR-021, FR-024, CHECK-5 and CHECK-6 |

New shared evaluator module and focused tests/check script are permitted. Read any additional
existing file before editing it; associated rules-origin, exception and SARIF suites are part
of the regression scope, not substitutes for authentic new report CLI tests.

## Architecture Notes

The full blind research is `roster/actionable-review-reports/research.md` at `dcb5116f`.
An independent Sol design probe and root source inspection agree on shared in-process rule
evaluation. A detached JSON input would introduce an unsolved binding between results and DB;
it is not selected. Preserve one assembled report value for all renderers. Extracting the
evaluator must not introduce an Arch_report/Arch_rule_eval dependency cycle: move shared result
types or keep evaluation input separate as needed, without a second verdict vocabulary.

Evaluation occurs once per report invocation using the same open read-only DB handle. Record
the supplied rules path and available producer metadata. This is not a transactional snapshot
or a cryptographic freshness certificate; use a quiescent index, and document that concurrently
mutating it is unsupported. Do not claim a digest or path proves provenance of imported data.

When rules were supplied and parsed/evaluated, verdict census availability is COMPUTED even
if individual rules returned NOT_COMPUTED. Without rules, preserve the eight compatibility
zeros with NOT_COMPUTED and an explanation. Coverage, rule verdict, verdict-census availability,
syntactic operand category and producer soundness are separate facts. Never map one into another.
An empty supplied rules file is rejected with exit 2 and an explicit diagnostic, matching the
existing shared parser contract. Malformed/unreadable rules also fail before artifact writes;
no fallback to an apparently successful no-rules report. On successfully rendered reports,
exit 0 means artifacts written, even when rules contain VIOLATION or UNKNOWN; arch-rules remains
the separate CI gate. Existing report usage/broken-DB exit 2 and refused-read exit 3 remain.

Research correction during specification: the initial intake assumed the parser accepted an
empty file. Fresh source research found its explicit `defines no rules` rejection. Preserving
that behavior removes an unnecessary parser divergence; this bounded correction is recorded
under standing autonomy, not described as a new human approval.

The report's artifact ordering is a reviewer convenience, not a probability of correctness or
severity conversion. SARIF viewers may reorder alerts. Preserve witness order and use existing
Arch_sarif codeFlows conversion; UNKNOWN witnesses stop at the frontier, not at a claimed target.
External prior art distinguishes ordered paths from secondary locations and severity from
confidence; use these distinctions, not a fabricated numeric confidence score.

Operand context comes from the CMT typed AST, not a potentially newer source file on disk.
Literal representation preserves integer kind without arithmetic or host-width reinterpretation;
identifier text is a display label, not a stable semantic identity. Unsupported complex syntax
has an explicit category and no fabricated source text. Bound representation and HTML-escape it.
All divisions, including literal nonzero divisors, remain recorded origins with unchanged
escape behavior. Supporting context does not enter allow identities or exempt counts. Old
indexes require no mutation/migration on read; absent metadata stays unavailable.

No project KB, claims reconciler, skill hooks, AGENTS.md or CLAUDE.md is installed in this
worktree. README and the reporting contract were read. The deterministic trust and critical
keyword checks on the canonical task sentence both returned false. Type and Trust boundary
are confirmed under the user's standing autonomous execution instruction; no new interactive
approval or comprehension quiz is claimed. Material scope changes still require escalation.

### Resolved specification details (part of this intake's planning contract)

- Rule ordinal is one-based in the parsed rule list (comments/blank lines do not count).
  Duplicate display names remain distinct via ordinal in all formats; no across-edit identity
  guarantee. Full rule results retain declaration order; alert entries use tier then ordinal.
- New rule findings identify the evaluator as arch-rules, not whichever producer_runs row
  sorts last. Do not inherit foreign importer soundness/version. Preserve exact, contract_ok,
  verdict and reasons separately; index producer metadata and imported attribution stay intact.
- Origin supporting contexts use existing site identity plus occurrence position, preserving
  row multiplicity. Keep 200 offender sites; separately cap contexts at 200 per result, emitted
  only for displayed offender sites. context_total counts all matching offender-origin rows;
  context_omitted is that total minus emitted contexts, independent of detail_total. Order by
  site identity, source line/column, then row id for ties. No context contributes to an exemption.
- Literal/identifier text is limited to 256 UTF-8 bytes. Omit an oversized representation whole
  with a limit reason; preserve its category/primitive/slot. No invalid UTF-8 truncation.
- Old absent column/SQL NULL means unavailable. Malformed non-NULL operand metadata or unknown
  category/type refuses diagnostically (report 3, arch-rules 2); no fabricated normalization.
- Preserve witness labels/repetitions verbatim as ordered data; logical-only labels remain
  logical SARIF locations. Operand context is a structured property, never a flow or fake URI.
- All report strings are escaped in HTML. Write failures return 2 without a success summary;
  pre-write input rejection preserves preexisting outputs. Atomic three-file publication is
  not promised; document partial I/O output as unusable.
- New self-contained checker cases are rules, ordering, operands, compatibility. Include
  non-vacuous mixed verdicts/importer controls, duplicate rule names, both context/site limits,
  malformed/old metadata and authentic compiler fixtures. Wire through normal Tezt CI.

## Quality Gates

Run sequentially in this sole task worktree, with explicit switch and Dune root:

```bash
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune exec --root . tezt/tests/main.exe -- --file report.ml
rtk proxy git diff --check
```

No separately configured formatter/linter gate is documented. Supplemental opam lint has an
existing maintainer metadata error and is not a passing gate. CI's self-index smoke golden,
recalibration and architecture rules remain mandatory; if added indexer functions move the
golden, measure per ADR 001 and update only explained source-driven changes. MCP is skipped
without its token and must not be claimed tested. Roster review and QA convergence gates must
pass with truthful evidence. The spec must supply self-contained check commands distinguishing
0 pass, 1 assertion failure, >=2 execution error, wired into normal CI tests rather than relying
on ambiguous test-runner exit codes. New tests must demonstrate RED then GREEN.

## Open Questions

None. Implementation choices within these boundaries are delegated; unresolved specification
contradictions or quality-gate failures are not auto-approved.
