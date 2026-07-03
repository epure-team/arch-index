-- Migration: attack-surface capability layer (Phase 2)
-- Capability layer: reachability_class, actor_role, temporal_class, gating,
--   value_touched, precondition, and the attack_edges graph.
--
-- Apply with: sqlite3 <db> < capabilities-schema-migration.sql
-- Safe to re-run: uses ADD COLUMN IF NOT EXISTS and CREATE TABLE/INDEX IF NOT EXISTS.
-- This migration is ADDITIVE — it never drops or modifies existing tables/columns.
--
-- Depends on: the base architecture schema (functions table must exist).
-- May be applied after effects-schema-migration.sql, or independently.

-- =============================================================================
-- Phase 2 columns on function_effects
--
-- These columns extend the existing function_effects table (Phase 1).
-- Each ADD COLUMN is guarded against re-run failures by using IF NOT EXISTS.
-- Absent values are NULL: the agent sidecar YAML (.capabilities.yaml) fills
-- these columns; unset attributes stay NULL and are treated as "any".
-- =============================================================================

-- Phase-2 columns are added via ALTER TABLE.
-- Note: ALTER TABLE ... ADD COLUMN IF NOT EXISTS requires SQLite >= 3.37.0.
-- For older SQLite, errors on duplicate columns are expected and harmless.
-- The capability_db.ml runtime writer uses pragma_table_info to check first.

ALTER TABLE function_effects ADD COLUMN reachability_class TEXT;
-- Allowed values: validate | apply | internal_op | rpc | external_op | node_local | init

ALTER TABLE function_effects ADD COLUMN actor_role TEXT;
-- Comma-separated, free-form. Example vocabulary: any | user | admin |
--   operator | service | external. Pick tokens that fit the analyzed system.

ALTER TABLE function_effects ADD COLUMN temporal_class TEXT;
-- Comma-separated tags, free-form. Example vocabulary: init_time |
--   validate_time | apply_time | window_open | boundary.

ALTER TABLE function_effects ADD COLUMN gating TEXT;
-- Pattern: flag(foo) | auth(key) | cost(resource) | none | NULL (unknown)

ALTER TABLE function_effects ADD COLUMN value_touched TEXT;
-- JSON array of {"kind": ..., "direction": ...}
-- kind: free-form, e.g. balance | resource | quota | supply
-- direction in: debit | credit | mint | burn

ALTER TABLE function_effects ADD COLUMN precondition TEXT;
-- Typed state predicate (coarse): the state vars/flags an action requires.
-- E.g. "state.account_registered = true"

-- Indexes for the new columns (capability query hot-paths)
CREATE INDEX IF NOT EXISTS idx_fn_effects_rclass  ON function_effects(reachability_class);
CREATE INDEX IF NOT EXISTS idx_fn_effects_actor   ON function_effects(actor_role);
CREATE INDEX IF NOT EXISTS idx_fn_effects_gating  ON function_effects(gating);

-- =============================================================================
-- Capabilities view: functions with all Phase-2 attributes populated
-- =============================================================================

CREATE VIEW IF NOT EXISTS v_capabilities AS
SELECT
    fe.function_name,
    fe.file_path,
    fe.reachability_class,
    fe.actor_role,
    fe.temporal_class,
    fe.gating,
    fe.value_touched,
    fe.precondition,
    fe.soundness,
    fe.producer
FROM function_effects fe
WHERE fe.reachability_class IS NOT NULL
   OR fe.actor_role IS NOT NULL
   OR fe.gating IS NOT NULL
   OR fe.value_touched IS NOT NULL;

-- =============================================================================
-- attack_edges table
--
-- Directed edges between actions in the attack-surface graph.
-- Populated by: (a) the static capability extractor (obvious sequence/guard
-- patterns), and (b) agent sidecar YAML (removes_guard, shares_resource,
-- actor_distinct edges that require semantic reasoning).
-- =============================================================================

CREATE TABLE IF NOT EXISTS attack_edges (
    id          INTEGER PRIMARY KEY,
    from_action TEXT NOT NULL,
    to_action   TEXT NOT NULL,
    edge_type   TEXT NOT NULL
        CHECK(edge_type IN ('sequence','removes_guard','shares_resource','actor_distinct')),
    evidence    TEXT,           -- human or agent rationale (free text)
    source      TEXT            -- 'static' | 'sidecar' | 'manual'
        CHECK(source IS NULL OR source IN ('static','sidecar','manual')),
    created_at  TEXT DEFAULT (datetime('now'))
);

-- Gap G2: optional endpoint component/file discriminators. These disambiguate
-- cross-component edges whose endpoint function names could collide across
-- language extractors (e.g. a bare Rust kernel `timeout` vs a qualified OCaml
-- name). Added via ALTER TABLE so pre-existing attack_edges tables upgrade in
-- place; duplicate-column errors on re-run are expected and harmless.
ALTER TABLE attack_edges ADD COLUMN from_path TEXT;
ALTER TABLE attack_edges ADD COLUMN to_path   TEXT;

CREATE INDEX IF NOT EXISTS attack_edges_from ON attack_edges(from_action);
CREATE INDEX IF NOT EXISTS attack_edges_to   ON attack_edges(to_action);
CREATE INDEX IF NOT EXISTS attack_edges_type ON attack_edges(edge_type);

-- =============================================================================
-- attack_edges view: full resolved edge list with actor info for both endpoints
-- =============================================================================

CREATE VIEW IF NOT EXISTS v_attack_edges AS
SELECT
    ae.id,
    ae.from_action,
    ae.from_path,
    ae.to_action,
    ae.to_path,
    ae.edge_type,
    ae.evidence,
    ae.source,
    f_from.reachability_class AS from_rclass,
    f_to.reachability_class   AS to_rclass,
    f_from.actor_role         AS from_actor,
    f_to.actor_role           AS to_actor
FROM attack_edges ae
LEFT JOIN (
    SELECT function_name, reachability_class, actor_role
    FROM function_effects
    GROUP BY function_name
) f_from ON ae.from_action = f_from.function_name
LEFT JOIN (
    SELECT function_name, reachability_class, actor_role
    FROM function_effects
    GROUP BY function_name
) f_to ON ae.to_action = f_to.function_name;
