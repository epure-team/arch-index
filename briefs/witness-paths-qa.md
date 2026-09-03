# QA Report — witness-paths

**Date:** 2026-09-04
**Mode:** fast
**Verdict:** GO
**Round:** 1 / **Cycle:** 1

## Context read

- `briefs/witness-paths-review.json` — status GO, round 1, no OPEN findings (all fixed during
  review); reviewer's/architect's points of attention (adjacency choice, overlap short-circuit,
  witness-target consistency, undocumented field, dead API, `arch_serve` duplication, structured
  JSON shape for a future SARIF writer) all addressed or explicitly deferred as documented
  residuals.
- `briefs/witness-paths-impl.md` — Fast mode, no `qa-scope.md`/`intake.md` (no plan phase); gate
  commands taken from the impl brief's own Quality Gates section.

## Deterministic quality gates

1. **Build** — `dune build --root . @all` (opam switch `arch-index`) → clean, zero warnings.
2. **Tests (full suite)** — a full unfiltered `dune test --root . --force` hit unrelated,
   pre-existing environmental flakiness in this session's shared `/tmp` scratchpad: Go's VCS
   auto-stamping resolves its subprocess's cwd to `/tmp` itself (not the project directory) in
   this specific tmpfs-backed worktree layout, breaking every test that builds Go code
   (`callgraph_go.ml`, `effects.ml`'s Go SSA extractor test); a separate `pcc.ml` test hits a
   "blank JSON input" error from concurrent-session noise in the same shared `/tmp`. **Rigorously
   confirmed unrelated to this task** during review: `git stash` (removing 100% of this task's
   diff) reproduces both failures identically against the unmodified pre-review commit. A fresh,
   independent QA-phase run — `./_build/default/tezt/tests/main.exe --not-match "callgraph-go"
   --not-match "pcc:" --not-match "Go SSA" --not-match "Go:"` — passes **105/105**, including
   both `tezt/tests/rules.ml` witness tests, re-run cleanly a second time after clearing a
   disk-space issue (below) to confirm stability. `serve.ml`'s two tests pass in this same run
   (relevant given codex's cross-runtime attempt below).
3. **Format/lint** — not re-run this round; no `lib/arch_index`/schema files touched, and this
   task's own files (`arch_graph.ml`, `arch_rules.ml`, `rules.ml`, `main.ml`) showed no new `@fmt`
   drift during review's build passes.
4. No project-specific gate beyond the above documented in the impl brief.

## Spec runnable checks

`specs/witness-paths.md` absent (Fast mode, no spec phase) — N/A.

## Code-intel invariant gate

No `kb/properties.md` code-intel block installed in this repo — `RESULT: skip`, no verdict impact.

## TUI check

N/A — no TUI scope in this task.

## Environment note: shared-tmpfs disk exhaustion

Mid-QA, the shared `/tmp` tmpfs hit 100% (0MB free, an `ENOSPC` on a codex tool invocation) —
caused by OTHER concurrent sessions' worktrees on the same machine, not this task. Freed ~549MB by
removing only this task's own regenerable `wt-witness/_build` directory (never touched another
session's files), rebuilt cleanly afterward. Noted here since it briefly interrupted the
cross-runtime QA attempt below.

## Cross-runtime QA

`codex` breaker check returned `status: "available"` for the QA phase (independent of the review
phase's session-wide `skipped-degraded` state). Ran one independent QA pass via
`scripts/xruntime-exec.sh codex --write`, instructed to re-run the filtered suite, independently
verify the VIOLATION-adjacency (`must_fwd`) and overlap-short-circuit code claims by direct
inspection, and independently reproduce the two "unrelated environmental failure" claims via its
own `git stash` isolation.

**Result: degraded, not a genuine blocking discrepancy.** Codex's own sandboxed execution
environment could not complete verification: its filtered suite run stopped at 38/105 with
`serve.ml: Operation not permitted` (a network/port-bind restriction in codex's own sandbox — I
independently re-ran the identical filtered command myself immediately after and got a clean
105/105, `serve.ml` included, twice), and it reported `git stash` failing with "the linked
worktree's Git index is read-only" (I ran `git stash`/`git stash pop` successfully multiple times
in this exact same worktree, both during review and QA). Both are execution-sandbox limitations
specific to codex's own environment in this session — consistent with codex's `skipped-degraded`
status recorded for every prior task's review phase this session (non-conforming-output/sandbox
constraints) — not a semantic disagreement with any claim in the diff. Codex never reached the
point of disputing the actual code claims (items 3/4 of the QA prompt: the `must_fwd` adjacency
choice, the overlap short-circuit narrowing) before its sandbox blocked it, so there is no
disputed CRITICAL/HIGH finding to block on — only an execution environment that could not run the
network-binding test or use git the way this task's own investigation did. Recorded as
`cross_runtime.codex.status: "degraded"` in the QA state, not `"healthy"`.

## Verdict composition

- Causes this round: none (`causes: []`) — the cross-runtime degradation is recorded but is not a
  qualifying NO-GO cause (it is not a disputed gate result; codex's own sandbox prevented
  execution, and the primary QA gates all passed cleanly and reproducibly).
- `qa_no_go_round`: 0 (GO verdict resets/starts at 0).
- `rounds_audit`: one entry, round 1, verdict GO, `qualifying: false`.
- Gate (`check-qa-convergence.js`): exit 0, no violations.

## Summary

Independent fresh-fixture reverification confirms the implementation and all review-round fixes:
witness paths for `VIOLATION`/`POSSIBLE`/`UNKNOWN` verdicts are correctly wired — `VIOLATION`
walks `must_fwd` (verified both by direct code inspection and by a deliberate mutation-and-revert
proving the dedicated adjacency test actually catches a wrong choice), the overlap short-circuit
correctly narrows to overlap-only hits, and the JSON field is documented. Two test files fail in
this environment for reasons rigorously proven unrelated to this task (`git stash`-isolated during
review); a filtered run excluding exactly those passes 105/105, twice, independently, including
both new witness tests. A cross-runtime codex QA pass hit its own sandbox's network-bind and
git-index restrictions before it could dispute any code claim — recorded transparently as degraded
rather than silently ignored, consistent with codex's status all session. **GO — ready to ship.**
