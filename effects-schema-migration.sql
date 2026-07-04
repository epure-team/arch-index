-- Migration: add effects / mutation tracking + value-kind taxonomy
-- Capability A: effects/mutators-of (Phase 1)
-- Apply with: sqlite3 <db> < effects-schema-migration.sql
-- Safe to re-run: all CREATE TABLE/INDEX use IF NOT EXISTS.

-- =============================================================================
-- Value-kind taxonomy
-- A "value kind" is a named category of mutable state that effect analysis
-- tracks. Examples: GlobalVar, FieldAccess, ArrayElem, HashTbl, BytesBuf,
-- HeapRef, IoSideEffect, EnvVar, FileSystem, Network.
-- =============================================================================

CREATE TABLE IF NOT EXISTS value_kinds (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,     -- e.g. 'GlobalVar', 'FieldAccess', 'ArrayElem'
    description TEXT,              -- human-readable explanation
    -- Extension point for capability B (yield-race): add 'race_relevant BOOLEAN'
    -- Extension point for capability D (error-sink): add 'is_error_sink BOOLEAN'
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Seed the standard taxonomy
INSERT OR IGNORE INTO value_kinds(name, description) VALUES
  ('GlobalVar',    'Module-level mutable reference (ref, Hashtbl, array at module scope)'),
  ('FieldAccess',  'Write to a mutable record field'),
  ('ArrayElem',    'Write to an array element (Array.set, array.(i) <- v)'),
  ('HashTbl',      'Hashtbl mutation (add, replace, remove, clear, reset)'),
  ('BytesBuf',     'Bytes/Buffer mutation (Bytes.set, Buffer.add_*)'),
  ('HeapRef',      'Dereference-and-write through a ref (:=) or mutable pointer'),
  ('IoSideEffect', 'I/O side-effect (print, write, send, flush)'),
  ('EnvVar',       'Environment variable mutation (Sys.putenv, os.Setenv, std::env::set_var)'),
  ('FileSystem',   'File-system mutation (write, create, delete, rename, chmod)'),
  ('Network',      'Network I/O (send, connect, listen, accept)'),
  ('UnknownMut',   'Unknown or opaque mutation (used when kind cannot be determined)');

-- =============================================================================
-- Per-function effect/mutation attributes
-- A single function may have multiple mutation records (one per value-kind it
-- can write). This table stores the direct (own) mutations; transitive mutations
-- are computed at query time via the call graph.
-- =============================================================================

CREATE TABLE IF NOT EXISTS function_effects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    -- Identity: function by name + file (mirrors the calls table key space)
    -- NULL function_id means the function is external / not in the main index.
    function_id INTEGER REFERENCES functions(id) ON DELETE CASCADE,
    function_name TEXT NOT NULL,   -- same key as functions.name / calls.caller_name
    file_path TEXT,                -- source file (for display; may be relative)

    -- Mutation attribute
    value_kind_id INTEGER REFERENCES value_kinds(id) ON DELETE SET NULL,
    value_kind TEXT NOT NULL,      -- denormalized for queries without join
    target TEXT,                   -- optional: field name, global name, param name, …
    is_direct BOOLEAN NOT NULL DEFAULT 1,  -- 1=own, 0=transitive (materialized by arch-effects)
    -- Soundness label: how was this determined?
    --   'sound'     - derived from a Tier-1 backend (CMT/MIR/SSA); sound over-approx
    --   'candidate' - derived from Tier-0 (tree-sitter / LSP); may under-approximate
    --   'manual'    - human-annotated
    soundness TEXT NOT NULL DEFAULT 'candidate'
        CHECK(soundness IN ('sound', 'candidate', 'manual')),

    -- Extension point for capability B (yield-race): add
    --   'yield_before BOOLEAN DEFAULT 0,  -- mutation occurs before a yield point'
    -- Extension point for capability D (error-sink): add
    --   'is_error_path BOOLEAN DEFAULT 0, -- mutation is only on error/failure paths'

    -- Producer provenance: which tool/extractor populated this row
    producer TEXT,                 -- e.g. 'arch-effects-ocaml', 'arch-effects-go', 'arch-effects-rust'
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_fn_effects_fname  ON function_effects(function_name);
CREATE INDEX IF NOT EXISTS idx_fn_effects_kind   ON function_effects(value_kind);
CREATE INDEX IF NOT EXISTS idx_fn_effects_fnid   ON function_effects(function_id);
CREATE INDEX IF NOT EXISTS idx_fn_effects_direct ON function_effects(is_direct);

-- Idempotency: identity of an effect row is (function, file, kind, target,
-- producer, direct/transitive). NULL file_path/target/producer fold to '' so
-- re-loading the same NDJSON stream is a no-op (writers use INSERT OR IGNORE,
-- which conflicts on this index instead of duplicating every row).
CREATE UNIQUE INDEX IF NOT EXISTS fn_effects_identity
  ON function_effects(function_name, COALESCE(file_path, ''), value_kind,
                      COALESCE(target, ''), COALESCE(producer, ''), is_direct);

-- =============================================================================
-- Purity / pure flag (per-function summary; derived from function_effects)
-- A function is "pure" iff it has no own or transitive mutations AND no
-- MAY_TOP edges are reachable from it. This view materializes the purity flag
-- for the functions in the main index.
-- =============================================================================

CREATE VIEW IF NOT EXISTS v_pure_functions AS
SELECT
    f.id            AS function_id,
    f.name          AS function_name,
    m.path          AS module_path,
    CASE WHEN EXISTS (
        SELECT 1 FROM function_effects fe WHERE fe.function_id = f.id
    ) THEN 0 ELSE 1 END AS is_pure
FROM functions f
JOIN modules m ON f.module_id = m.id;

-- =============================================================================
-- Mutators-of view: given a value_kind, which functions directly mutate it?
-- For transitive mutators use arch-query mutators-of <kind> (walk the call graph).
-- =============================================================================

CREATE VIEW IF NOT EXISTS v_direct_mutators AS
SELECT
    fe.value_kind,
    fe.function_name,
    fe.file_path,
    fe.target,
    fe.soundness,
    fe.producer
FROM function_effects fe
WHERE fe.is_direct = 1
ORDER BY fe.value_kind, fe.function_name;
