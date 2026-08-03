# R5 — hit rate on real code and on merged PRs

**Date:** 2026-08-02. **Tool:** [`poc/decision-lint`](../../poc/decision-lint/).
**Question the study left open (§11, R5):** *is the finding rate high enough to
justify a CI gate?* Answered here two ways — a third corpus, and a replay of
merged pull requests.

---

## Summary

| | |
|---|---|
| third corpus (sarek, 125 k lines, **explicitly AI-assisted**) | 29 findings raw → **17 verified**, 12 were a false-positive class |
| cross-corpus density | arch-index **0.0**, octez-manager **4.6**, sarek **4.8** per 1 000 decisions |
| merged PRs replayed (octez-manager, squash merges) | 25 |
| PRs whose **own diff** contained a finding | **1 (4 %)**, verified genuine |

**The headline is not the rate — it is that the third corpus exposed a
false-positive class the first two had not.** That is what R5 was for.

---

## 1. The third corpus, and what it broke

`mathiasbourgoin/sarek` was chosen because its README states the recent rework
*"was completed with assistance from AI agents"* — the closest available proxy
for the failure mode this whole line of work targets. 490 files, 3 575 boolean
decisions.

First run: **29 findings**. Nine of the first dozen inspected were wrong, and all
of one shape:

```ocaml
let min x y =
  if x <> x then y        (* x is NaN *)      <- flagged SMT_CONSTANT_FALSE
  else if y <> y then x
let is_finite x = x = x && x <> infinity && x <> neg_infinity
                  ^^^^^                                        <- flagged dead
```

`x <> x` is the idiomatic NaN test in OCaml. For a float it is *true* when `x` is
NaN, so it is not constant — and the comment saying so was on the adjacent line.
The tool declared deliberate, load-bearing float code dead.

