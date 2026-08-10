# Plan — review-findings-fixes

**Date:** 2026-08-09
**Status:** VALIDATED

## Sequential steps

1. **Preserve curation ledgers through atomic reindex (AI-01)** — Extend the preservation contract in `lib/arch_index/arch_index_support.ml` and `.mli`, the orchestration in `lib/arch_index/arch_index.ml`, and, if durable orphan identity requires it, `architecture-schema.sql`. Back up all `coverage`, `unsafe_params`, `gardening_tasks`, and `gardening_log` data with stable module/function identity; rebuild, unambiguously remap surviving targets, preserve recognizable identity for removed targets, and restore within one rollback-capable transaction. Add focused helper tests and a two-reindex integration regression in `selftest-curation.sh`. Update `docs/schema.md` and `docs/curation-workflow.md` for any schema or orphan-retention behavior. Complete when exact row counts and all values, timestamps, provenance, issue/PR numbers, fixed status, and history survive twice, while ambiguity/restoration failure leaves the original database intact.

2. **Make main-schema coverage writes append coherent history (AI-02)** — Change `bin/arch_coverage/arch_cov_write.ml` and its `bin/arch_coverage/arch_coverage.ml` entry point so a main-schema write appends one atomic, single-timestamp snapshot without a whole-table delete; retain current-state-only behavior only for flat-schema `coverage_by_name`. Verify deterministic latest-per-function reads against `bin/arch_coverage_load/arch_coverage_load.ml` and the existing query contract. Expand `selftest-coverage.sh` to seed and invoke both writers in both orders, retain byte-queryable history, prove latest selection, and prove failed or ambiguous writes append nothing. Document the schema distinction. Complete when the two writers interoperate without deleting prior snapshots.

3. **Require verified canonical equality for duplicate proofs (AI-03)** — Replace unsafe per-line whitespace trimming in `lib/arch_index/arch_index_compare.ml` with the conservative canonicalisation allowed by the brief, and require canonical-body equality after any digest grouping. Add a forced-collision seam that cannot let unequal bodies reach `Identical`. Extend `test/test_arch_index_compare.ml` and `selftest-duplicates.sh` for multiline literal/comment/blank-line differences, ordinary indentation-only changes, unreadable and empty bodies, and forced equal digests. Align the proof wording in `bin/arch_body_compare/arch_body_compare.ml` and `docs/curation-workflow.md`. Complete when `Identical` means confirmed canonical equality and every unprovable case is `Differs` or the existing refusal result.

4. **Establish a completed decision-analysis contract and strict impact CLI (AI-04, AI-06 impact half)** — Define one recognized, versioned decision completion record and validate producer outcome plus parse/walk completeness through shared authoritative helpers in `lib/arch_tools/arch_db.ml`; update `poc/decision-lint/bin/decision_lint.ml`, `architecture-schema.sql`, `docs/schema.md`, `bin/arch_impact/arch_impact.ml`, and relevant PCC receipts/scripts to use exactly that contract without treating stale legacy metadata as current proof. In the same end-to-end impact slice, make `arch-impact` reject unknown options, duplicate singleton options, missing values, invalid enums, and extra positionals with diagnostic/exit 2. Expand `selftest-impact.sh`, `selftest-decision-lint.sh` as needed, and `selftest-pcc.sh` for complete zero findings, stale rows, missing/invalid stamps, partial runs, strict parsing, JSON/text agreement, and exit codes; remove the synthetic finding workaround. Complete when unavailable/invalid/partial is `refused`/3 under `--fail-on-new-findings`, new findings are `fail`/1, and complete clean analysis is `pass`/0.

5. **Require cone-complete effect evidence and strict rules CLI (AI-05, AI-06 rules half)** — Build on the validated metadata helper from step 4 to persist and validate an effect producer/completeness contract in `bin/arch_effects_load/main.ml`, `lib/arch_effects/effects_db.ml`, and `architecture-schema.sql`. Make `bin/arch_rules/arch_rules.ml` authorize a clean effect rule only when every function in the evaluated cone has valid complete coverage; keep `--allow-skip` visibly partial and unstamped. In the same rules slice, strictly parse all argv and reject unknown, duplicate, missing, invalid, or extra arguments with diagnostic/exit 2. Expand `selftest-rules.sh` and affected effect tests for unrelated rows, complete zero-effect cones, partial loads, stale metadata, genuine violations, typo/duplicate/missing/positional errors, fail-policy behavior, and JSON/text consistency. Update `docs/schema.md` and `docs/fitness-functions.md`. Complete when a different cone's row can never authorize PASS and missing/partial evidence yields documented `NOT_COMPUTED` or `UNKNOWN` behavior.

