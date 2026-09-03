# Implementation Brief — witness-paths

**Date:** 2026-09-04
**Mode:** fast
**Status:** COMPLETED

## Where the work lives

Worktree `/tmp/claude-1000/-home-mathias-dev-arch-index/14fbc421-dfc7-4b31-91d6-c084baeb45e0/scratchpad/wt-witness`,
branch `feat/witness-paths`, based on `origin/main@003e951`.

## Scope

Roadmap Phase 1 item 1.5: witness paths. Makes a `POSSIBLE`/`VIOLATION`/`UNKNOWN` verdict from
`arch-rules` carry a concrete, checkable call path instead of only a rule name and an offender
list. Pre-implementation research: grepped the whole repo for `sarif`/`SARIF`/`codeFlow` — no
SARIF writer exists anywhere yet, so the roadmap's "output shape is fixed by SARIF" is a future
consumer, not a present one. Scoped this task to the graph-level path functions plus wiring them
into `arch-rules`' own three output formats (text/md/json) as a new `witness` field — the concrete,
buildable slice matching the roadmap's own **S** effort estimate. Full SARIF `codeFlow`/
`threadFlow` emission is a separate, larger (`M`/`L`-sized) piece of work with no consumer to feed
yet — documented residual, not silently dropped.

## Decisions made

- **Both a single-source and a multi-source path API.** The roadmap's own note asks for
  `shortest_path g ~from ~to` and `witness_to_top g ~from` with a singular `~from : key` — those
  ship exactly as specified, independently testable. But a `reach` rule's actual source is a
  *selector*, which resolves to a SET of keys (`Arch_sel.select`), and the rule's own
  VIOLATION/POSSIBLE/UNKNOWN verdict already only claims "some seed in this set reaches the
  target" — it does not say which one. So `arch_rules.ml` needs a multi-source variant, added as
  `shortest_path_from_set`/`witness_to_top_from_set`. Both single- and multi-source functions share
  one private BFS core (`bfs_search ~adj ~seeds ~stop`), so there is exactly one BFS
  implementation, not two independently-maintained near-duplicates.
- **`shortest_path_from_set` takes `~adj` explicitly, not a whole graph `g`.** `arch_rules.ml`
  needs to choose between `g.must_fwd` (a VIOLATION's own proof edges — the tightest, most
  defensible witness for a *definite* path) and `g.fwd` (the wider MUST ∪ MAY_ENUMERATED cone a
  POSSIBLE verdict is actually built from). Passing the adjacency map directly, rather than the
  graph plus a "which map" enum, keeps the function honest about needing exactly one input it
  actually reads.
