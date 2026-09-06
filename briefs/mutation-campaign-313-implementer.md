# Implementer sub-brief — mutation-campaign-313

**Date:** 2026-09-05T14:35:00+02:00
**Status: VALIDATED**

Self-contained. You are not assumed to have seen anything else in this session.

## Where you work

`/mnt/ssd-external-2to/arch-index-mutation-313`, branch `feat/mutation-campaign-313`, based on
`origin/main` at `879fedb`.

**Never write in `/home/mathias/dev/arch-index`.** Two other sessions own that checkout.
**Keep this worktree outside that checkout.** `tezt/lib/arch_tezt.ml`'s `locate` walks ancestor
directories from the working directory, so a worktree placed inside another checkout runs the
parent's binary. That binary is unmutated, so every mutant survives and the report becomes a page
of false test gaps that reads exactly like a real finding. `scripts/check-binary-provenance.sh`
enforces this; run it before trusting any campaign result.

**Three files must not be written**, at all, for any reason: `bin/arch_rules/arch_rules.ml`,
`lib/arch_tools/arch_sel.ml`, `lib/arch_tools/arch_graph.ml`. A step that seems to need one must be
re-cut, not negotiated.

```
eval "$(opam env --switch=/home/mathias/dev/arch-index --set-switch)"
dune build && dune test --force        # --force is required; dune caches aggressively
```

Measured baseline: **188/188 tezt cases, 0 failures**, full build, in this worktree, at commit
`2ca774b` on branch `feat/mutation-campaign-313` — *not* at `879fedb`, which is only the base this
branch sits on. That distinction is the point: a number attributed to the base is attributed to a
tree that does not contain the branch's own commits. Do not carry this number forward — re-measure
and say what you measured, naming the commit you measured at.

## Goal

Add the layer that **executes** a mutation campaign, on top of the static targeting already
shipped (`arch-mutants plan` / `report`, `arch-impact --diff`, `arch-coverage`). Today nothing runs
a campaign, nothing is persisted, and arch-index emits no verdict of its own about mutants.

The contract is `specs/mutation-campaign-313.md`. Read its counts from the file itself rather than
from this sentence — it has grown during planning and will grow again. Read it in full before writing code. The plan and its reasoning are
in `briefs/mutation-campaign-313-plan.md`; the operational facts inherited from the roadmap
guardian are in `roster/mutation-campaign-313/task.md`.

## The one idea the whole thing rests on

`lib/arch_tools/arch_graph.ml:99-113` routes a `MAY_TOP` edge into a separate frontier map and
never into the traversable adjacency maps — "never dropped, never traversed". So every backward
closure is a **lower bound** on the tests that reach a function. Running only that set is an
exclusion, and a lower bound cannot license an exclusion.

Every other verdict-reaching consumer in this repository already widens on ⊤ — `arch-rules` returns
`UNKNOWN` rather than `PASS`, `arch-query unreachable` likewise, `dead-code` degrades to
`candidate`, `pure-fns` widens the impure set, `may-fail` returns `UNBOUNDED (⊤)`, `arch-impact`
keeps a separate may-bucket, `arch-coverage` keeps `covered_via_top_only` distinct. **`arch-mutants`
is the only one that does not.** It filters the escapes to the test cone and describes them in
prose, and that prose reaches no verdict. You are applying the house rule to the one tool that
skipped it, not inventing a principle.

## Slices, in order

**Slice 1 — drive and persist one campaign, and measure the pilot.**
The schema DDL for the four tables lands in the **same commit** as the driver that writes them. No
DDL without a writer: a table nobody fills is not demoable and hides its own integration risk.

- `arch-mutants run <db> --plan <file> --engine <cmd> [--tests <selector>] [--profile <name>]`.
  Subcommand first, database positional — match the existing `plan` / `report` grammar.
- `--tests` must pass an explicit `~allow` to `Arch_sel.parse`, which takes it as a mandatory
  argument. Accept `file:`, `fn:`, `module:`; refuse `ext:` exactly as `plan` refuses it. A verb
  that does not declare its kinds inherits a default by omission — that is how `Dep` came to
  silently reinterpret its arguments.
- **The execution model, stated once so it cannot be read two ways.** The driver invokes the engine
  **once**. The engine loops over its own mutants internally — that is how mutaml and cargo-mutants
  both work, and the driver cannot change it. What runs **once per mutant** is a **wrapper** that
  the driver passes as the engine's test command. So: driver → engine (once) → wrapper (N times, one
  per mutant) → the selected tests. The per-mutant test set is a **superset** of the reaching set,
  never a subset, and the wrapper records the intended set and the executed set separately.
  Anything asserting "the engine was invoked twice for two mutants" is asserting the wrong thing:
  assert on the **wrapper's** invocations.
