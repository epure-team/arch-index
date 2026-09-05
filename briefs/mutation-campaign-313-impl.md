# Implementation Brief — mutation-campaign-313

**Date:** 2026-09-05T16:40:00+02:00
**Mode:** full (critical route)
**Status:** COMPLETED **for a re-scoped deliverable.** Mathias re-sequenced the work on
2026-09-05: ship slices 1 to 3 plus FR-034 first, then run the miaou pilot and build slices 4 and
5 on top of the merged base. This brief therefore covers slices 1, 2 and 3 plus the FR-034
refusal, and both the pilot and slices 4–5 are **out of this deliverable's scope by instruction**,
not left undone.

**What that means for the reader, stated because it is easy to lose:** the campaign mechanism is
established by reading the engine's source and has **never been observed running**.
`scripts/check-mutaml-integration.sh` returns 3 — unverified — and that must not be read as
covered. The pilot measurement that would change this comes after merge.

The earlier `implement/PARTIAL` event stays in the ledger. It was correct when written, and the
append-only history is the record of the re-scoping rather than a contradiction of it.

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

Re-measured at branch commit `c5ce100`, full build, opam switch
`/home/mathias/dev/arch-index`:

- Build: `dune build` → exit 0 ✅
- Tests: **217 of 217 cases executed, 216 SUCCESS, 1 FAILURE.** The single failure is the
  MUST-with-NULL-callee ceiling at 373 against 372, with `calls=17551` on the same log line. It
  is main's undeclared drift, not this branch's rows, and #83 clears it.

  **The count required `--keep-going`, and that is not a detail.** `dune test --force` stops at
  the first failure: it reported exit 1 having run **156 of 217** cases, leaving 61 unexecuted
  with nothing in the output saying so. Only
  `./_build/default/tezt/tests/main.exe --keep-going` produced the full 217. The defect is
  asymmetric — a green run is unaffected, because nothing stopped it — so a **red** run from the
  standard gate reports a lower bound on failures and says nothing about how many cases never
  ran. Carried to the roadmap session as a repo-wide gate finding; it is not a 3.13 item and does
  not travel on this branch.

**An earlier figure in this section is withdrawn, not corrected.** It read
"`dune test --force` → 193 SUCCESS, 0 FAILURE (baseline 188, five new)", measured at `ec5f23b`.
That commit is a pre-rebase revision on neither `main` nor this branch, and `main` gained 42
commits between it and `ba2804a`, absorbed by the rebase. So 193 and 217 are not comparable and
the growth is main's, not this branch's. It is withdrawn with its commit and its reason rather
than restated, because a corrected number invites the same comparison a second time.
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

---

# Round 2 — the review's nine HIGH findings

**Date:** 2026-09-06T00:18:45+02:00 · **Status: COMPLETED** · Base `4e74c72`, HEAD `8ab712d`.

Round 1 returned NO-GO on 9 HIGH. All nine are fixed. Each fix was accepted only because the
positive control that exposed the defect turns the repaired code red — a fix whose control was
not re-run is not a fix, and three of these findings were themselves gates that had been reported
green all day on their exit codes alone.

## Ratchet

Every HIGH finding carries a **new, self-contained** check under `checks/`, directly runnable and
honouring the convention `0 = passes · 1 = assertion fired · ≥2 = error`. Modifying an existing
assertion would not have satisfied the ratchet. Each was proven red by restoring its own target
from HEAD into a copy — **`git stash` was never used**, on any of them.

| Finding | Check | Red command | Proven red |
|---|---|---|---|
| `check-no-score.sh` scanned 789 of 2215 lines — `count(*)` in a SQL string opened a phantom OCaml comment | `checks/no-score-scans-sql-strings.sh` (CHECK-21) | `bash checks/no-score-scans-sql-strings.sh` | exit 1 with the guard restored from HEAD; the reverted guard reported `inspected 11 line(s)` while passing |
| `check-status-provenance.sh` judged the file, not the enclosing record | `checks/status-provenance-per-record.sh` (CHECK-22) | ditto | exit 1; the reverted guard reported `1 JSON record(s)` and PASS |
| `check-binary-provenance.sh` probed four hardcoded paths and never invoked the driver | `checks/binary-provenance-invokes-driver.sh` (CHECK-23) | ditto | exit 1; the reverted guard printed `0 of 1 resolved binaries lie outside the tree` without invoking a driver |
| a wrapper refusal (`exit 2`) was read by the engine as a clean KILL | `checks/wrapper-refusal-not-a-kill.sh` (CHECK-24) | ditto | exit 1: `expected "status":99, got "status":2` and `a refusal is not a kill — expected 0, got 1` |
| a trace-less mutant had its PLANNED set recorded as executed, and could receive a kill attribution | `checks/unobserved-executed-set-is-not-an-attribution.sh` (CHECK-25) | ditto | exit 1 on three assertions, incl. `t_gamma is never named as a killer — got t_gamma` |
| FR-030/AC-24 unimplemented: both resolvers walked ancestors with no tree boundary | `checks/tree-boundary-refusal.sh` (CHECK-26) | ditto | exit 1 on probe 1 (refusal from a subdirectory) while probes 2 and 3 stayed green — which is what makes probe 1 attributable |
| `report` published survivors with no provenance and gated CI on them | `checks/report-survivor-carries-its-provenance.sh` (CHECK-27) | ditto | exit 1, 9 assertions fired; the negative control (`--fail-on-survivors` *does* fire on a proved survivor) stayed green |
| `prior_mutants` read a status without its provenance | `checks/prior-status-read-with-its-provenance.sh` (CHECK-28) | ditto | exit 1: `a ⊤-bounded survivor is UN-RECHECKABLE, a proved one is not`; the other five assertions stayed green |
| `load_generic` accepted any status string; `report` bucketed the rest as errors | `checks/generic-status-vocabulary-is-closed.sh` (CHECK-29) | ditto | exit 1: `a misspelled status aborts rather than being counted — expected 2, got 0` |