- **`witness_to_top`/`witness_to_top_from_set` stop at the CALLER that holds the ⊤ edge, not at
  some further synthetic node.** `arch_graph.ml`'s own `load` already records `tops` keyed by the
  caller of a `MAY_TOP` edge (a ⊤ edge "goes everywhere", so it is recorded as a frontier marker on
  its caller, never traversed as a real successor — see `load`'s own comment). So "the node that
  escapes" IS a real function in the graph; the witness path ends there, which is exactly the
  concrete evidence a reviewer needs for why the verdict is UNKNOWN rather than PASS.
  Verified against the existing `layered_stream` test fixture: `job.run --MUST--> util.helper
  --MAY_TOP--> ⊤` — `util.helper` (not some placeholder) is where `g.tops` is nonzero, and the new
  test asserts the witness path is exactly `[job.run; util.helper]`.
- **VIOLATION's src/dst-overlap sub-case carries no witness.** When the two selectors literally
  overlap (a function matched by both `from` and `to`), `arch_rules.ml`'s existing `note` text
  already explains this is "reachable from itself" membership, not a call path — the witness field
  stays `[]` there rather than fabricating a one-hop "path" that would look identical to a real
  proof.
- **`witness` on every OTHER verdict form (`Exported`, `Effect`, `Dep`, `NOT_COMPUTED`, `PASS`,
  `NO_SOURCE`/`NO_TARGET`) is always `[]`.** None of those carry a reachability claim a path could
  illustrate — `Exported`/`Dep` are direct fact checks (`exact = true` already says as much),
  `Effect` reasons over a cone membership test rather than a specific edge, and `PASS`/
  `NOT_COMPUTED`/the vacuous cases assert nothing was found. Populating `witness` there would
  imply a path exists when none was computed.
- **`calls.resolution`-adjacent scoping is untouched** — this task is purely additive to
  `arch_tools`/`arch_rules`, touches nothing in `lib/arch_index`, so the self-index golden fixture
  (ADR 001) needed no regeneration; confirmed by regenerating it anyway and diffing byte-for-byte
  identical (21 modules / 576 functions / 3994 calls, unchanged from the top-anchor-taxonomy
  task's post-review count).

## Modified files

| File | Type of change | Reason |
|---|---|---|
| `lib/arch_tools/arch_graph.ml` | addition | `bfs_search` (shared private BFS core), `shortest_path`, `shortest_path_from_set`, `witness_to_top`, `witness_to_top_from_set` |
| `bin/arch_rules/arch_rules.ml` | modification | New `witness : string list` field on `result`; computed for `Reach`'s VIOLATION/POSSIBLE/UNKNOWN; `[]` at the other 6 construction sites; rendered in text, md, and json output |
| `tezt/tests/rules.ml` | modification | New `register_witness`: VIOLATION/POSSIBLE/UNKNOWN each carry the expected two-hop witness path over the existing `layered_stream` fixture; PASS carries none |
| `tezt/tests/main.ml` | modification | Registers `Rules.register_witness` |

## Quality Gates

- [x] Build: `dune build --root . @all` (under the `arch-index` opam switch) ✅ clean, zero warnings
- [x] Tests: `dune test --root . --force` ✅ 112/112 tezt tests pass (1 new)
- [x] Self-index golden fixture confirmed unaffected (regenerated and diffed: unchanged at
      21 modules / 576 functions / 3994 calls) — no `lib/arch_index` file was touched by this task

## Points of attention for review

- Confirm the shared `bfs_search` core is correct for both roles it plays: exact-target search
  (`shortest_path`/`shortest_path_from_set`, `stop = (fun x -> x = to_)`) and predicate search
  (`witness_to_top`/`witness_to_top_from_set`, `stop = (fun x -> SM.mem x g.tops)`) — in
  particular that BFS layer-order guarantees the first `stop`-satisfying node popped is at minimum
  distance from the (possibly multi-seed) start set, not merely *a* satisfying node.
  `bfs_search` checks `stop x` on `x` when it is POPPED from the queue (not when discovered/pushed)
  — confirm this ordering is actually where a self-satisfying seed (`from = to_`, or a seed that
  is itself a ⊤-holding caller) gets caught correctly on the very first iteration.
- Confirm `shortest_path_from_set ~adj:g.must_fwd` is the right adjacency choice for VIOLATION's
  witness (rather than `g.fwd`) — the verdict's own OWN proof (the `must` closure in
  `reach_verdict`) is over `must_fwd`, so the witness should walk the identical edge set the proof
  used, not a wider one that could produce a "witness" over edges the proof itself never relied on.
- Confirm the VIOLATION src/dst-overlap sub-case correctly produces `witness = []` and does not,
  say, accidentally fall through to the general VIOLATION branch and attempt (and fail, silently)
  a BFS that was never meaningful there.
- `shortest_path`/`witness_to_top` (the singular, roadmap-literal signatures) have NO direct test
  of their own — they are only exercised indirectly, through the multi-source variants, via
  `arch-rules`' CLI-level tests (this codebase's established testing convention: no unit-test
  layer exists for `lib/arch_tools` functions independent of a consuming binary). Confirm this is
  an acceptable testing posture for a first-class new API a downstream SARIF writer (a Phase 1.5+
  follow-up) would call directly, not just through the multi-source path.

## Identified out-of-scope (deferred, not silently dropped)

- Full SARIF `codeFlow`/`threadFlow` emission (a `--format sarif` output, or a dedicated
  `bin/arch_sarif`) — no consumer or writer exists in this codebase yet to receive it; this is a
  separate, larger piece of work the roadmap itself scopes at `M`/`L`, not this item's `S`.
- `GitHub caps a run at 1 000 threadFlowLocations` (the roadmap's own note) is a SARIF-writer
  constraint, inapplicable until that writer exists.
- A direct unit-test layer for `Arch_graph`'s new functions, independent of `arch-rules` — matches
  this codebase's existing convention (no such layer exists for any `arch_tools` function today),
  not a gap introduced by this task specifically.

## Review-round addendum

`reviewer` + `architect` spawned in parallel (blast radius 4 files > 3, Fast mode). Cross-runtime
`codex` not separately invoked for this task's review (breaker state carried from the prior task's
session-wide `skipped-degraded`).

- **MEDIUM (reviewer, confirmed via a disclosed mutation test)** — the witness test asserted only
  substring membership (`Batch.contains` on the joined path), not hop order, so a reversed path
  passed identically to a correct one. The reviewer demonstrated this directly: it mutated
  `arch_graph.ml`'s `build` helper to add an erroneous `List.rev`, reran the suite, and the test
  still reported SUCCESS — then reverted its own mutation. Independently, I had already applied
  the same fix (positional `Some [hop0; hop1]` matching) before the reviewer's report arrived, so
  this finding and my fix converged. Also added a dedicated adjacency-divergence fixture/test (a
  2-hop all-MUST chain alongside a shorter 1-hop MAY_ENUMERATED shortcut) and *verified it
  actually fails* under a manual `must_fwd`→`fwd` mutation before reverting it, closing the
  architect's related "fixture too weak to discriminate the design decisions" finding.
