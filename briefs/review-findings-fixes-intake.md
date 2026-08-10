# Intake Brief — review-findings-fixes

**Date:** 2026-08-09
**Status:** VALIDATED
**Type:** fix

## Goal

Correct every `arch-index` defect identified by the adversarial review of merged PRs #10 through #15.
The fix must restore the project's central soundness rule: a tool may report a proof or a
clean result only when its inputs are complete and validated, while persistent human curation
must survive routine reindexing intact.

The resulting PR must cover all ten requirements below as one reviewed compatibility change. It
must include adversarial regression tests for each former false-pass, false-proof, persistence,
path-containment, packaging, and PCC mutation case. User-facing documentation and machine-readable
contracts must agree with the implemented behavior.

## Scope Boundary

What is explicitly OUT of scope:
- Changing the call-graph extraction algorithms or the meaning of MUST, MAY, and MAY_TOP edges.
- Adding new health metrics, curation commands, rule forms, or language backends.
- Treating formatting-only duplicate bodies as identical when that cannot be proved without
  changing lexical content; conservative `DIFFERS` is acceptable, false `Identical` is not.
- Providing the operating-system sandbox for repository-authored PCC commands. That enforcement is
  owned by the coordinated `cabal-workflow-runner` fix; this repository must expose the execution
  requirement, reject worktree mutation, and supply cross-repository integration fixtures.
- Making the private `mcp-kit` dependency public or enabling `arch_mcp` in the default build.
- Reworking release naming, supported platforms, or unrelated existing CLI output.
- Repairing historical databases that were already reindexed and lost ledger rows before this fix;
  preservation is required from the first run of the corrected indexer onward.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `lib/arch_index/arch_index.ml` | Destructive CMT reindex orchestration | `backup_intents`; `DROP TABLE IF EXISTS`; schema recreation |
| `lib/arch_index/arch_index_support.ml` | Current preservation support and drop lists | `type intent_backup`; `backup_intents`; `restore_intents` |
| `lib/arch_index/arch_index_support.mli` | Preservation API contract | intent backup/restore declarations |
| `architecture-schema.sql` | Main schema and ledger foreign keys | `unsafe_params`; `coverage`; `gardening_tasks`; `gardening_log`; `comment_db_meta` |
| `bin/arch_coverage/arch_cov_write.ml` | LCOV `--write` persistence | `DELETE FROM coverage` before inserts |
| `bin/arch_coverage/arch_coverage.ml` | Public `--write` entry point | `Arch_cov_write.write` |
| `bin/arch_coverage_load/arch_coverage_load.ml` | Append-only coverage snapshot reference | `INSERT INTO coverage(...,recorded_at)` |
| `lib/arch_index/arch_index_compare.ml` | Duplicate-body proof implementation | per-line `String.trim`; MD5 grouping without equality confirmation |
| `test/test_arch_index_compare.ml` | Unit coverage for body extraction/comparison | `normalise`; `compare_bodies` cases |
| `bin/arch_body_compare/arch_body_compare.ml` | User-facing proof verdict | `Identical` rendered as a proven duplicate |
| `bin/arch_impact/arch_impact.ml` | Impact gate, decision availability, CLI parsing | `Arch_db.nonempty t "decisions"`; permissive option stripping |
| `poc/decision-lint/bin/decision_lint.ml` | Decision producer metadata | `decision_analysis`; parse/walk failure stamps |
| `bin/arch_rules/arch_rules.ml` | Effect-rule completeness and CLI policy parsing | global `function_effects` nonempty check; permissive option stripping |
| `bin/arch_effects_load/main.ml` | Potentially partial effect ingestion | `--allow-skip` behavior |
| `lib/arch_effects/effects_db.ml` | Effect rows and producer persistence | `function_effects` schema/inserts |
| `lib/arch_tools/arch_db.ml` | Authoritative index-contract validation | `require_contract`; `contract_ok` |
| `bin/arch_mcp/arch_mcp.ml` | MCP provenance and repository path resolution | raw `callgraph_contract`; lexical-only `repo_relative` |
| `scripts/pcc/pcc-index` | PCC index step executing target build/analysis | target `dune build`; JSON receipt |
| `scripts/pcc/pcc-preflight` | PCC preflight executing target build/tests | target `dune build`; `dune test`; JSON receipt |
| `selftest-curation.sh` | Ledger and curation integration tests | main-schema ledger operations |
| `selftest-coverage.sh` | Coverage write/load integration tests | `arch-coverage --write` assertions |
| `selftest-duplicates.sh` | Duplicate proof integration tests | whitespace-normalised duplicate fixture |
| `selftest-impact.sh` | Impact verdict and malformed-index tests | contract and `--fail-on-new-findings` cases |
| `selftest-rules.sh` | Rule policy and effect verdict tests | effect and fail-policy cases |
| `selftest-mcp.sh` | MCP protocol/provenance tests | `index_status` and path-bearing tool calls |
| `selftest-pcc.sh` | PCC scripts' success/failure contract | generated target repositories and JSON validation |
| `.github/workflows/ci.yml` | Required checks and release contents | shell-test list; release binary loop |
| `docs/schema.md` | Metadata contract documentation | currently documents `decision_contract`, unlike producer's `decision_analysis` key |
| `docs/curation-workflow.md` | Historical-ledger user contract | append-only snapshots and gardening history |
| `docs/mcp-server.md` | MCP trust and path-boundary contract | provenance semantics; fixed startup paths |
| `docs/change-impact.md` | Impact gate semantics | clean, not-computed, and refusal behavior |
| `docs/fitness-functions.md` | Rule completeness/policy semantics | effect rule and fail-closed policies |

