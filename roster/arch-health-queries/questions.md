# Research Questions — arch-health-queries

_Generated: 2026-07-08_
_DO NOT include the task description in this file or share it with the researcher._

1. What does /home/mathias/dev/arch-index/lib/arch_index/arch_index_compare.ml implement — its function-body normalization/hashing approach, its public interface (.mli if any), which binaries or commands currently invoke it, and what data it needs (DB columns or source files)?
2. Which health-oriented views and columns already exist in /home/mathias/dev/arch-index/architecture-schema.sql (v_large_files, v_large_functions, v_undocumented, v_most_called, v_high_deps, type_fields, type_constructors, type_usage) — their exact definitions, thresholds, and whether any CLI subcommand or view consumer reads them today?
3. How do the health commands in /home/mathias/dev/octez-manager/tools/arch_query.ml work (lines ~986–1100): `type-search` (field-name/-type matching semantics, flags), `god-modules`, `large-files`, `large-functions`, `missing-docs`, `missing-mli`, `unsafe-strings` — SQL shapes, threshold flags, and output formats?
4. How is the `unsafe_params` concept modeled in /home/mathias/dev/octez-manager (table population, what counts as unsafe, the 3+ repetition rule) and in /home/mathias/dev/miaou/docs/architecture-schema.sql lines 88–101 (columns, tracking fields)? Who populates these tables in each repo?
5. What function-body or signature data does each arch-index ingest path actually store (LSP path, CMT path via bin/arch_callgraph_ocaml, NDJSON arch-load) — specifically: signature column contents, parameter type availability, and whether any body text or hash is captured anywhere?
6. What conventions do the newest arch-query subcommands follow on the current feature branches (metrics subcommand, feature-detection via pragma_table_xinfo, exit-code taxonomy 0/1/2/3, limit/truncation patterns in lib/arch_mcp) that a reader should treat as the house style for query additions?
