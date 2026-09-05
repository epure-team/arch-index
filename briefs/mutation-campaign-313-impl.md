# Implementation Brief — mutation-campaign-313

**Date:** 2026-09-05T16:40:00+02:00
**Mode:** full (critical route)
**Status:** PARTIAL — slice 1's code is complete and verified, but the slice's stated **exit
criterion**, a measured campaign over `~/dev/miaou`, was not run. It needs a real engine, and
installing one needs a dedicated opam switch that only Mathias can authorise. The driver has been
exercised against stub engines and one faithful stand-in, never against a real mutaml.

Slices 2 to 5 are untouched, as scoped.

## Modified files

| File | Type of change | Reason |
|---|---|---|
| `mutants-schema-migration.sql` | addition | The four tables. Every statement `IF NOT EXISTS`, additive header, verified re-runnable. |
| `bin/arch_mutants/arch_mutant_db.ml` | addition | The only read-write path — `Arch_db.open_ro` is read-only. DDL is the migration text embedded through `ppx_blob`, so there is one text and no hand-copied `CREATE TABLE` to drift from it. |
| `bin/arch_mutants/arch_mutants.ml` | modification | `run` and its driver. `cone_escapes` was **extracted out of `plan`** so `run` shares the same binding rather than a second copy of the fold — the duplicate-call-site problem this campaign was itself created to notice. |
| `bin/arch_mutants/dune` | modification | `sqlite3`, `unix`, `ppx_blob`, and the preprocessor dependency on the migration. |
| `lib/arch_index/arch_index_db.ml` | modification | `current_schema_version` `1.10` → **`1.13`**. |
| `docs/schema.md` | modification | `1.11` and `1.12` recorded as burned, `1.13` for the four tables. |
| `tezt/tests/mutants.ml`, `tezt/tests/main.ml` | modification | Five new cases, existing registration pattern, `Fixture.flat` reused. |
| `scripts/mutaml-wrapper.sh` | addition | The per-mutant test command. Reads `MUTAML_MUTANT`, resolves it through the driver-written selection table, runs only those tests. **Refuses (exit 2) on an unset or uncatalogued mutant** rather than falling back to the whole suite — a fallback would silently turn a selection bug into a passing campaign. |
| `scripts/check-mutant-key.sh` | addition | Counts rows **rejected** by the UNIQUE constraint, never a `GROUP BY`. |
| `scripts/check-mutaml-integration.sh` | addition | Exit **3** when mutaml is absent. |

## Decisions made

**The schema version moved twice during this slice, and neither move was a mistake.** It was read
as `1.10`, so `1.11` was written. A branch in flight already held `1.11`, so `1.12`. Forty minutes
later a second branch was found holding `1.12`, so `1.13`. Both collisions came from two honest
sessions reading the same base and deducing the same next number. **The protocol's blind spot is
that a branch freezes the number when it is written and it is only confirmed at merge**, and this
branch is additionally invisible to any sweep because it is not pushed — the push authorisation is
Mathias's alone. Numbers are now assigned by the roadmap session rather than deduced. Both burned
numbers are documented next to the gap, stating the durable consequence rather than the transient
state of a branch: if the claiming branch never lands, the number is a hole like `1.6`, and a later
reuse would be a superset numbered beneath `1.13`.

**Three files were touched outside the manifest**, all necessary and none silently absorbed:
`bin/arch_mutants/arch_mutant_db.ml` (the new module), `bin/arch_mutants/dune` (its build stanza)
and `tezt/tests/main.ml` (test registration). The manifest was amended. Recording this is the
point: a scope gate that quietly widens is not a gate.

**Deviation from the sub-brief's grammar, and it was necessary.** The brief fixed
`run <db> --plan <file> --engine <cmd>`, but `plan` emits **targets** — functions with spans — not
mutants. Nothing in that grammar can tell the wrapper what a mutant identifier refers to, and
nothing names the engine's report file or the underlying test command. Four flags were added, all
**refusing rather than defaulting** where a guess would be load-bearing: `--catalogue` (the
engine's own mutant list, and the only place a mutant's file, line, column span and replacement
exist), `--report`, `--test-cmd`, `--from`. This is a real gap in the spec, not an implementer's
preference.

**"Group" was undefined anywhere.** It is implemented as the test's own source file, the closest
honest analogue of alcotest's group addressing. Flagged for a second opinion before slice 5
hardens it.

**FR-030's scope was ambiguous and was deliberately narrowed.** "Refuse a binary resolved outside
the working tree" cannot apply to the engine or the test runner — `mutaml-runner` legitimately
lives in an opam switch. It was applied to the wrapper only, both resolved paths are recorded per
FR-028, and the tree-boundary gate stays with `scripts/check-binary-provenance.sh`. If FR-030 was
meant to fire inside the driver too, that is a gap flagged rather than closed quietly.

## Quality Gates

Measured in this worktree at branch commit `ec5f23b` plus the uncommitted work, full build, opam
switch `/home/mathias/dev/arch-index`:

- Build: `dune build` → exit 0 ✅
- Tests: `dune test --force` → **193 SUCCESS, 0 FAILURE** ✅ (baseline 188, five new)
- Format: not documented for this project — no `.ocamlformat`, no `ocamlformat` in the switch. No
  gate to satisfy and none to break; not invented.
- `scripts/check-quint-red.sh` → 6/6 mutations caught ✅
- `scripts/check-binary-provenance.sh` → exit 0, 0 of 4 resolved binaries outside the tree ✅
- `scripts/check-mutant-key.sh` → **exit 2 with no argument**, which is correct: no database here
  carries a `mutants` table yet, and it says so — *nothing was measured, so nothing is asserted*.
  It returns 0 against a populated campaign database.
- `scripts/check-mutaml-integration.sh` → **exit 3**: mutaml is absent, so the integration is
  **unverified**. Per AC-20 that is the correct outcome and it must not be read as covered.

**Prove-red, one mutation at a time**, each restored and re-verified: five mutations in the driver
each turned exactly one new test red and left the others unchanged. `check-mutant-key.sh` was
red-proved by removing the `UNIQUE` line from the migration. `check-mutaml-integration.sh` had both
paths exercised through a stand-in reproducing the real runner's per-mutant loop — which proves the
script's assertions are reachable, and is **not** a verification against real mutaml.

**Assertion hygiene.** Two spots were rewritten after the "haystack already contains the needle"
case found elsewhere the same day. Self-certification is asserted on a computed **tag** plus
hand-counted per-status numbers, never on a word in the prose, because a word in a legend cannot be
distinguished from a word produced by detection. The missing-engine test asserts exit 2 **and** that
`mutant_campaigns` does not exist in `sqlite_master` — a fact no wording can simulate. One
hand-count was wrong on the first attempt and the test caught it, which is what a hand-counted
assertion is for.

## Points of attention for review

- The four added flags are a deviation from the sub-brief's stated grammar. Judge whether
  `--catalogue` is the right shape, since it carries the mutant site identity the whole `mutants`
  table depends on.
- "Group" as the test's source file is a definition invented here.
- The FR-030 narrowing is a deliberate gap, not an oversight.
- `check-mutaml-integration.sh` returning 3 means the core mechanism is **unverified at runtime**.
  It was established by reading the engine's source; it has not been observed working.

## Identified out-of-scope

- `arch_mutants.ml` had the reaching-test lower bound at two call sites. `cone_escapes` was
  extracted because `run` needed it, which removes one duplication; the `reaching` duplication
  between `plan` and `report` remains and belongs to slice 2.
- No mutation score, ratio or threshold anywhere, per `docs/mutation-testing.md`.
