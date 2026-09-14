---
auditor: spec-compliance-auditor
date: 2026-09-14
status: 0 open critical, 0 open warnings, 0 open info; 1 critical resolved in round
coverage: 34/34 FRs and 13/13 ACs verified (100%)
source_commit: cd3cb3c
---

# Tezos open-body spec compliance — round 1

The repaired implementation matches `specs/tezos-open-bodies.md`. All 34 functional requirements and all 13 acceptance criteria have implementation and executable-test evidence. No open spec finding remains.

## Compliance matrix

| Claims | Status | Implementation / evidence | Runnable proof |
|---|---|---|---|
| FR-001–FR-003 / AC-1 | PASS | Exact same-CMT `Ident` head resolves to the stored root body as `MAY_ENUMERATED`; caller/site retained; no new `MUST`. | CHECK-1; full Tezt open-body tests |
| FR-004–FR-007 / AC-3 | PASS | Shadow-aware binder identity, physical root identity, canonical name/cardinality, and exact open/function shape gate admission. | CHECK-1 identity/multiple mutations and shadow controls |
| FR-008–FR-012 / AC-4 | PASS | Inner literal arity and supplied-`Some` count drive partiality; one residual per actual overapplied occurrence. | CHECK-1 optional/default/refutable and residual controls; CHECK-6 |
| FR-013–FR-014 / AC-5 | PASS | Parameter/default traversal and effect/CFG ownership remain predecessor-identical; admitted edges do not claim effect execution. | CHECK-1 complete persisted preservation comparison |
| FR-015–FR-016 / AC-2, AC-7 | PASS | Callback, alias, local, nested, qualified, homonym, computed/structure/apply/unpack open paths remain outside admission. | CHECK-1 rich/flat and module-expression controls |
| FR-017–FR-021 / AC-2, AC-6 | PASS | Stored unique body admits; rejected parent/body becomes `dropped_node`; other mismatch remains `callback_param`; no dangling leaf. | CHECK-1 native Tezt, physical/cardinality mutations |
| FR-022–FR-025 / AC-2, AC-8 | PASS | Rich functions, complete pending-call metadata, relations, effects, CFG, scopes, carriers, origins, and duplicate-sensitive flat rows are preserved outside admitted changes. | CHECK-1 predecessor/current comparison; CHECK-4 |
| FR-026–FR-028 / AC-9, AC-11 | PASS | Reproducible pinned compiler evidence binds exact artifact, binder, owner, ranges, site, arity and group capacity; occurrences and residual heads are single-use. | CHECK-2; CHECK-6 |
| FR-029–FR-030 / AC-10 | PASS | Only callback TOP rows transition; every canonical removal/addition consumes exact capacity; no resolved relation is lost. | CHECK-2; CHECK-4 |
| FR-031 / AC-11 | PASS | Tampered, wrong-body, mismatched, reused, insufficient and ambiguous evidence refuses. | CHECK-2 (13 controls); CHECK-6 (2 residual-reuse refusals) |
| FR-032 / AC-2, AC-5, AC-7, AC-8 | PASS | Existing callers, relations, CFG, ownership, effects and flat contracts remain unchanged outside the specified transition/residual set. | CHECK-1; CHECK-4 |
| FR-033 / AC-12 | PASS | Distinct pinned baseline replays neutrally, rejects malformed state/recreation, and remains byte-identical. | CHECK-3 |
| FR-034 / AC-13 | PASS | Self smoke and full-guard policy are frozen; changed references are bound to pristine source-only attribution. | CHECK-5; full 336/336 guard |

## Resolved during round 1

### [C1] Residual witness could reuse one native head occurrence

- **Original status:** CRITICAL (`spec:residual-native-occurrence-reuse`)
- **Claims:** FR-027, FR-028, FR-031; AC-9, AC-11
- **Evidence:** The original residual loop accepted repeated `head_index` values, while the downstream comparator pooled capacity by canonical transition pair. Two indistinguishable transitions could therefore let one overapplied native occurrence justify two residual rows.
- **Resolution:** Commit `cd3cb3c` consumes each residual `head_index` once in `roster/tezos-open-bodies/witness.js`. `check-residual-witness.js` uses genuine compiler traversal to prove a mixed saturated/overapplied pair, two distinct overapplied heads, and two repeated-head refusals.
- **Final status:** RESOLVED; personally verified by CHECK-2, CHECK-4, and CHECK-6.

## Personal verification

- `opam exec -- dune build` — exit 0.
- `_build/default/tezt/tests/main.exe --no-color --keep-going` — exit 0, 336/336; log: `improvement/2026-09-14-tezos-resolution/attempt3-review-spec-full.log`.
- CHECK-1 `check-native.js` — PASS, including complete rich/flat preservation controls.
- CHECK-2 `check-witness-inputs.js` — PASS, 316 actual DB pairs and 13 refusal controls.
- CHECK-3 `check-baseline.js --replay` — PASS, 45,052 rows, digest `00f1769d6db7f6ee91ee51becabccd7b4ce13975acb6610c95ace69a7f620e9b`, neutral replay and 17 record refusals.
- CHECK-4 witnessed comparison — PASS, candidate digest `9ab4e0b13457247fb93dc83bf80323fcc5cec67866a18f56995ac0ec4a20867e`, 316 protocol relation gains, 0 Irmin gains, 0 relation losses, 45,052 rows.
- CHECK-5 `check-self.js` — PASS.
- CHECK-6 `check-residual-witness.js` — PASS, two genuine positives and two reuse refusals.
- `scripts/review-bundle-verify.js` — PASS, 22 files present and SHA-matched.
- `git diff --check` — PASS.

Formatter and coverage gates are not configured; no pass is claimed for them.
