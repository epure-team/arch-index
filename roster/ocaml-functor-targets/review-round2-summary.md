# Roster review — round 2

Reviewed commit: `a874c14` (`fix(ocaml): authenticate functor target publication`).

Verdict: **GO**. All open correctness, spec, testing and scope findings from
round 1 have a concrete correction and an executable regression. The accepted
scope extensions are the schema lifecycle files required by v2, source-growth
ratchets, and call-ID-independent compatibility checking; none expands the
bounded same-CMT target semantics.

Evidence replayed on this head:

- build and the full native suite: **354/354**;
- CHECK-1: nine authentic scenarios, including `arch-query`, local variant
  proof retention and durable-chain corruption;
- CHECK-3: frozen 410-CMT replay, **+7 Irmin / +0 protocol / 0 loss / 0 new or
  upgraded MUST**, with exact witnesses;
- all six explicit checker controls: assertion exit 1, setup exit 2.

The full resolved ledger is `review-round2-resolved-ledger.json`. This review
does not claim QA, hosted exact-head CI, merge or Stage-4 delivery; those are
the remaining pipeline gates.
