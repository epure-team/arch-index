# Implementation Brief — ocaml-functor-targets

**Date:** 2026-09-16
**Mode:** full
**Status:** LOOPBACK READY FOR INDEPENDENT REVIEW

## Review-loopback update — 2026-09-17

Round 1 was a NO-GO for authentication and atomic-publication gaps, not for the
bounded target semantics. The corrective implementation changes the main
schema from 1.16 to 1.17 and the target contract from v1 to v2. It adds durable
artifact-local `functor_target_occurrences` (including zero-positive-site
occurrences) and `functor_target_candidates`; each witness now references both
exact keys. Variants collect their own local proof inventory and only reconcile
to one stable representative occurrence. Target calls, local provenance and the
completion marker are committed as one target-only transaction, so a failed
positive candidate leaves no consumable target call.

Loopback scope additionally includes the schema drop list, compatibility
normalisation (semantic call identities rather than allocator row IDs), fresh
self-index/origin ratchets, direct `arch-query` coverage and corruption tests
for occurrence and actual/member-to-candidate substitution. It is a necessary
correction to the original task contract, not a new semantic capability.

Fresh verification: build passes; CHECK-1 passes its nine scenarios and
assertion/setup controls; the full native suite passes 354/354; CHECK-3 passes
on the frozen 410-CMT corpus with seven fully witnessed Irmin additions, zero
protocol additions, zero removed resolved relations and zero new/upgraded MUST.
Evidence: `improvement/2026-09-16-ocaml-functor-targets/check3-1789624905367-458970.json`.
Review, QA, PR, exact-head CI and merge remain pending.

## Modified files

| File | Type of change | Reason |
|---|---|---|
| `architecture-schema.sql` | modification | Persist versioned functor-target inputs and positive provenance witnesses with indexed identity chains. |
| `lib/arch_index/arch_index_bindings.ml` | modification | Retain artifact-local formal identities and supported actual paths without weakening refusal rules. |
| `lib/arch_index/arch_index_bindings.mli` | modification | Expose the bounded binding collector contract. |
| `lib/arch_index/arch_index_cmt.ml` | modification | Add authenticated formal-member to actual-member candidate resolution while retaining TOP. |
| `lib/arch_index/arch_index_cmt.mli` | modification | Expose target input, witness and reconciliation types. |
| `lib/arch_index/arch_index.ml` | modification | Reconcile exact-copy and uniquely compatible variants, persist candidate calls and witnesses, and validate the contract. |
| `lib/arch_index/arch_index_db.ml` | modification | Bump the main schema version from 1.15 to 1.16. |
| `lib/arch_index/arch_index_support.ml` | modification | Register the new main-schema compatibility range. |
| `tezt/tests/functor_bindings.ml` | modification | Cover direct, repeated, curried, nested, alias, refusal, copy, variant and corruption cases. |
| `tezt/tests/must_null_ceiling.ml` | modification | Recalibrate the source-only self-index ceiling after the new implementation. |
| `roster/ocaml-functor-targets/check-cmt.js` | addition | Check the authentic CMT/DB/query contract and 0/1/2 controls. |
| `roster/ocaml-functor-targets/check-native.js` | addition | Run the independent functor contracts and full deterministic Tezt suite. |
| `roster/ocaml-functor-targets/check-tezos.js` | addition | Compare the frozen Stage-3 pinned410 baseline with the candidate and authenticate every gain. |
| `roster/ocaml-functor-targets/calibrate-self.js` | addition | Perform the task-scoped 2x2 self-index calibration. |
| `roster/ocaml-data-preservation/check-cmt-copies.js` | modification | Strengthen exact-copy and independently compiled variant coverage. |
| `checks/origin-recurring-consumer.js` | modification | Recalibrate the source-only self-index consumer allowance. |
| `test/fixtures/origin-consumer/reference.json` | modification | Record current source-only consumer totals. |
| `test/fixtures/origin-consumer/self.allow` | modification | Move the unique allowance to the current source location. |
| `test/fixtures/self-index-stats.txt` | modification | Record the current 27/1200/7356 self-index totals. |
| `test/fixtures/compatibility-rich-baseline.json` | modification | Record the compatible richer schema/output baseline. |
| `docs/functor-catalogue.md` | modification | Document the bounded correspondence, provenance and refusal contract. |
| `docs/schema.md` | modification | Document schema 1.16 and the new lifecycle marker. |
| `specs/ocaml-functor-targets.md` | addition | Define the validated Stage-4 requirements, acceptance criteria and checks. |
| `briefs/ocaml-functor-targets-*` | addition/modification | Persist Roster research, intake, plan, implementation and review context. |
| `roster/ocaml-functor-targets/` | addition | Persist task questions, research and implementation evidence. |
| `skills-meta/friction.jsonl` | modification | Record pipeline friction and corrective methods. |

