# Reviewer round 1 / cycle 1

Recommendation: **changes required**. Two MEDIUM test findings are recorded in the adjacent JSON. No demonstrated arithmetic containment, binder-identity, entry-reset or unsupported-precedence product defect found. Passing current checks do not establish the missing contract cases.

Reviewed implementation HEAD `2b8b7bf`, main merge-base `77c7691436a716bfec503e22f1649a4303179fcc`. Read reviewer role/schema, intake, plan, implementation/reviewer briefs, frozen spec and all changed product/test/documentation sources. Reviewed the full diff listing and pipeline evidence; historical logs are provenance, not reused as execution evidence. Scope gate is delegated to the actually executed root gate as assigned. `.claude/patterns/` is absent (read attempt exit 1; discovery exit 2), so no language-pattern policy could be applied. No source fixes, commits or manually created worktrees.

## Findings

1. `scripts/check-arch-guard.js:202`: CHECK-1 has no malformed-shape coverage for labelled/overapplied/missing-original-slot/later-saturation applications. The private helper currently cannot construct these cases. Add exact eligibility and original-slot assertions under the existing owned-fixture scope.
2. `scripts/check-arch-guard.js:268`: vocabulary-only reason checks accept an UNSUPPORTED site whose only reason asserts a nonzero divisor. CHECK-5 also lacks complete multi-status text/JSON equivalence. Strengthen the semantic oracle and its negative controls.

The second finding has direct sensitivity evidence: a Node in-memory loader executed the actual `validateReport` against the actual CLI report for `_build/default/lib/arch_guard/.arch_guard.objs/byte/arch_guard__Guard_domain.cmt`; replacing its reason with `divisor_nonzero_if_reached` returned exit 0 and printed `{"acceptedWrongReasons":[{"status":"UNSUPPORTED","reasons":["divisor_nonzero_if_reached"]}]}`. No product files or fixtures were modified. An initial VM-context version exited 1 on a cross-realm deepStrictEqual prototype mismatch; that was a harness error, corrected by using `new Function` in the same realm, not a product failure.

## Executed gates

All commands cwd `/home/mathias/dev/arch-index-worktrees/guard-division-analysis`. Every shell command after reading RTK used `rtk proxy`. Compiler-backed commands use prefix `rtk proxy opam exec --switch=/home/mathias/dev/arch-index --` (abbreviated P below). Each exit is observed terminal status, not inferred from prior logs.

| Command | Exit / evidence |
| --- | --- |
| P `dune build --root .` | 0 |
| P `dune test --root . --force` | 0; 255/255 Tezt plus 64 Alcotest; session 7719. Tezt first/last timestamps 06:18:55.303–06:21:26.811. Includes all six modes and both deliberate exit controls. Tool display truncates some suite output; no complete raw log claim. |
| `rtk proxy git diff --check` | 0 |
| P `node scripts/check-arch-guard.js inventory` | 0; 9 sites, 2 numeric, 7 unsupported |
| P `node scripts/check-arch-guard.js numeric` | 0; 26 additional cases plus 12-site fixture, census 3 NONZERO / 1 ZERO / 2 MAY_ZERO / 1 UNREACHABLE / 5 UNSUPPORTED |
| P `node scripts/check-arch-guard.js domain` | 0; 640734 actual responses, 23219242 law assertions, exhaustive widths 3–8 and sampled 31/63 |
| P `node scripts/check-arch-guard.js inputs` | 0; inclusive/one-over nodes 100000/100001, sites 10000/10001, depth 512/513, files 128/129, per-file 33554432/33554433, aggregate 268435456/+1 |
| P `node scripts/check-arch-guard.js report` | 0; six metadata cases and JSON 16777216/16777217-byte boundary |
| P `node scripts/check-arch-guard.js owned` | 0; precisely 23 owned library artifacts and zero target sites/status counts |
| P `node checks/origin-recurring-consumer.js authentic` | 0 |
| P `node checks/origin-recurring-consumer.js failures` | 0; intentional injected cleanup/final-record diagnostics |
| P `node checks/origin-recurring-consumer.js package` | 0 |
| `rtk proxy mktemp -d /tmp/guard-review-r1.XXXXXX` | 0; resolved `/tmp/guard-review-r1.Fpew97` |
| P `node scripts/origin-consumer.js --out /tmp/guard-review-r1.Fpew97/origin` | 0; held |
| `rtk proxy node scripts/origin-consumer-artifacts.js /tmp/guard-review-r1.Fpew97/origin` | 0 |
| P `./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe --build-dir=_build/default/lib/arch_index --db-path=/tmp/guard-review-r1.Fpew97/self.db --schema-path=architecture-schema.sql` | 0; 23 modules / 828 functions / 5223 calls |
| `rtk proxy bash -c 'diff test/fixtures/self-index-stats.txt <(sqlite3 /tmp/guard-review-r1.Fpew97/self.db "SELECT '\''modules: '\'' \|\| count(*) FROM modules; SELECT '\''functions: '\'' \|\| count(*) FROM functions; SELECT '\''calls: '\'' \|\| count(*) FROM calls;")'` | 0; CI SQL and golden unchanged. The displayed escaped pipes denote literal SQL concatenation; actual command used `||` without backslashes. Process substitution replaces only the temporary stats file. |
| P `./arch-rules /tmp/guard-review-r1.Fpew97/self.db arch-rules.txt --on-vacuous fail` | 0; one proved, three UNKNOWN, no failures |
| P `./arch-impact /tmp/guard-review-r1.Fpew97/self.db --diff 77c7691436a716bfec503e22f1649a4303179fcc..HEAD --repo .` | 0; no touched indexed functions; 67 changed files outside index UNKNOWN, effects/decision analysis not computed. This is not zero semantic impact. |
| P `env DUNE_CACHE=enabled DUNE_CACHE_STORAGE_MODE=copy ./scripts/recalibrate.sh --check` | **2**; refused because root's untracked `briefs/guard-division-analysis-review-trace.jsonl` makes the worktree dirty. No calibration result obtained. Root notified and will schedule an independent rerun after clean artifact checkpoint. |