## Architecture Notes

### Required outcomes and acceptance criteria

**AI-01 — Reindex preserves all curation state.**

- Rebuilding an existing main-schema index must not delete any `coverage`, `unsafe_params`,
  `gardening_tasks`, or `gardening_log` row.
- References to modules/functions that still exist after reindex must be remapped to their new IDs
  by stable identity, including module path plus function name where required for disambiguation.
- When a referenced symbol no longer exists, the ledger row and enough durable target identity for
  a human to identify the former target must survive; silently deleting the row or reducing the
  only target identity to `NULL` is forbidden.
- Backup, schema rebuild, remapping, and restoration must be one transaction. Any restoration or
  ambiguity error must roll back rather than leave a partially rebuilt database.
- Reindexing the same fixture twice must preserve exact ledger row counts, values, timestamps,
  provenance, issue/PR numbers, fixed status, and append-only history. Add an integration regression
  to `selftest-curation.sh` and focused unit coverage for the preservation helper.

**AI-02 — Coverage writers share one historical contract.**

- `arch-coverage --write` on a main-schema DB must never execute a whole-table delete or erase
  snapshots written by `arch-coverage-load`.
- A successful invocation must append one coherent timestamped snapshot atomically. Existing rows
  remain byte-for-byte queryable, and `arch-query low-coverage` continues to select the latest
  snapshot per function deterministically.
- A failed or ambiguous write must append nothing. The flat-schema `coverage_by_name` behavior may
  remain current-state-only, but documentation must state that distinction explicitly.
- `selftest-coverage.sh` must seed history through both writers, invoke them in both orders, and
  prove that old snapshots remain and latest-snapshot reads are correct.

**AI-03 — Body identity is a verified equality, not a hash/whitespace heuristic.**

- Normalisation must not change whitespace inside string literals, quoted strings, comments, or
  any other lexically significant source region. If language-independent safe normalisation cannot
  prove equivalence, compare conservatively and return `Differs`.
- A digest may accelerate grouping but must not itself establish identity. Before returning
  `Identical`, compare the canonical bodies for equality; a forced digest-collision test seam must
  demonstrate that unequal bodies remain `Differs`.
- Preserve the existing unreadable/empty-body refusal behavior.
- Add unit and CLI regressions for multiline strings differing only in leading/trailing/blank-line
  content, ordinary indentation-only source changes, unreadable bodies, and forced equal digests
  over unequal bodies. Update `docs/curation-workflow.md` so its proof claim matches the exact
  canonicalisation contract.

**AI-04 — Decision gates require a completed producer run.**

- Replace `decisions` table non-emptiness as the availability test with one authoritative metadata
  contract shared by producer, consumer, schema documentation, PCC scripts, JSON, text output, and
  exit status. Resolve the current `decision_analysis` versus documented `decision_contract` name
  mismatch without accepting stale legacy metadata as a current proof.
- A completed analysis that produces zero findings is available and may pass. A table containing a
  finding without a valid completion stamp is unavailable and must refuse. A stamped run reporting
  parse or walk failures is partial and must not produce a clean gate unless the contract explicitly
  and truthfully records complete coverage.
- With `--fail-on-new-findings`, missing/invalid/partial analysis must return JSON
  `verdict:"refused"` and exit 3; new findings return `fail`/1; a complete clean analysis returns
  `pass`/0. Human output must make the same distinction.
- Remove the synthetic pre-existing finding workaround from `selftest-pcc.sh`. Add zero-finding,
  stale-row, missing-stamp, invalid-stamp, and partial-analysis cases to `selftest-impact.sh` and
  `selftest-pcc.sh`.

**AI-05 — Effect rules require cone-relevant completeness.**

- The global presence of any `function_effects` row must not authorize PASS for a different cone.
- Define and persist a producer/completeness contract that distinguishes a complete zero-effect
  analysis from missing or partially skipped functions. `--allow-skip` output must remain visibly
  partial and cannot create a completeness stamp.
- An effect rule may PASS only when every function relevant to its evaluated cone is covered by a
  valid completeness contract and no matching effect exists. Missing or partial coverage yields
  `NOT_COMPUTED` or `UNKNOWN` according to documented semantics and obeys the selected fail policy.
- Add `selftest-rules.sh` cases for an unrelated effect row, a complete zero-effect cone, a partial
  `--allow-skip` load, stale metadata, and a genuinely violating effect.

**AI-06 — Safety-relevant CLIs reject unknown and malformed arguments.**

