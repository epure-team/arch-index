---
auditor: spec-compliance-auditor
date: 2026-09-15
status: 0 critical, 0 warnings, 0 info
coverage: 13/13 currently verifiable functional requirements pass; FR-014/AC-20 pending shipping delivery
spec: specs/tezos-local-recursion.md
review_head: ae50e6d3309d57d1596de9cc3f088afe42287cad
---

# Spec compliance — Tezos local recursion

Verdict: PASS for the implemented and locally verifiable contract. No open
spec-compliance finding remains. FR-014/AC-20 is intentionally not marked PASS
or MISSING: review, QA, exact-head CI and guarded merge are future delivery
conditions and remain pending until those events occur.

## Compliance matrix

| Requirements | ACs | Status | Implementation evidence | Verification evidence |
|---|---|---|---|---|
| FR-001, FR-002 | AC-1, AC-3, AC-4, AC-5, AC-7, AC-13 | PASS | Exact active `Ident.same` recursive-RHS stack and singleton `Recursive, [_]` / `Tpat_var` / direct `Texp_function` boundary in `lib/arch_index/arch_index_cmt.ml:1541-1546,1991-2007`; ordinary stamp insertion remains after RHS traversal at `:2008-2020`. | Native compiler traversal and exclusions in `roster/tezos-local-recursion/recursive-witness.ml:180-290`; CHECK-1 and CHECK-2. |
| FR-003 | AC-1, AC-6 | PASS | Physical expression observation uses the existing allocated literal name at `lib/arch_index/arch_index_cmt.ml:1940-1949`; successful row insertion confirms storage at `:3661-3674`; dropped, unique and ambiguous/missing finalization is at `:3964-3995`. | Actual SQL root and parent refusal tests in `tezt/tests/local_recursion_targets.ml:240-296`; collision/root/storage validation in `roster/tezos-local-recursion/witness.js:62-113`; CHECK-1/2. |
| FR-004 | AC-8, AC-9 | PASS | Supplied `Some` slots and physical root arity are selected only for the active recursive target at `lib/arch_index/arch_index_cmt.ml:2308-2348`; existing result-arrow partiality remains at `:2355-2358`. | Compiled optional/default/refutable/partial fixtures in `tezt/tests/local_recursion_targets.ml:20-58`; native arity and supplied-slot validation in `roster/tezos-local-recursion/witness.js:103-106`; CHECK-1/2/6. |
| FR-005 | AC-8, AC-10 | PASS | One shared residual emission covers actual overapplication plus the scoped legacy hidden-arrow preservation predicate at `lib/arch_index/arch_index_cmt.ml:2455-2476`. | Genuine same-line overapplications and independent residual capacity/refusal in `roster/tezos-local-recursion/check-witness-inputs.js:16-48`; CHECK-6 delegates to that native control. |
| FR-006 | AC-11, AC-15 | PASS | Refinement changes only head/arity selection inside the existing caller CFG and pending-call path; active outer scopes are restored with `Fun.protect` at `lib/arch_index/arch_index_cmt.ml:2003-2007`. | Native deepest-caller/range validation at `roster/tezos-local-recursion/witness.js:84-90`; nested/default/conditional and full preservation controls in CHECK-1. |
| FR-007 | AC-1, AC-12 | PASS | Recursive heads are emitted as `Head_enumerated` at `lib/arch_index/arch_index_cmt.ml:2377-2390` and finalized explicitly to the observed name at `:3981-3986`; TOP metadata is stripped or prescribed during finalization. | Stored-callee/MAY-only Tezt assertions at `tezt/tests/local_recursion_targets.ml:145-199`; transition validation rejects MUST/TOP metadata in `roster/tezos-local-recursion/witness.js:96-102`; CHECK-1/2/4. |
| FR-008 | AC-2, AC-4, AC-5, AC-12, AC-13, AC-14 | PASS | Public wrapper omits the optional private recursive table at `lib/arch_index/arch_index_cmt.ml:3083-3089`; process ingestion alone enables it at `:3208,3615-3628`. | Complete predecessor/current rich comparison and duplicate-sensitive flat comparison in `roster/tezos-local-recursion/check-native.js:109-149`; unsupported controls and flat Tezt at `tezt/tests/local_recursion_targets.ml:200-238,298-321`; CHECK-1/5. |
| FR-009 | AC-2, AC-14, AC-15 | PASS | No additional production surface is introduced; semantic preservation is verified externally. | `native-preservation-probe.ml:9-39,107-178` normalizes complete pending, modules, deps, rebinds, type usages, types, fields, constructors, functions, carriers, scopes, catches and origins. CHECK-1 requires each configured boundary nonempty, positive mutation/deref effects, a module-alias reexport edge, and exact old/current equality at `check-native.js:109-149`. |
| FR-010 | AC-2, AC-3, AC-10, AC-16, AC-17 | PASS | Product evidence remains private and is not accepted as witness authority. | Compiler-only probe records artifact, binder/UID, group, physical root/ordinal, caller, full locations, arity and supplied slots in `recursive-witness.ml:1-447`; `witness.js:62-113,156-213` replays pinned CMT evidence and consumes head/residual capacity once; tamper controls are in `check-witness-inputs.js:32-50`. |
| FR-011 | AC-18 | PASS | Canonical comparison algebra is reused without implicit permissions. | `check-comparison.js:29-74` covers unapproved transitions, duplicate capacity, residual approval, count-neutral loss, point-free loss and new MUST; fixed410 verification requires positive gains and zero losses at `:76-92`; CHECK-4. |
| FR-012 | AC-2, AC-19 | PASS | Product/schema/public interface boundaries remain scoped as specified. | Frozen producer/schema/database/410 manifest validation and neutral replay are implemented in `baseline.js:12-25,75-145`; compatibility binds candidate/source/reference attribution and exact origin 2x2 evidence in `check-compatibility.js:13-118`; CHECK-3/4/5. |
| FR-013 | AC-16, AC-17, AC-19 | PASS | No product behavior maps infrastructure errors to semantic success. | CHECK scripts distinguish assertion exit 1 from setup/runtime exit 2+, including `check-native.js:159`, `check-witness-inputs.js:51`, `check-comparison.js:98-104` and `check-residual-capacity.js:1-9`; negative input controls pass under CHECK-2/3. |
| FR-014 | AC-20 | PENDING DELIVERY | Local comparison explicitly reports `retention_authorized:false` in `verify.js:32-44` and `check-comparison.js:86-90`; compatibility does the same at `check-compatibility.js:152-158`. | Positive witnessed local gain and zero loss pass CHECK-4, but independent review/QA, exact-head CI and guarded merge must still complete before retention is authorized. |

