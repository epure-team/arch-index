---
slug: mutation-campaign-313
date: 2026-09-05
component: bin/arch_mutants/arch_mutants.ml (+ new `run` driver, `mutants` / `mutant_kills` tables, architecture-schema.sql)
backend_recommendation: quint
human_decision: null
downgrade_reason: null
---

## Properties

| ID | Name | Backend | Priority | Severity | ELI5 | Why tests miss it |
|---|---|---|---|---|---|---|
| P1 | Selection soundness under ⊤ | Quint | HIGH | 4 | "When we only run the tests we *know* touch a piece of code, and the analysis admits it may have missed some callers, then a mutant nobody killed must be reported as 'we don't know', never as 'no test catches this'." | A test can only exercise one index at a time. The bug appears exactly when the call graph loses track, which is a property of the *input index*, not of any single run. You would need an index with an unresolvable edge in the test cone AND a mutant in the escaped region AND a test that really does reach it — a conjunction no fixture is written for. |
| P2 | Proof sources are additive only | Quint | HIGH | 4 | "Evidence that a test *did* run through some code may only ever add that test to the list we run. No source of evidence is allowed to remove a test from the list." | A unit test pins the output of one selection call. Subtraction shows up as a *smaller* result on inputs nobody enumerated — the coverage file that lists fewer tests than the graph does. The defect is a direction, and direction is not observable at a point. |
| P3 | Kill is proof, survival is not | Quint | HIGH | 4 | "Killing a mutant proves the tests notice the change. A mutant surviving proves nothing — it may be a change that cannot alter behaviour at all. The report must never turn silence into a claim." | Tests assert on report content for chosen fixtures. The failure is a *category* error in the report's vocabulary, uniform across all inputs, so any fixture that encodes the wrong vocabulary passes happily. |
| P4 | Site identity is actually a key | none (empirical) | HIGH | 4 | "Two different mutation sites must never collide onto the same identifier, or one silently overwrites or hides the other." | Not a formal property — a fact about real corpora. Measured precedent: a site-identity key collided **0 times on a 37-row demo corpus and 1 150 times on the 25 479 real rows**. A test corpus is chosen; the collision lives in the corpus you did not choose. |

Tie-break order within severity 4 (all properties inherit Q3's score): P1 (central invariant, combinatorial detectability gap) > P2 (central, directional) > P3 (report vocabulary, uniform) > P4 (empirical, measurable without a backend).

**Grounding from the read-only scan** (worktree `/mnt/ssd-external-2to/arch-index-mutation-313`, branch `feat/mutation-campaign-313`, base `70cb47f`):

- `bin/arch_mutants/arch_mutants.ml:122` already computes `let proof = escapes = [] && sound` — the exact admissibility predicate P1 needs. The plan reports the escaped cone as "a heuristic here, not a restriction you can trust" (lines 205–211). The datum exists; nothing consumes it as a *gate* on the verdict.
- `arch_mutants.ml:53` computes `escapes` restricted to the test-reachable set, which is the right restriction (a ⊤ edge outside the test cone cannot make an untested function secretly tested).
- The status vocabulary (lines 25, 245, 347–349) is `SURVIVED | KILLED | TIMEOUT | ERROR`. **There is no `UNKNOWN`.** P1 cannot be expressed in the current schema; adding the state is a precondition, not a refinement.
- `reaching` (lines 88–92) is `SS.inter (closure {key} g.bwd) test_keys` — a backward closure over resolved edges, i.e. a **lower bound** on the tests that reach the function. Using it as the exclusive run-set is precisely the unsound exclusion P1 forbids.

## Backend Argument

Recommendation: **Quint**.

The three formalisable properties are all about a small machine: a selection set that grows, a
verdict that may only be emitted under a stated condition, and a report vocabulary that must not
promote silence to a claim. Quint models exactly that — explicit state, a transition relation,
and invariants over runs — and it catches P2 in the only way P2 can be caught, by quantifying over
sequences where evidence arrives in any order.

Rocq would fit if the obligation were arithmetic or an extraction correspondence. Here there is no
theory to prove, only a state machine to explore, and Rocq would cost proof-development weeks to
say what a bounded model check says in minutes. What Quint misses is P4: site-key uniqueness is a
fact about real corpora, not a theorem — no model check substitutes for `GROUP BY key HAVING
count(*) > 1` over Octez. P4 is therefore carried as an empirical gate, not assigned to a backend.

The repository also already has the replay half: `~/dev/ocaml-quint-connect` drives an OCaml
implementation from a committed ITF trace, so the model can be checked against the real selection
function without Quint present at CI time.

## Q3 Answer

**a) An attacker gains a capability they should not have.** — severity_score 4, priority HIGH.

Recorded as answered by the human. For the record, this skill's scan argued *against* (a) and
recommended (b): arch-index is an out-of-production audit instrument with no attackable trust
boundary in this component, and the Tier A trigger fired only on the words "hash source" (a
content hash used for cache invalidation). The human's answer stands and sets severity; this note
exists so the divergence is visible rather than silently smoothed.

## Q1, Q2, Q4, Q5 — derived, NOT elicited

These four were **not** put to the human in this run (only Q3, the closed-choice severity question,
was asked). The answers below are derived from the roadmap guardian's arbitration and the code
scan, and are marked as such so they are never mistaken for human answers. Correct them at the
intake gate if wrong.

1. **All inputs, or only ours?** All inputs. The selection function must stay correct on any index,
   including ones whose test cone escapes through ⊤ — which is the normal case on Octez (286 356 ⊤
   edges at last measurement).
2. **Temporal properties?** Yes, two. Selection is monotone under arriving evidence (P2), and the
   kill matrix is append-only per campaign, so a verdict may be superseded but never rewritten.
3. **Reference defining "correct"?** Yes: the roadmap guardian's arbitration of item 3.13, the
   `UNKNOWN`-over-`PASS` semantics `arch-rules` already implements, and `docs/mutation-testing.md`,
   which refuses a mutation score on record.
4. **What does failure look like?** A silent wrong answer. The report names a real test and states
   it failed to kill a mutant it may never have run. It reads as an actionable defect, sends someone
   to strengthen a test that was never the problem, and looks identical to a true finding.

## Cost of --critical (Quint)

All figures are estimates — actual cost depends on component complexity.

```
Implementation effort
  Spec writing       ~1 day. AI drafts the .qnt; you validate at the quiz gate.
                     Small state space: a selection set, a verdict enum, an evidence source.
  Driver             1–2 days for the connect Driver + State implementation against the
                     real selection function (ocaml-quint-connect).

Token cost           ~1.5–2× a standard Full run (first-principles estimate).

CI changes           ⚠ CI/CD change — requires human approval per escalation.md.
                     ocaml-quint-connect replays pre-committed ITF traces, so Quint itself
                     does NOT need to be in the CI image. Added build time: seconds.

Ongoing              The driver must stay in sync with the implementation: a change to the
                     selection function without a matching driver update makes the replay
                     pass against a model of code that no longer exists.
```

P4 carries no backend cost: it is one SQL probe over the Octez index, plus the discipline that
under a `UNIQUE` constraint the probe must count **rejected rows**, not collisions.

## Next

`/roster-spec`, then `/roster-spec-formal` immediately after. The human's backend decision is
filled in by the intake gate, not here.
