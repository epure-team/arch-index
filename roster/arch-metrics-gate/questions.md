# Research Questions — arch-metrics-gate

_Generated: 2026-07-08T00:00:00Z_
_DO NOT include the task description in this file or share it with the researcher._

1. How is the `arch-query` CLI structured in /home/mathias/dev/arch-index — where are subcommands registered, how are arguments parsed, and what conventions do existing subcommands follow for implementation and wiring?
2. What machine-readable (JSON or similar) output formats do existing `arch-query` subcommands emit, and what serialization helpers or schema conventions are used in the codebase?
3. What aggregate codebase statistics (e.g., function counts, call counts, lines of code, fan-in/fan-out) does arch-index currently compute or store, and where in the SQLite schema and query layer do those live?
4. How do `cmd_metrics` and `cmd_compare` work in /home/mathias/dev/octez-manager/tools/arch_query.ml — what metrics are collected, what is the JSON structure, how is the baseline compared, and how does the `.metrics-accept` waiver file format and parsing work (per-metric bounds, inline reasons)?
5. How does /home/mathias/dev/epure/tools/arch_query_impl.ml integrate its metrics/compare flow into the pre-commit hook — what exit-code and failure-reporting conventions does it use, and how is the baseline file located and committed?
6. What structure and thresholds does /home/mathias/dev/aegis-cloth/kb/arch-metrics-baseline.json use (LOC caps, fan-in growth thresholds), and how are per-metric tolerances expressed?
7. How does arch-index currently handle golden/baseline files and non-interactive execution — where are goldens stored and regenerated, how are diffs against them checked in tests or CI, and what error-handling, exit-code, and pre-commit/CI integration patterns already exist?
