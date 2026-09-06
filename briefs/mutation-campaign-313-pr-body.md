# Roadmap 3.13 — the executed mutation campaign

Adds the layer that **executes** a mutation campaign, on top of the static targeting arch-index
already had. Before this, `arch-mutants` could say which functions were worth mutating and which
tests reached each one, and could attribute a survivor reported by an external engine — but nothing
ran a campaign, nothing was persisted, and arch-index emitted no verdict of its own about mutants.

Roadmap item 3.13. Spec: `specs/mutation-campaign-313.md`. Formal model:
`specs/mutation-campaign-313.qnt`.

## The one idea it rests on

`lib/arch_tools/arch_graph.ml` routes a `MAY_TOP` edge into a separate frontier map and never into
the traversable adjacency maps — "never dropped, never traversed". So **every backward closure is a
lower bound** on the tests that reach a function. Running only that set is an *exclusion*, and a
lower bound cannot license an exclusion.

Research established that every other verdict-reaching consumer in this repository already widens
on ⊤ — `arch-rules` returns `UNKNOWN` rather than `PASS`, `arch-query unreachable` likewise,
`dead-code` degrades to `candidate`, `pure-fns` widens the impure set, `may-fail` returns
`UNBOUNDED (⊤)`, `arch-impact` keeps a separate may-bucket, `arch-coverage` keeps
`covered_via_top_only` distinct. **`arch-mutants` was the only one that did not.** So this is the
house rule applied to the one tool that had skipped it, not a new principle.

## What lands

- **Four tables** (`mutant_campaigns`, `mutants`, `mutant_runs`, `mutant_kills`) in an additive
  migration, shipped **in the same commit as the driver that writes them** — no DDL without a
  writer. Schema `1.13`; `1.11` is main's, `1.12` is claimed by an open branch, and the reason for
  the gap is recorded next to it.
- **`arch-mutants run`** — invokes the engine once, and passes a **wrapper** as the engine's test
  command. The engine loops internally; the wrapper runs once per mutant, reads `MUTAML_MUTANT`,
  and resolves that mutant to its reaching tests. Established by reading mutaml's own runner and
  ppx, not its README.
- **`arch-mutants verdict`** — the published verdict, **derived and never stored**: `KILLED` or
  `TIMEOUT` publish as killed whatever the provenance, because a kill is a proof; `SURVIVED`
  publishes as `SURVIVED`, `UNKNOWN` or `UNKNOWN_NO_CONTRACT` according to how the selection was
  obtained; and `PENDING` is the *absence* of a run row in an open campaign. A test asserts no
  verdict column exists in the schema.
- **`run --diff <range>`** — selection scoped to a diff in both directions: mutants of touched
  functions, mutants of everything a modified or added test reaches, and for a deleted test the
  mutants it alone killed — with the honest half shipped alongside, every mutant whose attribution
  was never known reported as un-recheckable rather than silently skipped.
- **A refusal rather than a wrong answer.** No table records which sites a campaign catalogued, so
  on a database holding two campaigns an open one would report the *other's* sites as pending. The
  verdict surface exits 3 — refused, not failed — and names what would make it answerable.
- **Five guard scripts**, each red-verified on its own injection: the Quint red harness, binary
  provenance, status-without-provenance, catch-all match arms, and no-score.

**The gate that carries the weight is `scripts/check-quint-red.sh`, and it is worth saying why.**
A typecheck, a 20 000-sample invariant run and an Apalache temporal check all prove that the
checker executed. **None of them proves the invariants can fail** — a model asserting `true` would
produce the same three greens. Only the red harness does, by injecting one defect at a time and
requiring a *named* invariant to go red for each. On its first execution it found one invariant
**tautological**: it related the published verdict to a derived value the publication function ties
together by construction, so it could not fail whatever the code did. It was rewritten over the
primitive state before it could ship green and empty. Every check in this PR that reports zero has
been shown capable of reporting non-zero, and a `sed` matching nothing is reported as a failure
rather than a pass, so a stale mutation cannot masquerade as a caught one.

## The campaign, executed — and what it says about the design

