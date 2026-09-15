(** Effects database writer.

    Applies [effects-schema-migration.sql] to an existing arch-index SQLite
    database (or a fresh one) and writes [function_effects] rows.

    This module is the write side of Capability A; the read side is
    [arch-query mutators-of / effects-of] (shell queries in arch-query). *)

(** [migrate db_path migration_sql_path] applies the effects schema migration
    DDL to the database at [db_path]. Re-running preserves existing rows;
    rebuilding the payload index refuses incompatible duplicates atomically.
    Returns [Ok ()] or [Error msg]. *)
val migrate : db_path:string -> migration_sql_path:string -> (unit, string) result

(** [write_effects ~db_path effects] atomically inserts or re-associates direct
    effect rows. Main-schema association joins [functions.module_id] to
    [modules.path]; alternative schemas use [functions.file_path]. Supplied
    paths are matched exactly after lexical normalization, while a missing path
    binds only a unique exact name. Flat schemas retain NULL associations.

    The returned pair is [(written, unchanged_duplicates)]. Any preparation,
    binding, stepping, or commit error rolls the batch back and returns [Error]. *)
val write_effects
  :  db_path:string
  -> Extractor_intf.effect_record list
  -> (int * int, string) result
