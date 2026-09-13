# Locator report

_Role: locator (Terra mapping for unavailable Haiku)_
_Method: path/name search only; file contents were not inspected by this role._

Likely implementation entry points:

- `lib/arch_index/arch_index_cmt.ml` — CMT traversal, path and call-head extraction.
- `lib/arch_index/arch_index.ml` — relational insertion and call-target resolution.
- `lib/arch_index/arch_index_support.ml` — source-path and producer-table support.
- `lib/arch_index/arch_index_db.ml` — row insertion.
- `lib/arch_tools/arch_graph.ml` — loaded call-graph identity and traversal.
- `bin/arch_query/arch_query.ml` — query verdicts.
- `architecture-schema.sql` — relational entities and constraints.

Located test surfaces:

- `tezt/tests/ocaml_shapes.ml`
- `tezt/tests/callgraph_nested.ml`
- `tezt/tests/module_alias_heads.ml`
- `tezt/tests/qualified_library_scoping.ml`
- `tezt/tests/point_free_aliases.ml`
- `tezt/tests/exn_raise_sets.ml`
- `tezt/tests/contract.ml`
- `tezt/tests/top_anchor_taxonomy.ml`
- `tezt/tests/query_limits.ml`

This report is only an orientation artifact. All claims retained in `research.md` were independently checked against live source.