It ran. Corpus: `miaou`, `src/` entire — 392 `.ml` files, 64 661 lines, 6169 indexed
functions, 1124 test roots. Engine mutaml 0.3, profile `group`, runner `alcotest`.

```
full-selected.db   4976 catalogued · 4931 runs → 772 KILLED, 4159 SURVIVED
```

`arch-mutants verdict` on the 76-mutant pair publishes **KILLED 60, SURVIVED 0,
UNKNOWN 15, UNKNOWN_NO_CONTRACT 0, PENDING 1**, and prints its own falsifier without
being asked:

> 0 published SURVIVED. What would have made it non-zero: a mutant the engine reported
> SURVIVED whose selection provenance is `proved_superset` — a bounded selection publishes
> UNKNOWN instead, on purpose.

**Read that number as a result about the design, not about the implementation.** Every
one of the 4931 runs carries `selection_provenance = top_bounded`; not one is
`proved_superset`. So the tool answers *I cannot tell* about its entire population and
publishes no survivor at all. The alternative — publishing 4159 survivors — is exactly
the false confidence the ⊤ machinery exists to refuse. The soundness rule works. Its cost
is now visible for the first time, on real code.

The same shape has been reached independently in this repository on roadmap 3.1, with a
different tool and different corpora: at 54.4% / 59.5% unresolved edges no cone is ⊤-free,
so every generated rule lands on `UNKNOWN`. Two tools, two corpora, both correctly
reporting that they cannot tell. That suggests **the product is the named frontier — the
`top_bounded` provenance itself — rather than the verdict.**

### Three things the execution found that six review rounds could not

None of these is visible in a diff. All three appeared within twenty minutes of the first
real run.

1. **The provenance is computed once per campaign, not once per mutant.** `cone_escapes`
   (`bin/arch_mutants/arch_mutants.ml:121`) takes the whole test cone and
   `selection_provenance` (:139) derives one value, applied to every row — hence
   `top_bounded` on 4931 of 4931. It is one measurement broadcast 4931 times, not 4931
   verdicts. On this corpus **358 ⊤ escapes against 6169 indexed functions, 5.8%**, nullify
   100% of the output. Soundness for a given mutant depends only on its own backward cone;
   nothing in the rule requires the global reading, only its granularity does.

2. **Half the population is vacuous.** 2500 of the 4931 runs have `intended_tests = 0` and
   `executed_tests = 0` — mutants in code the test cone never reaches (`unreached: 3668`).
   A SURVIVED where no test ran is not a test gap. The campaign agent reached the same 2500
   by a different route ("sites mapping to no indexed function"). **The actionable
   population is 1659, not 4159**, and this record previously said 4159.

3. **The A/B compared nothing.** `ab-naive.db` and `ab-selected.db` have an identical md5
   over every run row, and both carry profile `group` in `mutant_campaigns`, 48 seconds
   apart. The same configuration ran twice. The naive arm of the full campaign has 0 runs.
   **There is no wall-clock naive-vs-selected measurement in this branch** — the 60/15 pair
   quoted above is one configuration, not a comparison.

## What this does NOT establish

**The three blockers above are unfixed on this branch.** The campaign establishes that the
machinery executes on real code and that the ⊤ rule holds; it does not establish that the
capability produces an exploitable answer. On this corpus it produces none.
`scripts/check-mutaml-integration.sh` still returns **3**.

Formal evidence tier is **E0m-abstract**: the model's invariants are verified by checkers re-run at
the gate (typecheck, a 20 000-sample invariant run, an Apalache temporal check, and a red harness
catching 6 of 6 injected defects), but **nothing in this repository is wired to
`ocaml-quint-connect`**, so the committed ITF trace is generated and never consumed.
Model-to-implementation correspondence is a manual argument. Details in
`briefs/mutation-campaign-313-formal-verify.md`.

## Effect on the MUST-with-NULL-callee ratchet

This branch adds **15** rows to the metric, and they are not one class:

- **12** from the new `bin/arch_mutants/arch_mutant_db.ml`, all `Sqlite3.*`. Stated without any
  hand-maintained exclusion list: its non-Stdlib rows number 12 and its `Sqlite3.*` rows number 12,
  therefore all of them. That is the inert "never in this index, carries no signal about a resolver
  miss" class the ratchet's own re-scope note names alongside Stdlib. The module makes those calls
  because `Arch_db.open_ro` is read-only and a campaign has to write.
