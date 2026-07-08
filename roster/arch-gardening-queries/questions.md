# Research Questions — arch-gardening-queries

_Generated: 2026-07-08_
_DO NOT include the task description in this file or share it with the researcher._

1. What are the exact column definitions, constraints, and generated columns of `unsafe_params`, `coverage`, `gardening_tasks`, and `gardening_log` in /home/mathias/dev/arch-index/architecture-schema.sql (:125-180), and what do the views `v_unsafe_params`, `v_low_coverage`, and `v_open_tasks` select?
2. How does the existing NDJSON loader (`arch-load`, lib/arch_db/arch_load.ml) parse records, validate fields, report errors, and what exit-code contract does it follow (including its abort-on-malformed behavior)?
3. How do the effects/sidecar loaders (`bin/arch_effects_load/`, `bin/arch_sidecar_load/`) structure their NDJSON ingestion into an EXISTING DB (no DROP) — idempotency (INSERT OR IGNORE / UNIQUE indexes), meta stamping, and reporting?
4. How do miaou (~/dev/miaou/docs/architecture-schema.sql :88-144) and octez-manager document or populate their unsafe_params/gardening/coverage tables — sample INSERT patterns, status/category vocabularies, and any tooling that writes them?
5. What house conventions do the newest arch-query subcommands and selftests follow on the current feature branches (health-branch helpers hq_*, exit taxonomy, selftest fixture patterns)?
