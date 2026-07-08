# Task — arch-gardening-queries

Make arch-index's existing-but-dormant curation tables usable: the schema already defines unsafe_params (curated newtype-debt ledger, architecture-schema.sql:125), coverage (:140), gardening_tasks (:155), gardening_log (:171) and views v_unsafe_params/v_low_coverage/v_open_tasks — but no arch-query subcommand reads any of them and nothing populates coverage. Add: (1) read-only arch-query subcommands over these tables (low-coverage [N], gardening [open|log], unsafe-params ledger listing with fixed-status filter); (2) a small coverage NDJSON loader (arch-coverage-load) so CI coverage tools can populate the coverage table generically; (3) docs for the curation workflow (how the ledger rows get inserted — documented SQL, matching miaou/octez practice). Read-only query surface; no schema changes.

Item 5/5 (rescoped: tables pre-exist; this ships the query surface + coverage loader). Items 1-3 = PRs #3/#4/#5 (stack); item 4 verified already-present.
