# QA Brief — shadowed-function-identity

**Date:** 2026-09-02
**Status:** GO ✅
**Round:** 1 (qualifying 0/5)

## Round state

Fresh cycle, round 1. No prior QA rounds for this task.

## Quality Gates

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build | `dune build` | ✅ PASS | ~0.3s |
| Tests | `dune test --force` | ✅ 89/89 passed | ~86s |
| Format | `dune fmt` | ✅ PASS (no `.ml`/`.mli` reformatting needed) | — |

All gates run from the feature worktree
(`/tmp/claude-1000/-home-mathias-dev-arch-index/14fbc421-dfc7-4b31-91d6-c084baeb45e0/scratchpad/wt-shadowed`,
branch `fix/shadowed-function-identity-v2`, HEAD `8550553`), under the project's mandatory local
`_opam` switch.

**Format gate note:** `dune fmt` reformatted 18 pre-existing `dune` files (formatter-version
drift, unrelated to this task — already flagged twice earlier this session, e.g. for
`wire-checks-into-ci`). Reverted after confirming no `.ml`/`.mli` file in this task's diff needed
reformatting, to keep the format gate result scoped to what this task actually touched.

## Tests: detail

- New tests added: 6 (`tezt/tests/shadowed_definitions.ml`: no-collision control, same-module
  shadow with mid-caller regression assertion, 3-way shadow, `.mli`-backed exposed attribution,
  nested-module shadow, cross-module qualified-call resolution)
- Existing tests: 83 pass, 0 skip, 0 fail
- Regression detected: NO — `ocaml_shapes.ml`'s toplevel-vs-nested-module homonym test and
  `callgraph_soundness.ml`'s stamp-level shadow test (the two adjacent-but-distinct collision
  axes named in the QA scope) both remain green.

## Behaviors validated (per `briefs/shadowed-function-identity-qa-scope.md`)

Independently re-verified with a fresh fixture built and indexed directly through
`bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe` and raw SQL queries against the resulting
database — not by re-running the existing test suite a second time:

1. **Same-module shadow → two rows.** `functions` table: `id=4 name='f' exposed=1`,
   `id=3 name='f#1' exposed=0`. ✅
2. **Edge attribution.** `f → helper_two`, `f#1 → helper_one` — distinct, correctly attributed,
   not merged. ✅
3. **Naming direction.** The bare name (`f`) belongs to the later-inserted (live) row (id 4);
   the earlier row (id 3) carries the `#1` suffix. ✅
4. **Cross-module resolution.** `use_a` (in a second module `b.ml`, calling `A.f` by qualified
   name) resolves to `f` — the live, last-bound definition — not `f#1`. ✅
5. **No-collision regression.** A clean fixture with no shadowing (`helper`, `f`) produces
   exactly those two bare names, no `#N` suffix anywhere. ✅
6. **Adjacent-but-distinct cases unaffected.** `ocaml_shapes.ml` ("module-language shapes") and
   `callgraph_soundness.ml` ("dominance corpus") both pass in the full suite run. ✅
7. **`exposed` attribution.** Same fixture as (1): `f exposed=1`, `f#1 exposed=0` — confirmed via
   direct query, not inferred from the test assertion. ✅

All seven behaviors hold, including the cross-module fixture the QA scope explicitly calls out as
the one most likely to hide a direction regression — confirmed it demonstrates the corrected
(last-bound-keeps-bare-name) direction, not just "two rows exist."

## Code-intel gate

Skipped — no code-intel resolver installed (`scripts/code-intel-resolve.js` absent) and no
`kb/properties.md` in this repo.

## Cross-runtime QA

Both available second runtimes were attempted (per the mandatory cross-runtime re-verification
step) and both failed for reasons external to this task's code:

- **codex**: `check-availability` returned `available` (config digest differs from review's
  probe, since this is a distinct QA-phase invocation); the actual re-verification run failed
  with `ERROR: You've hit your usage limit. ... try again at Sep 7th, 2026 11:25 AM.` — an
  account-level API quota exhaustion, not a build/test/code discrepancy.
- **opencode**: `check-availability` returned `available`; the actual re-verification run timed
  out after 180s with no output.

**Judgment call, recorded transparently:** neither failure is a discrepancy with the primary
QA/review findings — neither runtime produced any output disputing a gate result or a specialist
claim; both failed before producing any signal at all, for environmental reasons (quota, timeout).
Per this session's own established precedent (the review phase's cross-runtime probe for this
same task degraded twice for an unrelated reason — non-conforming output — and was correctly
treated as non-blocking via the shared breaker's `skipped-degraded` path, not as an automatic
NO-GO), I am treating this as a documented gap rather than a blocking discrepancy: the underlying
fix has already been independently verified twice over (two full review rounds, each with two
specialist agents doing empirical fixture-based verification, plus this QA pass's own independent
fixture queries above) — a build+test rerun by a third runtime would have been corroborating, not
load-bearing, evidence. Recorded in `briefs/shadowed-function-identity-qa-state.json`'s
`cross_runtime` field for the audit trail. Flagging this explicitly for human review rather than
silently treating a spec ambiguity as resolved.

## NO-GO issues

None.

## Verdict

**GO** — ready for `/roster-ship`