## Resolved review finding

The first review cycle found FR-009/AC-15 UNTESTED for nonempty paired effects,
reexports/dependencies, rebinds and type-shape facts. The initial strengthened
assertions produced a genuine semantic RED (`old modules preservation array
present`). The fixture and compiler-native preservation probe were then extended
without product changes. Personal CHECK-1 passed after the fix, and the complete
personal gate sequence below passed on the final review head. The finding is
resolved and is not present in `spec-compliance-findings.json`.

## Personal deterministic gates

Evidence directory:
`improvement/2026-09-14-tezos-resolution/attempt4-review-spec-cSiIIW`.
The before/after status and scoped source hashes are byte-identical, and HEAD
remained `ae50e6d3309d57d1596de9cc3f088afe42287cad`.

| Gate | Exit | Duration | Log |
|---|---:|---:|---|
| `opam exec -- dune build` | 0 | 1s | `01-build.log` |
| `opam exec -- dune exec tezt/tests/main.exe -- --no-color` | 0 | 269s | `02-full340.log` |
| `node scripts/review-bundle-verify.js` | 0 | 0s | `03-bundle.log` |
| `git diff --check` | 0 | 0s | `04-diff.log` |
| CHECK-1 `check-native.js` | 0 | 29s | `05-check1.log` |
| CHECK-2 `check-witness-inputs.js` | 0 | 4s | `06-check2.log` |
| CHECK-3 `check-baseline.js` | 0 | 4s | `07-check3.log` |
| CHECK-4 `check-comparison.js` | 0 | 52s | `08-check4.log` |
| CHECK-5 `check-compatibility.js` | 0 | 29s | `09-check5.log` |
| CHECK-6 `check-residual-capacity.js` | 0 | 4s | `10-check6.log` |

## Independence limits

This specialist authored the product refinement and the later FR-009 coverage
extension, so this report is not independent evidence for those authored edits.
The product was separately audited and gated by the architect; the coverage fix
was separately reviewed and gated by the owner, with no open finding reported.
This specialist's independent review emphasis is the compiler-native witness,
tamper/capacity controls, comparison algebra and code-to-contract mapping, which
were not authored by this specialist. No checker output is treated as authority
for its own implementation, and no local checker claims future shipping success.

## Unspecified implementation scan

No new public API, schema field, flat-consumer behavior, general value-flow
analysis or new MUST classification was found. The scoped legacy residual OR is
specified by FR-005/FR-008 and is covered by the hidden-arrow native regression.
