# Independent reviewer round 1 — tezos-recursive-typed-bodies

**Date:** 2026-09-15  
**Reviewer:** roster owner (`reviewer`)  
**Target HEAD:** `d954303f7059f0a60b6bee3e463060508dd20eee`  
**Recommendation:** approve for the next pipeline phase; no concrete reviewer finding.

This is an independent code-review recommendation only. It is not a final
pipeline GO, human approval, formal-verification claim, CI result, retention
authorization, or merge authorization.

## Pin and state custody

- HEAD before checks: `d954303f7059f0a60b6bee3e463060508dd20eee`.
- HEAD after checks: `d954303f7059f0a60b6bee3e463060508dd20eee`.
- Current producer: `_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe`.
- Producer SHA-256 before checks: `1cb7943cefa15a56f0df39fd2c2e741832d1acefaeedb92d189eb643075e9593`.
- Producer SHA-256 after checks: `1cb7943cefa15a56f0df39fd2c2e741832d1acefaeedb92d189eb643075e9593`.
- `baseline.js state()` SHA-256 before checks:
  `12db66f6fe4d9be8bf822e5b351d0947237faca35f09be734af16e31a7b6a0a3`.
- `baseline.js state()` SHA-256 after checks:
  `12db66f6fe4d9be8bf822e5b351d0947237faca35f09be734af16e31a7b6a0a3`.
- Post-check `assertStateUnchanged` completed successfully.
- The unrelated user untracked files were preserved. The task review trace also
  remained untracked and unchanged by this review.

## Personally executed gates

Commands ran sequentially with no concurrent build process:

| Command | Exit | Evidence |
|---|---:|---|
| `rtk proxy opam exec -- dune build` | 0 | Build completed without diagnostic output. |
| `rtk proxy opam exec -- dune exec tezt/tests/main.exe -- --no-color --keep-going` | 0 | 342/342 tests reported `SUCCESS`, including both recursive-open-body tests. |
| `rtk proxy node roster/tezos-recursive-typed-bodies/check-native.js` | 0 | Authentic targets and complete rich/flat preservation PASS. |
| `rtk proxy node roster/tezos-recursive-typed-bodies/check-witness-inputs.js` | 0 | Genuine-CMT identity, shape, ordinal, head/residual capacity, and tamper refusals PASS. |
| `rtk proxy node roster/tezos-recursive-typed-bodies/check-baseline.js` | 0 | 45,052 rows; digest `082bdce92c6cab7b654f87a90db59ca9979d7004f45a42997a33718f6cd7c67a`; Irmin 4,849; protocol 12,157; neutral replay. |
| `rtk proxy node roster/tezos-recursive-typed-bodies/check-comparison.js` | 0 | Witnessed candidate PASS with 14 eligible relation gains and zero claimed retention authority. |
| `rtk proxy node roster/tezos-recursive-typed-bodies/check-compatibility.js` | 0 | Public/schema/flat and historical self-policy preservation PASS; CI explicitly remains unverified. |
| `rtk proxy node roster/tezos-recursive-typed-bodies/check-residual-capacity.js` | 0 | Genuine-CMT omitted/partial/overapplication and single-use residual controls PASS. |

The already-completed scope gate was not rerun. `git diff --check` was also
observed at exit 0 during the read-only review inspection.

## Review dimensions

- **Native identity and admission:** the product change admits only the existing
  direct-function case or one `Texp_open` whose operand is `Tmod_ident` and whose
  immediate body is `Texp_function`. The recursive descriptor retains the
  original inner expression object and derives arity from that object. No module
  path is interpreted as target evidence.
- **Binder scope and target custody:** existing `Ident.same`/unique-identifier
  scope behavior remains in the surrounding collector. The native witness
  reconstructs binder, physical root, caller, range, arity, and allocation
  ordinal from compiler artifacts; candidate storage is validated separately
  before a bounded target is accepted.
- **Witness completeness and capacity:** complete fixed-410 evidence is hash
  bound and replayed. Same-printed-head groups must be complete. Positioned-row,
  head, and residual capacities are counted and single-use; malformed, mixed,
  partial, duplicated, stale, and tampered evidence controls refuse.
- **Preservation:** paired predecessor/current collection compares complete rich
  non-resolution facts and non-call families, asserts non-vacuous exception,
  channel, effect, conditional, and dead-code fixtures, and compares the full
  duplicate-sensitive public flat multiset. Parent, continuation, escape,
  ordinary lookup, schema, public interface, historical checkers, and self-index
  boundaries remain covered.
- **Arity and residual behavior:** supplied `Some` arguments determine the new
  body count, result-arrow partiality is retained, and overapplication permits at
  most one separately witnessed returned-call residual while preserving legacy
  behavior.
- **Regression and abuse risk:** dedicated native tests cover exact admission,
  excluded nested/annotated shapes, nested callers, optional/default/refutable
  functions, partial and overapplied calls, parent and continuation facts, and
  rejected storage. No new `MUST`, public API, schema, ordinary binding table, or
  CI/self-policy change was found in the reviewed diff.

## Findings and recommendation

No reproducible correctness, security, architecture, specification, scope, or
regression defect was found. `reviewer-round1.json` is therefore an empty
standard-finding array. Recommendation: proceed to independent QA while retaining
the specification's exact-final-head CI and guarded-merge requirements.
