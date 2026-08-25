# Plan — sound-qualified-name-resolution

Spec: `specs/sound-qualified-name-resolution.md`. Intake: `briefs/…-intake.md`.
Sequenced so the red test exists before any production change.

## Step 1 — the red test (no production change)
Add a multi-library Tezt fixture. No such fixture exists: all 8 OCaml callgraph fixtures are
single-library (verified). Nearest shape to copy: `tezt/tests/ocaml_shapes.ml:172-183`
(`arch_tezt_qual`), but that is intra-library nesting — this one needs two `(library ...)` stanzas.
`with_fixture` (`tezt/lib/arch_tezt.ml:329-333`) already accepts arbitrary relative paths, so no
harness work.

Fixture: `liba/{dune,api.ml}`, `libc/{dune,api.ml}` (both define `run`), `libb/{dune,caller.ml}`
calling `Liba.Api.run ()`. Assertions per CHECK-1 (correct owner, or MAY_*; never MUST to libc)
and CHECK-2 (alias/include stays MAY_TOP).
**Gate: this test must FAIL on current `main`. Record the red output.** (Falsifier F4.)

## Step 2 — preserve library identity through the extractor
`path_to_module_name` (`arch_index_cmt.ml:499-510`) flattens `Path.Pdot` to `(Some "Api", "run")`,
discarding the persistent root ident that names the dune library. Carry the root through to the
pending call/dep/type-usage records so the resolver can use it. This is additive: a new field
alongside the existing qualified name, so nothing downstream breaks until step 3 reads it.

## Step 3 — resolve within the owning library, degrade otherwise
Rewrite `resolve_qualified` (`arch_index.ml:321-338`): when the root names a known library, look up
the inner module **only among that library's modules**; when the root is absent or names nothing
known, emit `MAY_TOP` rather than falling back to the global basename table.
**Hard constraint (F2): no single-candidate narrowing may re-stamp `MUST`.** A `MUST` requires a
positively identified owner, not "one survivor after filtering".

## Step 4 — the other two sites
Apply the same rule at `arch_index.ml:421-432`/`:443-453` (module deps) and `:479-493` (type
usages). Three instances of one bug (AC2). Also add `ORDER BY` or drop the ambiguous tables
entirely — a non-deterministic winner is not acceptable even as a fallback.

## Step 5 — self-index re-baseline, explained
Re-run the self-index; update `test/fixtures/self-index-stats.txt` **with the edge-kind delta
stated in the commit message** (AC4). Check F3: the MUST count must not collapse
(current: MUST 1107 / MAY_ENUMERATED 2106 / MAY_TOP 178). Run `arch-rules … --on-vacuous fail`.

## Verification gates
`dune build` → 0 · `dune runtest` → all green incl. the new fixture · self-index golden diff
reviewed, not auto-promoted · `arch-rules --on-vacuous fail` exit 0.

## Risks
- **Precision loss** (F3) if library identity is unavailable more often than expected → measure on
  the self-index before/after; if MUST collapses, stop and report rather than shipping a vacuous P1.
- **`(wrapped false)` libraries** — untested territory (noted as unverified in research); must
  degrade, not guess.
- **Out of scope, do not touch**: `call_graph_extractor.ml` raw-name keying, `arch_query`
  `WHERE name=?`, `is_dune_alias_module`, LSP nominal path.
