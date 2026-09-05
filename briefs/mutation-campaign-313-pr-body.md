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

## What this does NOT establish

**The campaign mechanism has never been observed running.** It is established by reading the
engine's source. `scripts/check-mutaml-integration.sh` returns **3** — unverified — and that must
not be read as covered. The pilot measurement on a real corpus comes after this merges.

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
- **3** `Arch_tezt.Temp.dir` call sites added to `tezt/tests/mutants.ml`, 0 on main. These are
  **not** the inert class — `Arch_tezt` is in this repository, so they are the signal-carrying
  residue the ratchet exists to notice. They are an instance of a shape main already carries at
  39 / 26 / 16 rows for `Check.option` / `Temp.file` / `Temp.dir`, not a new defect, but they are an
  addition to the class that matters and this PR says so rather than filing them with the twelve.

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