6. **Unify MCP provenance with validated CLI soundness (AI-07)** — Route `bin/arch_mcp/arch_mcp.ml` provenance through the same `Arch_db.contract_ok` validation used by CLI consumers, including required `calls.kind` presence and recognized non-NULL values. Expand `selftest-mcp.sh` with identical valid, unstamped, missing-kind-column, NULL-kind, and invalid-kind fixtures and assert agreement among structured provenance, prose caveat, reachability verdict, and CLI behavior. Update `docs/mcp-server.md`. Complete when raw metadata presence alone can never produce sound provenance.

7. **Contain MCP paths by canonical repository boundary (AI-08)** — Canonicalise the configured root and each existing candidate before use in `bin/arch_mcp/arch_mcp.ml`, then enforce a path-component containment boundary while retaining rejection of absolute paths, `..`, missing targets, and invalid shapes. Expand `selftest-mcp.sh` for valid nested files, traversal, absolute paths, external file and directory symlinks, and similarly prefixed sibling roots; assert responses and subprocess diagnostics never disclose external contents. Update `docs/mcp-server.md`. Complete when only canonical targets inside the canonical root are usable.

8. **Detect every candidate-tree mutation around PCC execution (AI-09 repository half)** — First freeze a shared versioned PCC contract with the coordinated runner: JSON field names/types, JSON-only stdout and exit matrix, digest algorithm and domain, and a submission manifest covering base OID, index, tracked overlay/deletions, non-ignored untracked files, modes, symlinks, submodules, and protected metadata while explicitly excluding ignored files. In `scripts/pcc/pcc-index` and `scripts/pcc/pcc-preflight`, snapshot tracked content/state, staged state, untracked state, and HEAD before repository-authored commands and compare on all success and failure paths without resetting or deleting user data. Any mutation must fail and must produce JSON/exit status that cannot claim success. Keep temporary logs secure and cleaned. Declare that CWR alone chooses isolation mounts/environment/network and materializes a read-only source snapshot with separate writable build/temp space; these scripts own target/digest/test semantics and direct mutation detection but do not claim protection from live-checkout out-of-band mutation or outside-repository writes. Expand `selftest-pcc.sh` with hostile commands that otherwise pass after creating tracked, staged, untracked, and post-test changes, and assert refusal without cleanup. Supply the shared fixture for runner tests that distinguish snapshot mutation, live-checkout out-of-band mutation, and direct unsandboxed script mutation. Complete locally when all in-tree mutations are detected; final acceptance also depends on testing an explicit PR-SHA pair, merging arch first, pinning its immutable SHA in CWR, rerunning integration, and proving outside-write and ambient secret/network blocking.

9. **Make release contents an asserted contract (AI-10)** — Update `.github/workflows/ci.yml` so every supported platform archive includes `arch_body_compare`, `arch_coverage_load`, and `arch_curate` alongside all existing public executables, continues intentionally excluding `arch_mcp`, fails on any missing executable, and validates the final archive manifest including executable bits. Add a CI-testable manifest check that runs without a publication tag, keep the private MCP check protected, and document the intentional MCP exclusion in the relevant release documentation/README. Complete when the non-publishing check proves exact expected contents and modes for every release-platform archive.

10. **Close compatibility, documentation, and adversarial gates (AI-01 through AI-10)** — Reconcile README, schema, curation, impact, fitness, MCP, PCC, and release statements with implemented machine contracts; run unit, affected integration, MCP-private, and complete CI shell gates. Run the coordinated runner's real PCC integration against this branch. Have an independent adversarial reviewer rerun every former false-pass, false-proof, persistence, containment, packaging, and mutation reproduction. Complete only when JSON fields and exits match human output, migrations work against existing `main` databases, all gates pass, and no CRITICAL or HIGH review finding remains.

