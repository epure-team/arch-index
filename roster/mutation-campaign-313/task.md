# Task — mutation-campaign-313

**Roadmap item:** arch-index 3.13 — "campagne de mutation exécutée" (executed mutation campaign).
**Depends:** 1.2 (provenance), 1.6 (stable identity, shipped). **Not** 5.2.
**Mode:** full, `--critical` route chosen by the human; backend recommended Quint
(`briefs/mutation-campaign-313-formal-triage.md`).
**Worktree:** `/mnt/ssd-external-2to/arch-index-mutation-313`, branch `feat/mutation-campaign-313`,
base `main` at `70cb47f`. The shared checkout `/home/mathias/dev/arch-index` belongs to two other
active sessions and must not be touched.

## Goal

Add to arch-index the layer that **executes** a mutation campaign, on top of the static targeting
already shipped (`arch-mutants plan`/`report`, `arch-impact --diff`, `arch-coverage`). Five slices
of a single roadmap item:

1. **Driver `arch-mutants run`** — from the plan, emit one command per mutant carrying only the
   tests that reach the mutated function, drive an external engine (mutaml, cargo-mutants,
   go-mutesting), collect NDJSON. Agnostic: it manipulates test identifiers and an engine CLI
   contract, nothing language-specific.
2. **Persisted tables** — `mutants` (site, replacement, source content hash, `function_id`) and
   `mutant_kills` (mutant, test, status, seed, duration, `producer_run_id`). Keyed by the stable
   identity of 1.6; an entry whose hash diverges from the current commit is "to refresh", not true.
3. **Diff-scoped selection** — the union of: mutants of functions touched by the PR; mutants of
   everything reached by a modified or added test (test helpers included); and, for a deleted test,
   the mutants it was the only one to kill (read from `mutant_kills`).
4. **Per-added-test verdict** — "this test killed no mutant of what it reaches". A defect list,
   never a ratio and never a threshold (`docs/mutation-testing.md` refuses the mutation score on
   record). Consumed by the Épure judge as an automatic rejection.
5. **Test-node → invocation adapters** — alcotest (suite + index), tezt (title), cargo test,
   go test, pytest. One per framework, declared as a TOML profile under `profiles/`. A language
   with no adapter reads `mutation: not_analysed` in the 1.3 analysis-coverage matrix.

## Arbitrated correctness constraints (non-negotiable)

Ruled by the arch-index roadmap guardian. Running only the tests that reach the mutated function
is an **exclusion**, and ⊤-bounded reachability cannot license an exclusion.

- **P1** — under ⊤-bounded selection a survivor is `UNKNOWN`, never `SURVIVED`. `SURVIVED` is
  admissible only when the executed selection was a **proved superset** of the reaching tests:
  a closed cone (no ⊤ edge in the test cone) or the full suite.
- **P2** — a dynamic proof of coverage (per-test LCOV) may only **add** tests to the selection,
  never remove any. No proof source wired in subtraction.
- **P3** — a kill is proof, a survivor is not (possibly an equivalent mutant). "Assumed
  non-equivalent" is a hypothesis for the 3.2 discharge ledger, never a report claim.
- **P4** — the site-identity key must be proved a key on the **largest** population (Octez), not
  a demo corpus. Under a `UNIQUE` constraint the probe counts **rejected rows**, not collisions.
  Precedent: a site key with 0 collisions on 37 demo rows and 1 150 on the 25 479 real ones.

## Guardian's reservations

- Do not write `bin/arch_rules/arch_rules.ml` (session arch-index-0e, verb 3.12), nor
  `lib/arch_tools/arch_sel.ml` / `arch_graph.ml` (PR #73 in re-review).
- Do not freeze the schema version: read it at implementation time, bump the minor by one, add a
  line to `docs/schema.md`. Three sessions are active; two have already collided on that constant.
- Never publish a zero without saying what would have made it non-zero.
- Beware a test whose pattern filters exactly what it should observe.
- Every measurement names the **population and the working tree**, not only the commit.

## Anchors from the read-only scan (to re-verify, not to trust)

- `bin/arch_mutants/arch_mutants.ml:122` — `let proof = escapes = [] && sound`, the admissibility
  predicate P1 needs; nothing consumes it as a verdict gate.
- `arch_mutants.ml:53` — `escapes` restricted to the test-reachable set.
- Status vocabulary at lines 25, 245, 347–349: `SURVIVED | KILLED | TIMEOUT | ERROR`, no `UNKNOWN`.
- `reaching` at lines 88–92 is `SS.inter (closure {key} g.bwd) test_keys`, a lower bound, used
  today as an exclusive run-set.

## Pilot and references

Campaign pilot on `~/dev/miaou` (28k source / 10k test lines, alcotest + bisect_ppx); Octez is the
population for the P4 key probe. Engine work (a typed OCaml planner, a mutaml fork for ppxlib and
the lib_protocol build-per-mutant mode) stays **outside** this repository.

Dedicated note: `~/notes/2026-09-05-mutation-campaign/plan.md`.
Roadmap: `~/notes/2026-09-01-arch-index-roadmap.md`, item 3.13.

## Build

```
eval "$(opam env --switch=/home/mathias/dev/arch-index --set-switch)"
dune build && dune test --force
```
