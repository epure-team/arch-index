# Implementer Brief — review-findings-fixes

**Date:** 2026-08-09
**Status:** VALIDATED

## Goal

Correct all ten reviewed defects while enforcing one rule: proof or clean output requires complete, validated evidence, and routine reindexing must preserve human curation. Deliver one compatibility change with adversarial regression coverage and aligned human/machine contracts.

## Scope Boundary

Do not change call-graph extraction or MUST/MAY/MAY_TOP meaning; add metrics, commands, rules, or backends; claim OS sandboxing in this repository; publish `mcp-kit` or enable `arch_mcp` by default; change release naming/platforms or unrelated CLI output; or repair history already lost before the corrected indexer. Conservative body `Differs` is acceptable when equality cannot be proved.

## Files and Anchors

| Capability | Files to modify first | Existing anchors |
|---|---|---|
| Curation preservation | `lib/arch_index/arch_index.ml`, `arch_index_support.ml`, `arch_index_support.mli`, `architecture-schema.sql`, `selftest-curation.sh` | `backup_intents`, `restore_intents`, `DROP TABLE IF EXISTS`, ledger FKs |
| Coverage history | `bin/arch_coverage/arch_cov_write.ml`, `arch_coverage.ml`, `bin/arch_coverage_load/arch_coverage_load.ml`, `selftest-coverage.sh` | `DELETE FROM coverage`, timestamped `INSERT` |
| Body proof | `lib/arch_index/arch_index_compare.ml`, `test/test_arch_index_compare.ml`, `bin/arch_body_compare/arch_body_compare.ml`, `selftest-duplicates.sh` | per-line `String.trim`, MD5 grouping, `Identical` |
| Decision contract/impact argv | `lib/arch_tools/arch_db.ml`, `poc/decision-lint/bin/decision_lint.ml`, `bin/arch_impact/arch_impact.ml`, `selftest-impact.sh`, `selftest-pcc.sh` | `require_contract`, `contract_ok`, `decision_analysis`, `decision_contract`, `Arch_db.nonempty`, permissive option stripping |
| Effect completeness/rules argv | `bin/arch_effects_load/main.ml`, `lib/arch_effects/effects_db.ml`, `bin/arch_rules/arch_rules.ml`, `selftest-rules.sh` | `--allow-skip`, `function_effects`, global nonempty check, permissive option stripping |
| MCP trust | `bin/arch_mcp/arch_mcp.ml`, `selftest-mcp.sh` | raw `callgraph_contract`, lexical `repo_relative` |
| PCC mutation | `scripts/pcc/pcc-index`, `scripts/pcc/pcc-preflight`, `selftest-pcc.sh` | target `dune build`/`dune test`, JSON receipt, temporary logs |
| Releases | `.github/workflows/ci.yml` | release binary loop and `dist/` listing |
| Contracts/docs | `README.md`, `docs/schema.md`, `docs/curation-workflow.md`, `docs/mcp-server.md`, `docs/change-impact.md`, `docs/fitness-functions.md` | old coverage/proof/metadata/completeness/containment/safety claims |

## Sequential Steps

1. Implement AI-01 as an atomic preservation/remap/restore slice, including removed/ambiguous identity behavior, unit coverage, double-reindex integration, migration docs, and rollback proof.
2. Implement AI-02 append-only atomic main-schema snapshots, both-writer ordering tests, deterministic latest reads, failure atomicity, and flat-schema distinction docs.
3. Implement AI-03 conservative canonical equality plus post-digest byte comparison, forced collision seam, refusal regressions, CLI verdict, and exact proof docs.
4. Implement AI-04 and impact-side AI-06: one versioned completed-run contract atomically binding run ID, source/index digest, producer version, analyzed universe, outcome/failures, and result rows; strict shared validation; crash/tamper/stale/zero-result fixtures; producer/consumer/PCC alignment; full verdict/exit matrix; and strict argv parsing.
5. Extend that pattern for AI-05 and rules-side AI-06: cone-relevant effect completeness, partial `--allow-skip` that cannot stamp completion, crash/tamper/stale/zero-effect fixtures, fail-policy behavior, and strict argv parsing.
6. Implement AI-07 by using authoritative `Arch_db.contract_ok` for MCP provenance and malformed stamped fixtures shared with CLI expectations.
7. Implement AI-08 canonical root/target containment and all traversal, symlink, sibling-prefix, missing-target, and non-disclosure tests.
8. Freeze the shared PCC v1 typed JSON/exit/digest contract and hostile fixture, then implement repository-local AI-09 mutation snapshots across success/failure paths, truthful receipts/docs, refusal without cleanup, and runner integration fixtures. The manifest covers base OID, index, tracked overlay/deletions, non-ignored untracked files, modes, symlinks, submodules, and protected metadata. CWR alone owns mounts/environment/network and read-only-source plus writable-build/temp isolation.
9. Implement AI-10 exact archive manifests and executable-bit checks for every platform through a tag-free CI test; add all three missing binaries, retain documented MCP exclusion, and keep the private MCP gate protected.
10. Reconcile all documentation and machine contracts, run every quality gate, run coordinated runner integration, and submit to independent adversarial review with zero CRITICAL/HIGH findings.

## Acceptance Obligations

Every criterion is mandatory: AI-01 curation survival and rollback; AI-02 writer interoperability/history; AI-03 verified equality; AI-04 completed decision evidence; AI-05 cone-complete effects; AI-06 strict argv; AI-07 authoritative MCP provenance; AI-08 canonical path containment; AI-09 mutation detection plus runner sandbox; AI-10 exact release manifests. Use the plan's acceptance-coverage table as the traceability checklist.

## Points of Attention

- Decide durable orphan identity before destructive schema work; never allow an error path to commit a partial rebuild.
- Test coverage reindex preservation and append-only writing together because both touch the same ledger.
- A recognized metadata key alone is insufficient: validate version, outcome, failures, completeness, and relevant scope.
- A digest is an index only; canonical bytes establish identity.
- Default body proof to exact equality unless a language-aware canonicalisation proves safety; unreadable/empty input remains an all-or-nothing refusal.
- Do not turn repository mutation detection into cleanup, and do not describe it as OS isolation.
- Distinguish direct script mutation, snapshot mutation under CWR, and out-of-band live-checkout mutation. Candidate code must not choose isolation mounts, environment, or network.
- Assert JSON, absence of trailing stdout, human output, and exit code together.
- Keep all existing exact documented invocations/defaults compatible while rejecting malformed argv.
- Structure reviewable commits in dependency order: contract/migration, producers, consumers, PCC, packaging/docs. Validate an explicit arch/CWR PR-SHA pair, merge arch first, pin its immutable SHA in CWR, and rerun.

## Exact Quality Gates

```bash
opam install --deps-only --yes .
opam exec -- dune build
opam exec -- dune test

./selftest-impact.sh
./selftest-rules.sh
./selftest-coverage.sh
./selftest-duplicates.sh
./selftest-curation.sh
./selftest-curation-doc.sh
./selftest-pcc.sh

ARCH_MCP=yes opam exec -- dune build bin/arch_mcp/arch_mcp.exe bin/arch_load bin/arch_query
./selftest-mcp.sh

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

The MCP gate requires the private `mcp-kit` environment. Also run the coordinated runner's real PCC integration against this branch. There is no lint/format command to invent.
