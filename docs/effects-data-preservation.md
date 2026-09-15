# Effects data preservation

The OCaml effects pipeline associates an effect with a function only when the
source identity is exact. In the native schema this means the effect's
lexically-normalized `file_path` equals `modules.path` and its name equals
`functions.name`. The alternative ID schema uses `functions.file_path`.
Provided paths never fall back to basename, suffix, underscore conversion, or
name-only lookup. A missing path may use a unique exact name; ambiguity,
unmatched input, and flat schemas retain the effect with a NULL `function_id`.

Effect payload identity includes function name, optional file path, value kind,
optional target, producer, directness, and soundness. NULL and an empty string
are distinct. Reloading an equal payload recomputes its association: a changed
association is repaired in place (retaining the effect row ID), while an
unchanged row is counted as a duplicate.
Path normalization governs association, not loss of the supplied payload:
`src/./a.ml` and `src/a.ml` may bind the same function but remain distinct raw
payload spellings. Reloading the identical supplied spelling remains idempotent.

Schema preparation and each write batch use one SQLite transaction. SQL
preparation, binding, stepping, index creation, and commit failures return an
error and roll back the batch. The canonical identity-index migration never
deletes rows to resolve conflicts; incompatible legacy duplicates or
constraints make migration fail unchanged.

For the CMT producer, relative `cmt_sourcefile` metadata is interpreted against
the explicitly selected source root, independent of the object directory.
Contained absolute paths become root-relative, outside-root paths remain
absolute, missing metadata stays absent, and normalization is lexical. For
supported top-level variable bindings, Typedtree declaration order names the
earlier definitions `f#1`, `f#2`, and the live final definition `f`.

These guarantees do not add nested/lambda effect discovery, reconstruct
already-lost historical payloads, relocate arbitrary metadata, or make output
streaming atomic with the committed database transaction.

## Exact CMT copies

Within one index run, an exact copy may reuse a successfully extracted graph
under the same root, resolved source and compiler unit. Reuse checks full bytes
against the representative and its stored SHA-256. The cache retains paths and
digests, not all artifact bytes or typedtrees. Inputs must remain immutable;
changed/unreadable inputs and partial graph extraction cannot authorize reuse.
The cache is recreated on each run. This is not independently compiled variant
unification; nonidentical same-source artifacts still follow explicit rejection.

Each selected artifact spelling, including a symlink, retains its own catalogue
and binding collection. Sharing graph facts does not turn a failed collection
into a successful one or grant it a completion marker. Issue #68 remains partial;
independent compilation variants are assigned to the later functor stage.