## Dependencies

- Step 1 precedes the final compatibility gate because it defines reindex and migration behavior for existing main-schema databases.
- Steps 1 and 2 are coordinated on the `coverage` schema: coverage history must both survive reindex and remain append-only between writers. Neither slice may invalidate the other's fixtures.
- Step 4 precedes step 5 because the decision slice establishes the shared recognized-key/version/outcome/completeness validation pattern that the effect slice extends rather than weakly reimplements.
- Steps 4 and 5 each include their CLI half of AI-06 so strict parsing is tested against the actual safety policy it protects.
- Step 6 precedes step 7 only to keep MCP failures attributable: provenance validation is stabilized before path-boundary handling changes in the same executable.
- Step 8 can finish its repository-local contract independently, but its final acceptance and step 10 require the coordinated runner sandbox integration.
- Within step 8, the shared v1 contract and hostile fixture precede either repository's implementation; test a declared arch/CWR PR-SHA pair, merge arch first, then pin the immutable arch SHA in CWR and rerun.
- Step 9 is independent of runtime behavior but precedes step 10's full manifest and CI validation.
- Step 10 follows all capability slices because it is reconciliation and independent verification, not a substitute for per-slice tests.

## Voice 1 — Implementation Decomposition

The primary decomposition uses nine capability-complete slices followed by one closure gate. It keeps schema, logic, interface, regression tests, and documentation together for each observable contract. Shared metadata validation is introduced by the decision slice and extended by the effect slice so it remains exercised end to end rather than becoming an unverified infrastructure layer. The implementation PR should preserve reviewable dependency order in commits: contract/migration, producers, consumers, PCC, then packaging/docs, while each plan step still lands with its tests.

The highest-risk ordering is step 1 before the coverage interoperability closure, and step 4 before step 5. Reindex restoration can destroy irreplaceable ledger history if transactional/orphan behavior is wrong. Decision metadata is the first concrete consumer/producer contract and therefore must establish the strict shared validation semantics before effects depend on them.

## Voice 2 — Independent Adversarial Decomposition

The skeptical cross-repository review challenges underspecified evidence boundaries rather than the ten outcomes. It requires a shared v1 contract before coupled PCC work, with typed JSON, digest domain, a complete Git submission manifest, hostile fixtures, and an immutable two-PR integration protocol. It assigns isolation launch and the read-only-source/writable-build layout exclusively to CWR; arch owns target/digest/test meaning and detects direct mutation without allowing candidates to choose mounts, environment, or network.

For database evidence, it requires completion stamps to bind a run ID, source/index digest, producer version, analyzed universe, and outcome atomically, with crash, tamper, stale, zero-result, and `--allow-skip` tests. It requires ledger migrations to preserve durable original identities and total ordering/run identity through shipped-schema migrations. For proofs and distribution, it prefers exact body equality unless a language-aware canonicalisation can prove safety, all-or-nothing refusal on unreadable/empty input, protected private MCP validation, and archive manifest checks that include executable bits.

It also requires reviewable commit sequencing: contract/migration, producers, consumers, PCC, packaging/docs. This is compatible with vertical acceptance slices when each commit retains its corresponding tests and the shared contract is introduced by the first concrete producer/consumer slice rather than as an untested infrastructure phase.

## Consensus Table