§6.3 of the design doc says precisely this ("decline floats; NaN breaks the
identities one reflexively assumes, `x <> x` is satisfiable"). **The PoC never
implemented it**, and the tool's own README claimed a float atom was "treated as
an opaque boolean, sound because opaque atoms never merge" — which was wrong: in
a comparison a float becomes `ARel("<>", TVar x, TVar x)`, which the encoder
turns into `distinct x x`, unsat.

Fixed two ways: the Typedtree frontend checks `exp_type` and declines float
comparisons outright; both frontends decline the *shape* `x = x` / `x <> x`,
which the untyped frontend can do without types. Four float cases were added to
the fixture as true negatives.

**29 → 17 findings.** All 17 were then read back against the source; all are
genuine. Two are in **production** code:

- `sarek/ppx/Sarek_convergence.ml:372` — `true || expr_uses_barriers step_body ||
  expr_uses_barriers cont`. The `true ||` short-circuits: neither call can ever
  run.
- `sarek/ppx/Sarek_convergence.ml:641` — `else if usage.uses_x then Simple1D
  else Simple1D`. Both arms identical; the test is dead.

The other 15 are test-file vacuities of the class already seen on
octez-manager — `assert (jit <> direct)` on two distinct constructors, which the
type system guarantees; `(result.ty <> t_unit) || (result.ty = t_unit)`; and one
genuinely interesting redundancy, `i_inc >= 0 && i_extern >= 0 && i_inc <
i_extern`, where the middle conjunct follows from the other two.

**Two verdicts fired for the first time on real code**: `SMT_DEAD_CONDITION` and
`IMPLIED_TRUE`. The latter is the path-sensitive check §6.1 predicted and that
the first two corpora never triggered:

```ocaml
if tid < n then begin
  let p = if tid < n then Pick 0 else NoPick in       (* implied *)
  ... match if tid < n then Circle src.(tid) ...      (* implied *)
```

---

## 2. Replaying merged pull requests

**Method.** For each merged PR: take its diff against its parent, run the linter
at the PR's head in a detached worktree, and keep findings whose `file:line`
falls inside a line range the PR added. That answers *"would this PR have been
flagged at review time?"*

**A first attempt was invalid and is recorded as such.** It enumerated
`git log --merges`, which on this repository returns 59 old-style merge commits —
but the recent work is **squash-merged**, so those commits were missed entirely
and the ones replayed had only 65 `.ml` files against 354 today. The tell was the
median finding count over the whole tree: 0. A run that analysed almost nothing
cannot report a rate.

**Corrected population:** commits whose subject ends in `(#N)`, the squash-merge
signature. 25 of them touch `.ml`. Median findings tree-wide at those heads: 6
(max 12), so the linter was genuinely working.

**Result: 1 of 25 PRs (4 %)** introduced a finding inside its own diff —
`feat: detect and manage external Octez services (#334)`, an `IMPLIED_FALSE` at
`src/ui/pages/instances.ml:603`.

**Verified.** The finding needs three levels of guard, and a first hand-check
wrongly dismissed it:

```ocaml
else if s.num_columns <= 1 then …            (* line 547 — else branch: ncols > 1 *)
  …
  if List.length s.services > 0 && s.num_columns > 1 then …
  else if List.length s.services > 0 then …  (* line 603 *)
```

Reaching line 603 requires `¬(len > 0 ∧ ncols > 1)`, and the enclosing else has
already established `ncols > 1`. Therefore `len > 0` is **false** and that branch
can never be taken. Genuine dead code, shipped in a merged PR.

---

## 3. What this says about a CI gate

**A blocking gate on absolute findings is not justified.** At 4 % per PR the
signal is real but thin: roughly one PR in twenty-five. A gate that fires that
rarely will be ignored between firings and mistrusted when it fires.

**A ratchet is justified** (R4): fail only on *new* findings against a committed
baseline. The measured rate is exactly the profile a ratchet suits — low enough
that it almost never blocks, specific enough that when it does, the finding is
real. All three of the PR-diff and production findings above are one-line
deletions.

**The bulk of the value is the one-time sweep, not the per-PR check.** 17
findings on octez-manager and 17 on sarek were already in the tree; only one
arrived through the 25 PRs sampled. A tool run once over an existing codebase
pays for itself immediately; run per-PR it is cheap insurance, not a discovery
engine.

**On authorship, see §4** — this section originally concluded the hypothesis was
"not supported", from a comparison of octez-manager against sarek. Both are
AI-written, so that was AI-versus-AI and settled nothing. A human-written control
was added; the conclusion changed.

---

## Verification notes

- Every finding quoted was read back against the source. The 12 float findings
  are recorded as false positives and the fix is in the same branch.
- The first PR replay was wrong and its numbers are not used. Recorded because
  the failure mode — measuring a population that excludes what you care about —
  is worth remembering.
- The replay ran with `NO_SMT=1` for speed, so it **undercounts**: on
  octez-manager today the solver contributes 5 of 17 findings. The 4 % figure is
  a floor.
- 25 PRs is a small sample. A 4 % rate on 25 observations has a wide interval;
  treat it as an order of magnitude, not a measurement.
- sarek and octez-manager were analysed with the Parsetree frontend (neither was
  built here), so rung 1 is scope-based rather than stamp-based and the purity
  join was unavailable. Both cost recall, so these counts are floors too.


---

## 4. A human-written control: Octez

The §3 comparison was invalid. octez-manager and sarek are **both** AI-written,
so measuring one against the other tested nothing. The control added here is
`tezos/tezos` — 8 455 files, **3.34 M lines**, a codebase ten years old whose
bulk predates LLM coding assistants. It is not a *pure* human control (it carries
a `CLAUDE.md` and an `AGENTS.md` today), but it is the best available.

### What the run first reported, and why it was wrong

**117 findings — of which 97 were `IMPLIED_FALSE`**, a verdict that had fired
twice in total across all previous corpora. That concentration was the tell.

```ocaml
let c = compare len1 len2 in
if c <> 0 then c
else
  let c = compare (Bytes.get b1 pos) (Bytes.get b2 pos) in
  if c <> 0 then c else …          (* flagged: guard says not (c <> 0) *)
```

The compare-chain idiom **rebinds `c`**. The inner `c` is a different variable,
and the outer guard says nothing about it — but the guard stack matched them **by
name**. Keeping a guard across a rebinding of a name it mentions proves live
branches dead, and this is one of the most common idioms in OCaml.

Both frontends had the bug. The Parsetree one was fixed by invalidating any
guard mentioning a name the scope rebinds. The Typedtree one — which a code
comment had claimed "immune by construction" — was **not** immune: `print_e`
built canonical keys from `Path.name`, the plain name, so the stamps that
distinguish the two `c`s were available and unused. Fixed at the root, by keying
local identifiers on `Ident.unique_name`.

**117 → 19 findings.** 98 were this one bug.

One true positive was lost to the fix and is now documented as undetectable:
`| m when m > 5 -> … | m when m > 100 -> …` really is a subsumed guard, but each
arm binds its own `m`, and relating them needs scrutinee identity rather than a
name match. Detecting it by name was the *same* unsoundness, so it was removed
rather than kept.

### The comparison, after the fix

Enumeration tier only (`NO_SMT=1`), so all four are comparable:

| corpus | authorship | lines | decisions | prod | test | total | per 1 000 decisions |
|---|---|--:|--:|--:|--:|--:|--:|
| arch-index | AI-assisted | — | 389 | 0 | 0 | **0** | 0.00 |
| octez-manager | AI-written | 125 k | 3 728 | 5 | 7 | **12** | 3.22 |
| sarek | AI-assisted | 137 k | 3 575 | 2 | 3 | **5** | 1.40 |
| **octez** | **predominantly human** | **3 344 k** | 33 629 | 4 | 15 | **19** | **0.56** |

**In production code, by volume:** octez carries **4 findings in 3.34 M lines**
(≈1.2 per Mloc) against octez-manager's 5 in 125 k (≈40 per Mloc) and sarek's 2
in 137 k (≈15 per Mloc) — a **13× to 33× gap**.

### What that does and does not license

**Supported:** the two AI-written corpora carry substantially more detectable
dead logic per line of production code than the mature human-written one.

**Not supported: that authorship is the cause.** The confounders are not
separable in this design and they are large — Octez is ten years old with heavy
review, the others are young; Octez is protocol and cryptography, the others are
UI and tooling. A ten-year-old human codebase has had a decade for exactly these
defects to be found and removed.

**A counterexample inside the AI set:** arch-index is itself agent-developed —
its `briefs/` are the record — and reports **zero**. At 389 decisions that is
weak evidence, but it is evidence against a simple "AI implies denser".

**What is robust regardless of authorship:** the tool's yield is far higher on
young codebases than on mature ones, and **the majority of findings live in test
files** in every corpus that has them (7 of 12, 3 of 5, 15 of 19). Vacuous
assertions are the dominant class everywhere, and they are invisible to coverage
because those lines are covered and those tests pass.

### Revised recommendation

The one-time-sweep conclusion of §3 strengthens: a sweep of a *young* codebase is
where the value is. The per-PR ratchet conclusion is unchanged. And the ordering
in §3 — that the false-positive discovery mattered more than the rate — repeats
here: **a second and larger false-positive class was found by adding a fourth
corpus, and it would have made the tool unusable on any codebase using the
compare-chain idiom.**


---

## 5. Blaming the survivors — and the reversal it forces

§4 reported a 13×–33× density gap in production code between the AI-written
corpora and Octez, while warning that age and review intensity were inseparable
confounders. `git blame` on every surviving finding separates them, and the
answer overturns the naive reading.

### When was each finding introduced?

| corpus | introduction dates of its findings |
|---|---|
| octez-manager (12) | **all 2026** — nine in Jan–Feb, one in May |
| sarek (5) | **all 2025-2026** — two Jul 2026, three Dec 2025 |
| **octez (19)** | 9 on **2023-07-11**, 3 on 2023-03-09, 2 in **2019**, and one each in 2019-12, 2020-09, 2023-02, 2024-02 — **one single finding from 2025-2026** |

Two things fall out.

**Review does not remove these defects.** Octez's dead logic is *old* — some of
it six years old — and has survived a decade of one of the most heavily reviewed
OCaml codebases in existence. So "Octez is cleaner because review caught them"
is **false**: the defects are there, they were never caught, and this is an
argument for the tool that is independent of who wrote the code.

**The density gap was an artefact of dilution.** Octez's 19 findings are spread
over ten years and 3.34 M lines; the AI corpora's 17 arrived in about one year.
Comparing static per-line density compares a decade of accumulated stable code
against a year of new code.

### Normalised by work actually done

`.ml` lines added since 2025-01-01, against findings introduced in that window:

| corpus | authorship | findings since 2025 | `.ml` lines added | **per 100 kloc added** |
|---|---|--:|--:|--:|
| octez-manager | AI | 12 | 185 828 | **6.5** |
| sarek | AI | 5 | 294 419 | **1.7** |
| octez | mostly human | 1 | 26 357 | **3.8** |

**Octez sits between the two AI corpora, and sarek — AI-assisted — is the
lowest of the three.** The 13×–33× gap of §4 does not survive normalisation.

### Conclusion on authorship

**Not supported — and §6 shows it is not even measurable here.** §3's version of
this conclusion came from an invalid AI-versus-AI comparison; §4 appeared to
overturn it; §5 overturned §4; and §6 shows §5's numerator was itself an
artefact. Read §6 before quoting any figure from this section.

Caveats, and they are severe: Octez contributes **one** finding in the window, so
its rate has an enormous interval; the three differ by domain (protocol vs UI vs
GPU DSL); and "lines added" counts churn, not new logic.

**What survives all three passes** is authorship-independent and is the actual
result of R5:

- the majority of findings are in **test files** in every corpus (7/12, 3/5,
  15/19), and they are assertions that cannot fail;
- **long-lived review does not remove this class** — Octez's oldest survivors are
  from 2019;
- and the tool's real yield is the **one-time sweep**, not the per-PR gate.


---

## 6. The 2023-07-11 cluster — and why §5's rate is also wrong

Nine of Octez's nineteen findings share one introduction date. That is not how
code gets written, and chasing it invalidates §5's normalised comparison too.

**Two artefacts, both confirmed.**

*Vendoring.* The 2023-07-11 commit is `lib_bls12_381: add tests` — a bulk import.
All nine findings are in `src/lib_bls12_381/test/`, third-party cryptography test
code brought in wholesale. `git blame` dates every line to the import, and the
code was not authored by the Octez team on that day or in that repository.

*Protocol snapshotting.* Octez creates each new protocol by copying the previous
one. So one defect appears once per snapshot:

- `script_ir_translator.ml` — **4 rows** (proto_005 ×2, proto_006, proto_007),
  one underlying defect;
- `test_dal_slot_proof.ml` — **2 rows**, and the pair is **byte-identical**:

```ocaml
let level, sindex =
  if false then (Raw_level_repr.succ published_level, index)
  else (published_level, succ_slot_index index)
```

A hardcoded `if false`, live in Octez test code since 2024 — and the "2026"
occurrence §5 counted is that same line, copied into `proto_025_PsUshuai` by the
snapshot. **Octez introduced zero genuinely new findings in 2025-2026.**

**Deduplicated:** 19 rows → 15 distinct sites → **6 authored in this repository
by this project**, the other 9 being vendored.

### The consequence

§5 computed 1 finding over 26 357 lines added since 2025 and concluded Octez sat
*between* the two AI corpora at 3.8 per 100 kloc. That single finding was a
snapshot copy, so the real numerator is **0**. And 0 over 26 k lines does not
distinguish "very clean" from "sample far too small" — it carries no information
either way.

**So the authorship comparison is not merely unsupported — it is
unmeasurable from this data, in either direction.** Three passes were needed to
reach that:

1. §3 compared AI against AI and concluded "no difference" — invalid.
2. §4 added a human control, found a 13×–33× gap, and read it as authorship —
   confounded by age and codebase size.
3. §5 normalised by recent work and found the gap reversed — but on a numerator
   that was a copy.
4. §6 removes vendoring and snapshot duplication and finds there is no usable
   denominator or numerator left on the control side.

The tool's *findings* survived every pass — the `if false` above is real, has
been in Octez since 2024, and is exactly the class this work targets. What did
not survive is any claim about **who** writes such code. That question needs a
corpus designed for it: comparable domain, comparable age, comparable review, and
no vendoring or snapshotting. None of the four repositories here qualifies.
