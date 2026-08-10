# Reviewer Brief — review-findings-fixes

**Date:** 2026-08-09
**Status:** VALIDATED

## Review Objective

Audit a ten-criterion compatibility fix whose core claim is fail-closed evidence: no proof or clean result without complete validated inputs, no routine reindex loss of human curation, canonical MCP containment, truthful PCC mutation receipts, and complete release archives. Independently rerun the former reproductions; approval requires no open CRITICAL or HIGH finding.

## Audit Order

1. Audit `lib/arch_index/arch_index.ml`, `arch_index_support.ml/.mli`, `architecture-schema.sql`, and `selftest-curation.sh` for atomicity, durable original identity, run identity/total ordering, orphan identity, ambiguity rollback, shipped-schema migration, and exact double-reindex preservation (AI-01).
2. Audit both coverage writers and `selftest-coverage.sh` for deletes, coherent timestamps, transaction boundaries, deterministic latest selection, and failure atomicity (AI-02).
3. Audit `arch_index_compare.ml`, its unit tests, CLI integration, and proof docs for lexical changes, post-digest equality, and forced collisions (AI-03).
4. Audit `arch_db.ml`, decision producer, impact consumer, PCC contract, schema/docs, and strict argv tests as one producer-to-verdict path (AI-04, AI-06).
5. Audit effect loader/database, cone evaluation, rules policies, strict argv tests, and completeness docs as one producer-to-verdict path (AI-05, AI-06).
6. Audit MCP provenance and path resolution with identical malformed fixtures and real symlink boundaries (AI-07, AI-08).
7. Audit the shared PCC v1 typed JSON/exit/digest contract, complete Git manifest domain, and hostile fixture before both scripts; then audit success/failure mutation dimensions, JSON-only stdout, non-cleanup, truthful ownership language, and coordinated runner integration (AI-09). Confirm CWR alone controls mounts/environment/network and read-only-source/writable-build isolation.
8. Audit workflow assembly and the final archives rather than staging-directory listings; confirm all public binaries, executable bits, protected private MCP checks, and intentional MCP exclusion on every platform (AI-10).
9. Audit README/docs against actual schema, JSON, text, exits, and migration behavior; rerun the complete gates.

## Adversarial Checks

- Reindex a populated database twice; remove and ambiguously rename symbols; force restoration failure; compare every ledger field and confirm rollback retains the original DB.
- Interleave both coverage writers in both orders; create timestamp ties and failed writes; query old rows directly and latest values through `arch-query low-coverage`.
- Place significant whitespace inside multiline strings/comments and force equal digests for unequal canonical bodies; verify no false `Identical`.
- Create zero-finding completed decision runs, stale rows without stamps, legacy-key-only metadata, malformed versions/outcomes, parse/walk failures, and partial results; verify JSON/text/exit agreement.
- Crash between result and stamp writes; tamper with run ID/source digest/analyzed universe; replay a valid old stamp against new input; verify atomic binding prevents authorization.
- Put an effect row outside the evaluated cone; use complete zero-effect and partial `--allow-skip` inputs; verify only complete cone evidence can pass.
- Fuzz both safety CLIs with unknown/typo, duplicate, missing-value, invalid-enum, and positional arguments; every malformed invocation must diagnose and exit 2.
- Compare MCP and CLI on valid, unstamped, missing-kind, NULL-kind, and invalid-kind DBs; then attempt absolute, traversal, external symlink, symlinked-directory, and sibling-prefix paths without leaking file content.
- Mutate tracked, staged, untracked, HEAD, and post-test state from commands that otherwise pass and fail; cover modes, symlinks, submodules, deletions, protected metadata, and ignored-file exclusion; verify refusal, preserved changes, secure log cleanup, and no success receipt.
- Distinguish direct unsandboxed script mutation, mutation of the runner's read-only snapshot, and out-of-band live-checkout mutation. Verify candidate content cannot select mounts, environment, or network.
- Validate an explicit arch/CWR PR-SHA pair, then verify arch-first merge, immutable SHA pinning in CWR, and the post-pin rerun.
- Inspect each produced archive manifest and executable mode and test the same assertion without a tag.

## Highest-Risk Failure Modes

Partial schema commit, orphan identity collapse, global metadata mistaken for scoped completeness, digest-as-proof regression, lexical prefix containment, incomplete git-state snapshots, JSON/exit disagreement, and confusing repository detection with sandboxing are release blockers.

## Expected Behaviors

The exact behavioral matrix is the plan's AI-01 through AI-10 acceptance table. Missing, stale, invalid, partial, ambiguous, or malformed evidence must never degrade to a pass. Existing documented valid invocations and defaults remain compatible. Existing databases from `main` migrate/reindex without losing post-fix history.

## Required Gates

Run `opam exec -- dune build`, `opam exec -- dune test`, every shell command in the QA scope, the private MCP gate, and the coordinated runner integration. Verify actual JSON fields, stdout framing, and exit status rather than relying on shell success alone. Record any CRITICAL/HIGH finding as blocking.
