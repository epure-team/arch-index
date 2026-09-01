# ADR 002 — arch-index as an integrator of external analysers

**Status:** Proposed
**Date:** 2026-09-01

## Context

arch-index already ingests from four external sources: `arch-load` (NDJSON, the documented
bring-your-own-producer contract), `arch-coverage-load` (LCOV), `arch-effects-load`, and
`arch-sidecar-load` (`.capabilities.yaml`). Its producers delegate the hard semantics to mature
frontends — `golang.org/x/tools/go/ssa` + CHA for Go, `rustc_private` MIR for Rust, the OCaml
`.cmt` typedtree, and LSP servers (`ocamllsp`, `gopls`, `rust-analyzer`, `pylsp`,
`typescript-language-server`) for the rest.

The integration surface is therefore not new. What is missing is breadth of adapters, and a
decision about what merging facts from tools of *differing rigour* does to the edge-kind lattice.

That question is load-bearing. A Semgrep pattern hit and a `go/ssa` CHA edge are both "a fact
about the code", but only one of them is sound. Merged without distinction, the lattice stops
meaning anything and arch-index becomes a data lake with SQL on top — which is the one thing it
has never been.

## Decision

**arch-index accepts facts from any external analyser, and records the rigour of each fact as
first-class data.**

Three soundness classes, stamped per fact and per producer run:

| Class | Meaning | Examples |
|---|---|---|
| `sound_with_top` | Over-approximate; unresolvable cases are marked ⊤, never dropped | `go/ssa`+CHA, rustc MIR, OCaml CMT producer |
| `heuristic` | Best-effort; absence proves nothing | Semgrep, clippy, staticcheck, gosec, grep-likes |
| `asserted` | A human or agent claim | `.capabilities.yaml`, curation ledgers, discharge assumptions |

**The governing rule: a `heuristic` fact may raise a finding, but may never discharge a ⊤ anchor
and may never license a `PASS`.** It can add information; it cannot subtract uncertainty. This is
the existing "un-⊤-marked index can never yield PASS" invariant extended to imported facts.

**Coverage is recorded, not implied.** Every (language × analysis) pair a run *could* have covered
is recorded with its outcome, including `not_analysed`. A query over a language no adapter
supports returns `NOT_ANALYSED`, never zero rows. This repository has already been bitten by the
inverse: `v_pure_functions` once certified every function pure because the effects table was
empty, which is why `Arch_db.nonempty` exists and why `tezt/tests/effects.ml` asserts "a producer
with no extractor still satisfies the contract". Imported analyses inherit that discipline rather
than re-learning it.

**Two adapter formats are preferred over N bespoke loaders:**

- **SARIF in** — findings from Semgrep OSS, clippy, staticcheck, gosec, Infer and most linters.
  Ingested as `heuristic`.
- **SCIP in** (Sourcegraph, Apache-2.0) — symbols and references from `scip-typescript`,
  `scip-python`, `scip-java`, `rust-analyzer`. Ingested as `MAY_ENUMERATED` with a recorded
  producer, **never** as `MUST`: an indexer's reference is not a proof of a unique call target.

Preference for adapters is free/open-source and fast, in that order. CodeQL is deliberately
excluded: it is free only for open-source use, and its unsoundness is parameterised
(`accessPathLimit`, `fieldFlowBranchLimit`, one level of virtual-dispatch context, suites graded
on precision rather than recall), so importing it faithfully would mean modelling those knobs.

## Consequences

**Good.** One adapter buys many tools. arch-index becomes the place where per-language, per-tool
results are joined against a sound call graph — and the join is what nobody else offers. The
sharpest instance: dependency-vulnerability alerts (osv-scanner, Trivy) triaged by *sound*
reachability. Commercial SCA reachability sells this with 60–95% alert-reduction claims while
being unsound by construction, so "not reachable" there is a triage guess. Here it is a result,
because ⊤ blocks `PASS`.

**Bad.** Provenance columns touch every ingest path, and the coverage matrix is one more thing
that can go stale. Adapters are ongoing maintenance against other projects' output formats.

**Rejected alternative — merge without soundness classes.** Simpler, and destroys the property
the tool exists for. A single unsound edge silently licensing a `PASS` is worse than no
integration.

**Prerequisite.** `functions.language` and `functions.universe` (FR-001,
`SPEC-sound-callgraph.md`) do not exist. `language_registry.mli` detects the language at index
time and discards it. The coverage matrix cannot be expressed without them, so the language tag
is foundational to this ADR rather than an optional refinement.
