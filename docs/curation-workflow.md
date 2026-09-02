# Curation workflow: measure → decide → ledger

The pile's rule: never confuse "I don't know" with "no", and never gate on a score. This is
what that rule looks like applied to code health.

- **Fact** (A1) — exact, binary. `arch-query missing-mli`, `arch-query missing-docs`.
- **Measure** (A2) — an exact number, sorted. `arch-query large-files`, `arch-query
  large-functions`, `arch-query god-modules`. The number is true; "too big" is a judgement call.
  None of these commands can fail a build — there is no `--fail-on-...` flag to reach for.
- **Proof** (A3) — a verdict a machine can actually stand behind. `arch-body-compare duplicates`
  proves two function bodies hash identical after whitespace normalisation; it never reports an
  "approximate" duplicate.
- **Human judgement, recorded** (B) — what A can only measure or prove, a human decides. That
  decision is written to a ledger with provenance (who, when, which issue/PR), not left as a
  comment on a PR nobody will find again in six months.

Nothing A produces ever gates a build by itself. What gates review is either a proof (A3, or the
pile's existing sound gates — `arch-impact`, `arch-rules`) or a human decision recorded here.

## The flow

1. **Measure or prove** (A). `arch-query god-modules`, `arch-query large-functions`,
   `arch-body-compare duplicates`, `arch-query missing-docs` surface candidates. None of them
   fail a build; they inform review.
2. **Decide** (a human, or an agent acting on a human's behalf). Is this god-module intentional?
   Is this duplicate worth de-duplicating now, later, or never? Is this `string` param actually a
   type-safety risk?
3. **Record** (B, `arch-curate`). The *decision* — not the raw measurement — goes into the
   ledger, with who decided and why: a GitHub issue, a PR.
4. **Read back** (B, `arch-query`). `low-coverage`, `gardening open|log`, `unsafe-params` let
   anyone — human or agent — see what was already decided, so the same god-module doesn't get
   re-litigated every sprint.

## Reading the ledgers

```sh
./arch-query docs/architecture.db low-coverage 20        # least-covered, latest snapshot only
./arch-query docs/architecture.db gardening open          # tasks not yet done (open + in_progress)
./arch-query docs/architecture.db gardening log            # append-only history, newest first
./arch-query docs/architecture.db unsafe-params             # unfixed string-typed params (default)
./arch-query docs/architecture.db unsafe-params fixed        # ...or fixed|all
```

Every one of these refuses with exit 3 on an index that doesn't carry the table it needs (a flat
`arch-load` index, or a main-schema DB that predates a migration) — never a silent empty result
that reads as "nothing to report".

## Feeding the coverage ledger

`arch-coverage-load` appends one snapshot per invocation from a name-keyed NDJSON stream —
independent of `arch-coverage`'s own LCOV/reachability report, so any CI coverage tool can feed
it:

```sh
your-coverage-tool --format-per-function \
  | jq -c '{function: .name, covered_lines: .covered, total_lines: .total}' \
  | ./arch-coverage-load docs/architecture.db
```

A function name shared by more than one module is silently IGNORED unless you also give
`module` (a `modules.path` value) to disambiguate:

```sh
your-coverage-tool --format-per-function \
  | jq -c '{function: .name, module: .file, covered_lines: .covered, total_lines: .total}' \
  | ./arch-coverage-load docs/architecture.db
```

Repeated runs build history (`arch-query low-coverage` always reads the latest snapshot per
function); a malformed record aborts the whole load before a single row is written.

## Recording a decision

### Open a gardening task

```sh
./arch-curate docs/architecture.db open-task \
  --issue 214 --category type-safety \
  --title "installer.ml: string instance id should be typed" \
  --function install_node
```

### Record an unsafe param

```sh
./arch-curate docs/architecture.db add-unsafe-param \
  --function install_node --param instance \
  --current string --target Instance_name.t --issue 214
```

### Mark it fixed, once the PR lands

```sh
./arch-curate docs/architecture.db mark-fixed --function install_node --param instance
```

### Log the work, with provenance

`--contributor` and `--pr` are **required** — this ledger's entire point is recorded provenance,
not an unattributed note:

```sh
./arch-curate docs/architecture.db log \
  --contributor jdoe --category type-safety \
  --description "typed install_node's instance param (Instance_name.t)" \
  --pr 217 --issue 214
```

## Ledger schema reference

`arch-curate` is the supported way to write these tables: it validates, resolves names
exactly-one (refuses rather than guesses on 0 or 2+ matches), and wraps every write in a
transaction. The SQL below is the shape it produces, kept here as a reference — and pinned by
`selftest-curation-doc.sh`, which extracts every ` ```sql ` block on this page and actually runs
it against a fresh `architecture-schema.sql` database, in order. A schema change that breaks this
reference breaks CI instead of quietly going stale.

### `gardening_tasks` — open a task

```sql
INSERT INTO gardening_tasks(github_issue, category, title, target_module_id, target_function_id, status)
VALUES (214, 'type-safety', 'installer.ml: string instance id should be typed',
        NULL, (SELECT id FROM functions WHERE name = 'install_node'), 'open');
```

### `unsafe_params` — record a string-typed param that should be proper

```sql
INSERT INTO unsafe_params(function_id, param_name, current_type, target_type, github_issue)
VALUES ((SELECT id FROM functions WHERE name = 'install_node'),
        'instance', 'string', 'Instance_name.t', 214);
```

### `unsafe_params` — mark it fixed

```sql
UPDATE unsafe_params
SET fixed = 1, fixed_at = '2026-08-07'
WHERE function_id = (SELECT id FROM functions WHERE name = 'install_node')
  AND param_name = 'instance';
```

### `gardening_log` — append an entry

**APPEND-ONLY: there is no UPDATE/DELETE example here, on purpose — `gardening_log` is never
rewritten, only added to.**

```sql
INSERT INTO gardening_log(date, contributor, category, description, pr_number, issue_number)
VALUES ('2026-08-07', 'jdoe', 'type-safety',
        'typed install_node''s instance param (Instance_name.t)', 217, 214);
```

## Constraints (non-negotiable)

- `gardening_log` is **append-only** — `arch-curate` has no edit/delete subcommand against it,
  and this reference carries no UPDATE/DELETE example for it either.
- Every write is **transactional**: it all lands, or none of it does.
- Name resolution is **exactly-one**: a function name matching zero or more than one row is
  refused, never guessed at.
- `github_issue` is UNIQUE per task; `(function_id, param_name)` is UNIQUE per unsafe param —
  re-using either is a clear error, never a silent overwrite.
- Nothing in Livrable A (facts, measures, proofs) gates a build. A threshold with a consequence
  is either a proof (A3) or a decision recorded here — never a `--fail-on-...` flag bolted onto a
  measure.
