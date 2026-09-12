# Implementation baseline and ownership

- Base/manifest captured before build: `61ab54606b6797f86129e0b154c95949e112fdee`.
  Clean tracked/untracked status, no pre-task dirty exclusions. ACTIVE_TASK is this task.
  Control files written with apply_patch per host's higher-priority local-edit constraint;
  no freeze hook installed, not an unreported shell-only skill operation.
- Root `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install`:
  terminal exit0,0.118s.
- Root `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force`:
  session13640 resolved to terminal exit0. 240/240 Tezt plus64 Alcotest passed.
  Tezt first success18:27:58.729, last18:30:10.743 (132.014s first-to-last; not whole command
  duration). Existing deliberate assertion/execution/error diagnostics are positive controls.
  Readiness interphase heuristic warning and advisory MUST-null350 vs pin383 retained, not failures.
- Root owns phase artifacts/roadmap and independent read-only verification preparation.
  `/root/origin_implement` (fresh Sol) owns product edits and every build/test after baseline;
  shared current worktree, no new worktree or concurrent Dune.
- Installed `.claude/agents/implementer.md` fully read. `.claude/patterns/` absent; no language
  adaptation invented. JS feature with small OCaml test registration, no >50-line OCaml logic
  specialist threshold yet; reassess if implementation expands.
- Input review: indexer reads `.cmt` and `.cmti` (`arch_index_cmt.ml:323`), discovers optional
  root `arch-errors.toml` (`arch_index.ml:81`), so actual provenance must cover these inputs too.
- Diagnostic attempts: `_build/log` absent; scoped process inspection showed live test/LSP,
  not a completion result. One unnecessary broad read-only /tmp filename search returned
  unrelated fixtures/permission errors; discarded, no files touched or ownership inferred.

## Independent verification targets (not gate results)

| Boundary | Required adverse evidence |
|---|---|
| Gate input | Missing/extra rule, wrong contract, empty origins, source selection vacuity, malformed JSON and process-exit mismatch cannot hold. |
| Population | Raw total equality cannot conceal group redistribution; zero-key semantics and module-set drift directional and nonzero. |
| Exemptions | Real native new identity and same-line x2 over x1 fail even with reference counters updated. |
| Input attribution | .cmti/interface/config changes included; same counts are not a source freshness proof; unrelated dirtiness does not fail. |
| Package | Wrong shared gate/JSON/SARIF fields, missing HTML and post-publication tampering fail validation, no partial-success marker. |
| Retention | Started consumer failure cannot suppress validation/upload attempts or be masked by successful upload; absent expected file fails independently. |
| Ownership | Existing leaf/dangling symlink untouched; symlinked parent resolved; only own tmp paths cleaned, no DB/build uploads. |

Official upload-artifact documentation inspected2026-09-12:
https://github.com/actions/upload-artifact and
https://raw.githubusercontent.com/actions/upload-artifact/v7/action.yml .
v7 declares node24; retention-days14 is supported; if-no-files-found defaults warn, so error
must be explicit. That option alone does not validate every required filename. GitHub status
functions documented at https://docs.github.com/en/actions/reference/workflows-and-actions/expressions .

## In-progress agent evidence (not review or independent root QA)

- Initial checker asserted runner file existence only. Agent had already drafted production
  after that setup red; root rejected it as behavioral test-first evidence. Complete native
  package assertion then failed with actual SARIF-parity error (checker1), and passed after
  serializer-consistent correction (checker0). This is a disclosed sequencing lapse, not a
  retrospectively claimed strict test-before-code cycle.
- Root draft inspection caught top-level SARIF property/category/ID guesses, key-order-sensitive
  equality, setup outside owned-output error handling, skipped symlink directories and tests
  that would retain invalid gate JSON, mutate the wrong input or mask missing HTML with a
  previous digest error. Sent to product owner before final implementation; not review verdicts.
- Agent reports first coherent green full-suite session82459 terminal0:240Tezt+64Alcotest.
- Agent reports real new-site `fresh | consumer.ml:2 | division | Division_by_zero | ×1`
  and same-site `allowed | consumer.ml:1 | division | Division_by_zero | ×2`, each runner1,
  policy-failed/VIOLATION; observing these correctly makes the checker0.
- Agent reports package checker0, deliberate checker assertion1/execution2. First fixed
  production run consumer0+validator0: held/UNKNOWN,23/828/5223/491,deltas[],46source
  inputs (.ml/.mli),48CMT-family inputs (.cmt/.cmti),absent root arch-errors.toml.
- Agent integrated Tezt and CI, then reported final session7896 terminal0:245Tezt+64Alcotest;
  @install and authentic/failures/package each0. Production evidence retained at
  `/tmp/origin-consumer-evidence.HJPNIC/output`: consumer0/validator0,held UNKNOWN,zero drift.
- Root handoff inspection found concrete finalization gaps: main DB cleanup failure left
  reports on error, sidecar cleanup failures were ignored, staging cleanup could bypass the
  error record, and validated policy was assigned only after report copies. Returned these
  to the same product owner for test-first cleanup/final-record controls before phase completion.
  Independent review/QA and remote CI have not run. Root doc links and whitespace pass only.
