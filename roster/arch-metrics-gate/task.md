# Task — arch-metrics-gate

Add a metrics/compare regression gate to arch-index: an `arch-query metrics` command emitting machine-readable codebase metrics JSON, an `arch-query compare` command diffing current metrics against a committed baseline and failing on regression, and a `.metrics-accept` reviewed-waiver protocol (per-metric bounds with inline reasons) so intentional regressions can be accepted.

Reference implementations to study:
- ~/dev/octez-manager/tools/arch_query.ml (cmd_metrics, cmd_compare, .metrics-accept)
- ~/dev/epure/tools/arch_query_impl.ml (metrics/compare wired into pre-commit)
- ~/dev/aegis-cloth/kb/arch-metrics-baseline.json (LOC caps, fan-in growth thresholds)

This is item 1 of a 5-item consolidation roadmap (2: MCP server over arch-query stdio, ref ~/dev/epure/src/mcp_server/mcp_server_arch.ml; 3: code-health query pack — duplicate-function detection via body hash, unsafe-params, god-module/large-file/missing-docs, type-shape search; 4: language registry auto-detect + ts-morph TS enricher from epure; 5: gardening/coverage tables). Each item runs its own full pipeline cycle.
