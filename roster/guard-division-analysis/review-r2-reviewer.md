# Independent R2 reviewer report — guard-division-analysis

Reviewed commit: `c586a931903992392bda5026b5a1f694b922a4c2`
Base: `origin/main` merge-base `77c7691436a7`
Recommendation: **APPROVE / no new primary findings**

## Scope and method

Read the reviewer and implementation briefs in the required order, the complete 439-line feature specification, prior R1 review ledger and gate report, reviewer instructions, RTK instructions, all changed production/analyzer files, owned fixtures and independent checkers, and the complete per-file diff. The requested review scope was limited to the general analyzer and owned/native fixtures; external or Tezos security analysis was not performed. The already-passing manifest gate owns scope-discipline assessment.

Review dimensions covered: correctness and regression behavior; input and output safety; compiler-artifact trust boundary; public/private architecture boundary; all FR/AC/CHECK obligations; exact test-oracle sensitivity; package/install behavior; maintainability and OCaml/JavaScript antipatterns. `.claude/patterns/` is absent, so there were no language-pattern files to apply.

## R1 finding dispositions

All seven prior stable findings are verified closed by corrective code and independently executed gates. These are dispositions for the primary owner; this report does not mutate the review ledger.

1. `scripts/check-arch-guard.js:202:correctness#a58d9378` — **RESOLVED**. CHECK-1 now exercises later saturation, over-application, labelled operands, missing original slot 2, combined eligibility failures, 256/257-byte identifiers, duplicate coordinates, and non-native/unresolved operand slots (`scripts/check-arch-guard.js:241-276`; `tezt/fixtures/arch_guard/fixture_probe.ml:44-48,393-436`). Inventory mode independently passed with 12 seam cases.
2. `scripts/check-arch-guard.js:268:correctness#a7a5c45d` — **RESOLVED**. The shared oracle enforces exact status/reason correspondence and real exclusions for UNSUPPORTED (`tezt/fixtures/arch_guard/checker_report_oracle.js:28-43`), while report mode rejects wrong semantic reasons plus omitted and duplicate text-site fields (`scripts/check-arch-guard.js:297-318`). Report mode independently passed.
3. `lib/arch_guard/guard_interpreter.ml:111:architecture#c4061b21` — **RESOLVED by boundary removal**. The implementation library no longer has a `public_name` (`lib/arch_guard/dune:1-3`); the install oracle requires the CLI and rejects library/META payloads (`scripts/check-arch-guard.js:473-477`); documentation declares only the CLI and wrapper supported (`docs/arch-guard.md:16-20`). Owned/package checks passed.
4. `lib/arch_guard/arch_guard.ml:213:spec#cd378d70` — **RESOLVED with ratchet**. Text is projected from the same `tool` and `analysis` values as JSON (`lib/arch_guard/arch_guard.ml:206-224`), and shared limitations explicitly include indirect operations and omitted artifacts (`lib/arch_guard/arch_guard.ml:152-157`). The standalone actual-CLI check passed on empty and classified artifacts (`scripts/check-guard-report-context.js:20-58,60-89`). This is the declared ratchet `scripts/check-guard-report-context.js`; its prior RED evidence remains in the implementation brief and R2 independently observed GREEN.
5. `scripts/check-arch-guard.js:206:spec#95fac6f3` — **RESOLVED**. Same application-shape/type seam evidence as disposition 1; inventory mode passed and its mutations assert exact accumulated reasons and stable metadata.
6. `scripts/check-arch-guard.js:152:spec#64aca30b` — **RESOLVED**. Native cases cover aliasing, shadowing, simultaneous groups, fresh nested function entries, immediate/curried captures, defaults, cases, recursion, compound patterns, sticky unsupported ancestry, supported siblings, loop condition/bounds, opaque/unlisted/short-circuit/method paths (`tezt/fixtures/arch_guard/r1_cases.ml:3-131`). The expected table asserts every exact status/reason (`tezt/fixtures/arch_guard/checker_numeric_cases.js:31-44`). Numeric mode passed with 36 R1 sites: 19 numeric, 17 unsupported.
7. `scripts/check-arch-guard.js:280:spec#7516ba96` — **RESOLVED**. Full semantic text/JSON projection is checked per site (`tezt/fixtures/arch_guard/checker_report_oracle.js:49-54`); special filenames include spaces, delimiters and newlines (`scripts/check-arch-guard.js:309-313`); duplicate coordinates and 256/257-byte identifier boundaries are covered (`scripts/check-arch-guard.js:257-276`); direct/root help/version, copied-wrapper missing-binary, and private install boundary are covered (`scripts/check-arch-guard.js:462-477`). Report, inventory and owned modes passed.

## Independent command evidence

- Full `opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .`: exit 0.
- Full forced `dune test --root . --force` in the same explicit opam environment: exit 0; 256/256 Tezt successes, including the guard checkers, and the suite-reported 64 Alcotest cases.
- `git diff --check`: exit 0.
- `check-arch-guard.js` modes `inventory`, `numeric`, `domain`, `inputs`, `report`, `owned`: each exit 0. Salient counts: domain 640734 probe responses / 23219242 law assertions; owned census 23 artifacts / 0 sites; private library absent from install manifest.
- `check-guard-report-context.js`: exit 0, actual CLI JSON/text PASS for empty and classified artifacts.
- `origin-recurring-consumer.js` modes `authentic`, `failures`, `package`: each exit 0. The expected injected cleanup/final-write diagnostics appeared only in `failures`.
- Fresh self index under `/tmp/guard-r2-review.gg3ylk/self.db`: exit 0, exactly 23 modules / 828 functions / 5223 calls. Fresh self rules: exit 0, 1 PASS and 3 explicit UNKNOWN, no vacuous or failing rules. Fresh impact: exit 0, zero indexed functions and 102 changed files explicitly reported outside the index as UNKNOWN. Fresh origin producer and artifact validator: each exit 0.
- Literal `env DUNE_CACHE=enabled DUNE_CACHE_STORAGE_MODE=copy ./scripts/recalibrate.sh --check` without the project opam environment exited 2 (`dune not found in PATH`). The required compiler-backed invocation was rerun as `opam exec --switch=/home/mathias/dev/arch-index -- env ... ./scripts/recalibrate.sh --check`: exit 0; golden 23/828/5223 in A/B/C/D and ceiling 396/396/437/437 with pin 430 and unchanged 25 headroom.

## New findings and residuals

No new objective finding was identified. Green gates were corroborated against the test logic: the oracles are status-sensitive, reason-sensitive, field-sensitive, use actual CLI outputs where claimed, and disclose private Typedtree seams where native CMT construction cannot express malformed cases. The analyzer remains deliberately report-only, process-isolated at the supported boundary, bounded, and explicit about unsupported ancestry and unknown impact.

The pre-existing opam lint metadata failure described in the implementation brief was not rerun because it is explicitly non-gating debt and dependency/pin metadata changes were forbidden. Cross-runtime review was not re-probed because the prior same-cycle ledger records OpenCode as degraded/non-conforming; this owner review did not fabricate a specialist invocation.

Repository status was clean before and after review. No repository artifact, ledger, commit, or push was written.
