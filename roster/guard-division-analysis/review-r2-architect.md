# Architect R2 cycle 1 — independent review

## Verdict

Architecture risk: **low**. One LOW documentation/integration finding is recorded in
`findings.json`; it is non-blocking and does not alter the public product contract.

## R1 architect disposition

`lib/arch_guard/guard_interpreter.ml:111:architecture#c4061b21` — **RESOLVED**.

The R1 invariant applied to a public installed library embedding surface. At this
head that surface is deliberately absent: `lib/arch_guard/dune:1-3` defines a
private library with no `public_name`; `bin/arch_guard/dune:1-4` alone exposes
the installed `public_name arch_guard`; `docs/arch-guard.md:15-21` and
`specs/guard-division-analysis.md` FR-033 clarification define only the
executable and root dispatcher as public. This is a legitimate narrowed
contract, not a claim that `Load_path` state is restored. Independent `owned`
verification passed and reported `publicCli:true`, `privateLibraryInstalled:false`,
and four present private probes. The generated install manifest check is part of
that checker. No host-process restoration, new embedding API, or compiler-global
state proof is claimed.

## Independent runtime evidence

- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` — exit 0.
- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force` — exit 0; 256/256 Tezt cases and the 64 Alcotest cases reported.
- Six guard checker modes plus standalone context check — all exit 0. Domain: 640734 probe responses and 23219242 law assertions; this is executable coverage, not a machine-checked proof.
- Origin checker modes `authentic`, `failures`, and `package` — all exit 0.
- Fresh self index — exit 0; 23 modules, 828 functions, 5223 calls. CI golden comparison exit 0.
- Fresh self rules — exit 0; one proved, three UNKNOWN, zero failures. UNKNOWN is retained as unknown.
- Fresh origin producer and artifact validator — exit 0; held result, no proof claim.
- Fresh self impact — exit 0; 102 changed files outside the index are UNKNOWN, not zero impact.
- `rtk proxy env DUNE_CACHE=enabled DUNE_CACHE_STORAGE_MODE=copy opam exec --switch=/home/mathias/dev/arch-index -- ./scripts/recalibrate.sh --check` — exit 0 at `c586a9319039`; golden 23/828/5223; ceiling A=B396 and C=D437; pin 430 remains within unchanged 25 headroom.

## Scope and exclusions

Scope gate was already exit 0 at the exact tip and was intentionally not reassessed.
No Tezos or external-corpus scan, no external safety/proof/gain claim, no opam
install/pin, and no production/task-artifact write occurred. Existing opam lint
debt and absent odoc were not used as gates. No KB was present.
