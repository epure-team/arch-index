# Pattern report

_Role: pattern finder (Terra mapping for unavailable Haiku)_

## Traversal and path patterns

```ocaml
| Tmod_structure s -> List.iter (item ~prefix) s.str_items
| Tmod_functor (_, body) -> module_expr ~prefix body
| Tmod_constraint (inner, _, _, _) -> module_expr ~prefix inner
| Tmod_apply _ | Tmod_apply_unit _ | Tmod_ident _ | Tmod_unpack _ -> ()
```

`lib/arch_index/arch_index_cmt.ml:191-196` — definition traversal descends definition-bearing bodies and stops at references/applications.

```ocaml
| Path.Papply _ | Path.Pextra_ty _ -> "<apply>"
```

`lib/arch_index/arch_index_cmt.ml:745-756` — nested applied path prefixes are rendered as `<apply>`; this is formatting, not instance materialization.

```ocaml
match Hashtbl.find_opt module_alias_stamps (Ident.unique_name id) with
```

`lib/arch_index/arch_index_cmt.ml:1374-1392` — alias rewriting uses binder identity and preserves path segments below the root.

## Call-state patterns

- `Head_unknown` becomes `MAY_TOP`; `Head_enumerated` becomes `MAY_ENUMERATED`; unique unconditional saturated local/qualified heads become `MUST` (`lib/arch_index/arch_index.ml:878-892`).
- Multiple distinct qualified targets become `MAY_TOP/ambiguous_unit`; no indexed qualified target remains a nullable external leaf unless it is known dropped (`lib/arch_index/arch_index.ml:1458-1490`).
- Graph loading traverses `MUST ∪ MAY_ENUMERATED`, keeps `MUST` separately, and records `MAY_TOP` as a frontier (`lib/arch_tools/arch_graph.ml:28-33`, `lib/arch_tools/arch_graph.ml:84-120`).

## Fixture patterns

- Curried functor and two applications: `tezt/tests/ocaml_shapes.ml:53-71`; application non-materialization assertions: `tezt/tests/ocaml_shapes.ml:256-265`.
- Anonymous `include struct`: `tezt/tests/callgraph_nested.ml:130`; `module M = Make (Impl)`: `tezt/tests/callgraph_nested.ml:155`; no `M.%` definitions: `tezt/tests/callgraph_nested.ml:202-207`.
- Alias scopes, intermediate segments, functor-parameter calls: `tezt/tests/module_alias_heads.ml:74-180`.
- Ambiguous qualified unit: `tezt/tests/qualified_library_scoping.ml:342-364`.
- Exception declaration/rebind identity: `tezt/tests/exn_raise_sets.ml:28-35`, `tezt/tests/exn_raise_sets.ml:262-267`, `tezt/tests/exn_raise_sets.ml:395-411`.
- Bounded and top graph behavior: `tezt/tests/contract.ml:22-52`, `tezt/tests/contract.ml:138-167`.