- **12** `Arch_tezt.Temp.*` call sites added by this branch's tezt tests. **CORRECTED: these are
  ALSO the inert class.** An earlier version of this section called them the signal-carrying
  residue, reasoning that `Arch_tezt` is a module in this repository. That reasoned from the
  module PATH, not from where the callee lives. Measured: `tezt/lib/arch_tezt.ml` is
  `include Tezt` / `include Tezt.Base`, so `Arch_tezt.Temp` **is** `Tezt.Temp`, re-exported — the
  callee comes from the *tezt* package and is no more in this index than `Stdlib` is. The
  principle the `Stdlib.` exclusion states — "never part of this index, so the row carries zero
  signal about a resolver miss" — covers them exactly.

  So this branch adds **no signal-carrying rows at all**: all of its additions are calls that
  leave the indexed universe, and none of them is a resolver miss. That is a weaker claim than
  the one it replaces and it is the true one.

  The wider point belongs to the metric, not to this branch: the exclusion is implemented as a
  NAME (`Stdlib.%`) where the property is MEMBERSHIP — is this callee outside the indexed
  universe, so that no resolver could ever have resolved it? Patching in `Arch_tezt.%` beside
  `Stdlib.%` would move the boundary rather than remove it. That re-baselining is roadmap 4.11's
  and is deliberately not done here: a shared gate is recalibrated by one branch at a time.

`must_null_ceiling.ml` is **identical to main** in this branch, deliberately. A first version
recalibrated it and that was withdrawn: a shared gate must be recalibrated by one branch at a time,
because several branches writing different values to one line merge cleanly against an ancestor
that has neither, and the last to land silently overwrites the others' attributions with no
conflict marker. #83 sets the pin; this branch's 373 then sits under 392 with 19 to spare and needs
no recalibration here.

## Reviewer's attention

- `--catalogue`, `--report`, `--test-cmd` and `--from` are **additions to the CLI grammar the spec
  fixed**. They were necessary: `plan` emits targets, not mutants, so nothing in the stated grammar
  could tell the wrapper what a mutant identifier refers to. All four refuse rather than default
  where a guess would be load-bearing.
- **"Group" is a definition invented here** — the test's own source file, as the closest honest
  analogue of alcotest's group addressing. Worth a second opinion before the profile loader hardens
  it.
- **FR-017 is not computable as written.** It asks to intersect a git range with `mutant_kills`,
  which stores a test name and no file. The implementation falls back to index-wide, which
  over-selects — the safe direction — but is not what the requirement says.
- **FR-032's exit-3 path is unreachable through the real `arch-impact` today**, which produces 3
  only under a flag the driver does not pass. The handling is pinned through a stub at the real
  process boundary: a fact about the callee, not about the handling.
- One residual left deliberately: `report`'s file-based `if`-chain over engine statuses is the exact
  silent-fifth-value shape FR-031 describes, and the spec cites that very line as its reason. It
  reads a third-party file rather than a schema `CHECK`, and changing it would alter a shipped
  command's behaviour for an unknown status.

## A consequence for `arch-report` that this PR creates

`lib/arch_tools/arch_report.ml:196` builds its verdict row as `List.map (fun v -> (v, 0))` over a
fixed eight-token vocabulary. Two of those tokens, `UNKNOWN` and `UNKNOWN_NO_CONTRACT`, are also
`arch-mutants`' vocabulary. Today no table stores them, so the zeros are honest. **After this
merges they stop being honest**: a `GROUP BY selection_provenance` over `mutant_runs` returns them,
and the report will publish 0 against a database that holds them. Measured on a fixture carrying
the migration plus three run rows — the query returns 1 and 1, the report publishes 0 and 0.

This is not a regression this PR introduces. It is a hardcoded zero finally meeting data, and it
belongs to issue #84 rather than here — recorded so the reviewer of #84 has the date it starts
mattering. Findings handed to the roadmap session separately.

## What a GO on this branch can and cannot mean

