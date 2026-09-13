# Implementation Brief — functor-binding-resolution

**Date:** 2026-09-13
**Mode:** full
**Status:** COMPLETED

## Outcome

Same-CMT local named-functor formal provenance is implemented, including local
identity aliases and literal curried telescopes. Each collected catalogue
application receives one matched or unresolved result. The independent v1 marker
requires complete committed catalogue/binding validation. The read-only command
validates the whole snapshot before limiting or rendering.

The historical PARTIAL authority blocker was resolved by explicit user approval
of neutral-attribution reference recalibration. Prior RED/GREEN checkpoints remain
in implementation-progress.md and the append-only ledger. This brief supersedes
their intermediate status. Review, QA, CI and PR/merge remain pending.

## Modified files

- architecture-schema.sql, lib/arch_index/arch_index_db.ml, docs/schema.md:
  three additive main tables, provisional schema1.15; flat schema unchanged.
- lib/arch_index/arch_index_functors.ml/.mli: ordinal-preserving callback.
- lib/arch_index/arch_index_bindings.ml/.mli: identity census, matching/refusals,
  isolated storage and complete persisted-data finalization.
- lib/arch_index/arch_index.ml, arch_index_support.ml: producer integration,
  independent eligibility latch, clearing and finalization after commits.
- lib/arch_tools/arch_functor_bindings.ml/.mli, arch_functor_catalogue.ml/.mli:
  read-only snapshot query and minimal existing-reader reuse.
- bin/arch_query/arch_query.ml: strict parsing and six-format projection.
- tezt/tests/functor_bindings.ml, main.ml, dune, scripts/check-functor-bindings.js:
  54 tests including four independent check families with exact-build staging deps.
- README.md, task spec evidence section, briefs/, roster/functor-binding-resolution/,
  skills-meta/friction.jsonl: probes, evidence and docs. Roadmap updated externally.
- Authorized calibration only: tezt/tests/must_null_ceiling.ml,
  test/fixtures/self-index-stats.txt, test/fixtures/origin-consumer/reference.json,
  checks/origin-recurring-consumer.js. Clean524 plus unchanged headroom25.

## Decisions

Producer Sqlite3/Yojson predicates intentionally mirror private arch_tools without
a public-to-private dependency;31 positive-seeded corruption parity tests cover both.
Ident.same determines identity; serialized keys are artifact-local opaque provenance.
Savepoint failure preserves existing catalogue/graph facts; uncertainty never earns
the marker. Finalizer/reader exception handlers enclose commit.

Native and premise-checked synthetic evidence are distinguished explicitly.
A serialized/reread duplicate-Ident CMT reaches the real producer failure path.
Reader begin/commit/rollback injection is direct API evidence; genuine accessed-SQL
overflow separately proves real CLI exit2/empty stdout, without production hooks.

Probe compilers inherit the selected parent environment; ARCH_FUNCTOR_OPAM_SWITCH
is optional. Runtime probes compile in owned temporary directories, avoiding corpus
changes. Two symmetric2x2 calibrations proved source-only attribution without
graph/rule/allowlist/headroom relaxation (calibration/README.md).

## Quality Gates

- [x] Build: rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . (exit0).
- [x] Full: rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force (exit0,320/320Tezt+64Alcotest, runner completion18:17:46).
- [x] Focused bindings:54/54 pass; final full suite includes the last accessed-SQL assertion.
- [x] CHECK1–4 all execute in the full suite:36 exact renderer oracles,57 limit0
  corruptions,10 schema/7 marker refusals, default50-of60, native/synthetic census,
  real producer failures,16-surface main compatibility and3 flat query oracles.
- [x] node scripts/review-bundle-verify.js:22/22 hashes, bundle1.6.0.
- [x] bash scripts/check-scope-diff.sh briefs/functor-binding-resolution-manifest.txt: exit0.
- [x] git diff --check; node --check scripts/check-functor-bindings.js: exit0.

No configured standalone formatter/coverage instrument; no such execution or
numerical code-coverage percentage is claimed. Detailed evidence: acceptance-status.md.

## Fresh bounded Tezos/Irmin observation

Manifest SHA2569e38880a52f855c58081b1a171af5879058cbaa2697aaa5694827cbd16f8ecd1
verified before/after.410 collected inputs,1275 applications,202 matched formals
(protocol120/Irmin82),1073 unresolved,149 declarations,52 matches beyond slot1.
No increase over the previous observation; no call-target/closure gain.
Tezos revision and47 dirty entries unchanged; no source edits/build. Temporary
corpus/DB removed. Binary hashes and aggregates: tezos-irmin-bindings/report.json.
Three obsolete task-generated attribution DBs (~18MiB) removed; reports retained.

## Points of attention for review

Audit26FR/12AC, ordinal/Ident correspondence, mirrored-validator parity, failure
isolation and transaction exits, full validation before output, independent oracles,
authorized reference attribution and honest target-measurement boundaries.
Schema1.15 remains provisional until remote ship-slot verification.

## Identified out-of-scope

No general0CFA, cross-unit/member normalization, actual substitution, runtime
instances, new call targets, extra headroom, Tezos modifications, held issue or
PR93 changes. The1050 unsupported_path results suggest a future scoped path census;
they are not distinct paths and not necessarily all external units.

## Corrective round2 implementation — COMPLETED

Spec revalidation and sequential Sol/Terra plan retained26FR, added AC13/CHECK5.
Product correction only in arch_index.ml: queue immutable payloads during CMT
collection, drain per input after all old producer transactions, continue after
failure and keep independent eligibility false. No Typedtree retention or new API.
Standalone two-input global-rollback and three-input continuation tests have real
local RED exit1 then GREEN exit0. Existing four check families rerun exit0.

Full post-correction suite initially319/320 due solely to origin reference drift.
Two fresh symmetric2x2 calibrations prove SOURCE_ONLY with identical same-corpus
grouped calls/origins/modules; references updated25/956/6145/554. Ceiling pin524,
headroom25, rules and allowlist unchanged. Both owned temporary build trees removed.
Final full build exit0; final full suite320/320Tezt+64Alcotest exit0,
completion18:54:18UTC. Log: roster/functor-binding-resolution/rollback-final-tests.log.
Scope, syntax, whitespace and bundle gates pass. Independent bounded Sol source
audit found no findings (no builds executed by that role); formal review still next.
Detailed correction/oracle/calibration evidence: rollback-correction.md.

## Ratchet

- **Finding:** lib/arch_index/arch_index.ml:616:spec
  **Check:** roster/functor-binding-resolution/check-global-rollback.js (spec CHECK-5)
  **Red command:** node roster/functor-binding-resolution/check-global-rollback.js
  **check_encodable:** true
  **Pre-fix SHA:** 5338a81ebeafbe11eb1fe61bf11aa8a0e65b74c5

The checker is standalone and builds the exact checkout producer under the inherited
selected OCaml environment. No new helper or installed binary is used in scratch.
Local RED exit1 and GREEN exit0 are recorded in rollback-correction.md. Formal
convergence verification against the archived pre-fix SHA remains review's gate.
