# Implementation Brief — review-findings-fixes

**Date:** 2026-08-09
**Mode:** full
**Status:** IMPLEMENTED — all arch-index gates pass; coordinated CWR remains external

## Modified files

| Area | Files | Change |
|---|---|---|
| AI-01 curation | `lib/arch_index/arch_index.ml`, `arch_index_support.ml/.mli`, `architecture-schema.sql`, `selftest-curation.sh`, `docs/schema.md`, `docs/curation-workflow.md` | Preserve all four human ledgers inside the rebuild transaction, back up durable identity even after live IDs become NULL, and prove exact survival across repeated pre- and post-removal reindexes. |
| AI-02 coverage | `bin/arch_coverage/arch_cov_write.ml`, `selftest-coverage.sh`, `docs/schema.md` | Append coherent main-schema snapshots while retaining replace semantics for the flat compatibility schema; test both writer orders and history. |
| AI-03 body proof | `lib/arch_index/arch_index_compare.ml/.mli`, `bin/arch_body_compare/arch_body_compare.ml`, `test/test_arch_index_compare.ml`, `selftest-duplicates.sh`, `docs/curation-workflow.md` | Require exact canonical body bytes after digest grouping and add forced-collision/whitespace regressions. |
| AI-04/06 decisions and impact | `lib/arch_tools/arch_db.ml`, `poc/decision-lint/bin/decision_lint.ml`, `bin/arch_impact/arch_impact.ml`, `selftest-impact.sh`, `selftest-decision-lint.sh`, `architecture-schema.sql`, `docs/change-impact.md`, `docs/schema.md` | Bind decision result rows to a run and canonical source-universe/current-index/result digests, recompute them in consumers, normalize DB paths, propagate persistence failures, and strictly parse impact argv. |
| AI-05/06 effects and rules | `lib/arch_effects/effects_db.ml/.mli`, `effects_load.ml/.mli`, `bin/arch_effects_load/main.ml`, `bin/arch_effects_load/dune`, `bin/arch_rules/arch_rules.ml`, `bin/arch_impact/arch_impact.ml`, `architecture-schema.sql`, `effects-schema-migration.sql`, `selftest-effects.sh`, `docs/fitness-functions.md`, `docs/schema.md` | Atomically replace complete effect snapshots, bind run/universe/index/result identities, invalidate completion on partial loads, use shipped `value_kind`/`target` columns, and test clean/violation/partial/tamper/replay consumption. |
| AI-07/08 MCP | `bin/arch_mcp/arch_mcp.ml`, `selftest-mcp.sh`, `docs/mcp-server.md` | Use authoritative `Arch_db.contract_ok`, canonical real-path containment, and add malformed-contract/symlink/sibling-boundary fixtures. |
| AI-09 PCC | `scripts/pcc/pcc-target-manifest`, `pcc-evidence`, `pcc-index`, `pcc-dossier`, `pcc-preflight`, `selftest-pcc.sh`, `docs/pcc-contract.md` | Implement the shared bounded v1 evidence contract and route every post-capture index failure through a final snapshot; mutation overrides build/analyzer failure with a typed refusal/3 receipt. |
| AI-10 release | `.github/workflows/ci.yml`, `scripts/package-release`, `scripts/check-release-manifest`, `selftest-release-manifest.sh`, `README.md` | Create the actual platform tarball, inspect exact members and modes after creation, upload only that archive, and exercise missing/extra/wrong-mode/private-MCP archive negatives tag-free. |

## Decisions made

- The initial default-switch failure was an environment mismatch, not a source regression. A repository-local switch was created at `/tmp/arch-index-opam-switch` with `OPAMROOT=/tmp/arch-index-opam-root`, OCaml 5.3.0, and the declared dependencies. Shared switches were not changed.
- Curation restoration is part of the destructive rebuild transaction. Removed targets retain original module/function identity with nullable live IDs rather than being discarded or ambiguously rebound.
- Ledger backups use left joins and prefer already persisted durable identity over live identity. This makes orphan preservation stable across every later reindex, rather than only the first rebuild after removal.
- Decision/effect availability is authorized only by recognized v1 completion metadata. Effect completion is written through the effect writer's transaction callback, so rows and authorization cannot commit separately.
- Completion metadata is not trusted by shape. Consumers recompute canonical source/universe, current-index, and result digests, require current run IDs on result/universe rows, and reject metadata edits, row edits, partial loads, stale index state, and replayed run IDs. Complete zero-result runs remain valid.
- Decision completion also binds every selected live input's repository-relative path, exact content digest, and permission mode. `arch-impact --repo` recomputes those values before exposing availability; a body-only or mode-only change invalidates even a zero-finding receipt. Main-schema reindex deletes all decision/effect results, universes, and metadata transactionally until producers restamp.
- PCC stdout is a bounded envelope. Detailed target/input manifests are authenticated mode-0600 temporary artifacts and are cleaned by wrappers. Paths in evidence use raw lowercase hex.
- `policy_digest` binds the selected architecture rules and `.pcc/task.md`. `tool_bundle_digest` is a compatibility field for protected arch/PCC files, not an ambient runtime-closure attestation.
- Candidate scripts never claim sandbox enforcement. CWR must own immutable materialization, isolated PATH/runtime, secrets, network, and sandbox-policy attestation.
- PCC v1 refuses submodule-bearing targets because the current index producer cannot prove complete source-path coverage across submodules, although target identity still detects nested state changes.

