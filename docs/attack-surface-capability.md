# Attack-Surface Capability Layer (Phase 2)

Phase 2 adds a **multi-dimensional attack-surface map** on top of the Phase-1
call graph and effects index.  It answers questions like:

- Which functions are reachable by one actor role vs. another?
- Which operations are gated behind a feature flag, and what unsets that flag?
- Which pairs of operations touch the same mutable value (e.g. `balance`,
  `resource`, `quota`) from distinct actor roles — the classic confused-deputy
  / race-condition surface?

The layer is a static-analysis fact store.  A downstream model generator can
consume these facts to produce falsifiable system properties (e.g. a Quint or
TLA+ model), but the fact store itself is agnostic to any particular consumer
or codebase.

---

## Schema contract

### Phase-2 columns on `function_effects`

The migration (`capabilities-schema-migration.sql`) adds six nullable columns to
the existing `function_effects` table:

| Column              | Type   | Values / format                                                   | Source       |
|---------------------|--------|-------------------------------------------------------------------|--------------|
| `reachability_class`| TEXT   | `validate\|apply\|internal_op\|rpc\|external_op\|node_local\|init` | **Static**   |
| `actor_role`        | TEXT   | comma-separated, free-form: e.g. `any\|user\|admin\|operator\|service\|external` | Sidecar |
| `temporal_class`    | TEXT   | comma-separated, free-form: e.g. `init_time\|validate_time\|apply_time\|window_open\|boundary` | Sidecar |
| `gating`            | TEXT   | `flag(X)\|auth(Y)\|cost(Z)\|none`                                  | **Static**   |
| `value_touched`     | TEXT   | JSON array: `[{"kind":"balance","direction":"debit"}, ...]`       | Sidecar      |
| `precondition`      | TEXT   | free-form state predicate: `"state.flag_enabled = true"`          | Sidecar      |

**Statically derivable** means the extractor populates these from source file
paths or call-site patterns.  **Sidecar** means an agent or human must supply
the value via a `.capabilities.yaml` file.

The `actor_role` and `temporal_class` vocabularies are **not fixed** — the
columns are free text.  The example tokens above are just conventions; pick a
vocabulary that fits the system under analysis.

`NULL` = not yet determined.  Downstream tools treat `NULL` as "any" (safe
over-approximation).

### `attack_edges` table

```sql
CREATE TABLE attack_edges (
    id          INTEGER PRIMARY KEY,
    from_action TEXT NOT NULL,
    to_action   TEXT NOT NULL,
    edge_type   TEXT NOT NULL
        CHECK(edge_type IN ('sequence','removes_guard','shares_resource','actor_distinct')),
    evidence    TEXT,
    source      TEXT CHECK(source IN ('static','sidecar','manual')),
    created_at  TEXT DEFAULT (datetime('now'))
);
```

Edge semantics:

| `edge_type`        | Meaning |
|--------------------|---------|
| `sequence`         | `from_action` is typically followed by `to_action` in a single transaction or unit of work |
| `removes_guard`    | `from_action` unsets a gate/flag that `to_action` requires (creates a temporal ordering constraint) |
| `shares_resource`  | Both actions touch the same mutable resource — pruning signal |
| `actor_distinct`   | The composition is interesting when performed by two *different* actors |

---

## Static vs sidecar derivation

### What the static extractor fills

`Capability_extractor.make_static_record` derives:

1. **`reachability_class`** — from the source file path (heuristic keyword
   match; returns `NULL` when no keyword is present):
   - path contains `validate` → `validate`
   - path contains `apply` → `apply`
   - path contains `rpc` → `rpc`
   - path contains `internal` + `operation`/`op` → `internal_op`
   - path contains `init` or `genesis` → `init`
   - path contains `mempool`, `p2p`, `node`, or `shell` → `node_local`
   - path contains `operation`/`op` → `external_op`

2. **`gating`** — from direct callee names (priority order):
   - callee contains `gas.check` / `check_gas` / `fees.check` / `assert_gas` → `cost(gas)`
   - callee contains `signature.check` / `bls.check` / `check_signature` → `auth(signature)`
   - callee contains `assert_manager` / `check_manager` / `check_source` → `auth(manager_key)`
   - callee matches `check_*_enabled` / `assert_feature_*` / `*_feature_enabled` → `flag(X)`

These keyword lists are **heuristic defaults**, not a fixed contract.  On a
codebase that uses different conventions they simply yield `NULL`, and the
sidecar supplies the value instead.

### What requires a sidecar

- `actor_role` — which actors can trigger this action
- `temporal_class` — which window/phase applies
- `precondition` — required state invariant
- `value_touched` — which value flows occur
- `attack_edges` — composition edges between actions

---

## Sidecar YAML format

Sidecar files are named `<component>.capabilities.yaml` and placed alongside
the source component.  Load with `arch-sidecar-load <db> <sidecar.yaml>`.