Dune slot was released immediately after the calibration refusal and root notified. Scratch `/tmp/guard-review-r1.Fpew97` retained for root-owned evidence/cleanup; no deletion performed.

## Contract and risk coverage

PASS below means source audit plus applicable current runtime evidence; it is not a universal proof. UNTESTED identifies a missing adversarial test obligation even if implementation appears correct by inspection.

| FR | Assessment / evidence |
| --- | --- |
| 001, 004, 005, 007, 008, 009, 012, 013, 014 | PASS for current fixtures; inventory/input/report checks and source identity/order review. Original-slot and duplicate-coordinate corner combinations remain covered by the UNTESTED rows below. |
| 002, 003 | UNTESTED unusual/later-saturation application shapes; finding 1 |
| 006 | PASS native/type-alias positive behavior by numeric fixtures and compiler-based implementation; UNTESTED unresolved/non-native operand seam negatives |
| 010, 011 | PASS exercised input failures and buffering. Corrupted-interface diagnostic distinction not independently reproduced here; spec specialist reports this separately. Output-device failure is not exercised. |
| 015, 016, 017, 018, 019, 020, 021 | PASS tested statuses, guard operators, shadowing, simultaneous RHS semantics, joins and identity-based implementation. Alpha-renaming and every multi-cause combination not independently exercised. |
| 022, 023, 024 | PASS independent modular oracle/domain laws and code review; high-width samples are not exhaustive proofs |
| 025, 026, 027, 028, 029, 030 | PASS source dispatch/reset audit plus existing nested/capture/opaque/unsupported examples; UNTESTED full excluded-family/default-containing-target/sticky-nested/malformed-known combinations |
| 031 | PASS product status/reason implementation; test oracle incomplete (finding 2) |
| 032 | PASS unchanged extractor/rules/reference diff, self golden and full suite; pristine calibration UNTESTED because refusal 2 |
| 033 | PASS shared rendering source; full runtime site equivalence UNTESTED (finding 2) |
| 034, 035 | PASS CLI/wrapper source and exercised usage errors; help/version not separately invoked by this reviewer |
| 036 | FAIL source audit: default text omits linked compiler and several required assumptions/limitations; canonical product finding belongs to spec-compliance specialist. Both-format indirect/omitted-artifact limitation wording is also absent under C-5. |
| 037, 038, 039, 040, 041, 042, 043 | PASS current schema/census/metadata/text fixtures and product source; status/reason correspondence oracle incomplete, duplicate-coordinate/UTF-8-specific fixtures UNTESTED |
| 044, 045, 046, 047 | PASS real CLI boundary checks, independent counters, trusted-artifact limitations and actual empty owned census; changed-read is explicitly a private shared-reader seam, not a timed live filesystem race |

AC-1 PASS; AC-2 PASS with calibration pending; AC-3 partial (FR-036 failure and missing full text oracle); AC-4 UNTESTED shapes; AC-5 partial positive/type-alias coverage; AC-6 PASS; AC-7 PASS tested boundaries with changed-read seam disclosed; AC-8/10 partial because FR-036; AC-9 PASS; AC-11 partial (identity/groups tested, full alias/alpha variants untested); AC-12/13/14 partial (full nested/excluded/malformed combinations untested); AC-15 PASS core precedence; AC-16 PASS sampled loop/recursion plus source; AC-17 PASS; AC-18 partial diagnostic distinction; AC-19 partial oracle/duplicate-coordinate gaps. CHECK-1 through CHECK-6 all actually exit 0, but CHECK-1/2/5 have the described contract-coverage gaps.

Correctness, regression, security/trust boundaries, test impact and maintainability were reviewed. Compiler artifacts are explicitly trusted; no hostile CMT experiment or external scanning was performed. Inputs do not cause artifact-recorded arbitrary include paths to load. No machine-checked proof, coverage percentage, production improvement, or exact-head remote CI result is claimed. Cross-runtime/specialist coordination and remote CI are root-owned gates, not simulated here.

Open work: fix the two test findings, incorporate independently confirmed product findings, and rerun the pristine calibration after the review artifacts are checkpointed clean. Recommendation remains changes required.
