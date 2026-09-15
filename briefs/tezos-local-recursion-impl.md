# Implementation Brief — tezos-local-recursion

**Date:** 2026-09-15
**Mode:** full
**Status:** COMPLETED

Attempt4/5 implementation only. Review, QA, PR, exact-head CI and guarded rebase
merge remain mandatory. Still3/5 delivered; no fourth KEEP or attempt5 start.

## Modified files

- lib/arch_index/arch_index_cmt.ml: private exact singleton Recursive RHS
  invocation descriptors, observed physical root/name/storage, MAY_ENUMERATED
  refinement and preserved legacy returned-call residuals.
- tezt/tests/local_recursion_targets.ml and tezt/tests/main.ml: four authentic
  native target/exclusion/storage/flat tests and registration.
- roster/tezos-local-recursion/: compiler-libs witness, fresh probe replay,
  single-use proof validation, immutable baseline and six executable checks;
  pristine self/origin attribution diagnostics and reviewed evidence reports.
- test/fixtures/self-index-stats.txt, test/fixtures/origin-consumer/reference.json,
  test/fixtures/origin-consumer/self.allow, checks/origin-recurring-consumer.js:
  exact source-only reference refresh authorized before editing by
  roster/tezos-local-recursion/reference-refresh-authorization.json.
- briefs/ and skills-meta/friction.jsonl: implementation handoff and phase record.

## Decisions made

Only singleton plain-variable/direct-function local recursive self-heads within
their RHS are admitted. No early ordinary local-table insertion; the public flat
wrapper omits the optional descriptor table and remains unchanged. Actual lambda
allocation observes the physical root; storage and unique observation are checked
before removing internal markers. No guessed collision ordinal or new MUST.

Native literal arity and supplied Some slots govern admitted heads. Actual Irmin
tree.ml:1920 exposed a legacy conservative residual from a hidden arrow alias;
an authentic alias_hidden fixture failed before the narrow OR correction, then
passed. One shared emission preserves old residuals without duplicating genuine
overapplication residuals. Earlier count gain with that lost row was REFUSE.

Only after pristine crossed calibration A=B and C=D were four exact reference
paths added to the manifest and updated. Golden A/B25/998/6335, C/D25/1004/6389;
origins570→580, only compare50→52 and option320→328. The same sole assertion
allowance remains x1, with source-coordinate shift only. Ceiling policy524±25,
schema, public interface and all old checker code remain unchanged. Owned
diagnostic worktrees/builds were removed; retained DB evidence is intentional.

## Quality Gates

Executed serially on unchanged source state. Raw logs and per-command durations:
improvement/2026-09-14-tezos-resolution/attempt4-final-gates-kWgcIV/.

| Gate | Exit | Duration |
|---|---|---|
| opam exec -- dune build | 0 | 415ms |
| opam exec -- dune exec tezt/tests/main.exe -- --no-color --keep-going | 0,340/340 | 270630ms |
| node roster/tezos-local-recursion/check-native.js | 0 | 28493ms |
| node roster/tezos-local-recursion/check-witness-inputs.js | 0 | 3897ms |
| node roster/tezos-local-recursion/check-baseline.js | 0 | 4068ms |
| node roster/tezos-local-recursion/check-comparison.js | 0 | 53026ms |
| node roster/tezos-local-recursion/check-compatibility.js | 0 | 28978ms |
| node roster/tezos-local-recursion/check-residual-capacity.js | 0 | 3981ms |
| node scripts/review-bundle-verify.js | 0 | 83ms |
| git diff --check | 0 | 64ms |

Formatter/coverage: not configured, not PASS. Claims check rerun: upstream parser
exit2 on legacy specs/functor-binding-resolution.md:375; no stale managed claim
or context projection exists. Isolated new-spec40-record validation passed earlier.

TDD: original336 baseline allPASS; authentic full340 RED had only two new failing
target/storage assertions. First product full run had338PASS/2reference failures;
those were resolved only after immutable pristine attribution. Setup failures
(warning39, reserved fixture keyword, JS destructuring) are not semantic RED.

Fixed410 comparison with reviewed native witness:45052rows on both sides,
181 head replacements,179 new relations (+68Irmin/+111protocol),0lost relations,
0unexplained changes,0new MUST,0removed legacy TOP residual. Candidate digest
082bdce92c6cab7b654f87a90db59ca9979d7004f45a42997a33718f6cd7c67a.
Fresh native replay is independent of candidate targets. Frozen PR107 baseline
remains4781Irmin/12046protocol with exact neutral copied-producer replay.

## Points of attention for review

Audit private activation, exact Ident and physical-root/storage correspondence,
RHS stack nesting, actual collision ordinal, arity/optional/default contexts,
rich/flat counted preservation and independent head/residual capacities. Examine
both duplicate groups and preserved Tree1920 residual in native-pair-review.md.
Check immutable reference authorization and post-commit compatibility scope.
All specialists must execute gates under main's serial schedule, not trust this
handoff as their own run. Seven unrelated user files remain intentionally dirty;
no blanket staging or cleanup is permitted. Any dirty-tree SHA field must be null
with reason, not a fabricated clean-head claim.

## Identified out-of-scope

Mutual recursion, alias patterns, wrappers, computed RHSs, non-head value flow,
general0CFA and functor expansion remain excluded. No Tezos source changes,
corpus expansion, old-spec parser repair, heldPR93 action or foreign cleanup.
No installed OCaml specialist/CWR/hooks/KB/context pack; scoped Sol/Terra workers
and manual roster chain used under standing autonomy. No quiz answers invented.
