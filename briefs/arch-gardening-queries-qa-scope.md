# QA Scope — arch-gardening-queries

**Status:** VALIDATED. Floor: specs/arch-gardening-queries.md CHECK-1..5.

Gates: `opam exec -- dune build && opam exec -- dune test --force`; selftests contract/load/mcp/health; metrics self-gate.
Checks: CHECK-1 (query scenarios incl. latest-record exclusion, gardening open incl. in_progress, unsafe-params filters, flat exit 3); CHECK-2 (loader written→ignored idempotency + rollback-on-malformed leaves count unchanged); CHECK-3 (ambiguous/unknown skips, exit 0); CHECK-4 (documented SQL executes via extraction); CHECK-5 (full suite green).
Extra: `--stamp bad-format` → exit 2; `low-coverage 101` lists all; determinism double-run.
Excluded: selftest-effects.sh (pre-existing).