```yaml
capabilities:
  - fn: "Module.function_name"
    actor_role: ["user", "admin"]
    temporal_class: ["validate_time", "window_open"]
    precondition: "state.account_registered = true"
    gating: "auth(manager_key)"

  - fn: "Another.function"
    actor_role: "operator"
    temporal_class: "window_open"
    value_touched: [{"kind": "resource", "direction": "debit"}]

attack_edges:
  - from: "Module.fn_a"
    to: "Module.fn_b"
    edge_type: "removes_guard"
    evidence: "fn_a sets flag X that fn_b requires"

  - from: "Store.open"
    to: "Store.finalize"
    edge_type: "sequence"
    evidence: "open must precede finalize"
```

**Notes:**
- `actor_role` and `temporal_class` accept either a YAML list or a
  comma-separated string scalar.
- Sidecar values **override** statically-derived values field-by-field on merge
  (only non-`None` fields from the sidecar win).
- Parse errors on individual items are skipped with a warning; the file load
  never aborts entirely.
- A non-empty sidecar that yields **zero** capabilities and **zero** attack
  edges is rejected (`arch-sidecar-load` exits non-zero) — this is almost
  always a schema/dialect mismatch rather than an intentional empty file.

---

## The 5 capability queries

All queries require the Phase-2 schema.  Apply the migration once:

```bash
sqlite3 arch.db < capabilities-schema-migration.sql
```

### 1. `capabilities-of <component>`

List all actions in a component with their Phase-2 attributes.
`<component>` is a case-insensitive substring matched against `file_path` and
`function_name`.

```
arch-query arch.db capabilities-of validate
```

Output columns: `function_name`, `rclass`, `actor_role`, `temporal_class`,
`gating`, `value_touched`, `precondition`, `soundness`.

### 2. `compose <action>`

Show the **forward composition frontier** of an action: all `sequence` and
`removes_guard` edges from that action.

```
arch-query arch.db compose "Validate.apply_operation"
```

Output columns: `to_action`, `edge_type`, `evidence`, `to_rclass`, `to_actor_role`.

Use case: find what an attacker can do *next* after triggering `action`.

### 3. `removes-guard <guard>`

Find all actions whose `gating` matches `<guard>` (substring), together with
any `removes_guard` edges pointing at them.

```
arch-query arch.db removes-guard "flag(feature_x"
```

Output columns: `gated_action`, `gating`, `unlocker`, `evidence`.

Use case: find all paths that can remove a safety gate.

### 4. `actor-paths <value-kind>`

Find pairs of actions that both touch `<value-kind>` (e.g. `balance`,
`resource`, `quota`, `supply`) but are attributed to **different actor roles**.
These are the classic cross-role value-flow opportunities.

```
arch-query arch.db actor-paths balance
```

Output columns: `action_a`, `actor_a`, `action_b`, `actor_b`,
`value_touched_a`, `value_touched_b`.

Use case: identify cross-actor value-interaction candidates for downstream
property generation.

### 5. `prune <component-A> <component-B>`

Pruning signal: check whether component A and component B share a
`shares_resource` edge.  If they do, an attack-surface slice that covers A
must also cover B — they cannot be pruned independently.

```
arch-query arch.db prune validate apply
```

Output: either `PRUNE: no shared resource found` (safe to prune) or
`DO NOT PRUNE: N shared_resource edge(s)` (followed by the edge list).

---

## How Phase 2 feeds a downstream model generator

The capability fact store is the **contract** for a downstream model/property
generator (e.g. Quint, TLA+):

1. Each `function_effects` row with `reachability_class` becomes an **action**
   in the appropriate phase machine.
2. `actor_role` determines which **principal** can invoke the action.
3. `temporal_class` places the action in the correct **temporal guard**.
4. `gating` becomes a **precondition** on the action's enablement.
5. `value_touched` generates **state-variable update** templates.
6. `attack_edges` of type `removes_guard` generate **action-ordering
   invariants** to falsify.
7. `attack_edges` of type `actor_distinct` seed **multi-principal interaction
   properties**.

`NULL` attributes are treated as universally quantified (any value, any actor,
any window) — conservative but sound for the downstream layer.

---

## Workflow summary

```
# 1. Build the arch-index (Phase 1 — call graph + effects)
arch-load --src /target/src arch.db
arch-effects-ocaml /target/src | arch-effects-load arch.db

# 2. Apply Phase-2 migration (idempotent)
sqlite3 arch.db < capabilities-schema-migration.sql

# 3. Load agent sidecar annotations
arch-sidecar-load arch.db target.capabilities.yaml

# 4. Query
arch-query arch.db capabilities-of <component>
arch-query arch.db compose "Module.action"
arch-query arch.db removes-guard "flag(feature_x"
arch-query arch.db actor-paths balance
arch-query arch.db prune <component-A> <component-B>
```
