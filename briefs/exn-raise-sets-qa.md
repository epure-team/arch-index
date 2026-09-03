# QA Brief — exn-raise-sets

**Date:** 2026-09-03
**Status:** GO ✅
**Round:** 1 (qualifying 0/3)

## Round state

Fresh cycle, round 1; `qa_no_go_round` 0/3 (causes: none). Gated with
`scripts/check-qa-convergence.js` → exit 0.

## Quality Gates

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build | `dune build --root .` | ✅ PASS (exit 0) | 0s (cached) |
| Tests | `dune test --root . --force` | ✅ 91 passed / 0 failed (exit 0) | 85s |
| Format | not documented (no `.ocamlformat`, no fmt step in CI) | n/a | — |
| Self-index + rules | `arch_callgraph_ocaml … lib/arch_index` + `arch-rules … --on-vacuous fail` | ✅ 4 rules, 0 failing | — |
| Golden (CHECK-2) | `diff test/fixtures/self-index-stats.txt` | ✅ `modules: 20 / functions: 532 / calls: 3804` | — |
| CHECK-4 | `git diff 69e5c3d --stat -- lib/arch_index/runner.ml` empty; schema diff additive only | ✅ | — |

## Tests: detail

- New tests added: 2 tezt scenarios (`tezt/tests/exn_raise_sets.ml`, 31 + 24 assertions incl. US-1.11/1.12 from review) + 4 inline tests in `arch_index_exn.ml`
- Existing tests: 89 pass, 0 skip, 0 fail (`must_null_ceiling` recalibrated 260 → 289 for the new module's compiler-libs leaves)
- Regression detected: NO

## Spec runnable checks

- CHECK-1 (tezt red-then-green): PASS — both scenarios green; the producer scenario was red before the producer existed, the query scenario red before the subcommands existed (implement phase log).
- CHECK-2 (build + tests + rules + golden): PASS (table above).
- CHECK-3 (proto_alpha measurement + spot checks): PASS — below.
- CHECK-4 (additive schema; `runner.ml` untouched): PASS.

## Code-intel gate

Code-intel gate: skipped (no `kb/properties.md`, no `scripts/code-intel-resolve.js`).

## Cross-runtime QA

Cross-runtime QA: skipped (review breaker, unchanged runtime version — codex `skipped-degraded`,
digest `codex:bec3ccacdd6c8654`). No second runtime verified the gates independently.

## CHECK-3 — Tezos `proto_alpha` measurement (raw log: `briefs/exn-raise-sets-qa-proto-alpha.log`)

Corpus: `/home/mathias/dev/tezos/tezos/_build/default/src/proto_alpha/lib_protocol` (HEAD
`1727d7e192f`, 500 `.cmt` — the protocol proper, the environment/functor/lifted wrappers, **and
`lib_protocol/test/`**). DB `/mnt/ssd-external-2to/arch-index-runs/proto-alpha-exn.db`.
Index: 468 modules, 14 452 functions, 73 588 calls (26 693 resolved), **0 rejected rows**, 3 s.

```
exn-stats                          exn-stats --assume-externals-pure
nodes            14452             nodes                  14452
bounded          3436 (23.8%)      bounded                6705 (46.4%)
unbounded        11016 (76.2%)     unbounded              7747 (53.6%)
  external       3273                may_top_edge         7743
  may_top_edge   7743                unknown_exn_value    4
origins 1219 (escaping 1219) · scopes 18 · call links 35 · rebinds 6 · fixpoint 0.38 s
origins by form: assert 585 · compare 262 · division 150 · index 124 · failwith 58 · raise 20 · invalid_arg 14 · unknown 5 · reraise 1
```

Reading: the protocol signals errors as `tzresult` values, so `raise`/`try` are rare (20 literal
raises, 18 scopes, 35 scoped calls); the escaping origins are the implicit kind (`assert`,
integer division, bounds checks, polymorphic comparison). ⊤ is dominated by `may_top_edge` —
calls through the functor/module parameters (`alpha_context`, `Saturation_repr`), the class
roadmap 3.7 targets. Under the externals-pure hypothesis the bounded share doubles.

Spot checks (source read, `raises` answer, verdict):

1. `Arith.integral_exn` (`gas_limit_repr.ml:91`): `match Z.to_int z with … | exception Z.Overflow ->`
   → scope `match_exception` catching `Tezos_protocol_environment_alpha.Z.Overflow`; `raises` =
   `UNBOUNDED (⊤): {}` — `Z.to_int` is an external (⊤) and lines 84/87/88 go through the
   functor parameter `S`. Consistent; the handler cannot subtract from ⊤ (by design).
2. `Index.rpc_arg.<fun:46:21>` (`sc_rollup_staker_index_repr.ml:47`): `try Ok (Z.of_string s) with
   Failure _ ->` → scope catches `Failure`; `raises` = ⊤ `external Z.of_string`; under the
   hypothesis `BOUNDED_UNDER_HYP: {}`. Consistent.
3. `classify_annot` (`script_ir_annot.ml:129-143`): `raise Exit` inside the lambda passed to
   `List.fold_left`, wrapped in `try … with Exit`: origin attributed to the lambda node
   (`Tezos_protocol_environment_alpha.Pervasives.Exit`, escaping), the occurrence edge carries the
   try scope, and `raises --assume-externals-pure classify_annot` = `{}` — the lambda's `Exit`
   flows through the occurrence edge and is closed by the try. Byte-identical canonical strings
   on both sides. Consistent — this is the user's hard requirement, on real code.
4. `bin_expr_exn` (`legacy_script_patches.ml:44`): `raise (Failure "…")` → `Failure | - | direct`,
   `UNBOUNDED (⊤): {Failure}` (externals). Consistent.
5. `of_z_opt` (`saturation_repr.ml:62-65`): `Invalid_argument | direct` (comparison at the
   functor-parameter type) + `may_top_edge saturation_repr.ml:62`. Consistent, over-approximating.
6. Entry points (`main.ml`): `begin_application` → `{Assert_failure, Division_by_zero,
   Invalid_argument}` transitively via `apply_liquidity_baking_subsidy`, plus ⊤ through
   `alpha_context.ml:542/594/611`; `apply_operation`, `finalize_block` → `{Assert_failure,
   Division_by_zero}` + ⊤; `init` → ⊤ (externals only). These are findings for a human: the
   protocol's stated invariant is that nothing escapes to the shell; the asserts and integer
   divisions on that cone are named with witnesses.

No `raises` answer contradicts the source → no soundness NO-GO.

Observations for the ship gate (not blocking):
- `validate_operation` exists in `validate.ml` and `main.ml`; `raises validate_operation` prints two
  verdicts labelled by name only — the label should carry the file (LOW, UX).
- Module-alias paths: `test/helpers/tez_helpers.ml` catches `Tezos_protocol_alpha.Environment.Z.Overflow`
  while the protocol spells it `Tezos_protocol_environment_alpha.Z.Overflow` — the same exception
  through a module alias never unifies (over-approximating: the handler closes nothing). Residual
  to document; a `Path` alias normalisation would fix it (LOW).
- The corpus includes `lib_protocol/test/`; a protocol-only measurement would exclude
  `.tezos_alpha_test_helpers.objs` etc. — the numbers above are for the whole directory.

## Verdict

**GO** — ready for `/roster-ship`.
