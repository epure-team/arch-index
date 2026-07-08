# Implementation Brief — selftest-effects-failure

**Date:** 2026-07-09
**Mode:** fast
**Status:** COMPLETED

## Modified files

| File | Type of change | Reason |
|---|---|---|
| `lib/arch_effects/ocaml_effects_extractor.ml` | modification | Emit **unqualified** function names (`Ident.name id`) instead of `modname ^ "." ^ Ident.name id`, matching `arch_index_cmt`'s `functions.name`/`callee_name` convention so `effects-of`/`pure-fns` joins match. Dropped the now-orphan `modname` binding (warning 26). GlobalVar site also unqualified. |
| `lib/arch_effects/capability_db.ml` | modification | `fn_exists` now matches exact **OR** unqualified-suffix, so historical qualified `fn: "Module.function_name"` sidecar entries still resolve against the now-unqualified extractor rows (no spurious NoEffect). |
| `selftest-effects.sh` | modification | Fixed stale fallback binary path `arch_effects_ocaml/main.exe` → `arch_effects_ocaml/arch_effects_ocaml.exe`. |
| `.github/workflows/ci.yml` | modification | Added `selftest-effects.sh` to the chmod list and the shell-integration-tests run block — CI ratchet now that it is green. |
| `docs/attack-surface-capability.md` | modification | Documented that `fn:` accepts qualified `Module.function_name` **or** unqualified `function_name`. |
| `briefs/selftest-effects-failure-investigation.md` | addition | Root-cause investigation report. |

## Decisions made

- **Unqualified naming is the system-wide identity convention.** `arch_index_cmt` already
  stores unqualified `Ident.name` for both `functions.name` and `callee_name`. Qualifying
  effect names broke every transitive join and corrupted `pure-fns` (all fixture mutators
  reported pure). Aligning on unqualified is the correct, minimal fix.
- **Accepted trade-off (documented):** bare names can collide across modules (`A.f` vs `B.f`).
  This is the pre-existing convention for the whole callgraph, not new debt. Follow-up logged:
  id-keyed effects (`function_id` + `file_path` joins) to eliminate collisions.
- **Backward-compat for sidecars** kept via exact-or-suffix matching in `fn_exists`.

## Quality Gates

**ENV NOTE (load-bearing):** all gates require the project's **local opam switch**, not the
shell default. Run first:
```bash
eval $(opam env --switch=/home/mathias/dev/arch-index --set-switch)
```
The default `octez-setup` switch has an older eio/cohttp-eio/mirage-crypto-rng and the build
fails with unrelated API errors (`_ Eio.Flow.source`, `Cohttp_eio.Server.respond_string`,
`Mirage_crypto_rng_unix.use_default`) — an environment artifact, not a code defect.

- [x] Build: `dune build` ✅
- [x] Tests: `dune test --force` ✅
- [x] selftest-effects.sh ✅ (the fix under test)
- [x] selftest-contract.sh ✅
- [x] selftest-load.sh ✅
- [x] selftest-callgraph-go.sh ✅

## Points of attention for review

- Join-compatibility: extractor output names must equal the callgraph producer's naming.
- Sidecar backward-compat via `fn_exists` exact-or-suffix.

## Identified out-of-scope

- `selftest-callgraph-ocaml.sh` fails on clean main (verified identical on `main`), for two
  independent reasons: (1) a name-pattern assertion `name LIKE '%.add'` that assumes qualified
  names (trivial), and (2) the deeper, real issue — `arch-callgraph-ocaml` in **main-schema
  mode emits `calls.kind = NULL` and sets no `callgraph_contract` meta flag**, so all
  edge-kind soundness verdicts (`reaches`/`unreachable`/`escapes`) and the edge-kind integrity
  check fail. Fixing (2) is a producer soundness feature in `arch_index_cmt`, a separate task —
  NOT folded into this effects fix. Logged as a follow-up.