**No campaign has ever run.** Measured, not assumed: no database under `~/dev` or
`/mnt/ssd-external-2to` carries a `mutants` table. There are no kills, no survivors, no
attributions. The machinery's intended output has never been observed by anyone.

**But the mechanism underneath it now has been, and that is new since round 3.** This section
first said `check-mutaml-integration.sh` returns 3 — unverified — and that the premise everything
rests on was established by reading the engine's source. That is no longer true. The unverified
state was a missing `--build-context` flag, not a fixture limitation: mutaml-runner resolves
`--muts` under its build context. Supplied, the check passes against the real mutaml 0.3 —
**runner exit 0, the wrapper invoked twice, once per mutant and not once per engine run, with
`lib/x:1` resolving to `t_alpha` and `lib/x:2` to `t_beta,t_gamma`, each its declared set.**
AC-20 is verified. The honest-refusal arm survives the engine becoming available: with no runner
on PATH the check still returns 3, and it now probes the runner's `--help` for the flag so that
"engine present, fixture cannot drive it" stays 3 rather than collapsing into a harness error.

So the per-mutant selection mechanism — the one thing this whole design rests on — has been
**observed**, not argued. What has still never happened is a campaign over real code.

**Three review rounds have produced 96 findings on that machinery.** Every one read code, gates,
schemas, provenance or specs; none read a campaign result, because none exists. That is the
correct order — build the harness before running it, and the nine ratchet checks, the reconciler
and the guards are real artefacts either way. But it is exactly the kind of fact that stops being
visible once a branch has fifty commits and a NO-GO/GO history behind it.

So the claim a GO here supports is narrow, and worth stating in the words that bound it: **the
machinery is correct, not that the campaign it exists for produces attributable kills.** A reader
who sees a passing verdict on a mutation-campaign branch will assume kills have been observed.
They have not.

**What would change this, and what would not.** Running a campaign to satisfy a review is how the
review stops measuring the thing, so that is not the answer. That was done in round 3, and it is
recorded above: the flag was supplied, the check passes against the real engine, and the wrapper
mechanism is now observed rather than read. It produced no campaign result, exactly as expected —
it moved the premise from argued to measured and nothing else.

Until a pilot runs on a real corpus — the miaou measurement, deliberately sequenced after this
merges — the honest summary is: **the selection rule is sound, the persistence is sound, the
verdict derivation is sound, the refusals are sound, and nothing has been mutated.**

---

## The 24 open findings, and what they mean for merging

**They are UNDECIDED, and the decision is Mathias's.** Not "known and accepted, merge
anyway", and not "blockers, do not merge" — the branch has never been GO'd by its own
review, and the evidence that would decide it is the campaign result, which arrives
with this body or not at all. Stating this because a reviewer seeing "24 open" will
otherwise read *unfinished branch*, and the author will not be here to correct it.

**1 HIGH, 13 MEDIUM, 7 LOW, 3 INFO.** The severities matter more than the count:

- **The single HIGH is in a CHECK, not in the shipped tool.** `checks/tree-boundary-anchor-is-structural.js`
  prints "arms DERIVED from the type declaration, not written down here" while both
  halves of its derivation filter on a name prefix — so a constructor without that
  prefix can duplicate an anchor tag while the check reports the arms are pairwise
  distinct and passes. It makes a guard weaker than it claims. **It does not make
  `arch-mutants` produce a wrong answer**, and the fix is one character class.
- **The 13 MEDIUM concentrate in the apparatus**, not the product: 3 in the ratchet
  runner, 1 in a dispatch gate, 1 in a provenance script, 1 in the review record
  itself. **3 are in `bin/arch_mutants/arch_mutants.ml`** and those are the ones a
  merge decision should read first.
- LOW and INFO are carried, named, and none is a correctness claim.

**What each option costs.** Merging ships a tool whose verdict logic is reviewed and
whose guards are, in one named place, weaker than their labels — with every one of
those places written down here rather than waiting to be rediscovered. Not merging
leaves 118 commits on a branch that is now safely on the remote, and the campaign
evidence available whenever someone wants it. Neither is obviously right, which is why
this is stated as a decision rather than a recommendation.

## What went wrong in producing this branch, and one of it changed the work

