# Functor application catalogue

`arch-query DB functor-applications [limit]` reports a persisted inventory of
immediate OCaml module applications found in the selected CMT artifacts of one
completed producer run. It is syntactic provenance, not target resolution,
defunctorization, runtime instance counting, a closed-world statement, or a
source-freshness check.

The optional limit is strict non-negative ASCII decimal (`50` by default; `0`
returns the summary and no application rows). Invalid, prefixed, negative,
overflowing, or extra positional values exit 2. A completed catalogue requires a
nonempty selected input set and every selected input collected. Missing schema,
markerless state, and inconsistent persisted facts are refused with exit 3; a
completed zero-occurrence catalogue is successful and distinct from refusal.

Successful output has a summary table followed by applications. The summary
columns are `contract, selected_inputs, collected_inputs, total, returned,
truncated, scope, limitations`; v1 fixes `scope` to
`selected_cmt_syntax_only` and `limitations` to
`not_runtime_instances;not_closed_world;no_target_resolution;no_source_freshness_check;paths_are_artifact_selections`.
Application columns are `artifact, source, compiler_unit, ordinal,
application_kind, location, head, argument, diagnostics`. Applications sort by
artifact then ordinal. In `ARCH_QUERY_FORMAT=json`, the two tables are two JSON
arrays separated by one newline; descriptor/location/diagnostic cells remain
JSON-valued strings.

An occurrence identity is exact selected artifact path plus its positive preorder
ordinal. Paths are not realpath/inode/digest identities: copies and symlink path
strings can be different selected inputs. `apply` and `apply_unit` are the only
application kinds. Operand descriptors are deliberately shallow (`path`,
`structure`, `functor`, `unpack`, `constraint`, `application`, and unit only for
an `apply_unit` argument); nested applications are separate rows. A `Papply`
inside an identifier remains a path descriptor with `contains_apply=true`, not
an extra occurrence or a resolved target.

Locations use compiler byte columns. An invalid location is represented by null
file/coordinates while retaining `ghost` and `unusable_location`; ghostness by
itself does not invalidate a valid location. Diagnostics are sorted unique
syntax warnings only and never evidence of target resolution.

## Build and inspect

Rebuild the project's CMT artifacts first, then run the OCaml producer with the
main schema (version 1.16). Existing databases need a full reindex; reading an old
database does not migrate or collect anything.

```sh
arch-callgraph-ocaml --build-dir _build/default --db-path architecture.db --schema-path architecture-schema.sql
ARCH_QUERY_FORMAT=json arch-query architecture.db functor-applications 2
```

The producer replaces the catalogue on reindex. `functor_catalogue_runs` stores
the selected-input count; `functor_catalogue_inputs` stores each exact artifact
selection and expected occurrence count; `functor_applications` stores occurrences.
For example, diagnostic SQL can inspect partial collection without granting it
the query's completion guarantee:

```sql
SELECT artifact, outcome, expected_applications
FROM functor_catalogue_inputs
ORDER BY artifact;
```

Each input has one of `unreadable`, `unsupported_annotation`, `missing_source`,
`dropped_module`, `collection_failed`, or `collected`. Failed inputs have no
application rows. A module insertion collision is `dropped_module`, not success
borrowed from a previously indexed copy. A collected input may have zero
applications. The `functor_catalogue_contract=v1` marker is cleared before
replacement and earned separately after complete catalogue data is committed.
An empty selection, or any failed input, cannot earn it. This marker is separate
from call-graph and exception-analysis completion.

All formats (`box`, `list`, `json`, `csv`, `line`, `markdown`) follow the existing
renderer; in particular list and CSV output do not introduce header records.
JSON always includes the second array, even when it is `[]`. All persisted rows
are checked before applying the limit. Refusals have empty stdout, with diagnosis
precedence `UNSUPPORTED_SCHEMA`, then `NOT_COLLECTED` (including available failure
counts), then `INCONSISTENT_CATALOGUE`. Operational database failures exit 2.

## Authenticated formal-member targets

The main CMT producer can add a bounded target when the same artifact proves the
whole chain from a collected functor application to a named formal slot, a
supported local named actual module, and a direct or invocation-safe one-hop
member body. For example, a body call `X.f` plus a matched local `F(A)` may add
`A.f` as `MAY_ENUMERATED`.

This is additive evidence, not defunctorization or a closed-world result. The
original `X.f` `MAY_TOP/module_param` row remains, no application-specific body
or function is cloned, and the correspondence never creates or upgrades a
`MUST` edge. Persistent and cross-unit actuals, `Path.Papply`, module aliases,
anonymous structures, unpacked modules, opaque members, multi-hop aliases, and
Shapes/UID reconciliation remain outside this contract. The flat LSP producer
does not infer these targets.

`functor_target_inputs` records the outcome and expected witness count for every
selected artifact. `functor_target_witnesses` retains each positive proof even
when several applications deduplicate to the same canonical call row. A witness
links the application ordinal, declaration/formal position and key, actual and
member paths, physical caller occurrence, candidate call row, and target
function row. `functor_target_contract=v1` is written only after every selected
input and every expected witness passes the complete foreign-key and semantic
join validation. Missing, partial, corrupt, or failed target provenance remains
unmarked rather than appearing as an empty successful result.

Diagnostic SQL can inspect the supported subset:

```sql
SELECT cm.path AS caller_path, caller.name AS caller, c.call_site,
       tm.path AS target_path, target.name AS target,
       w.artifact, w.application_ordinal, w.formal_position,
       w.actual_path, w.member_path
FROM functor_target_witnesses w
JOIN calls c ON c.id = w.candidate_call_id
JOIN functions caller ON caller.id = c.caller_id
JOIN modules cm ON cm.id = caller.module_id
JOIN functions target ON target.id = w.target_function_id
JOIN modules tm ON tm.id = target.module_id
ORDER BY caller_path, caller, c.call_site, target, w.artifact,
         w.application_ordinal;
```

On the fixed 410-artifact Tezos/Irmin corpus, the Stage-4 gate compares against
the frozen Stage-3 snapshot and currently attributes seven new resolved
relations in Irmin and none in the protocol slice, with zero relation loss and
zero new `MUST`. These are corpus observations for the supported local subset;
they are not a completeness, whole-program, or performance claim.