## Quality gates

- [x] Dependency install: `OPAMROOT=/tmp/arch-index-opam-root opam install --switch=/tmp/arch-index-opam-switch --deps-only --yes .` — PASS (OCaml 5.3.0, 109 packages).
- [x] Build: isolated `opam exec -- dune build` — PASS.
- [x] Unit tests: isolated `opam exec -- dune test` — PASS.
- [x] Affected gates: `selftest-impact`, `selftest-rules`, `selftest-coverage`, `selftest-duplicates`, `selftest-curation`, `selftest-curation-doc`, and `selftest-pcc` — PASS.
- [x] Full shell matrix: `selftest-contract`, `load`, `impact`, `rules`, `mutants`, `coverage`, `effects`, `health`, `duplicates`, `curation`, `curation-doc`, `callgraph-ocaml`, `STRICT=1 callgraph-soundness`, `callgraph-go`, `decision-lint`, and `pcc` — PASS.
- [x] MCP source/test syntax: `ocamlc -stop-after parsing bin/arch_mcp/arch_mcp.ml` and `bash -n selftest-mcp.sh` — PASS.
- [x] Release manifest: locally staged all 12 built public executables and ran `scripts/check-release-manifest ... local-test` — PASS.
- [x] Diff hygiene: `git diff --check` — PASS.
- [x] Post-review orphan regression: isolated `dune build`, `dune test`, `selftest-curation.sh`, `selftest-curation-doc.sh`, and `selftest-coverage.sh` — PASS. The fixture removes a curated function, verifies all durable identities/counts, then performs two more reindexes and compares every ledger ID/value/timestamp/identity exactly.
- [x] NO-GO completion/effects regressions: `selftest-impact.sh`, `selftest-effects.sh`, and `selftest-decision-lint.sh` — PASS. Covers decision/effect metadata tamper, result tamper, source-universe tamper, replay, partial invalidation, canonical `./` path normalization, DB-write exit 2, and shipped-schema rules/impact clean and violation paths.
- [x] NO-GO PCC failure regressions: `selftest-pcc.sh` — PASS. Covers typed error/2 for a non-mutating failed build and refusal/3 with mutation precedence for tracked failed-build, failed-callgraph, and untracked failed-decision-analysis mutations.
- [x] NO-GO final archive regressions: `selftest-release-manifest.sh` — PASS. The same package/check path validates the final tarball and rejects missing, extra, wrong-mode, and private-MCP archive members.
- [x] Actual local archive path: staged all 12 built executables, ran `scripts/package-release`, then re-ran `scripts/check-release-manifest` against the resulting `.tar.gz` — PASS.
- [x] Final full rerun after all NO-GO fixes: isolated `dune build`, `dune test`, all 16 existing shell gates, `selftest-release-manifest.sh`, and `STRICT=1 selftest-callgraph-soundness.sh` — PASS.
- [x] Second-review freshness regressions: `selftest-impact.sh` and `selftest-effects.sh` — PASS. A real zero-finding decision run is computed while unchanged, unavailable after chmod, unavailable after a conditional body replacement with unchanged symbol identity, and remains invalidated after reindex until restamped. A completed effect receipt is likewise rejected after the modified source is rebuilt/reindexed.
- [x] Second-review special-file regression: `selftest-pcc.sh` — PASS. An untracked FIFO created by a failing build is discovered with `lstat` only and produces one `arch-index.pcc.index.v1` refusal envelope, exit 3, `failure_stage=dune_build`, and `mutation_detected=true` without deleting the FIFO.
- [x] Final isolated OCaml 5.3 rerun after freshness/FIFO fixes: `dune build`, `dune test`, every documented shell gate, `selftest-release-manifest.sh`, and strict callgraph soundness — PASS.
- [x] Private MCP build: isolated `ARCH_MCP=yes ... dune build bin/arch_mcp/arch_mcp.exe bin/arch_load bin/arch_query` — PASS after adding the wrapped `arch_tools` dependency/import.
- [x] Private MCP protocol gate: isolated `ARCH_MCP=yes ... ./selftest-mcp.sh` — PASS without skip. Covers valid/unstamped/missing-kind/NULL-kind/invalid-kind provenance, CLI agreement, canonical path containment, protocol framing, and subprocess failure/timeout behavior.
- [ ] Coordinated runner PCC integration — NOT RUN: no CWR revision/pinned arch SHA or engine-owned sandbox environment was available in this workspace.
- [ ] Format/lint — no project command is documented; none was invented.

## Points of attention for review

- The private MCP fixtures are now executed, not parse-only or skipped. The private pin came from `/home/mathias/dev/ocaml-mcp` in the isolated switch; public builds remain intentionally disabled unless `ARCH_MCP=yes`.
- Pair this exact tree with a CWR revision, pin the immutable arch revision in the runner, then verify the five shared identities, wrapper refusal envelopes, engine-owned sandbox policy, isolated runtime, network/secrets blocking, and outside-write behavior.
- The two-pass PCC target manifest detects observed concurrent changes but is not an adversarial snapshot guarantee. Certification depends on CWR-owned immutable materialization or locking.

## Identified out-of-scope

- Publishing `mcp-kit`, enabling private MCP in public builds, changing graph semantics, repairing curation already lost before this fix, and implementing OS sandboxing in this repository remain outside the accepted scope.
- No commit or push was performed.
