# QA Brief — rust-soundcg-whole-program

**Date:** 2026-09-03
**Status:** GO ✅
**Round:** 2 (qualifying 1/5)

## Round state

Round 2 in this cycle. `qa_no_go_round` reset to `0/5` on this GO. Round 1 was NO-GO (cause:
`spec-check-failure`, CHECK-6's workspace-inheritance variant) — see the round-1 `rounds_audit`
entry below.

## Quality Gates

| Gate | Command | Result | Duration |
|---|---|---|---|
| Build | `cd callgraph-rust && RUSTC_BOOTSTRAP=1 cargo build --release` (clean rebuild, `rm -rf target` first) | ✅ PASS | 0.74s |
| Tests | `./selftest-callgraph-rust.sh` | ✅ PASS (11/11 scenarios — 3 new since round 1: `wsinherit`, `pubcomment`, `pubarray`) | 1.9s |
| Repo-wide build | `dune build @all` (worktree) | ✅ PASS | 0.27s |
| Repo-wide tests | `dune test --force` (worktree) | ✅ PASS — 89/89 tezt tests SUCCESS | 84.8s |

Same `Statement error (CONSTRAINT): FOREIGN KEY constraint failed` stderr lines as round 1 —
confirmed (again) as the documented, intentional rejection-attribution diagnostic
(`lib/arch_index/arch_index_db.ml:44-111`), not a regression.

## Tests: detail

- New tests added since round 1: 3 selftest scenarios (`wsinherit`, `pubcomment`, `pubarray`)
- Existing repo tests: 89 pass, 0 skip, 0 fail
- Regression detected: NO

## Code-intel gate

`kb/` absent — skipped (no `code-intel` block).

## Spec runnable checks (specs/rust-soundcg-whole-program.md)

Since round 1's diff to this round only touched the publish-boundary TOML-scanning helpers
(`toml_publish_false`/`toml_key_is_workspace_true`), only CHECK-6 was re-verified with a fresh,
independent fixture this round. CHECK-1/2/3/4/5/7/8/9 are unaffected by this round's diff and
carry forward their round-1 independent verification (see
`briefs/rust-soundcg-whole-program-qa-state.json`'s round-1 audit entry / the round-1 QA report
history in `briefs/rust-soundcg-whole-program-state.json`).

| Check | Result | Evidence |
|---|---|---|
| **CHECK-6 (missing `publish = false`, including the workspace-inheritance variant)** | ✅ **PASS — independently reverified** | Fresh fixture (root `[workspace.package] publish = false` + member `publish.workspace = true`, identical shape to the round-1 NO-GO repro but built fresh, not reusing any file from that round): `publish_false: true`. Confirms the fix genuinely holds, not just that the code changed. |
| CHECK-1/2/3/4/5/7/8/9 | ✅ carried forward (unaffected by this round's diff) | See round-1 QA report / this round's build+selftest (11/11) reconfirms all prior scenarios still pass |

## Accepted-residual documentation check

Confirmed present in `callgraph-rust/README.md` (now 7 items, item 7 new this round):
- Cache-staleness precision cost (item 1) ✅
- Publish-flag proxy weakness (item 2) ✅ — the review round's own fixes (array-form, comment
  parsing, workspace inheritance) close the gaps that made this proxy weaker than documented;
  remaining weaknesses (multi-line tables, self-referential single-manifest workspaces) still
  plainly stated
- Whole-batch missing-facts fallback (item 3) ✅, RTA-union not implemented (item 4) ✅,
  build-script name collision (item 6) ✅ — unchanged from round 1
- **New this round:** self-referential single-manifest workspace inheritance (item 7) — safe
  direction only, plainly documented as a residual, not silently accepted

## Verdict

**GO** — ready for `/roster-ship`
