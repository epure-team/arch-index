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

## Operational facts inherited from the roadmap guardian (2026-09-05, post-spec)

Recorded here so the implementation phase inherits them rather than rediscovering them.

**Base moved.** The branch was rebased from `70cb47f` onto `2ac80eb`. Baseline re-verified on the
new base in this worktree: build clean, **165/165** tezt cases pass (was 163/163 — the `ext:`
selector work added two), Quint invariants green over 20 000 samples.

**`Arch_sel.parse` now takes a MANDATORY `~allow`.** Any new verb or command must declare
explicitly which selector kinds it can serve. A verb that does not declare them inherits the
default by omission — that is exactly how `Dep` was silently reinterpreting
`forbid dep from fn:foo to file:bar`. `arch-mutants run` will accept `--tests <selector>`, so it
must pass an explicit `~allow`.

**Issue #77 — the hazard that would make every mutant read as a survivor.**
`tezt/lib/arch_tezt.ml`'s `locate` walks ancestor directories from `Sys.getcwd ()` to find a
binary. A worktree whose `_build` is incomplete therefore runs the **parent checkout's** binary
instead, silently. For a mutation campaign that failure is maximally bad: the stale binary is
unmutated, so every mutant survives and the report is a page of false test gaps.

Verified empirically in this worktree rather than assumed: walking every ancestor of
`/mnt/ssd-external-2to/arch-index-mutation-313` finds exactly one `arch_mutants.exe`, its own.
Nothing under `/home/mathias/dev` is reachable upwards from here. **Keep the worktree outside the
checkout for this reason.** Setting `ARCH_MUTANTS` explicitly is the belt-and-braces override,
since `locate` prefers the environment variable and fails loudly when it points at nothing.

**A run containing at least one RED self-certifies its greens.** A stale binary cannot turn red,
so any suite that produced a genuine failure was running the code under test. The prove-red
harness satisfies this by construction: `scripts/check-quint-red.sh` reports 6 reds and 0
survivors, and its first run reported 1 survivor out of 5 — both runs self-certify.

**Every published number names its corpus, its commit AND its build state.** The same quantity was
derived three times in one day at 78.5 %, 6.7 % and 3.1 % — a factor of 25, all three correct,
because the rate measured which units had been *compiled*. Scope is not metadata here, it is the
result. This applies directly to CHECK-9's key probe and to any campaign count.

## Incoming changes and a key-identity precedent (2026-09-05, guardian pre-notice)

**The schema version will move under this branch before implementation.** Two converged PRs land
the main schema at 1.11 and the flat schema at 1.3. This is why FR-009 says to read the constant
at implementation time rather than carry a number from the spec: between writing this spec and
implementing it, the base moves twice, and three sessions are active on the repository. Protocol
after two recorded collisions: read the base, bump the minor by one, add the row to
`docs/schema.md`.

**`#76` (SARIF out) also lands on main**, bringing `arch-rules --format sarif`, a new
`lib/arch_tools/arch_sarif.ml`, and the mandatory `~allow` on `Arch_sel.parse`.

**`#77` fix is in progress.** Until it ships, keeping this worktree outside the main checkout is
load-bearing, not hygiene — see the previous section for why a stale binary is the worst possible
failure for a mutation campaign specifically.

**RETRACTED, 2026-09-05 — the 3.14 precedent as first recorded here was wrong in both halves,
and the corrected version is more useful.** It was recorded as: on the `option` channel ~28 500
origins share one identity string, therefore the grouping probe must yield to a reject count. The
investigation, once finished, refuted both claims.

- **The grouping probe is valid there.** `exn_origins` has an autoincrement primary key and **no**
  UNIQUE constraint, a single non-unique index, a plain `INSERT INTO` with no `OR IGNORE`, and no
  deduplication on the write path. So `GROUP BY … HAVING count(*) > 1` measures the data there, not
  the schema, and a reject count is unnecessary. The reject-count rule still applies to **our own**
  `mutants` table, because we are the ones declaring a UNIQUE constraint on it — but it is a
  consequence of our schema choice, not a general law.
- **The identity is not globally degenerate.** It is degenerate *within* a function: 2 158 distinct
  identities over 27 182 rows, one per function, because every `None` in a function collapses onto
  the same string. A key that includes the function is not ruined; it loses all resolution *below*
  the function.

**The precedent worth keeping is a different one, and it is sharper.** `line = 0` there is neither
a lost position nor a sentinel: it is the compiler saying the node has no source, because the
walker records an origin for every **omitted optional argument** — the `None` values the
type-checker synthesises. Attribution 100 %, zero residue, on two corpora. So roughly 94 % of that
population is **fabricated by the producer**, and a collision rate computed over it would be a
correct number describing an artefact rather than the system.

**Consequence for CHECK-9.** A key can be perfectly discriminating and still measure a fabricated
population. Before measuring a key, ask **what the population is made of**, not only how it is
counted. The campaign's own analogue is direct: a survivor count means nothing without saying which
mutants the engine could actually build, and a key probe means nothing without saying which rows
are real sites rather than producer artefacts. This is the same discipline as naming the build
state, applied one level further in.

**Every published number names its corpus, its commit AND its `.cmt` count.** Three derivations of
one quantity in a single day gave 78.5 %, 6.7 % and 3.1 % — a factor of 25, all three correct,
because the rate measured which units had been compiled. A number that names only its tree can be
neither reproduced nor contradicted.

## Known residual after slice 2 — the surviving `if`-chain in `report`

`bin/arch_mutants/arch_mutants.ml`'s `report` buckets the engine's file-based statuses with
`if st = "KILLED" || st = "TIMEOUT" then killed else if st <> "SURVIVED" then errored else survivor`.
That is exactly the silent-fifth-value hazard FR-031 describes, and the spec cites this very line as
the *reason* PENDING must not be stored — while leaving it in place.

It was deliberately not changed in slice 2, and the reason is worth recording rather than
rediscovering. It is an `if`-chain over the **engine's report file**, not a match over a schema
`CHECK`, so `scripts/check-total-matches.sh` correctly does not flag it. Rewriting it would change
`report`'s behaviour for an unknown status from "counted as errored" to "abort" — a behavioural
change to a shipped command, outside slice 2's scope and outside this item's brief.

The residual is therefore: **the campaign consumers are total, the file-based `report` path is not.**
Whoever changes it owns the behavioural change, and should note that "counted as errored" is not
obviously worse than "abort" for a path whose input is a third-party file.
