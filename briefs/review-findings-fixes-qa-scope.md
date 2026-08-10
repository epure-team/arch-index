# QA Scope — review-findings-fixes

**Date:** 2026-08-10
**Status:** VALIDATED

## Quality Gates

```bash
# Dependencies and build
opam install --deps-only --yes .
opam exec -- dune build

# Unit tests
opam exec -- dune test

# Directly affected integration tests
./selftest-impact.sh
./selftest-rules.sh
./selftest-coverage.sh
./selftest-duplicates.sh
./selftest-curation.sh
./selftest-curation-doc.sh
./selftest-pcc.sh

# Mandatory private MCP build and protocol gate
ARCH_MCP=yes opam exec -- dune build bin/arch_mcp/arch_mcp.exe bin/arch_load bin/arch_query
./selftest-mcp.sh

# Full documented CI shell gate
./selftest-contract.sh
./selftest-load.sh
./selftest-impact.sh
./selftest-rules.sh
./selftest-mutants.sh
./selftest-coverage.sh
./selftest-effects.sh
./selftest-health.sh
./selftest-duplicates.sh
./selftest-curation.sh
./selftest-curation-doc.sh
./selftest-callgraph-ocaml.sh
STRICT=1 ./selftest-callgraph-soundness.sh
./selftest-callgraph-go.sh
./selftest-decision-lint.sh
./selftest-pcc.sh
```

No lint/format gate is documented; do not add one. The MCP commands require the private `mcp-kit` pin/token. The coordinated runner must separately execute its real PCC integration against this branch before merge.

## Execution Evidence

- Isolated switch: `OPAMROOT=/tmp/arch-index-opam-root`, switch `/tmp/arch-index-opam-switch`, OCaml 5.3.
- Private pin: `/home/mathias/dev/ocaml-mcp` supplies `mcp-kit` and `mcp-kit.stdio`.
- `ARCH_MCP=yes opam exec -- dune build bin/arch_mcp/arch_mcp.exe bin/arch_load bin/arch_query` — PASS.
- `ARCH_MCP=yes opam exec -- ./selftest-mcp.sh` — PASS without `SKIP`; malformed-contract, canonical-containment, JSON-RPC, and subprocess cases executed.

## Behavior Matrix

| Criterion | Fixtures/scenarios | Required result |
|---|---|---|
| AI-01 | Populated ledgers, two reindexes, surviving/removed/ambiguous targets, injected restoration error, shipped schema from `main` | Exact rows/fields/history/run ordering retained; stable remap; durable original/removed identity; ambiguity/error rolls back; migration succeeds |
| AI-02 | Both writers in both orders, prior history, coherent snapshot, failed/ambiguous input | No main-table delete; old rows queryable; deterministic latest; failure adds zero rows; flat schema remains documented current-state-only |
| AI-03 | Multiline literal/comment/blank differences, indentation-only source, unreadable/empty body, equal digest over unequal bodies | Exact equality unless language-aware proof; no false `Identical`; digest followed by equality; all-or-nothing existing refusal preserved |
| AI-04 | Complete zero findings, new findings, stale rows, missing/legacy/invalid stamp, parse/walk failure, crash/tamper/replayed source digest | Atomically bound run ID/source-index digest/producer version/universe/outcome; clean `pass`/0; new `fail`/1; unavailable/partial `refused`/3 |
| AI-05 | Unrelated effect, complete zero-effect cone, partial skip, stale/tampered contract, crash, true violation | PASS only for atomically stamped fully covered clean cone; missing/partial follows documented `NOT_COMPUTED`/`UNKNOWN` and fail policy |
| AI-06 | Documented defaults plus typo, duplicate singleton, missing value, extra positional, invalid enum | Valid commands unchanged; malformed commands give precise diagnostic and exit 2 |
| AI-07 | Valid, unstamped, missing `calls.kind`, NULL kind, invalid kind | MCP and CLI agree; malformed evidence never reports sound provenance; structured/prose/verdict agree |
| AI-08 | Valid nested file, traversal, absolute, external-file symlink, external-dir symlink, sibling-prefix root, missing target | Only canonical in-root target accepted; rejects disclose no external contents |
| AI-09 | Shared v1 hostile fixture; passing/failing commands mutate base/index/overlay/deletions/non-ignored untracked/modes/symlinks/submodules/protected metadata; ignored files; direct/snapshot/out-of-band cases | Versioned typed JSON/digest agrees; step refuses required mutation without cleanup; ignored exclusion is explicit; CWR-only isolation blocks outside writes/secrets/network |
| AI-10 | Every supported platform archive, missing/mode-negative fixture, tag-free CI path | Exact manifest and executable bits contain all public executables including three additions, exclude documented `arch_mcp`, and fail on absence/wrong mode |

## Cross-Cutting Assertions

- Validate existing main-schema databases from `main`, including migrations and reindex.
- Validate recognized metadata key, version, producer outcome, failures, completeness, and relevant scope through the authoritative helper.
- Assert JSON values, text verdict, stdout framing, and exit status together.
- Rerun former false-pass, false-proof, persistence, containment, packaging, and mutation reproductions independently.
- Test a declared arch/CWR PR-SHA pair, merge arch first, pin the immutable arch SHA in CWR, and rerun the real integration.
- Do not accept completion with any open CRITICAL or HIGH review finding.

## TUI Matrix

Not applicable; the intake defines CLI, database, shell, MCP protocol, and CI/release behavior only.