`checks/mid-caller-shadow-attribution.js` is **main's**, not this branch's.

**All nine executed at `8ab712d`: exit 0.** `checks/` was added to the file manifest for this round.

## Decisions taken on a measurement, not a preference

**The two never-populated columns were DELETED, and the probe is why.** `mutants.function_id` and
`mutant_campaigns.producer_run_id` were passed `None` unconditionally by the only writer.
Populating them requires `PRAGMA foreign_keys = ON`; with the pragma on, an INSERT into `mutants`
against a **flat** index fails with `foreign key mismatch` **even binding NULL**, because
`arch-load`'s `functions` table has no `id` column, and `producer_runs` does not exist there at
all. So the columns cannot work on half this tool's inputs. Removed with their index and the EC-4
paragraph that documented a transition no run could produce. The pragma is now enabled, and it is
meaningful *because* every remaining foreign key points at a table this migration creates.

**The wrapper's refusal is a reserved exit code, not a side channel.** The review proposed a
parallel trace file. Reading mutaml 0.3's source showed `save_test_outcome` persists
`{ status = ret }` with `status : int` — the raw exit code; `passed`/`failed` are printed only.
Verified at runtime: `mutaml-runner` **printed** `Testing mutant lib_x:1 ... failed` while
**writing** `{"status":99}`. The label and the persisted integer disagreeing is the gap the old
adapter fell into, and the fix is one equality in the adapter rather than a new channel.

## Quality gates, measured at `8ab712d`

- `dune build` → exit 0
- `./_build/default/tezt/tests/main.exe --keep-going` → **243 of 243 executed, 243 SUCCESS, 0
  FAILURE**. `dune test --force` was NOT used: it aborts at the first failure, and reported 156 of
  217 earlier in this task while 61 cases never ran.
- ratchet: **403 against a ceiling of 428**, published although it passes. `clean_measured` moved
  383 → 403 in this branch, attributed 12 inert + 8 signal-carrying, measured by indexing both
  trees rather than counting a diff.
- `scripts/check-mutaml-integration.sh` → **exit 3, still UNVERIFIED**, now with a real mutaml 0.3
  installed: its own fixture cannot drive the real runner, which wants `.muts` files from a
  ppx-instrumented build. The campaign mechanism has still never been observed end to end.

## Identified out-of-scope

`mutant_runs.executed_tests` records what the wrapper **intended** to run, not what ran — under a
first-failure runner some of the N never execute. It compounds with the review's LOW finding that
`executed_superset` compares lengths instead of testing inclusion: **a reader who fixes only the
comparison will believe the item closed, and it will not be.** Filed as its own slice, not folded
in here. Slices 4 and 5 remain deferred by instruction and are now marked so in the spec.


## A note on this file's own timestamps

**Every hand-written date in this brief was unreliable, and one was in the future.** The round-1
re-measurement was recorded as happening "on 2026-09-06T02:55:00+02:00"; the commit carrying that
sentence was made at **2026-09-06T00:04:26+02:00** — the stated time was 2h51m ahead of the writing
of it. The dates are now either generated or omitted, and the commit sha is left to carry the
"when", since it is the value with a mechanism behind it.

This surfaced from a ledger anomaly worth recording rather than smoothing. `implement/COMPLETED`
carried 22:00 while `review/NO-GO` carried 21:55, so the array order and the timestamps disagreed.
I first called that clerical — which silently trusted the hand-written value and discarded the
generated one, the opposite of what the evidence supports. **Settled by measurement rather than by
preference:** the review's own generated date is 21:54:37 and its `reviewed_sha` `91e95b6` was
committed at 21:33:08, twenty-one minutes earlier and as the tip; no commit on this branch carries
a timestamp between 21:55 and 22:05. So nothing landed between the review and the implement event's
claimed time, and **the review is not stale by construction** — its findings describe the tree that
round 2 then fixed. The conclusion was right; the reasoning that first reached it was not, and the
other reading (a review closing over an object that had not stopped changing) would have meant the
round-2 gate closing on findings unattributable to the code that now exists.

**Measured, so the class is settled: the hand-written stamps are NOT recoverable.** Deltas against
each stamp's own commit **author** date: `+300, +27, +22, +3, 0, −36, −36, −45, −57` minutes.
Median 0, no cluster at +2h — so not a timezone error, and not timezone-plus-drafting-lag either.
The mechanism is plainer and less repairable: **every hand-written stamp is a round number**,
seconds at `00` and minutes on a multiple of five. Nobody read a clock; a plausible time was typed.
The only zero delta is the one generated above.

**Consequence for `briefs/<task>-state.json`, stated here because the next reader will reach for
those fields exactly when they need a timeline:** the ledger keeps its standing as an *ordered
record* — the event order was never in doubt and the shas carry it — but it has **no standing as a
chronology**. Its early `at` values are hand-written the same way. Sorting the events by time
yields fiction; read the order, and take the "when" from the commit.

**A first attempt at this measurement was wrong and is retracted.** It compared against `%cI` and
returned nine identical values — `00:04:26` across nine briefs written over twelve hours. **A
rebase rewrites every commit date to its own**, so the instrument was reporting the rebase rather
than the work; `%aI` is the one that survives. The tell was the uniformity itself: nine
independently written documents do not share a commit second. That is the third instrument in this
task to return a plausible answer while measuring something adjacent to the question — after a
registration count blind to suffixed forms, and a whole-file deletion check blind to deletions
inside surviving files. **A value too uniform for its population is the signature.**
