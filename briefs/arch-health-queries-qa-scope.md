# QA Scope — arch-health-queries

**Status:** VALIDATED
**Contract:** specs/arch-health-queries.md CHECK-1..6.

## Gates

```bash
opam exec -- dune build && opam exec -- dune test --force
./selftest-contract.sh && ./selftest-load.sh && ./selftest-mcp.sh && ./selftest-health.sh
```

## Checks (verbatim from spec Runnable Checks)

- CHECK-1: large-functions on self-index (rows, exit 0) + large-files on flat DB (exit 3).
- CHECK-2: `god-modules abc` → exit 2.
- CHECK-3: fixture duplicates group; `type-search - string`; flat type-search → exit 3.
- CHECK-4: arch-body-compare IDENTICAL on fixture; unknown name → exit 1.
- CHECK-5: full test+selftest suite + metrics self-gate still green.
- CHECK-6: `unsafe-strings 1` deterministic across two runs.

## Extra probes

- `type-search '100%'` literal matching; `large-functions 0`… wait 0 is numeric — confirm behavior specified (0 allowed → all functions; acceptable) — verify no crash.
- Pre-existing exclusion: selftest-effects.sh.