**This section exists because the alternative is a reviewer finding these later and
trusting nothing else in the body.** It is evidence of what was checked, not an
argument against merging — the defects below were found, measured and recorded, and
three of them are retractions of this branch's own published claims.



Six review rounds hardened this machinery. The defects that mattered most were not
found by any of it.

### The scoping number was wrong by a factor of fifty, and it decided the work

The campaign's target corpus was published as **21 550 `.ml` files and 3.9 M lines**,
and the first campaign was scoped down to a single library on that basis. The real
figures, by `git ls-files`: **392 files, 64 661 lines**. The count came from a `find`
that excluded `_build` and nothing else, so **17 951 files came from `_opam`** — the
local opam switch — and **3 207 from `.claude`**, agent worktrees.

It was used three times: published twice, used to decide the campaign's scope, and
repeated in the execution brief. Nobody checked it, because it was plausible. It
surfaced only because a human asked.

**This is the one defect here that changed what work was done.** Every other changed
what was believed. A scoping decision taken on an unverified number is precisely the
failure this branch's machinery exists to prevent, committed by its author against
himself, in the campaign that machinery was built for.

### Self-inflicted findings per closure: 0.79, then 0.29, then 1.50

Computed identically across three review rounds — findings about code the round
itself wrote, divided by that round's closures. **Round 6 is worse than round 4**, and
it crossed one: it produced more defects than it closed, two closures against three
self-inflicted findings.

Read it with what it is and is not. Rounds 5 and 6 changed object — round 4 worked on
the product, mutant identity and tree boundaries, while 5 and 6 worked on **probes,
gates, runners and labels**, the apparatus that checks the product. Each round's output
is then new surface, that surface is itself checking apparatus, and its defects are
found by the same apparatus, which generates more. 1.50 is what that recursion looks
like when measured. It is also why this branch stops at a pull request rather than a
seventh round.

### A rule reminder is not a withdrawal of permission

A standing authorization to push existed. A context block restating the rule was
repeated on every scheduled tick, and each repetition was read as re-imposing the
constraint — so **117 commits sat on one disk for hours** while every status report
dutifully noted "zero remote refs" as a blocker rather than asking to lift it.

That is the same class as every instrument defect in this campaign — a reading that
answers a nearby question — applied to a person's words instead of a query. It is the
one lesson here that generalises past software.

### The harness was hardened six times before its purpose was exercised once

"No mutation campaign has ever run" was reported as a **finding** for hours, in verdict
after verdict, rather than as a thing to fix. Each round supplied a reason to keep
hardening. Nothing was blocking it: the engine was installed, the per-mutant mechanism
had been observed against a real mutaml 0.3, the binary was built. The first campaign
began when someone asked why it had not.

### What the campaign's numbers are, and are not

One run. On a corpus scoped after correcting a fifty-fold error. They are evidence that
the machinery executes on real code — not that the capability is validated.

**Two figures were published from this run before they were checked, and both were
wrong in the same direction.** "4159 survivors" was reported as the headline population;
2500 of them had no test run at all, so the real figure is 1659 — an overstatement of
2.5x. And a 60/15 result was reported as an A/B between naive and selected profiles; the
two databases are md5-identical and carry the same profile, so it is one configuration
reported as a comparison. Both were caught by querying the databases rather than by
reading the report about them, which is the only method that would have caught either.
The lesson is not that the numbers were wrong — it is that a summary statistic was
published from an artefact whose columns had not been inspected once.

### Every ratchet figure in this record is unevaluable as gate output

`checks/run-ratchet.js` never builds. So any check grading a compiled artefact can
grade a **stale** one and return green having measured a previous compilation, and 25
of the 46 checks reference `_build`. CI is not exposed — it builds and runs the ratchet
in the same job, verified by parsing the workflow's job boundaries — but every ratchet
number quoted in this branch's own review record (37/1, 38/1, 39/1, 40/1) came from a
local invocation with no such guarantee.

Not wrong; **unevaluable**. Their credibility rests on `dune build` having been run by
hand before nearly every one, which is a habit, not a guarantee, and is not in the
record. A number whose credibility rests on the discipline of whoever produced it is
not evidence produced by the gate.