| Point | Voice 1 | Voice 2 | Status |
|---|---|---|---|
| Vertical acceptance slices | Nine end-to-end capabilities plus closure | Keep reviewable ordered commits around contracts, producers, consumers, PCC, packaging/docs | AGREE — use slices for acceptance and dependency-ordered commits for review |
| Reindex persistence | Durable identities, ambiguity/error rollback, existing-main migration | Add run identity/total ordering and test shipped-schema migration | AGREE — step 1 includes all evidence |
| Coverage history | Atomic coherent append and deterministic latest read | Bind snapshots to run identity/total ordering | AGREE — step 2 must make ties deterministic |
| Body equality | Conservative canonical bytes, digest only as accelerator | Exact equality unless language-aware proof; all-or-nothing unreadable/empty refusal | AGREE — exact fallback and existing refusal are mandatory |
| Completion stamps | Shared key/version/outcome/failure/completeness validation | Also bind run ID, source/index digest, producer version, analyzed universe, atomic commit | AGREE — steps 4 and 5 adopt the stronger evidence record |
| CLI parsing | Strict within the impact and rules slices | Hostile contract fixtures must assert output and exits | AGREE |
| MCP validation | Authoritative contract and canonical containment | Keep private MCP gate protected | AGREE |
| PCC ownership | Arch detects mutation; runner supplies OS sandbox | CWR exclusively selects mounts/env/network and read-only snapshot layout | AGREE — candidates cannot control isolation |
| PCC shared contract | Truthful receipt and integration fixture | Version typed JSON, digest domain, complete Git manifest, hostile fixtures | AGREE — contract precedes coupled implementation |
| Cross-repository merge | Runner integration is a merge prerequisite | Test PR SHA pair; merge arch first; pin immutable arch SHA in CWR; rerun | AGREE |
| Release verification | Exact archive manifests and intentional MCP exclusion | Also assert executable bits | AGREE |

No `DISAGREE` or `USER-CHALLENGE` item remains. Voice 2 strengthens implementation evidence and cross-repository sequencing without changing the validated scope or ownership boundary.

## Acceptance Coverage

| Criterion | Owning steps | Required proof |
|---|---|---|
| AI-01 | 1, 10 | Unit preservation tests; double-reindex ledger equality; rollback on ambiguity/error |
| AI-02 | 2, 10 | Both writer orders; retained old snapshots; deterministic latest reads; atomic failure |
| AI-03 | 3, 10 | Lexically significant differences; indentation case; refusal cases; forced collision |
| AI-04 | 4, 10 | Zero finding, stale row, missing/invalid/partial stamp; JSON/text/exit matrix; PCC workaround removed |
| AI-05 | 5, 10 | Unrelated row, complete empty cone, partial/stale evidence, real violation, policy matrix |
| AI-06 | 4, 5, 10 | Typo, duplicate, missing value, extra positional, invalid enum; diagnostic and exit 2 |
| AI-07 | 6, 10 | Valid/unstamped/malformed stamped fixtures agree between MCP and CLI |
| AI-08 | 7, 10 | Traversal/absolute/symlink/sibling rejection; valid nested use; no content disclosure |
| AI-09 | 8, 10 | Tracked/staged/untracked/HEAD/post-test mutation refusal; no cleanup; runner sandbox integration |
| AI-10 | 9, 10 | Tag-free exact manifest assertion for every platform and intentional MCP exclusion |

## Identified Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Recreated foreign keys cannot represent removed targets without losing the row or its only identity | High | Critical | Define durable target identity before destructive work; test removed and ambiguous symbols and transactional rollback |
| Coverage changes conflict between reindex restoration and append-only writers | High | High | Use shared fixtures and run steps 1 and 2 regressions together after either change |
| Timestamp ties make latest coverage selection nondeterministic | Medium | High | Define a coherent snapshot identity/timestamp and assert deterministic latest selection in both writer orders |
| Canonicalisation silently changes lexical content or a digest remains proof by accident | Medium | Critical | Keep canonicalisation conservative, compare canonical bytes, and force collision in unit and CLI regressions |
| Metadata consumers accept a recognized key without validating version, producer outcome, failures, or scope | High | Critical | Centralize full validation and make malformed/stale/partial fixtures fail every consumer consistently |
| Completion stamps are valid syntactically but detached from the analyzed source/index or committed separately from results | High | Critical | Bind run ID, source/index digest, producer version, analyzed universe, outcome, and rows in one atomic transaction; test crash/tamper/stale cases |
| Effect completeness is recorded globally rather than for the evaluated cone | High | Critical | Persist enough coverage evidence to check every cone member and test unrelated/partial evidence |
| Strict parser changes accidentally reject documented defaults or accept duplicated policy flags | Medium | High | Table-test exact supported invocations plus every invalid argv class and assert diagnostic/exit 2 |
| MCP path checks compare lexical prefixes or canonicalise only one side | Medium | Critical | Canonicalise root and target and test component-boundary sibling and directory/file symlink escapes |
| PCC mutation snapshot misses staged-only, HEAD, failure-path, or late post-test changes | High | Critical | Capture all required dimensions before commands and compare in one guaranteed finalization path |
| PCC digest omits Git modes, symlinks, submodules, deletions, or protected metadata | High | Critical | Freeze a versioned digest domain and submission manifest; use hostile shared fixtures and exclude ignored files explicitly |
| Candidate-controlled isolation parameters weaken the runner sandbox | Medium | Critical | CWR exclusively selects mounts, environment, and network; arch receipts declare but do not configure isolation |
| Cross-repository branches pass together but drift after merge | Medium | High | Test an explicit SHA pair, merge arch first, pin immutable arch SHA in CWR, and rerun integration |
| Repository-local mutation checks are mistaken for an OS sandbox | Medium | Critical | State the boundary in receipts/docs and require the coordinated runner integration before merge |
| Release validation checks staging files but not actual archive contents on every platform | Medium | High | Assert the final archive manifest in a tag-free CI path |
| Private MCP dependency or coordinated runner branch is unavailable at validation time | Medium | High | Treat both external gates as mandatory merge prerequisites and record their exact environment/commit |

