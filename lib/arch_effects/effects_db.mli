(** Effects database writer.

    Applies [effects-schema-migration.sql] to an existing arch-index SQLite
    database (or a fresh one) and writes [function_effects] rows.

    This module is the write side of Capability A; the read side is
    [arch-query mutators-of / effects-of] (shell queries in arch-query). *)

(** [migrate db_path migration_sql_path] applies the effects schema migration
    DDL to the database at [db_path].  Idempotent: uses IF NOT EXISTS throughout.
    Returns [Ok ()] or [Error msg]. *)
val migrate : db_path:string -> migration_sql_path:string -> (unit, string) result

(** [write_effects ~db_path effects] inserts the given [effect_record] list into
    [function_effects] (direct rows, [is_direct = 1]).  Resolves [function_id]
    by joining on [functions.name] when available.
    Returns [(n_inserted, n_skipped)] or raises [Failure] on a fatal DB error. *)
val write_effects
  :  db_path:string
  -> Extractor_intf.effect_record list
  -> (int * int, string) result
