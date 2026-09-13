# R1 correction challenge — guard-division-analysis

## Verdict

**Accept the CLI-only public boundary, with the clarification below.** This does not
weaken an existing observable acceptance behavior: the intake's requested deliverable is
a separate OCaml library/CLI (`briefs/guard-division-analysis-intake.md:8-12`), but its
specified public behavior is the explicit-input CLI/report contract
(`specs/guard-division-analysis.md:251-265`), not an embedding API. The current public
`arch-index.guard` library is an implementation accident with a demonstrated host-global
state regression (`roster/guard-division-analysis/review-r1-architect.md:7-13`).

The word “library” is the only possible ambiguity: if it meant a *supported installed
in-process API*, removal is a material user choice. Nothing in the intake, FR-001..047,
or AC-1..19 says that it does. Resolve that ambiguity expressly rather than silently
changing its meaning. No new user decision is needed for the bounded v1 interpretation;
ask only if supported host-process embedding is a desired product capability.

## Exact narrow spec clarification (no FR/AC renumbering or numeric-fragment change)

Add a **V1 public-boundary clarification** immediately before FR-033 (or in the CLI
contract section):

> V1 exposes only the installed `arch_guard` executable and the root `arch-guard`
> dispatcher as public arch-guard interfaces. `lib/arch_guard` is a private Dune
> implementation library used to link that executable and local test probes; it is not
> installed or documented as `arch-index.guard`, and `Arch_guard.render_json` and
> `render_text` are not supported in-process APIs. The analyzer may reset compiler-libs
> global state inside the command process. V1 promises neither restoration of such state
> nor a new subprocess/serialization API for embedding callers.

This preserves FR-034/035's public executable/wrapper behavior
(`specs/guard-division-analysis.md:252-253`) and leaves all 47 FRs, 19 ACs, statuses,
numeric domain obligations, report schema, and output behavior unchanged. It directly
removes the architect's public-boundary premise rather than attempting an incomplete
`Load_path`/`Envaux` restoration.

## Required check corrections

Tighten existing modes, retaining their IDs and mappings:

- **CHECK-1**: use the private trusted Typedtree/CMT fixture seam plus the actual CLI for
  later saturation, over-application, labelled operands, and `None` in original slot 2
  with later arguments. Assert one immediate site, unshifted original slot-2 metadata,
  `UNSUPPORTED` precedence, and the exact sorted/deduplicated accumulated eligibility
  reasons, including unsupported ancestry. This closes FR-002/003/004 and AC-4 rather
  than merely exercising a normal partial application (`specs/guard-division-analysis.md:213-218,272`).

- **CHECK-2**: add owned compiled/seam cases for alpha-renaming; alias-before versus
  alias-inside a refinement; fresh nested/curried/immediately-applied entries beneath
  nonzero, contradictory, and unsupported parents; default/case targets; every loop
  position; multiple unsupported causes; and unaffected later siblings. Assert exact
  reason arrays as well as statuses/census (FR-016, FR-019..031;
  `specs/guard-division-analysis.md:230-246`).

- **CHECK-5**: make its oracle status-aware: numeric statuses require their one exact
  conditional reason from FR-031, and `UNSUPPORTED` requires one or more applicable
  exclusion reasons, never a numeric semantic reason alone. On one multi-site fixture
  containing all five statuses, compare every text site to JSON artifact/id/status/
  primitive/reasons and census; include negative controls for mismatched reason and
  omitted text field. Retain duplicate-coordinate and UTF-8 controls required by AC-19
  (`specs/guard-division-analysis.md:251,257-261,287`).

Add a standalone, non-renumbering **report-context regression command** (for the
CRITICAL/HIGH ratchet):

`rtk proxy node scripts/check-arch-guard.js report-context`

It must invoke the actual built public CLI, not `Arch_guard.render_*` or a renderer
fixture. It must check **both** (1) an accepted zero-site artifact and (2) a classified
fixture, in JSON and text. Each successful output must prove the linked compiler version,
31/63 int width, supplied-artifact scope, same-compiler/same-target and no-source-
freshness assumptions, and all FR-036 limitations (whole-program completeness,
guaranteed execution, confirmed failure, machine-checked proof, interprocedural and heap
reasoning); it must also require the C-5 indirect-operations/omitted-artifacts limitation
in both formats. The command follows the existing checker 0/1/>=2 convention and caps
(`specs/guard-division-analysis.md:317-326`), but is a targeted ratchet, not a seventh
FR/AC or a change to numeric semantics.

## Dune/install feasibility (read-only)

This boundary is feasible with local patterns. The public executable already depends on
the implementation library (`bin/arch_guard/dune:1-4`), while the root wrapper dispatches
only a built binary (`arch-guard:1-9`). Test-only executables are deliberately not
installed (`tezt/fixtures/arch_guard/dune:5-15`) and Tezt consumes built paths with
`%{exe:...}` (`tezt/lib/dune:71-86`), so private probes do not require a public package
API. The generated install manifest currently contains the public binary
(`_build/default/arch-index.install:216-238`) separately from the current public guard
library payload (`_build/default/arch-index.install:135-163`); making the latter private
leaves the former as the documented installed input. This is a design/read-only finding,
not a Dune/source edit or an assertion that the stale manifest already reflects it.

## Remaining consistency obligation

Update documentation/install assertions to remove `arch-index.guard` as a public API and
state the CLI-only boundary. Do not remove local implementation-library linkage or private
probe capability. The current public exposure is explicit in `lib/arch_guard/dune:1-4` and
the current embedding functions are exposed by `lib/arch_guard/arch_guard.mli:5-6`; their
absence from the installed public surface must be tested as part of the corrected
`@install`/package evidence.
