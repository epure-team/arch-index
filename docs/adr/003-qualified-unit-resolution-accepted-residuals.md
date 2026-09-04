# ADR 003 — roadmap 1.6 ships with five accepted residuals

**Status:** accepted, 2026-09-04. **Decision:** the human, after
`scripts/check-review-convergence.js` returned `cause: round-cap` on the sixth
consecutive NO-GO round.

## Why this record exists

Six review rounds, each producing at least one novel HIGH-or-above finding
against a strike budget of 2. The mechanical convergence gate refuses a seventh
route-back by design — it exists to stop an agent iterating indefinitely on its
own work — and escalates the scope question to a human. This file is the answer,
written down so "accepted residuals" is an enumerated list rather than a gesture.

## What was settled, and is not in doubt

Measured identically on every round since round 2, on both external corpora,
classified by `calls.id` **and** by a content tuple (two independent keyings
agreeing):

| corpus | unchanged | NULL → resolved | resolved → NULL | re-targeted |
|---|---|---|---|---|
| octez-manager (58 553 calls) | 58 477 | **76** | **0** | 0 |
| proto_alpha/lib_protocol (73 588 calls) | 73 514 | **70** | **1** | **3** |

`fails-with` answer sets: **zero removals on both corpora** (+81 on
octez-manager, one identity of 31; +101 on proto_alpha, three of eleven). Every
peer-coupling tripwire on its frozen baseline, `exn_rebinds` content-identical.
MUST-with-NULL falls on both (15 785 → 15 712; 15 466 → 15 427). No ⊤ inflation.

The single proto_alpha loss is an improvement: `main` resolved
`test/helpers/script_big_map.ml:8`'s forwarding call **to the helper itself** — a
self-recursive call absent from the source. The three re-targets are corrections
of production protocol code that `main` attributed to a **test helper**, one of
them `MUST` from the Michelson interpreter.

## The five accepted residuals

Each is pinned by a test that **asserts the defect** and therefore **fails when
the residual closes** — none can be silently lost. Each reproduces identically
on `main`: this change is strictly better than `main` on every measured axis and
worse on none.

| # | shape | test | closing it needs |
|---|---|---|---|
| 1 | a reference rooted **outside** the index (`Stdlib.Buffer.add_string`, `Unix.*`, an unlinked library, a vendored duplicate) binds a local homonym as `MUST` | `register_unlinked_residual` | caller `.cmt` import list |
| 2 | an **aliased nested module** (`module Submod = Base`) binds an unlinked homonym as `MUST`, while the correct target is indexed | `register_aliased_nested_residual` | caller `.cmt` import list |
| 3 | a homonym unit **below the anchor** binds a **linked** wrong library as `MUST` | `register_linked_homonym_residual` | caller `.cmt` import list |
| 4 | `module_deps` and `type_usage` still key on the capitalised basename, last-writer-wins — spec S4's sites 2 and 3 | `register_sibling_sites_residual` | re-key `type_lookup` on `(path, name)`; route both sites through `unit_readings` |
| 5 | a library main module **shadowing** a sibling degrades to ⊤ where `main` resolved it — a **precision loss**, 1 corpus row | `register_shadowing_residual` | prefer the longest `__`-join that hits |

Residual 4 is the most consequential and is called out explicitly: `arch-rules`
derives its `forbid dep` verdict directly from `module_deps.target_module`, so on
a cross-library homonym it can report **pass** on a real architecture violation
and **FAIL** on a nonexistent one. This is unchanged from `main`. It is accepted
here because the resolver fix is independently valuable and the two sibling sites
need their own slice with their own corpus validation — not because the defect is
minor.

Residuals 1–3 are one defect wearing three shapes, and the index alone cannot
close any of them: each is structurally identical to the **legitimate**
cross-library re-export facade the resolver must serve (indexed root, deeper
segment naming a unit in another library). Separating them requires linkage
evidence — the caller's own `.cmt` import list, which names the unit a reference
actually reaches. Verified on a fixture: the caller imports `Stdlib__Buffer` and
**not** `Mylib__Buffer`. Specced in `briefs/linkage-evidence-followup.md`.

## What is NOT a residual

The `(wrapped false)` multi-path homonym was a residual until round 6 measured
that the branch **introduced** a wrong-library `MUST` there where `main` emitted
an honest unresolved leaf. It was closed rather than disclosed a fourth time
(`6e7b429`): a unit name mapping to several paths is
answerable-but-not-decidable, and one row among several candidate paths is the
absence of evidence in the others. Corpus cost: **zero**. `register_unwrapped_unlinked_residual`
now asserts the guarantee and is verified RED against `main`'s producer.

## Also accepted, and separate

`MUST`-with-NULL-callee into an **indexed** unit, where the row arrives through
an `include` elsewhere in the same unit (scenarios E and G). This is a
proof-shaped edge and it is a defect, not policy; closing it needs
`include`-following. It is budgeted against `must_null_ceiling` (branch measures
346 against a ceiling of 372) and disclosed in the resolver comment, in
`specs/sound-qualified-name-resolution.md`'s S3 amendment, and in both tests.

## Process note

Rounds 1–5 shared a defect that was not in the code: the author fixed his own
review findings with no independent verification of the fixes. Corrected from
round 5 by delegating fixes to an implementer and re-reviewing independently.
Rounds 3, 4, 5 and 6 each found the residual paragraph understating its own
scope — one shape, then two, then three, then a mechanism broader than its
stated precondition. The lessons are recorded as
`specs/qualified-unit-resolution.md` §10.1–§10.6.