- **How the driver learns each mutant's outcome.** Not from stdout, and not from exit codes. The
  engine writes its own report file, and the driver ingests it through the adapters
  `arch-mutants report` already has — `--from mutaml` for `mutaml-report.json`, or the generic
  NDJSON contract documented at `bin/arch_mutants/arch_mutants.ml:25`. "Do not persist engine
  stdout" means do not store the raw text; the parsed outcome is exactly what `mutant_runs` holds.
- **How per-mutant selection works against mutaml**, established by reading its source rather than
  its README. The source is **mutaml itself**, not this repository: `https://github.com/jmid/mutaml`,
  cloned read-only at `/mnt/ssd-external-2to/mutaml-src` (commit `783831d`). There,
  `src/runner/runner.ml:123-130` runs, per mutant,
  `MUTAML_MUTANT=<mut_id> timeout <n> <test_cmd>`, and `src/ppx/mutaml_ppx.ml:40` shows the
  instrumented code reading that variable through `Sys.getenv_opt`. The test command is a single
  fixed string, so mutaml cannot vary the test set itself — but the driver passes a **wrapper** as
  that command, and the wrapper reads `MUTAML_MUTANT`, resolves the mutant to its reaching tests
  through the plan, and runs only those.
- Tables: `mutant_campaigns`, `mutants`, `mutant_runs`, `mutant_kills`. **Never a name starting with
  `mutation_`** — `functions.mutation_sites` is already taken and counts imperative state writes.
- `mutants` is UNIQUE on `(file_path, line, col_start, col_end, replacement, source_hash)`, with a
  nullable `function_id` so a mutant the index cannot map is persisted rather than dropped. Use
  `Digest.to_hex (Digest.string ...)` for the hash — the repository's existing idiom, at
  `lib/arch_index/arch_index_compare.ml:129`.
- **`mutant_runs` carries a `selection_provenance` column**, TEXT, NOT NULL, with a
  `CHECK(selection_provenance IN ('proved_superset','top_bounded','no_contract'))`. This is a
  **stored column**, not a derived condition: FR-010 requires it, FR-013 forbids any emitter from
  writing a status without it, and the OCaml consumer must match on it **totally**, with no
  catch-all, so the compiler fails if a fourth value is ever added.
- `mutant_kills` is UNIQUE on `(campaign_id, mutant_id, test_name)` and holds a row **only** when
  attribution is genuinely known: the executed set was a singleton, or the engine named the killer.
  Never infer attribution from a larger set.
- Read the schema version constant from `lib/arch_index/arch_index_db.ml` **at the moment you
  implement**, bump the minor by one from **what you read**, and add the row to `docs/schema.md`.
  It reads 1.10 today, and two pending PRs will take it to 1.11 — so if you read 1.11, you write
  1.12, not 1.11. The rule is read-then-bump, never a literal from any document including this one.
  Two sessions have already collided on this constant.
  A `%test` at `arch_index_db.ml:122-123` asserts it parses as `major.minor` — keep that shape.
- Exit 2, naming the engine and the profile, when the engine cannot be resolved. Write no campaign
  row in that case: an empty campaign must never read as "no survivors".

**Exit criterion — this is not a stub demo.** Run the campaign for real on a worktree of
`~/dev/miaou` (28k source / 10k test lines, alcotest + bisect_ppx) and report wall clock for the
naive path and for the selected path, naming the corpus, the commit, the build state and **how many
mutants the engine could actually build**. If selection is not cheaper, that is a finding to
report, not a failure to hide — alcotest addresses tests by group regex plus a numeric index, not
by exact case name, so a `group`-granularity profile re-runs a whole group per mutant and the cost
argument may not survive contact with it.

**Slice 2 — the published verdict is sound.**
`KILLED` or `TIMEOUT` → `KILLED`, regardless of provenance: a kill is a proof and the selection
does not weaken it. `ERROR` → `ERROR`. `SURVIVED` → `SURVIVED` only under `proved_superset`,
`UNKNOWN` under `top_bounded`, `UNKNOWN_NO_CONTRACT` when the index carries no soundness contract.
`proved_superset` requires **both** a closed cone and a contract — reuse the predicate already
computed at `bin/arch_mutants/arch_mutants.ml:122`, do not recompute it.

The verdict is **derived, never stored**. `PENDING` likewise: it is the absence of a run row in a
campaign whose completion timestamp is null. Storing it would mean widening a vocabulary closed to
four values that `arch_mutants.ml:348-349` depends on — that line buckets with
`if st = "KILLED" || st = "TIMEOUT" then killed else if st <> "SURVIVED" then errored else survivor`,
so any fifth value falls silently into `errored`.