## Decisions made

- Candidate relations are monotone additions: every concrete target is `MAY_ENUMERATED`, and the original `MAY_TOP/module_param` relation is retained independently.
- Compiler identities are compared only inside the artifact that produced them. Persisted witnesses carry the application, declaration, formal, actual, call occurrence and target chain needed to audit a relation.
- Exact graph copies may share graph rows but retain separate artifact witnesses. Independently compiled same-source variants reconcile only when the normalized functor catalogue and target-relevant formal-call signature identify one representative; ambiguous or changed variants contribute nothing.
- Supported actuals are deliberately limited to local direct paths and one-hop value aliases. Module aliases, persistent paths, `Papply`, unpacked and anonymous modules fail closed.
- Synthetic target rows reuse the physical source occurrence ordinal and preserve sink/handler metadata; no body, function, caller or module node is cloned.
- Flat/LSP output is regression-tested for non-inference because it lacks the CMT compiler identities required by this proof.
- CHECK-3 uses a hash-validated Stage-3 baseline. The candidate adds seven witnessed Irmin relations, adds none in protocol, loses none globally, and creates or upgrades no `MUST` relation.

There was no deviation from the validated semantic scope. `lib/arch_index/arch_index_functors.ml` and new fixture files were unnecessary because existing catalogue ordinals and generated test fixtures supplied the required evidence.

## Quality Gates

- [x] Build: `opam exec -- dune build --root .` ✅
- [x] Focused contracts: `opam exec -- node roster/ocaml-functor-targets/check-cmt.js` ✅
- [x] Native/full suite: `opam exec -- node roster/ocaml-functor-targets/check-native.js` ✅ (351/351 Tezt tests)
- [x] Pinned corpus: `opam exec -- node roster/ocaml-functor-targets/check-tezos.js` ✅ (45,297 rows; +7 witnessed Irmin relations; 0 losses; 0 new/upgraded MUST)
- [x] Existing functor contracts: `opam exec -- node scripts/check-functor-bindings.js inventory`, `lifecycle`, `query`, `compatibility` ✅
- [x] Focused Tezt: `opam exec -- dune exec --root . tezt/tests/main.exe -- --job-count 1 --match 'functor|CFA'` ✅
- [x] Checker controls: all three task checkers return 0 for pass, 1 for assertion, and 2 for setup failure ✅
- [x] Calibration: `opam exec -- node roster/ocaml-functor-targets/calibrate-self.js` ✅ (2x2 same-corpus equality; +11 source-only rows; headroom 25)
- [x] Format/hygiene: `rtk git diff --check` ✅ (no standalone formatter or lint command is documented)

## Points of attention for review

- Audit every positive relation back to a complete artifact-local witness and ensure no display-name, basename or cross-artifact compiler-stamp join exists.
- Check physical occurrence identity for equal-location calls, repeated and curried applications, exact copies, and reversed artifact discovery order.
- Confirm nonidentical reconciliation cannot create nodes or borrow identities and refuses any ambiguous or target-relevant signature change.
- Confirm target rows remain `MAY_ENUMERATED`, TOP remains present, NULL candidate links fail validation, and incomplete/old contracts refuse rather than appear empty.
- Inspect the frozen Stage-3 baseline hashes and the seven CHECK-3 witness joins, not only the checker exit status.

## Identified out-of-scope

- General defunctorization, closed-world completeness, function/body cloning, `Path.Papply`, Shapes/UID resolution and cross-unit target recovery remain future work.
- The pinned protocol slice gains no target in this bounded stage; its unsupported cases should guide Stage 5 rather than weakening Stage-4 identity proofs.
- No performance bound is claimed; CHECK-3 records correctness and attribution only.
