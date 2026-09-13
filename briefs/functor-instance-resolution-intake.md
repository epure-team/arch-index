# Intake Brief — functor-instance-resolution

**Date:** 2026-09-13
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** yes

## Goal

Continue roadmap item 7 with its first independently shippable increment: an
OCaml CMT functor-application catalogue, persisted in the main SQLite index and
inspectable through arch-query. Preserve application structure, named versus
anonymous versus unit arguments, nested application order, and source provenance
without pretending to identify runtime instances. This makes the currently
discarded composition facts visible and testable before parameter substitution.

This is slice 0 of bounded functor-instance resolution, not completion of that
roadmap item. Value is observable composition coverage and explicit limitations;
no call-graph precision improvement is claimed. Subsequent separately reviewed
slices may recover heads, substitute parameters under justified closure rules,
and handle instance-dependent exceptions. Standing user authorization covers
autonomous bounded increments, full roster gates, exact-head green PRs followed
by rebase merge, roadmap updates, and owned worktree cleanup.

## Scope Boundary

In scope: source-backed application occurrences from successfully decoded OCaml
implementation CMTs; ordinary and unit applications; nested/chained applications;
named, anonymous, constrained and unsupported expression shapes with explicit
diagnostics; binder-shadowing-safe occurrence identity; deterministic ordering;
main-schema persistence and rebuild lifecycle; a read-only `functor-applications`
query with documented output and explicit refusal when collection did not run;
native owned fixtures and complete documentation/verification for this slice.

What is explicitly OUT of scope:

- Reclassifying any call, specializing or cloning function definitions, replacing
  module-parameter TOPs, or changing exception/error/rule/reachability verdicts.
- Inferring a closed world from observed applications, function exposure, or
  absence of a row; runtime application counts and cross-build UID guarantees.
- Global 0CFA, first-class-module target inference, Shape-based target reduction,
  external functor-body recovery, or compiler/toolchain upgrades.
- New standalone executable, flat/LSP schema production, MCP/UI integration,
  or publishing the private issue draft (its explicit publication hold remains).
- Third-party vulnerability scans, exploit reproduction, Tezos benchmark gains,
  or any claim of whole-program/formal verification.
- Cleaning unrelated worktrees/files or publishing local cost telemetry.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `lib/arch_index/arch_index_cmt.ml` | Existing typed-tree traversal and producer entry | `Tmod_apply _ ... -> ()` in definition traversal; `Implementation structure` entry |
| `lib/arch_index/arch_index_cmt.mli` | Producer data boundary; preserve existing call API | `type pending_call = { caller_module; caller_name; head; ... }` |
| `lib/arch_index/arch_index.ml` | Run lifecycle and insertion/resolution | Clears completion markers before table recreation; creates producer run and prepared statements |
| `lib/arch_index/arch_index_db.ml` | Main schema version and DB helpers | `let current_schema_version = "1.13"` |
| `lib/arch_index/arch_index_support.ml` | Reindex lifecycle | `completion_marker_keys`; `schema_tables_to_drop` |
| `architecture-schema.sql` | Main relational schema | `UNIQUE(module_id, name)` on functions; no application entity |
| `bin/arch_query/arch_query.ml` | Read-only CLI dispatch and formatting | `Arch_db.open_ro`; strict decimal `limit_of` |
| `tezt/tests/callgraph_nested.ml` | One-definition-per-body and frontier regression | Applied module creates no `M.%` function rows |
| `tezt/tests/schema_drop_list.ml` | Mechanical producer table lifecycle gate | Producer-written tables must be dropped or explicitly self-managed |
| `tezt/tests/completion_markers.ml` | Completion claim lifecycle gate | Written metadata keys must be classified |
| `.github/workflows/ci.yml` | Authoritative build/test/self-index/consumer gates | OCaml 5.3; full build before `dune test --root .` |
| `README.md` | Entry point documentation | CMT path and `arch-query` usage |

New collection/query/test files may be introduced by the validated plan. Existing
directly involved snippets above were read by the operator, not merely located.

## Architecture Notes

