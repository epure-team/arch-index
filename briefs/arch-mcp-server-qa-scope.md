# QA Scope — arch-mcp-server

**Status:** VALIDATED
**Contract:** specs/arch-mcp-server.md — CHECK-1..7 are the QA floor.

## Gates

```bash
opam exec -- dune build
opam exec -- dune test --force
./selftest-contract.sh && ./selftest-load.sh && ./selftest-mcp.sh
```

## Spec checks (run verbatim from specs/arch-mcp-server.md Runnable Checks)

- CHECK-1: initialize + tools/list pipe → protocolVersion 2024-11-05, 11 tools.
- CHECK-2: garbage line then valid request → -32700 then result, same session.
- CHECK-3: arch_find on flat fixture → isError false, matches array.
- CHECK-4: arch_unreachable on ⊤-marked fixture → verdict; on legacy DB → isError REFUSED.
- CHECK-5: arch_metrics text equals `arch-query <db> metrics` (jq diff) on self-index.
- CHECK-6: `--db /nonexistent` → exit 2.
- CHECK-7: dune test (test_arch_mcp suite).

## Extra probes

- stdout purity: run a full session, assert every stdout line parses as JSON (`jq -e .` per line).
- Notifications (incl. `notifications/initialized`) produce zero output.
- String request ids echoed back verbatim.
- arch_fan_in {"n":"25"} (string) → isError invalid arguments.
- Determinism: same session twice → identical outputs.
- Pre-existing failure exclusion: selftest-effects.sh (see item-1 QA brief).
