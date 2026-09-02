# Ship Gate — shadowed-function-identity

**Date:** 2026-09-02
**Branch:** `fix/shadowed-function-identity-v2` (worktree,
`/tmp/claude-1000/-home-mathias-dev-arch-index/14fbc421-dfc7-4b31-91d6-c084baeb45e0/scratchpad/wt-shadowed`)
**Target:** `main`
**Closes:** GitHub issue #41

## Commits prepared

```
0e1e4c1 fix(cmt): give same-level shadowed bindings distinct row identities (#41)
eae8f2e fix(cmt): make intra-module call targets shadow-aware, fix arg-escape naming, revert unsound LSP-path rename (#41 review round 1)
8550553 test(cmt): add node-runnable ratchet check for the #41 intra-module HIGH fix
```

Already up to date with `origin/main` (rebase was a no-op — branched from current `main` tip).

## What this fixes

GitHub issue #41 / roadmap item 0.6: two top-level bindings of the same name in one OCaml
compilation unit (`let f = ...` twice at the same level) previously produced only one `functions`
row (`INSERT OR REPLACE` on `UNIQUE(module_id, name)` silently dropped the earlier definition and
cascaded its deletion to every dependent row), and both bindings' outbound calls resolved onto
whichever definition survived.

The fix gives each same-level binding its own row via a `#N` ordinal suffix: the last
(source-order-final, live) binding keeps the bare name, earlier (shadowed) bindings take the
suffix — required in this direction because a cross-module caller can only ever spell the bare
name. A first-round review found the fix was incomplete on its inbound/intra-module direction (a
call lexically between two shadowed bindings resolved to the wrong one); fixed in round 2 and
independently re-verified by two specialist agents across two full review rounds plus this
session's own QA pass with fresh, from-scratch fixture verification.

## Full pipeline record

| Phase | Outcome |
|---|---|
| question/research/intake | COMPLETED / COMPLETED / VALIDATED |
| plan | COMPLETED |
| implement (round 1) | COMPLETED |
| review (round 1) | NO-GO — 1 HIGH, 3 MEDIUM, 4 LOW findings |
| implement (round 2) | COMPLETED — all round-1 findings fixed |
| review (round 2) | GO — all findings verified resolved, 4 new LOW findings (non-blocking, carried forward as OPEN) |
| qa | GO — all gates pass (89/89 tests), all 7 scoped behaviors independently re-verified |

Full detail: `briefs/shadowed-function-identity-review.json`, `briefs/shadowed-function-identity-qa.md`.

## Known residuals (non-blocking, documented — not silently dropped)

- 4 LOW findings from round-2 review remain OPEN (not blocking GO): dead public API surface in
  `arch_index_cmt.mli` (`build_binding_names`/`binding_name` exported with no external consumer
  after the LSP-path revert), one untested doc-attribution assertion in a test fixture, a
  **pre-existing, unrelated** indexing gap for type-annotated top-level bindings (confirmed
  byte-identical to `main` — not a regression, out of scope for #41), and a duplicate
  `build_binding_names` pass per compilation unit (correctness-neutral, minor efficiency nit).
- Cross-module homonym hazard in `bin/arch_query/arch_query.ml` — pre-existing, already-accepted,
  explicitly out of scope per the intake brief.
- Full Octez-scale re-measurement of the roadmap's cited 9629 `type_usage` FK-rejection signature
  — deferred as a documented follow-up; self-index-scale evidence used instead per the plan.
- QA's mandatory cross-runtime re-verification pass could not get a signal from either available
  runtime this round (codex hit an account API quota limit; opencode timed out) — documented as a
  judgment call in `briefs/shadowed-function-identity-qa.md`, not treated as blocking given the
  fix's correctness was independently verified twice over by specialist review already.

## User-visible naming-contract change (for the PR description)

Before this fix, `arch-query`'s bare-name lookups against a shadowed function always resolved to
whichever definition `INSERT OR REPLACE` left standing (in practice, the last-written one) — no
change for that case. After this fix, a previously-invisible extra row now appears for the
shadowed definition, under a `#N`-suffixed name, with its own correctly-attributed call edges.

## Push and PR plan

```
git push origin fix/shadowed-function-identity-v2
gh pr create --title "fix(cmt): give same-level shadowed bindings distinct row identities" \
  --base main --body <impl-summary + Closes #41>
```

`push_mode` is not configured in this repo (no `tunables.push_mode`) — defaulting to `pr` mode
(rebase-merge after human approval), the safer default absent an explicit `direct` configuration.
