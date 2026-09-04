# Spec completion — reexport-resolution

**Status: VALIDATED**
**Date:** 2026-09-04
**Spec file:** `specs/reexport-resolution.md`

4 user stories, 10 FRs, 5 runnable checks, 26 adversarial challenges + 8 edge cases,
all resolved in the spec or named as residuals.

**The spec re-scoped the task, on a measurement the intake brief had not made.** The
brief justified the work on ~49 000 edges reached through `include`. Measured at equal
scope (8714 `.ml` files, 8615 modules indexed):

| | in source | functor application | recordable | in `module_deps` | coverage |
|---|---|---|---|---|---|
| `include` | 7653 | 1283 | 6370 | **840** | **13 %** |
| `alias` | 7802 | 2437 | 5365 | **2811** | **52 %** |

`module_path_of_expr` handles only `Tmod_ident`/`Tmod_constraint`, so every functor
application yields no row — and the heaviest bucket goes through two of them
(`include … Lwtreslib.Traced (TzTrace)`, `include Monad_maker.Make (…)`). The 25 273
`Lwt_result_syntax` edges would not resolve even with the wire connected.

The brief measured the weight of the problem and assumed the data for the fix covered
it. It does not. The alias tier is deliverable now; the include tier is blocked in the
**producer**, not the resolver, and becomes its own slice.

Three challenge resolutions worth carrying forward:
- **C-16** — no contradiction with the sibling's `ambiguous_unit` policy: this chase is
  a fallback tier that runs only after existing resolution fails, so the two never
  compete for one decision.
- **C-13/EC-8** — a retarget may be a *correction*, since the FK it replaces is
  basename/last-writer-wins. So a retarget is a hard stop **for review**, not an
  automatic revert; each must be justified by naming old and new target.
- **C-26** — the literature gap (no tool separates "no candidate" from "several
  unranked candidates" as durable states) is **narrowed, not closed**: per-reason counts
  are delivered, per-edge queryable state is not, and the spec says so rather than
  claiming the credit.
