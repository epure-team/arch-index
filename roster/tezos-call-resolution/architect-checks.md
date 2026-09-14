# Architect checks — round 1, cycle 1

Reviewed HEAD `12ab1fcbd7f4e0cea6b54ea7452b7d9f83338a97` against `main`, the complete changed product files, the implementation/reviewer briefs, `specs/tezos-call-resolution.md` entities and acceptance contract, and `docs/edge-kind-contract.md`. Overall architecture risk is **high until the CRITICAL FR-007/AC-6 violation is corrected**. No product file, commit, branch, worktree, or existing dirt was changed.

The core ownership design otherwise keeps the intended boundaries: `Local_module_ids` keys roots by compiler `Ident` within the per-CMT context (`lib/arch_index/arch_index_cmt.ml:997-1007`); every `Pdot` hop requires a concrete owned structure and `Papply`/`Pextra_ty` refuse (`:1090-1102`); source-order value/module/include masks are constructed before lookup (`:1040-1084`); target identities come from `local_fn_stamps`/`binding_name` (`:973-995`, `:1053-1057`); both rich and flat collectors receive the same context (`:2994-2995`, `:3383-3394`, `lib/arch_index/call_graph_extractor.ml:269-280,320-329`); and the flat attribution guard requires the exact same-file stored name (`lib/arch_index/call_graph_extractor.ml:339-351`). Newly proven ordinary heads remain `Head_enumerated` (`lib/arch_index/arch_index_cmt.ml:2221-2225`), while point-free emission preserves its separate form (`:1582-1585`).

`build_local_module_targets` spans roughly 80 lines (`lib/arch_index/arch_index_cmt.ml:1009-1088`), above the role's configured 50-line informational threshold. I did not file this as a blocking or optional finding: its mutually recursive traversal, source-order accumulator, and identity registry implement one cohesive ownership boundary, and this review established no distinct maintainability defect that warrants broad refactoring during the focused arity correction.

## Commands personally executed

All commands used the RTK prefix and ran from `/home/mathias/dev/arch-index`.

| Command | Exit | Result |
| --- | ---: | --- |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` | 0 | PASS |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force` | 0 | PASS, Tezt 324/324 |
| `rtk proxy node roster/tezos-call-resolution/check-native.js` | 0 | PASS, four native cases |
| `rtk proxy node roster/tezos-call-resolution/check-native.js --self-test` | 0 | PASS, five wrapper-classification assertions |
| `rtk proxy node roster/tezos-call-resolution/check-comparison.js` | 0 | PASS, 28 assertions |
| `rtk proxy node scripts/review-bundle-verify.js` | 0 | PASS, bundle 1.6.0 and 22 hash-matched files |
| `rtk proxy git diff --check main...HEAD` | 0 | PASS |
| `rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --witness improvement/2026-09-14-tezos-resolution/attempt1-reviewed-witness.json` | 0 | PASS candidate; 795 relation gains (+400 Irmin, +395 protocol), zero losses, `retention_authorized=false`; report `improvement/2026-09-14-tezos-resolution/2026-09-14T06-13-02-194Z-candidate-2493995/report.json` |
| `rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --self` | 0 | PASS repeatability; 45,018 unchanged rows, zero movements; report `improvement/2026-09-14-tezos-resolution/2026-09-14T06-13-10-444Z-self-2494457/report.json` |
| `rtk sqlite3 -header -column /tmp/arch-index-reviewer-label-qt01kV/candidate.db \"SELECT ... WHERE caller.name IN ('partial','full') ...\"` | 0 | Confirmed both callers contain `M.f/MAY_ENUMERATED` and `*TOP*/MAY_TOP/callback_param`; the omitted-label `partial` residual violates FR-007/AC-6 |

The green aggregate/native/fixed410 gates do not invalidate the finding because the registered arity cases are positional and the reviewed fixed410 witnesses contain no omitted-label counterexample. The candidate comparison explicitly does not authorize retention. Recommendation: **NO-GO / changes required**, then rerun build, full tests, native checks, comparison and fixed410 after the focused correction.
