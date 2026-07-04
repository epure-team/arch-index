(** Capability database writer — Phase 2.

    Applies [capabilities-schema-migration.sql] to an existing arch-index
    SQLite database and writes capability attributes and attack_edges.

    This module is the write side of Capability Layer B; the read side is
    [arch-query capabilities-of / compose / removes-guard / actor-paths / prune]. *)

open Capability_types

(** [migrate ~db_path ~migration_sql_path] applies the Phase-2 schema migration.
    Idempotent (uses IF NOT EXISTS / ADD COLUMN IF NOT EXISTS).
    Returns [Ok ()] or [Error msg]. *)
val migrate : db_path:string -> migration_sql_path:string -> (unit, string) result

(** [write_capabilities ~db_path records] upserts capability attributes into
    [function_effects] rows.  For each record:
    - If a row with [function_name = cap_function_name] already exists, the
      Phase-2 columns are updated (NULL fields are left unchanged).
    - If no row exists, a new row is inserted with [value_kind = 'UnknownMut']
      and [soundness = 'manual'] as placeholders.
    Returns [(n_updated, n_inserted, n_skipped)] or [Error msg]. *)
val write_capabilities
  :  db_path:string
  -> capability_record list
  -> (int * int * int, string) result

(** [write_attack_edges ~db_path edges] inserts attack edges into [attack_edges].
    Duplicate (from_action, to_action, edge_type) tuples are silently skipped.
    Returns [(n_inserted, n_skipped)] or [Error msg]. *)
val write_attack_edges
  :  db_path:string
  -> attack_edge list
  -> (int * int, string) result
