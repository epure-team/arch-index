# Ship Gate — rust-soundcg-whole-program

**Date:** 2026-09-03
**Status: VALIDATED** — human quiz passed (all 3 recommended options confirmed), PR opened:
https://github.com/epure-team/arch-index/pull/52
**Review:** GO (round 2 / cycle 2) — `briefs/rust-soundcg-whole-program-review.json`
**QA:** GO (round 2) — `briefs/rust-soundcg-whole-program-qa.md`

## What this ships

A new, whole-program-aware Rust MIR call-graph producer (`arch-callgraph-rust` +
`bin/arch_callgraph_rust_merge`), landed fresh (not merged from the DO-NOT-MERGE
`feat/rust-soundcg-a1`/`a2` reference branches) against `specs/rust-soundcg-whole-program.md`.

- **US-1**: sound single-crate MUST/MAY_TOP walker, with all names crate-independent
  (`stable_def_path`) so cross-crate edges actually join to their target's own function row.
- **US-2**: a post-process merge pass that narrows `dyn`-dispatch `MAY_TOP` sites to
  `MAY_ENUMERATED` across the whole workspace, gated by a publish-boundary check (only narrows
  when the trait-defining crate is `publish = false`) and a blanket-impl detector, with a
  whole-batch missing-facts fallback.
- A repo-integrated, self-contained selftest (`selftest-callgraph-rust.sh`, 11 scenarios) replacing
  ad-hoc scratch fixtures.
- `README.md` documenting 7 accepted residuals plainly (cache-staleness, publish-flag proxy
  weaknesses, whole-batch fallback scope, RTA-union not implemented, build-script name collision,
  self-referential single-manifest workspaces), plus a filed-but-unactioned CI-wiring ticket.

**Untouched by design:** `bin/arch_load/arch_load.ml`'s strict record-type contract, and — per the
scope guard (CHECK-8, reconfirmed clean every round) — `lib/arch_index/call_graph_extractor.ml`
and `tezt/tests/lsp_languages.ml` (the existing rust-analyzer LSP path).

## Pipeline history (2 rounds each of review and QA — both fully documented, not glossed over)

1. Round-1 review (3 specialists + degraded cross-runtime): found and fixed 3 CRITICAL (cross-crate
   node-identity fragmentation; the harness's own documented direct-pipe usage was actually broken;
   a comment-parsing false positive in the publish-flag scanner), 1 HIGH (extern "C" symbol name
   dropped), 2 MEDIUM, 1 LOW — all same-round.
2. Round-1 QA: **NO-GO**. Its own scope brief explicitly named an "easy-to-miss" case to test —
   `[workspace.package] publish = false` + `publish.workspace = true` — and it was broken: the
   inheritance-resolution code was unreachable dead code. Also surfaced, while fixing it, a genuine
   process failure on my part: the round-1 review's comment-parsing "fix" had been marked RESOLVED
   without the code edit ever actually having been written. Both fixed together.
3. Round-2 review (2 specialists, scope narrowed correctly since the diff was small — still caught
   1 more HIGH in the same function family, a Cargo `publish = ["registry"]` array-form misread):
   GO.
4. Round-2 QA: independently reverified the fix with a fresh fixture: GO.

## Commits on this branch (14 total since `2592c77`, all already conventional)

```
087f04e fix(rust): HIGH — publish=["registry"] array form misread as literal false
1688a92 fix(rust): CRITICAL — publish.workspace=true inheritance was dead code (QA CHECK-6)
d7759a8 test(rust): add CHECK-3 extern "C" symbol-name coverage
8739e0f docs(rust): update residual #5's example, document build-script name-collision residual
bcdd796 fix(rust): MEDIUM — TerminatorKind::TailCall silently dropped (FR-002)
08b3537 fix(rust): CRITICAL cross-crate node-identity fragmentation + 2 more findings
3cb0e46 test(rust): add CHECK-4 flat-union scenario — the spec's hard requirement
57c2ac1 test(rust): add CHECK-6 (missing publish=false) scenario to the selftest
a5b5eda docs(rust): document the three accepted residuals + CI-wiring ticket
1baa3ec test(rust): repo-integrated multi-crate selftest for the merge pass
c7efe8b feat(rust): whole-program dyn-dispatch merge pass (US-2 core)
15aae52 feat(rust): add impl_fn_stable_name join key to trait_impl_fact
b376673 chore(rust): ignore callgraph-rust build output
1e2df39 feat(rust): emit crate-independent dyn-dispatch facts for the merge pass
0669352 Revert "fix(load): tolerate unrecognized NDJSON record kinds"
c08190e feat(rust): land a corrected sound single-crate MIR call-graph walker
```

Branch `feat/rust-soundcg-whole-program`, based on `2592c77` — `origin/main`'s current tip is
still `2592c77` (fetched and confirmed), so this is a clean fast-forward-able rebase target; no
rebase needed.

## No tracking issue

This task originated from the roadmap (`~/notes/2026-09-01-arch-index-roadmap.md` item 4.3), not
from a GitHub issue — there is no `Closes #N` to reference in the PR body.

## Push mode

`push_mode` is not set in `.harness/harness.json` — defaults to `pr` mode (rebase not needed, tip
already matches `origin/main`; push branch + open PR, human merges after CI).