**Slice 3 — diff-scoped selection.** `--diff <range>`, the union of mutants in touched functions
and mutants of everything a modified or added test reaches, plus the deleted-test rule.
**Shell out to `arch-impact --format json`** rather than extracting its mapping into a library: the
logic is binary-local at `bin/arch_impact/arch_impact.ml:72`, and extracting it is shared-library
surgery while three sessions are active. Confirm the JSON shape before depending on it.

**Slice 4 — the per-added-test defect verdict.** Three buckets, never one: a test whose attempted
reachable mutants all published `SURVIVED` is a defect; one whose mutants all published `UNKNOWN`
is unproven, not defective; one reaching no indexed function is neither. When the defect list is
empty, say how many tests were examined and what would have put one on it.

**Slice 5 — test-invocation profiles.** A loader for `<name>-tests.toml` with its **own**
discovery — do not generalise `discover_profile` at `lib/arch_index/arch_index.ml:105`, which
hardcodes both the `-errors.toml` suffix and its environment variable and has a live precedence
test another session may own. A profile missing `granularity` aborts with exit 2 naming the file
and the key; it is never silently defaulted.

## Things that are easy to get wrong

- **A green campaign proves nothing.** A campaign containing at least one kill self-certifies,
  because a stale binary is unmutated and cannot produce a kill. The contrapositive is what matters:
  an entirely green campaign cannot distinguish a weak suite from the wrong binary having run. And a
  campaign that is all `ERROR` also has zero kills, for a different reason, and must not be
  described in the same words.
- **Do not reuse the `GROUP BY … HAVING count(*) > 1` probe** at
  `bin/arch_body_compare/arch_body_compare.ml:82` for the key check. Under a UNIQUE constraint a
  duplicate never becomes a group — it becomes a rejected insert. Count rejects.
- **A key can be perfectly discriminating and still measure a fabricated population.** Before
  reporting a key probe, say what the population is made of, not only how it was counted.
- **Every number names its corpus, its commit and its build state.** One quantity was derived three
  times in a day at 78.5 %, 6.7 % and 3.1 %, all three correct, because the rate measured which
  units had been compiled.
- **Never publish a zero without saying what would have made it non-zero.**
- **A value added to a closed vocabulary is dropped with no error at all.** Not a crash, not a log —
  a smaller answer. Use a **total** match, never `| _ ->`, wherever a schema `CHECK` declares the
  set, so the compiler fails on the next addition. Measured precedents here: `top_reason =
  'ambiguous_unit'` arrived at schema 1.9, `form = 'inferred_bind'` at 1.8. Where the filter must be
  SQL, grep for the **members**, never for the column name.
- **Exit code 3 from a subprocess means refused, not failed.** `Arch_db.ok` is being changed to
  return 3 on a missing column, so "did not really run" arrives as its own code. Propagate it;
  never fold it into a failure or into an empty result.
- **Never emit a mutation score, ratio, percentage or threshold.** `docs/mutation-testing.md`
  refuses it on record.

## Guard scripts you must create

The spec names six guard scripts. **Two exist and pass today**:
`scripts/check-quint-red.sh` and `scripts/check-binary-provenance.sh`. **Four do not exist and are
yours to write**, each in the slice that needs it:

| Script | Slice | What it must do |
|---|---|---|
| `scripts/check-status-provenance.sh` | 2 | Grep every emitter under `bin/arch_mutants/` for a status field written without a provenance field in the same record. Exit 1 on any hit. |
| `scripts/check-mutant-key.sh` | 1 | Insert the campaign's mutants and report the count of rows **rejected** by the UNIQUE constraint. Never a `GROUP BY`. Print the population size and what it is made of. |
| `scripts/check-mutaml-integration.sh` | 1 | Run a real `mutaml-runner` over a two-function fixture and assert the wrapper resolved `MUTAML_MUTANT` to the right test set. Exit **3**, not 1, when mutaml is absent. |
| `scripts/check-total-matches.sh` | 2 | Grep the campaign's consumers for a `\| _ ->` arm on any vocabulary a schema `CHECK` declares. Fail naming the site. |

Each follows the exit convention 0 = passes, 1 = assertion fired, ≥2 = error, and each is
self-contained rather than relying on a test runner's exit codes.

## Standing gates, run from day one

`scripts/check-quint-red.sh` (6/6 mutations caught) and `scripts/check-binary-provenance.sh`
(red-verified on both branches) already exist and already pass. Keep them passing. When you add a
Quint invariant, add its mutation to the red harness in the same commit — a `sed` that matches
nothing counts as a failure there, so a stale mutation cannot pass for a green check.

Each of CHECK-4's three arms must be proved reachable by its own fixture and red-verified
separately: removing the expected verdict from **one** arm must fail that arm and no other.

## Not yours

No mutation engine. No mutant generation, no source rewriting, no build invocation from inside this
repository. No equivalent-mutant detection. No push, no pull request — this repository is public
and only Mathias authorises that.