## Decisions Made

| Point | Decision | Reason |
|---|---|---|
| Decomposition shape | Vertical capability slices | Each former false result is independently implementable, testable, and documentable |
| Shared completion validation | Establish through decision analysis, then extend for effects | Avoids a horizontal helper-only phase while enforcing one authoritative validation pattern |
| Completion stamp evidence | Atomically bind run ID, source/index digest, producer version, analyzed universe, outcome/failures, and result rows | Prevents stale, tampered, partial, or cross-input evidence from authorizing a pass |
| Body canonicalisation fallback | Use exact equality unless a language-aware transformation can prove lexical safety | The intake permits conservative `Differs`; unsafe language-independent normalization cannot prove identity |
| AI-06 ownership | Include strict parsing in impact and rules slices | Parser correctness is inseparable from the safety policy and exit behavior it guards |
| MCP ordering | Provenance before containment | Separates contract disagreement failures from path-resolution failures in one executable/test suite |
| PCC ownership boundary | Detect repository mutations here; require OS isolation from the coordinated runner | Matches the explicit scope boundary without overstating local protection |
| PCC digest domain | Version a manifest of base OID, index, tracked overlay/deletions, non-ignored untracked files, modes, symlinks, submodules, and protected metadata | Makes mutation detection and runner receipts comparable and hostile-fixture testable |
| Cross-repository integration | Shared fixture first; test named PR SHAs; merge arch first; pin immutable arch SHA in CWR; rerun | Prevents coupled contracts from being validated only against moving branch heads |
| Implementation commit order | Contract/migration, producers, consumers, PCC, packaging/docs | Keeps dependencies reviewable while plan completion remains capability-based |
| Plan state | Keep all artifacts DRAFT and omit `plan.json` | Human quiz, challenge resolution, approval, VALIDATED state, and JSON belong to the root gate |

## Assumptions

- The exact schema representation for durable orphan identities and producer coverage is an implementation choice, but it must satisfy existing-main migration and all stated observables.
- The authoritative decision metadata key may use either current spelling only after all producer, consumer, schema, PCC, JSON, text, and docs references converge; stale alternate spelling is not accepted as current evidence.
- The shared validation helper may expose decision- and effect-specific contracts while sharing strict key/version/outcome/failure validation behavior.
- Existing defaults and documented invocations define the CLI compatibility set; undocumented malformed argv is not compatibility surface.
- The coordinated runner provides the OS sandbox and a branch/fixture interface capable of running the real PCC integration required by AI-09.
- CWR, not candidate content or these arch scripts, controls isolation mounts, environment, network, read-only source materialization, and writable build/temp locations.
- No lint command is added because the validated intake explicitly states that none is documented.

## Human Gate Handoff

The root planner must incorporate Voice 2, resolve any `DISAGREE` or `USER-CHALLENGE`, and run the three-question human validation quiz. These artifacts must remain `DRAFT` until that gate succeeds.
