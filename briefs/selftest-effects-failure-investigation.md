# Investigation — selftest-effects-failure

**Date:** 2026-07-08
**Symptom:** `./selftest-effects.sh` fails on clean main: "effects-of exported_entry missing FieldAccess / missing HashTbl" (always reproducible; pre-existing, verified via git stash on 2026-07-08).
**Status:** ROOT CAUSE IDENTIFIED

## Root Cause

The two CMT producers disagree on function naming:
- `lib/arch_effects/ocaml_effects_extractor.ml:155-156` — `let fn_name = ... modname ^ "." ^ Ident.name id` → effects emitted as **`Efxtest.record_mutator`** (also :206 for module-level GlobalVar bindings).
- `lib/arch_index/arch_index_cmt.ml:91,231` — functions and callee names stored **unqualified** (`Ident.name`), e.g. `record_mutator`.

`arch-query effects-of` joins `function_effects.function_name IN (<closure of unqualified names>)` **exactly** → transitive effects never match → the two FAILs. `mutators-of` only "passed" because the selftest greps a substring of the qualified name.

**Worse impact (observed):** `pure-fns` compares `functions.name` against `function_effects.function_name` — with mismatched names, **all 4 fixture mutators are listed as pure** (reproduced: `arch-query pure-fns | grep -c mutator` → 4). On any CMT-built OCaml index, purity verdicts are silently wrong.

**Introduced:** undetermined (naming divergence present since the two extractors' initial versions).

## Tested hypotheses

| # | Hypothesis | Result | Evidence |
|---|---|---|---|
| H1 | NULL `kind` edges excluded from the transitive closure | REFUTED for main schema — `arch-query` effects-of main-schema branch already allows `c.kind IS NULL` | arch-query effects-of branch, main-schema CTE |
| H2 | Effects extractor emits module-qualified names; callgraph producer emits unqualified — exact join fails | CONFIRMED (observed on isolated fixture: NDJSON shows `Efxtest.*`, functions table shows bare names) | `ocaml_effects_extractor.ml:155-156,206` vs `arch_index_cmt.ml:91,231` |

## Fix plan

1. `lib/arch_effects/ocaml_effects_extractor.ml` — emit unqualified names (`Ident.name id`), matching the sibling CMT producer's identity convention (main-schema identity is `(module_id, name)`; the file_path field keeps disambiguation). Drop the now-unused `modname` binding if orphaned.
2. Add `./selftest-effects.sh` to CI (it was excluded because it failed — once green it must ratchet).
3. Fix the stale fallback binary path in `selftest-effects.sh:127` (`main.exe` → `arch_effects_ocaml.exe`).

## Fix risks

- Any consumer relying on qualified effect names: none in-repo (`test_effects.ml` asserts no qualified names; grep found no other consumer). Flat-schema/Go producers unaffected (their pairing is self-consistent).

## Tests to add

- Unit: extractor output names must equal the callgraph producer's naming for the same fixture (join-compatibility regression).
- CI: selftest-effects.sh (end-to-end guard).

## Impact scope

All CMT-built OCaml indexes: `effects-of` under-reports transitive effects; `pure-fns` over-reports purity (soundness-relevant). Flat NDJSON and Go paths unaffected.