- `arch-impact` and `arch-rules` must parse their complete argv strictly. Unknown options,
  duplicate singleton options, missing values, unexpected extra positionals, and invalid enum
  values must print a precise diagnostic and exit 2; they must never fall back to a permissive
  policy.
- Exact documented invocations and existing defaults remain compatible.
- Add typo regressions including `--fail-on-new-finding` and `--on-unkown fail`, plus duplicate,
  missing-value, and extra-positional cases, to `selftest-impact.sh` and `selftest-rules.sh`.

**AI-07 — MCP provenance uses the authoritative validated contract.**

- `reachability_is_sound` and its caveat must derive from the same `Arch_db.contract_ok` validation
  used by the CLI, not from raw metadata presence.
- A stamped DB with a missing `calls.kind`, NULL kind, or invalid kind must never report sound
  provenance. MCP and CLI must agree for the identical fixture.
- Add protocol tests for valid, unstamped, and each malformed stamped DB. Structured provenance,
  prose caveat, and reachability verdict must be mutually consistent.

**AI-08 — MCP repository paths resist symlink escape.**

- Canonicalise the configured repository root and candidate path before use and require the target
  to remain within that canonical root on a path-component boundary.
- Continue rejecting absolute paths, `..`, missing targets, and invalid argument shapes. Also
  reject a repository symlink that resolves to a file or directory outside the root.
- Add `selftest-mcp.sh` cases for a valid nested rules file, direct traversal, an absolute path, a
  symlink to an external file, a symlinked external directory, and similarly prefixed sibling roots.
  No rejected response or subprocess diagnostic may disclose external file contents.

**AI-09 — PCC steps cannot silently mutate the candidate tree.**

- `pcc-index` and `pcc-preflight` must snapshot the target repository's tracked, staged, untracked,
  and HEAD state before executing repository-authored build/test/analysis commands and compare it
  afterward, including failure paths. Any mutation makes the step fail and its JSON/exit status
  must not claim success.
- Their public contract and receipt must explicitly declare that they execute repository-authored
  code and require the caller-provided OS sandbox defined by the coordinated runner PR. The scripts
  must not claim to prevent writes outside the repository themselves.
- Temporary logs remain securely created and cleaned. Mutation detection must not erase or reset
  user data.
- Extend `selftest-pcc.sh` with passing commands that create tracked, staged, untracked, and
  post-test files, and assert refusal without cleanup. A coordinated runner integration test must
  prove outside-repository writes and ambient secret/network access are blocked by its sandbox.

**AI-10 — Releases contain every supported public executable.**

- Add `arch_body_compare`, `arch_coverage_load`, and `arch_curate` to every release-platform
  archive alongside the existing public binaries.
- The release job must fail if any expected executable is absent and must assert the final manifest,
  not merely list `dist/`.
- Add a CI-testable manifest check that does not require publishing a tag, and keep the intentional
  `arch_mcp` exclusion documented.

### Cross-cutting constraints

- Metadata completion stamps are evidence, not hints: validate recognized key, version, producer
  outcome, and relevant failure/completeness fields through shared helpers rather than duplicating
  weaker checks in each consumer.
- Database migrations/reindexing must remain compatible with existing main-schema databases from
  `main`; new metadata or durable identity columns require documented migration behavior.
- Machine-readable JSON fields and process exit codes are contractual. Tests must assert both and
  reject trailing/non-JSON stdout from PCC steps.
- Update README/docs wherever old statements promise whitespace-normalised proof, replaceable
  coverage, decision-contract spelling, effect completeness, MCP containment, or PCC safety that no
  longer matches behavior.
- The implementation PR is not complete until an adversarial reviewer independently reruns the
  former reproductions and returns no open CRITICAL or HIGH finding under the roster review rubric.

## Quality Gates

```bash
# Build (documented by README.md and CI)
opam install --deps-only --yes .
opam exec -- dune build

# Unit tests (CI)
opam exec -- dune test

# Shell integration tests affected by this fix (CI executes these after eval "$(opam env)")
./selftest-impact.sh
./selftest-rules.sh
./selftest-coverage.sh
./selftest-duplicates.sh
./selftest-curation.sh
./selftest-curation-doc.sh
./selftest-pcc.sh

# MCP build and protocol tests (conditional CI job; requires private mcp-kit pin/token)
ARCH_MCP=yes opam exec -- dune build bin/arch_mcp/arch_mcp.exe bin/arch_load bin/arch_query
./selftest-mcp.sh

# Full documented shell-test gate from .github/workflows/ci.yml
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

# Lint/format
# Not documented in AGENTS.md, README.md, dune-project, or CI; do not invent a gate.
```

The MCP gate is mandatory for the PR even though it is conditional in public CI: validation needs
an environment with the private `mcp-kit` dependency. The coordinated runner PR must additionally
run its real PCC integration against this branch before either PR merges.

## Open Questions

_(empty — repository contracts and the coordinated runner ownership boundary resolve the reviewed
behavioral requirements; implementation choices remain for roster-plan.)_
