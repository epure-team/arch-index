# Native functor-catalogue probe evidence

Status: root-run evidence is partial and current as of 2026-09-13. Root built successfully, verified the corrected ghost-valid synthetic CMT end-to-end through the real producer, and still owns reruns of the other synthetic modes. No Dune command was run by this task.

## Delivered test-only inputs

- `tezt/fixtures/functor_catalogue/catalogue.ml` is the real source seed. It includes ordinary, structure argument, chained, nested, unit, constrained, inline-head, inline-head/structure, functor-body, local module, unnamed local module, unpack, module-type-of, class method and initializer contexts. It is ordinary compiler-source output, not synthetic evidence.
- `tezt/fixtures/functor_catalogue/typedtree_probe.ml` reads an actual implementation CMT, independently traverses it with OCaml 5.3 `Tast_iterator.default_iterator`, and emits one JSON object. Setup failures (bad arguments, unreadable/non-implementation CMT, absent target shape, failed write/re-read) exit 2; the executable makes no assertion-to-success remapping.
- Synthetic modes are explicitly `synthetic:true`: `papply` rewrites one `Tmod_ident` operand path to `Path.Papply`; `ghost-valid` retains coordinates and sets ghost; `invalid-location` makes endpoint file/coordinates invalid while retaining ghost; `same-position` assigns one valid span to two distinct applications. Each mode re-reads its output and reports before/after application, unit-application, Papply-path and context census.

The re-read census also emits every immediate application's `{valid,ghost,span}` observation. `ghost-valid` requires a valid ghost observation after re-read, `invalid-location` requires an invalid observation after re-read, and `same-position` requires a repeated span after re-read. Setup/operational exceptions, including CMT/IO failures, exit 2; only explicit invariant assertions in the storage/lifecycle/selection probes exit 1.

The future Node checker must require the appropriate `ok`, `synthetic`, `changed`, and before/after premise fields before indexing a rewritten CMT. It must not call synthetic output ordinary source compilation.

## Real storage, selection and lifecycle seams

- `storage_probe.ml` links the real wrapped `Arch_index__Arch_index_functors.store_collected` API. Its owned in-memory trigger raises **after** ordinal 1 is inserted. The probe requires the real savepoint rollback to leave zero catalogue-input/application rows while preserving a pre-existing graph-fact row.
- `selection_probe.ml` calls `Arch_index__Arch_index_functors.selected_inputs`, the internal helper used by the producer; it proves exact-string sort/dedup without realpath/inode collapse. The initial public Arch_index.mli addition was removed during root scope integration: the helper belongs in the authorized new catalogue module, not a new main-library public API. It deliberately does not duplicate selection logic as an oracle.
- `lifecycle_probe.ml` calls the real `clear_contract` at the pre-drop boundary and strengthened `finalize_contract` at the post-commit/pre-marker boundary. Its minimal database includes producer, module path, catalogue-run header, collected input and closed JSON application rows; missing-header, wrong-input-run, wrong-source, dangling-module, expected-count and orphan-application variants must not finalize. Setup/SQL failures exit 2 and invariant failures exit 1. The wrong-input-run and wrong-source cases are test-first additions pending root's product finalizer fix; they must initially fail assertion 1 rather than be called covered.

On any future checker invocation, unavailable executables or missing/unreadable JSON evidence make the relevant setup incomplete (exit 2), not passed or skipped.

## Captured owner-run result

An earlier owner run compiled and exercised the first probe version, but its lifecycle evidence predates the strengthened finalization contract and its synthetic writer had not checked source preservation; it is superseded where stated below.

Root then verified the corrected `Unit_info.make ~source_file ... |> Unit_info.cmt` writer on a fresh-directory `catalogue.cmt` output (the basename is deliberately retained to preserve compiler-unit identity). The initial `Location.input_name`-only attempt failed setup 2 because the re-read CMT had no source mapping; that failure is evidence of the rejected approach, not a pass. The corrected `ghost-valid` output re-read with a ghost location and `source_mapping`, then the real producer exited 0 and recorded the input as `collected`, source `tezt/fixtures/functor_catalogue/catalogue.ml`, compiler unit `Catalogue`, 19 occurrences, and `functor_catalogue_contract=v1`.

`papply`, `invalid-location`, and `same-position` source-preserving producer reruns remain required before this document may call their end-to-end premises green. The real storage/lifecycle/selection probes must likewise be rerun after the strengthened lifecycle and exit-taxonomy changes; do not rely on their earlier prose figures.

Earlier lifecycle evidence predates this strengthened contract and must be replaced by the next owner run. Native results establish premise availability only. Future Node assertions must consume emitted JSON rather than treat this prose as an oracle, and must retain exit 2 for missing/unreadable probe prerequisites.

`same-position` is only equal-coordinate evidence. It does not establish a shared physical Typedtree node, which remains an explicit unimplemented premise; the checker must report setup 2 rather than claim it from same-position.

## Owner compile request

The owner completed this serial request: project-selected targets for all probe executables and the seed library were compiled, the CMT was located from the library build, all modes were invoked, and native tests were wired/run by the owner. Preserve their exact JSON/stdout in the checker evidence package; no Dune command was run by this task.
