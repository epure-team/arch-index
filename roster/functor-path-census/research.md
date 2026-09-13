# Research — functor-path-census

Generated2026-09-13. Mode full; online enabled. Six code questions and one ecosystem
question. Three fresh blind Sol/Terra roles; root handled locator from paths only.
No new corpus measurements performed in this research phase.

## Q1 — locations

Collector: lib/arch_index/arch_index_bindings.ml; syntax catalogue:
lib/arch_index/arch_index_functors.ml; reader: lib/arch_tools/arch_functor_bindings.ml.
Tests: tezt/tests/functor_bindings.ml, scripts/check-functor-bindings.js.
Measurements: roster/functor-binding-resolution/measure-bindings.js,
measurement/binder_census.ml, tezos-irmin-bindings/report.json; input manifest:
roster/functor-instance-resolution/tezos-irmin-candidate/manifest-410.tsv.
Paths are relative to /home/mathias/dev/arch-index, located with rg --files.

## Q2 — counts and retained rows

report.json:10 records1275applications,202matched,1073unresolved; query limit0
returned no individual rows. report.json:24-49 records1050 unsupported_path;
report.json:77-119 partitions them279Irmin/771protocol.
measure-bindings.js:39-45 uses count(*), not identity-distinct counts. The report
does not retain per-application paths. The temporary DB is removed at:50-53.
These figures count applications, not distinct paths or resolved module identities.

## Q3 — path and identity representation

arch_index_bindings.ml:169-175 accepts Pident heads and rejects other Tmod_ident
paths as unsupported_path. Recursive application heads advance a literal telescope
at:152-168. Constraints are peeled at:41-42. Actual-argument roots follow Pdot
but reject applied/extra-type paths and persistent roots at:179-197.
Identity comparisons use Ident.same(:62); serialized keys use Ident.unique_name(:44).
The syntax catalogue supplies original Typedtree heads and ordinals at
arch_index_functors.ml:73-103. Producer integration is arch_index.ml:666-676.

## Q4 — ownership and environments

arch_index_bindings.ml:78-104 preindexes module bindings, letmodules and parameters
from module expressions/types. Duplicate identities fail at:62-76. Literal functor
declarations retain location, identity and telescope at:106-134.
Resolution matches local identities, follows Pident-only aliases, detects cycles
and distinguishes persistent/parameter/missing heads at:136-177. No Env lookup
exists in that collector. Pdot member ownership is not recovered by this logic.

## Q5 — corpus metadata

manifest-410.tsv:1-3 defines slice/contentSHA/absoluteCMTpath. Four selected slices
contain66Irmin-core,17pack,52pack-unix and275proto-alpha CMTs
(tezos-irmin-candidate/report.md:27-44). provenance.json:2-21 records compiler5.3.0
and hashes. producer.log:1-4 records410CMT/0CMti; :6-19 records509dependencies,
405resolved. No per-unit dependency rows or separate CMI inventory are retained
in the aggregate binding report. This does NOT establish CMI absence on disk or
absence of embedded interface/import metadata inside CMTs.

## Q6 — existing patterns and exact assertions

tezt/tests/functor_bindings.ml:372-403: F/Alias/Alias2 Pident chain; one matched app.
:405-431: F(A)(B); two app ordinals, one declaration, formal positions2and1.
:434-479: nested/shadowed/local/class/recursive bindings; six apps, four distinct
same-named F identities. :482-522: Set.Make produces unsupported_path;
application-valued alias produces unsupported_alias_rhs; parameter produces
parameter_supplied_head. Seven apps, four matches, distinct actual-root assertions.
:646-783: synthetic duplicate IDs/collisions, alias cycles, missing/persistent
Pident and formal-kind mismatch. These are premise-specific tests, not a census.

## Q7 — external prior art

OCaml5.3 Path.t includes Pident/Pdot/Papply/Pextra_ty; flatten reports Contains_apply:
https://github.com/ocaml/ocaml/blob/5.3/typing/path.mli#L18-L58
Ident.same distinguishes local binding identity from name-equal persistent IDs:
https://github.com/ocaml/ocaml/blob/5.3/typing/ident.mli#L18-L64
Typedtree retains resolved paths, binding UIDs and node environments:
https://github.com/ocaml/ocaml/blob/5.3/typing/typedtree.mli#L600-L659
Types.Mty_alias represents module aliases:
https://github.com/ocaml/ocaml/blob/5.3/typing/types.mli#L483-L509
Env exposes summaries, find_module, lookup_module and normalize_module_path:
https://github.com/ocaml/ocaml/blob/5.3/typing/env.mli#L18-L101
https://github.com/ocaml/ocaml/blob/5.3/typing/env.mli#L286-L323
CMI records unit/signature/import CRCs:
https://github.com/ocaml/ocaml/blob/5.3/file_formats/cmi_format.mli#L29-L46
CMT stores imports, initial environment, load paths, UID declarations and shapes;
it may embed a CMI when no separate interface exists:
https://github.com/ocaml/ocaml/blob/5.3/file_formats/cmt_format.mli#L18-L100

## Coverage gaps

No saved per-path records, distinct-identity counts, CMI inventory or per-unit
dependency rows. Source establishes collector behavior, not what a fresh lookup
would return. External citations use maintained5.3 branch, not immutable5.3.0 tag.
Pattern role's inference from0CMti to absent CMI metadata was narrowed above:
CMti and CMI are different formats; CMT can itself contain interface metadata.
No graph orientation/claims reconciler installed. No code change proposed here.
