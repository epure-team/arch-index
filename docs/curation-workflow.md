# Curation workflow — ledgers & coverage

The schema ships three human-curated ledgers (`unsafe_params`, `gardening_tasks`,
`gardening_log`) and a `coverage` snapshot table. Queries are read-only
(`arch-query low-coverage | gardening | unsafe-params`); rows get in as follows.

## Ledgers: documented SQL (no CLI writes by design)

Ledger curation is a reviewed, human act — matching miaou/octez practice, inserts
are plain SQL. The blocks below are **executed verbatim by `selftest-health.sh`**
against a canonical-schema fixture, so they cannot drift from the schema.

The typical flow for `unsafe_params`: run the *heuristic* first
(`arch-query <db> unsafe-strings 3` — string fields repeated ≥3 times), review the
candidates, then record the accepted ones in the *ledger*:

<!-- selftest:begin -->
```sql
-- record a newtype-debt item (function looked up by name + module path)
INSERT INTO unsafe_params (function_id, param_name, current_type, target_type, github_issue)
SELECT f.id, 'instance', 'string', 'Instance_name.t', 42
FROM functions f JOIN modules m ON f.module_id = m.id
WHERE f.name = 'huge_fn' AND m.path = 'src/big.ml';

-- open a gardening task against a module
INSERT INTO gardening_tasks (github_issue, category, title, target_module_id, status)
SELECT 99, 'split-file', 'split src/big.ml', m.id, 'open'
FROM modules m WHERE m.path = 'src/big.ml';

-- log completed gardening work
INSERT INTO gardening_log (date, contributor, category, description, pr_number, issue_number)
VALUES ('2026-07-08', 'mathias', 'type-safety', 'introduced Instance_name.t', 101, 42);
```
<!-- selftest:end -->

Mark a ledger item done:

```sql
UPDATE unsafe_params SET fixed = 1, fixed_at = datetime('now') WHERE github_issue = 42;
UPDATE gardening_tasks SET status = 'done', completed_at = datetime('now') WHERE github_issue = 99;
```

Note: `arch-query gardening open` lists `status != 'done'` (open **and**
in_progress) — broader than the `v_open_tasks` view, which counts `open` only.

## Coverage: NDJSON contract (`arch-coverage-load`)

One record per line; pipe into an existing main-schema DB:

```json
{"type":"coverage","function":"huge_fn","module":"src/big.ml","covered_lines":8,"total_lines":10}
```

- `module` is optional but required when the function name is ambiguous
  (resolution is exactly-one-match; anything else is skipped and counted).
- `covered_lines ≤ total_lines`, both ≥ 0; `total_lines = 0` is legal (0%).
- One run = one snapshot: all rows share a `recorded_at` stamp
  (`--stamp YYYY-MM-DDTHH:MM:SSZ`, strict UTC, default now). Re-running with the
  same stamp is idempotent (`ignored`); a new stamp appends history —
  `arch-query low-coverage` always evaluates the **latest** snapshot per function.
- Any malformed record aborts the whole run (exit 2) with rollback: a snapshot
  is all-or-nothing.

```sh
your-coverage-tool --export-ndjson | ./arch-coverage-load --db index.db
./arch-query index.db low-coverage 50
```

Adapters from specific tools (bisect_ppx, istanbul, …) are out of scope by
design — the NDJSON line above is the interface.
