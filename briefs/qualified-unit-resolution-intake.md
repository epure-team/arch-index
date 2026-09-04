# Intake Brief — qualified-unit-resolution

**Date:** 2026-09-04
**Mode:** full
**Type:** fix (soundness) — with an observable-output change, so a spec is required
**Status:** VALIDATED
**Roadmap:** Phase 1, the resolver half of item 1.6

## Goal

A qualified OCaml call such as `Liba.Api.run` must resolve to the function in **the library the
caller actually links**, or be marked ⊤ if that cannot be established — never to a same-named file
in an unrelated library, and never stamped `MUST` when it was a guess.

## The defect, stated precisely

Resolution currently keys on the **capitalised file basename** (`Api`) in a project-wide table
with last-writer-wins semantics. Reproduced on `origin/main@cde3aad`
(`briefs/qualified-unit-resolution-research.md`, Finding 1):

```
caller       | callee_name    | kind | resolved_to
app/main.ml  | Liba.Api.run   | MUST | libb/api.ml      <-- WRONG library
app/main.ml  | Libb.Api.run   | MUST | libb/api.ml      <-- right, by coincidence
```

Two failures compound here, and the second is the serious one:

1. **Wrong attribution** — the edge points at another library's function.
2. **Dishonest confidence** — it is stamped `MUST` with no ⊤ marker, so every downstream consumer
   (`arch-rules`, `arch-impact`, reachability closure) treats a guess as a proven fact. A wrong
   `MUST` is worse than an honest `MAY_TOP`, because it can turn a real violation into a `PASS`.

**Scale, corroborated independently:** peer session `arch-index-0e`'s error-channels review
measured **540 of 14 452** `proto_alpha` function names as shared across modules. Homonyms are not
a toy case in this codebase's target corpora.

## Scope boundary

**In scope**
- `resolve_module_root` and the qualified-name resolution path in `lib/arch_index/arch_index.ml`
  used by the **call** resolution phase.
- Replacing basename keying with exact dune unit-name reconstruction, disambiguated per Finding 4
  (below), degrading to ⊤ on genuine ambiguity.
- Tests that pin each resolution shape, ported/adapted from the abandoned branch.
- Wiring the regression checks into CI so this class of defect cannot ship green again.

**Out of scope (documented, not silently dropped)**
- `functions.qualified_name` as a stored, UNIQUE column (the roadmap's own framing of item 1.6).
  Research showed resolver correctness is **separable** from persisting a qualified identity, and
  is independently valuable and shippable. The column becomes a follow-up item.
- The `module_deps` / `type_usage` resolution sites, **except** as required to not regress them —
  see Open Question 1; they share `resolve_module_root` but have no value name to disambiguate
  with. Any change there must be argued in the spec, not assumed.
- `bin/arch_serve`'s independent traversal code, and the LSP/flat-schema producers.
- Anything in the abandoned `rebase/sound-qual` branch's implementation.

## Approach (from research, not assumption)

Reconstruct the exact dune unit name and evaluate **both** structurally valid readings of
`Root.File.rest`:

- **(a)** `Root` is a library/executable wrapper, `File` a unit inside it → unit `Root__File`
- **(b)** `Root` IS the compilation unit, `File` a module nested inside that file

Disambiguate by **looking each reading up in the function table with the name it implies**
(Finding 4). A module alias (`module Bar = Bar`) contributes no function row, so in the common
both-readings-live case exactly one reading hits. Two hits = a genuine homonym → ⊤. Zero hits =
falls through to existing external-leaf handling.

**Explicitly rejected:** disambiguating on `cmt_imports` interface digests — the design the
abandoned branch's round-2 verdict approved. Research Finding 3 disproved it: in the
both-readings-live case the caller imports **all** candidate units (`Foo`, `Foo__`, `Foo__Bar`),
so digests cannot discriminate. Recorded here so it is not re-proposed.

## Relevant files

| File | Why |
|---|---|
| `lib/arch_index/arch_index.ml` | `resolve_module_root`, `resolve_qualified`, the call-classification match; also the `dropped_local`/`dropped_qualified` and `top_reason` logic from roadmap 1.4 that must keep working |
| `lib/arch_index/arch_index_cmt.ml` | Where unit names/module identities are collected from `.cmt` files |
| `tezt/tests/qualified_unit_names.ml` | To be created/ported — the per-shape fixtures |
| `checks/` | To be ported — regression checks; currently exists only on the abandoned branch |
| `.github/workflows/ci.yml` | To wire the checks in (they are useless unwired) |
| `test/fixtures/self-index-stats.txt` | ADR 001 golden; will move if resolution improves |

## Quality gates

- Build: `dune build --root . @all` — **always with `--root .`** (research Finding 6: a bare
  `dune` roots itself at `/tmp` in this environment and behaves nonsensically).
- Tests: `dune test --root . --force`.
- Self-index golden regenerated per ADR 001, **with the delta attributed**, not absorbed.
- Both ported regression checks run and pass, and are wired into CI.
- **Attribution gate (peer coupling) — escalated.** Per `arch-index-0e` (2026-09-04), exception
  **identities are canonical qualified paths** (e.g.
  `Tezos_raw_protocol_alpha__Tez_repr.Subtraction_underflow`), printed verbatim in every
  `may-fail`/`raises` answer and **matched on** by `fails-with <E>`. So this fix does not merely
  move module attribution — it can change **user-visible identity strings**, and therefore change
  which functions a `fails-with` query returns. Consequences to plan for, not discover:
  1. The frozen counts in `docs/exception-raise-sets-validation.md` may move → **attribute, never
     update the expected values**.
  2. Any identity whose spelling changes silently changes `fails-with` results → the spec must
     require a **before/after identity diff** on at least one external corpus, not just counts.
  3. Ping `arch-index-0e` to re-verify spellings on both corpora **before** merge.

## Open questions for the spec phase

1. **`module_deps` / `type_usage` sites.** They call the same `resolve_module_root` but have no
   referenced value name, so Finding 4's disambiguator does not apply. Options: accept ⊤ there;
   use digests *only* there (where "caller never imported this unit at all" IS refutable); or
   leave those two sites on today's behavior and scope this task to calls. Must be decided
   explicitly — the abandoned branch changed all three sites at once and the architect flagged the
   resulting tri-state inconsistency as a real finding.
2. **Ratchet metric.** The ported `no-must-null-regression.js` hard-codes `BASELINE = 1975`, a
   one-machine artifact. Replace with a reproducible metric — candidate: count only
   MUST-with-NULL-callee rows whose root resolves to an **indexed** unit, ratcheted at 0.
3. **Golden blindness.** The abandoned branch's round-2 review proved the self-index golden is
   blind to this defect class (regenerating it with `main`'s binary was byte-identical). The spec
   should say what new measurement actually detects a regression here.

## Prior art / why this is a reimplementation

Branch `rebase/sound-qual` attacked this defect and failed review twice (rounds 1 and 2, both
NO-GO, both for regressions invisible to every gate). Decision taken with the human on 2026-09-04:
reimplement against current `main` rather than rebase, because round 3 was a redesign anyway,
`main` has since evolved the same file (roadmap 1.4's `dropped_node`/`top_reason`), and merging two
independently-evolved versions of soundness-critical resolution logic is precisely the failure mode
that produced both NO-GOs. That branch's fixtures and checks are ported; its resolver is not.

Full evidence: `briefs/qualified-unit-resolution-research.md`.
