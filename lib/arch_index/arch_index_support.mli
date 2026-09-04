(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

type intent_backup = {
  module_intents : (string * string) list;
  function_intents : (string * string * string) list;
  type_intents : (string * string * string) list;
}

(** Views dropped before recreating architecture schema.

    {pre}
    (none)

    {post}
    Returns the list of view names that must be dropped before schema recreation.

    {violators}
    (none)

    {violates}
    (none) *)
(** The [comment_db_meta] keys whose PRESENCE claims an analysis RAN to
    completion.

    Listed beside the drop lists because they share their contract: after a
    re-index, nothing in the database may assert more than the current run
    actually produced. [comment_db_meta] is deliberately not dropped (the
    [self_managed] allowlist in {!module:Schema_drop_list}), so these keys
    outlive a re-index unless something removes them — which {!Arch_index.run}
    does twice, once before the schema is demolished and once after it is
    rebuilt.

    ONE list, because the failure is silent: a fourth marker spelled only at
    its producer site would survive a killed re-index and answer for a run that
    produced nothing, and no existing test would fail.

    {pre}
    (none)

    {post}
    Every key returned is written by this producer and is load-bearing for a
    consumer's "was this analysed?" decision.

    {violators}
    (none)

    {violates}
    (none) *)
val completion_marker_keys : string list

val schema_views_to_drop : string list

(** Tables dropped in dependency-safe order before schema recreation.

    {pre}
    (none)

    {post}
    Returns the list of table names in the order they must be dropped.

    {violators}
    (none)

    {violates}
    (none) *)
val schema_tables_to_drop : string list

(** Backup non-null intent fields before rebuilding index tables.

    {pre}
    (none)

    {post}
    Returns an [intent_backup] snapshot of all non-null intent and comment quality fields.

    {violators}
    (none)

    {violates}
    (none) *)
val backup_intents : Sqlite3.db -> intent_backup

(** Restore backed-up intent fields after rebuilding index tables.

    {pre}
    [backup] must have been produced by [backup_intents] on the same schema.

    {post}
    Writes backed-up intent and comment quality data back to the rebuilt tables; returns unit.

    {violators}
    (none)

    {violates}
    (none) *)
val restore_intents : Sqlite3.db -> intent_backup -> unit

(** Resolve source path for a [.cmt], including [.pp.ml] original files.

    {pre}
    (none)

    {post}
    Returns [Some path] with the source file path relative to [project_root], or [None] if unresolvable.

    {violators}
    (none)

    {violates}
    (none) *)
val source_path_of_cmt :
  project_root:string -> Cmt_format.cmt_infos -> string option
