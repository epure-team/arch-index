# Analyzer report

_Role: analyzer (Sol mapping for unavailable Sonnet)_

## Confirmed implementation facts

- The CMT producer accepts `Implementation structure`; an absent annotation or unresolved source path yields empty pending collections. Compiler unit identity comes from `cmt_modname` (`lib/arch_index/arch_index_cmt.ml:2755-2767`).
- The shared nested traversal descends named modules, recursive modules, includes, literal structures, functor bodies, and constraints. It stops at applications, unit applications, identifiers/aliases, and unpacking; `mb_id = None` is not descended (`lib/arch_index/arch_index_cmt.ml:162-198`).
- Dependency extraction accepts `Tmod_ident` through constraints only (`lib/arch_index/arch_index_cmt.ml:721-726`).
- Functor bodies are visited in isolated deferred blocks for call conditionality (`lib/arch_index/arch_index_cmt.ml:2518-2528`).
- Definitions use a flat qualified name below their source-file module. The schema makes `modules.path` unique and `functions` unique on `(module_id, name)` (`architecture-schema.sql:61-64`, `architecture-schema.sql:81-126`).
- Module aliases are keyed by binder identity and recorded only for persistent-root targets; application, literal structure, unpack, functor-parameter targets, and unit-local roots are declined (`lib/arch_index/arch_index_cmt.ml:1044-1079`, `lib/arch_index/arch_index_cmt.ml:1080-1108`).
- Qualified call resolution enumerates possible compilation-unit/name readings, de-duplicates target ids, and distinguishes one result, multiple results, and no indexed result (`lib/arch_index/arch_index.ml:896-922`, `lib/arch_index/arch_index.ml:1006-1022`, `lib/arch_index/arch_index.ml:1318-1333`).
- Resolver state is distributed across `callee_id`, `kind`, and `top_reason`, rather than stored in one resolution enum (`architecture-schema.sql:208-253`).
- Query `UNKNOWN` is a computed reachability outcome with a reachable unresolved frontier (`bin/arch_query/arch_query.ml:358-395`); exception `NOT_ANALYSED` means the producer contract/evidence is absent (`lib/arch_tools/arch_exn.ml:22-26`, `lib/arch_tools/arch_exn.ml:91-93`).

## Confirmed gaps

- No dedicated persisted definition-body or module-instance entity was found in the producer schema.
- Existing application fixtures assert that applied functor results do not create definition rows.
- No direct fixture was found that resolves an applied member whose compiler path itself contains `Papply`.
- No call-row uniqueness constraint is present in `calls`.
