# QA Brief — review-findings-fixes

**Date:** 2026-08-10
**Status:** NO-GO ❌

## Environment

- Repository branch: `fix/review-findings`
- Base revision: `59622c5fa72f53a812a23b781f106e86f8ac9175`
- Isolated switch: `OPAMROOT=/tmp/arch-index-opam-root`, `--switch=/tmp/arch-index-opam-switch`
- OCaml: `5.3.0`
- Dune: `3.24.2`
- Clean build: `_build` was removed with `dune clean` immediately before the recorded build.

## Quality Gates

| Gate | Command | Result | Duration |
|---|---|---|---:|
| Dependencies | `OPAMROOT=/tmp/arch-index-opam-root opam install --switch=/tmp/arch-index-opam-switch --deps-only --yes .` | ✅ PASS; nothing to install | 7.70s |
| Build | `OPAMROOT=/tmp/arch-index-opam-root opam exec --switch=/tmp/arch-index-opam-switch -- dune build` | ✅ PASS | 5.41s |
| Unit tests | `OPAMROOT=/tmp/arch-index-opam-root opam exec --switch=/tmp/arch-index-opam-switch -- dune test` | ✅ 51 passed, 0 failed | 3.94s |
| Impact | `./selftest-impact.sh` in the isolated switch | ✅ PASS | 1.63s |
| Rules | `./selftest-rules.sh` in the isolated switch | ✅ PASS | 0.76s |
| Coverage | `./selftest-coverage.sh` in the isolated switch | ✅ PASS | 1.51s |
| Duplicate body proof | `./selftest-duplicates.sh` in the isolated switch | ✅ PASS | 0.32s |
| Curation | `./selftest-curation.sh` in the isolated switch | ✅ PASS | 1.72s |
| Curation docs | `./selftest-curation-doc.sh` in the isolated switch | ✅ PASS | 0.09s |
| PCC repository contract | `./selftest-pcc.sh` in the isolated switch | ✅ PASS | 10.72s |
| Private MCP build | `ARCH_MCP=yes opam exec -- dune build bin/arch_mcp/arch_mcp.exe bin/arch_load bin/arch_query` in the isolated switch | ❌ FAIL, exit 1 | 0.09s |

The mandatory private MCP build failed. Per the QA stop rule, `selftest-mcp.sh`, the later full shell matrix, the release-manifest test, and cross-runtime re-verification were not run. No format/lint command is documented, so no format/lint gate was added.

The dependency gate emitted only the existing opam package metadata warnings for missing maintainer, authors, homepage, bug-reports, and license fields.

## Tests: Detail

- Unit tests: 51 pass, 0 skip, 0 fail.
- Shell gates completed before the blocker: 7 pass, 0 fail.
- Regression detected by completed local gates: NO.
- Task spec: `specs/review-findings-fixes.md` absent; no runnable spec checks apply.
- TUI: not applicable.

## Behavior Matrix

| Criterion | QA evidence | Result |
|---|---|---|
| AI-01 | `selftest-curation.sh`; `selftest-curation-doc.sh` | ✅ PASS |
| AI-02 | `selftest-coverage.sh` | ✅ PASS |
| AI-03 | 6 `arch_index_compare` unit tests; `selftest-duplicates.sh` | ✅ PASS |
| AI-04 | `selftest-impact.sh`; PCC decision path in `selftest-pcc.sh` | ✅ PASS |
| AI-05 | `selftest-rules.sh` | ✅ PASS for the directly affected gate; the later `selftest-effects.sh` rerun was not reached |
| AI-06 | strict CLI fixtures in `selftest-impact.sh` and `selftest-rules.sh` | ✅ PASS |
| AI-07 | Requires private MCP build and `selftest-mcp.sh` | ❌ BLOCKED |
| AI-08 | Requires private MCP build and `selftest-mcp.sh` | ❌ BLOCKED |
| AI-09 | Repository-local hostile fixtures in `selftest-pcc.sh` passed; pinned CWR sandbox integration remains unavailable | ❌ BLOCKED externally |
| AI-10 | Release-manifest gate occurs after the failed mandatory MCP gate and was not run | ⚠️ NOT VERIFIED in this QA run |

No open CRITICAL or HIGH code-review finding remains in `briefs/review-findings-fixes-review.json`; its status is `GO`. QA nevertheless cannot certify all AI-01 through AI-10 behaviors because mandatory execution environments are absent.

## External Blockers

### Private MCP

`mcp-kit.stdio` is not installed in the isolated switch. The protocol test was not counted as a pass because its executable could not be built.

### Coordinated Runner

The sibling `cabal-workflow-runner` worktree is on `fix/review-findings` at base revision `2cb184a23eb3e7224d68b100eaaa011dcfd74004` with uncommitted implementation changes. Its implementation brief reports a local 3/3 companion integration, but also records that the required reviewed, immutable `arch-index` SHA is unavailable. Its review JSON is absent, and the current CI still uses an availability-based floating checkout. Therefore the required explicit PR-SHA pair, arch-first merge, immutable pin, hostile sandbox rerun, and non-optional integration summary are not certified.

## NO-GO Issues

Raw mandatory MCP build error:

```text
File "bin/arch_mcp/dune", line 20, characters 20-33:
20 |  (libraries mcp-kit mcp-kit.stdio sqlite3 unix))
                         ^^^^^^^^^^^^^
Error: Library "mcp-kit.stdio" not found.
-> required by _build/default/bin/arch_mcp/arch_mcp.exe
```

## Cross-runtime QA

`opencode` is present in addition to the host `codex` runtime. Cross-runtime re-verification was not started because the primary mandatory gate failed and the QA procedure requires stopping all subsequent gates.

## Verdict

**NO-GO** — return to `/roster-implement` or the integration owners until both mandatory external gates are executable and passing: provide the private `mcp-kit` environment and complete the reviewed immutable arch/CWR SHA-pair integration. Then rerun QA from the clean build through the full shell, MCP, release, and cross-runtime gates.

## Friction Log

```jsonl
{"task":"review-findings-fixes","frictions":["Private mcp-kit.stdio is unavailable in the isolated QA switch.","The coordinated runner lacks a reviewed immutable compatible arch-index SHA and review decision."],"methods":["Used the repository-isolated OCaml 5.3 switch.","Stopped after the mandatory MCP failure as required by roster-qa."],"suggestion_type":"pipeline","suggestion":"Provision private MCP credentials/dependencies and a reviewed immutable cross-repository SHA pair before dispatching mandatory QA.","effort_estimate":"medium"}
```