- **MEDIUM (reviewer)** — VIOLATION's src/dst-overlap short-circuit (`witness = []` whenever
  `SS.inter src dst` was nonempty) was broader than the actual overlap case: `hit` can contain both
  self-overlap members and genuine must-reachable targets in the same result when a rule has both.
  Fixed: witness is only suppressed for hits that are themselves overlap members;
  `List.find_opt (fun k -> not (SS.mem k src && SS.mem k dst)) hit` finds a real target if one
  exists, and still gets its BFS path.
- **MEDIUM (reviewer)** — the new `results[].witness` JSON field shipped undocumented. Fixed:
  added to `docs/fitness-functions.md`'s field table and `CHANGELOG.md`.
- **LOW (reviewer)** — UNKNOWN's witness could end at a different function than `detail`'s first
  entry (one found by an independent nearest-⊤-holder BFS, the other by lexicographic `SS.elements`
  order over the same escaping set). Fixed: UNKNOWN's witness now targets `hit`'s own head
  directly (the same value `detail` renders), so the two fields can never disagree. This also made
  `witness_to_top_from_set` dead code (removed) and `witness_to_top` (singular) an
  intentionally-unused-for-now API surface matching the roadmap's own literal signature
  (unchanged from the architect's original point, see below).
- **LOW (reviewer)** — `shortest_path`'s docstring falsely claimed `None` for an absent key;
  `bfs_search` never consults node membership, so `shortest_path g ~from:k ~to_:k` is `Some [k]`
  for any `k`. Fixed the docstring to state this accurately rather than adding an unneeded
  membership guard that no real call site needs.
- **Nit (reviewer)** — `!found = None` (polymorphic compare on a ref) → `Option.is_none !found`.
  Fixed.
- **MEDIUM (architect)** — `shortest_path`/`witness_to_top` (the singular, roadmap-literal
  signatures) have zero call sites anywhere in the tree and no direct test — accepted as
  documented, intentional forward-looking API (a future SARIF writer's natural entry point),
  not removed; noted here so it doesn't read as an oversight.
- **MEDIUM (architect)** — the codebase already has two independent BFS implementations in
  `bin/arch_serve/arch_serve.ml` (`neighborhood_bfs`, `reaches_bfs`) with silently diverging
  semantics from `Arch_graph` (no MUST/MAY_ENUMERATED distinction, no ⊤-frontier handling — a
  raw-SQL traversal against the flat schema only). Real finding, **not fixed in this task**:
  consolidating `arch_serve` onto `Arch_graph`/`bfs_search` is a separate, larger piece of work
  (a different binary, a different schema-detection path) — flagged as a follow-up, not silently
  dropped.
- **HIGH (architect)** — the JSON `witness` field is pre-rendered display strings
  (`"name  (file)"`, no line number), not structured per-hop data, even though the BFS already
  produces real `key`s resolving to nodes with `line_start`/`line_end` available. A future SARIF
  writer needing `physicalLocation.region.startLine` per hop cannot reconstruct it from the
  rendered strings. **Not fixed in this task** — reshaping the field now, before any real consumer
  exists, risks guessing the wrong structure; deferred to whenever the SARIF writer is actually
  built (documented residual, same discipline as the other items below), at which point the
  `witness` field's shape should be revisited before anything depends on today's string-array
  shape.
- **LOW (architect)** — `result`'s field-threading (7 constructors) is an existing, established
  pattern in this file (`sizes`/`exact` already work this way) — accepted as-is, flagged only as
  "revisit if a third rule-specific field shows up".
- **LOW (architect)** — a POSSIBLE witness carries no per-hop edge kind (can't tell which hop is
  the MAY_ENUMERATED one). Accepted as a known limitation for this slice, noted in the impl brief's
  existing "Identified out-of-scope" list (unchanged).

**Re-verification after all fixes:** `dune build --root . @all` clean, zero warnings.
`dune test --root . --force`: this session's shared `/tmp` scratchpad hit unrelated environmental
flakiness affecting TWO test files that touch neither `arch_tools` nor `arch_rules`
(`callgraph_go.ml`, `effects.ml`'s Go SSA test, and `pcc.ml`) — Go's VCS auto-stamping resolves its
subprocess's cwd to `/tmp` itself rather than the actual project directory in this specific
tmpfs-backed worktree layout, and a separate, unrelated `pcc` test hit a "blank JSON input" error
from concurrent-session noise in the same shared `/tmp`. **Rigorously confirmed unrelated to this
task**: `git stash` (removing 100% of this task's changes) reproduces both failures identically
against the unmodified `7fd3e6a` commit. A scoped run excluding exactly those pre-existing-broken
tests (`--not-match "callgraph-go" --not-match "pcc:" --not-match "Go SSA" --not-match "Go:"`)
passes **105/105**, including all 8 `tezt/tests/rules.ml` tests (2 new). A targeted `--file
tezt/tests/rules.ml` run independently confirms 8/8. Self-index golden fixture unaffected (no
`lib/arch_index` file touched by this task) — confirmed unchanged at 21 modules / 576 functions /
3994 calls both before and after this review round.

## Ratchet

First round.
