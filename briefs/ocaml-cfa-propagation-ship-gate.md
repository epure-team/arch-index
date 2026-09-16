# Ship Gate — ocaml-cfa-propagation

**Date:** 2026-09-16  
**Status:** APPROVED

## Preconditions

- Branch: `feat/ocaml-cfa-propagation`
- Target: `main`
- Base: `origin/main` at `53907c5e508596057b9ea0b456be05d9a7093a3b`
- Review: GO, round 3, no open findings or convergence violation.
- QA: GO, round 1, build + 345/345 + CHECK1/2/3 + review ratchet.
- Merge strategy: rebase merge; delete remote feature branch after merge.
- Foreign untracked workspace paths are excluded from every commit.

## Delivery summary

Stage 3 adds bounded same-CMT CFA propagation through exact arguments, normal
returns, immutable lexical captures, supported recursion and finite partial
applications. Derived targets remain `MAY_ENUMERATED`; unsupported shapes retain
explicit callback uncertainty. Direct/root/local supported-let admission shares
one classifier, and partial LSP test runs are classified as setup failures.

Pinned410 qualification: Irmin +72, protocol +270, 342 total relation gains,
zero relation losses and zero new `MUST` rows.

## Authorization

The user explicitly authorized autonomous Roster execution for each of the five
stages, including PR creation, waiting for green CI, correction if necessary and
rebase merge before starting the next stage. That standing authorization
satisfies both ship gates for this stage; no new scope or merge strategy is
introduced here.

## Commits

All commits from `60cc88b` through the final QA receipt are in scope. Product,
tests and Roster evidence are kept as separate conventional commits and each
review/QA correction was validated before this gate.

## Decision

Push the feature branch, open the Stage-3 PR, require exact-head green CI, then
rebase-merge and resynchronize local `main` before Stage 4.
