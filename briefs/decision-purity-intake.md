# Intake Brief — decision-purity

**Date:** 2026-08-02
**Status:** VALIDATED (autonomous run)
**Type:** feature
**Roadmap:** lot 4 — the largest measured recall gap
(`docs/research/mcdc-coverage-feasibility.md` §11, R3)

## Goal

Replace the analyser's hand-written purity **allowlist** with a purity
**analysis**, by joining against the index's own effects data.

The measurement that motivates it — the census of *why* an atom is refused a
merge, over the top-40 heads:

| cause | octez-manager | arch-index |
|---|--:|--:|
| **project function** | **48.5 %** | **41.3 %** |
| mutable read (`!`, `Array.get`) | 21.0 % | 37.8 % |
| effectful stdlib (`Sys`, `Hashtbl`) | 19.5 % | 15.5 % |
| pure stdlib, allowlist gap | 7.8 % | 2.6 % |
| walker gap | 3.2 % | 2.8 % |

The single dominant cause is *a call to a function defined in the project*,
which the allowlist can never cover — it only lists stdlib names. Every one of
those atoms gets a fresh variable per occurrence and can never merge, so any
redundancy involving them is invisible. This is where recall is lost, and it is
where the study's §11 said it was lost.

The Typedtree frontend already resolves heads to a `Path`, which is exactly the
key needed to look a function up. This lot spends that.

## Scope Boundary

Explicitly OUT of scope:

- Improving `v_pure_functions` itself. Its precision is bounded by the call
  graph (a `MAY_TOP` edge blocks certification), which is R3 territory. This lot
  *consumes* the existing verdict, whatever it is worth.
- The Parsetree frontend. Without resolved names it cannot look anything up
  reliably; it keeps the allowlist and must say so.
- Populating the effects tables. They come from the effects pipeline
  (`arch-effects-ocaml` + the migration); this lot reads them if present.

## Relevant Files

| file | role |
|---|---|
| `poc/decision-lint/bin/decision_lint.ml` | purity table load + stability predicate |
| `effects-schema-migration.sql` | `v_pure_functions` — the verdict consumed |

## Design Decisions

**Fail closed, and say so.** If the DB has no effects tables, or `--db` was not
given, the purity set is empty and the tool falls back to the allowlist —
exactly today's behaviour. The armed-rungs stamp must record which of the two
ran, because a clean result from a run that could not consult purity is much
weaker evidence than one that could, and the two must not look alike.

**Purity certifies STABILITY, not absence of side effects in general.** The
predicate the analyser needs is "this expression has the same value at two
evaluation points in the same decision". A pure function applied to stable
arguments satisfies it. A pure function applied to an *unstable* argument does
not — `f !r` is unstable however pure `f` is. So the recursion into arguments
stays exactly as it was; only the head test changes.

**Name-keyed, and deliberately conservative about it.** `v_pure_functions` is
keyed by `(module_path, function_name)`. A resolved `Path` gives a module-
qualified name. When the two cannot be matched unambiguously the atom stays
unstable — a missed merge, never a wrong one.

## Quality Gates

- Fixture stays at **27 true positives / 15 true negatives** under both
  frontends, with the two still agreeing exactly.
- With no `--db`, behaviour is byte-identical to today.
- With a `--db` that lacks effects tables, behaviour is identical to today and
  the run says purity was unavailable.
- All arch-index selftests and `STRICT=1 selftest-callgraph-soundness` green.

## Acceptance Criteria

- AC-1: given a DB carrying effects tables, the Typedtree frontend treats a
  certified-pure project function as a stable head.
- AC-2: an unstable *argument* still makes the atom unstable regardless of the
  head's purity.
- AC-3: with no DB or no effects tables, the tool falls back to the allowlist
  and reports that it did.
- AC-4: the armed-rungs stamp distinguishes allowlist-purity from
  analysis-purity.
- AC-5: no false positive is introduced — the fixture's true negatives all hold.