- Research is `roster/functor-instance-resolution/research.md`, completed with
  four isolated specialists. It enriches the task; it does not replace its goal.
- Application occurrence, static definition, applicative type equality, and
  runtime module/exception identity are different things. The catalogue describes
  syntactic occurrences in selected decoded artifacts, never a runtime universe.
- Keep one indexed function per definition. Application collection must not
  change the existing definition traversal, pending calls or graph consumers.
- Occurrence keys must tolerate same-spelled binders and same-position synthetic
  nodes. Compiler stamps may distinguish binders during one artifact walk, but
  are not advertised as stable persisted identities across independent builds.
- A complete catalogue means collection finished for its explicitly stated input
  boundary, not that every project artifact or runtime application is known.
  Missing, unsupported and not-collected states must not read as an empty complete
  result. Specify the lifecycle and refusal rules before implementation.
- Any additive main-schema change follows current version 1.13; verify the next
  version against main at shipping, leave flat 1.3 unchanged. New tables belong in
  the reindex drop list; any completion marker must be cleared before rebuilding.
- Local compiler and CI are OCaml 5.3.0/5.3. Ecosystem sources describe 5.5;
  installed 5.3 interfaces and native tests are the implementation authority.
- Full task-text heuristic hits trust and critical keywords in authorization,
  authority disclaimers and excluded vulnerability scans. The earlier negative
  preflight check concerned only a normalized title. Conservatively retain Trust
  boundary=yes; standard Full pipeline under standing autonomy, no automatic
  critical/formal route. Adjacent formal specifications are absent at inspected
  existing source targets. No fresh human reply or formal evidence is claimed.
- No KB, hooks, claims reconciler or orientation resolver is installed. Claims
  metadata remains draft; no validation/projection authority is fabricated.
- Operator validates Type=feature and Trust boundary=yes under the user's express
  autonomy instruction. No new material external authority is needed for this
  bounded slice; publication of the held issue remains excluded.
- Spec clarification decisions for plan decomposition: traverse all reachable
  OCaml5.3 Typedtree children, but only immediate module applications are catalogue
  occurrences. Keep shallow operand descriptors and application-only preorder
  ordinals, scoped by the exact discovered artifact path (copies/symlink paths
  are distinct selections, not unique physical programs). Persist per-input
  outcomes, expected counts and producer provenance; publish no partial input's
  occurrences. Reindex clears eligibility first and drops catalogue tables;
  earn a separate v1 catalogue marker only after complete committed collection
  over a nonempty selected set. No graph/API tuple change.
- The query validates the entire catalogue before applying its default50 strict
  decimal limit or emitting two existing-format tables. Valid empty catalogue is
  exit0; schema/absent marker/inconsistent catalogue refuse exit3 with no stdout;
  malformed usage/open/operational failures remain exit2. Limits do not hide bad
  rows. Public output omits database/run ids and timestamps and states selected
  syntax-only scope, no runtime/closure/target/freshness guarantee. Native producer
  fixtures and independent hand-authored query DBs verify the two stories; typed
  artifact probes cover otherwise unavailable Papply/ghost premises explicitly.

## Quality Gates

Run from the active worktree, serially for Dune:

```bash
# Full build, then unit/integration tests (CI commands with explicit local switch)
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root .
# Installed review bundle integrity
rtk proxy node scripts/review-bundle-verify.js
# Patch hygiene (not a substitute for a formatter)
rtk proxy git diff --check
```

No standalone formatter/linter is configured. Preflight already built the
unchanged tree and collected tests; it did not run the suite. The spec must add
non-vacuous catalogue, compatibility/refusal, deterministic reindex and unchanged
graph checks, with standalone check exits 0/pass, 1/assertion, >=2/error. Full
roster review and QA remain mandatory. CI also runs self-index golden,
recalibration, architecture rules, origin-consumer/artifact validation and change
impact; capture actual outcomes at shipping. MCP skip is not a pass.

## Open Questions

None at intake scope level. Exact output fields, occurrence key format, supported
walk boundaries and completeness states are design obligations for the full spec,
not implementation assumptions. Any conflict with the preserved graph contract
must be resolved before planning or brought back to intake.
