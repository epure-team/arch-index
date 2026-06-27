(** NDJSON effects record reader + DB writer.

    The NDJSON contract for effects records:
    {[
      {"type":"effect","function_name":"pkg.Fn","file_path":"x.go",
       "value_kind":"HashTbl","target":"myMap","soundness":"sound",
       "producer":"arch-effects-go"}
    ]}

    Pipe: arch-callgraph-go-effects <pkg> | arch-effects-load out.db

    This module handles both reading the NDJSON stream and writing it to an
    effects-migrated SQLite database.  It can operate standalone (without the
    main arch_index OCaml code). *)

type load_result = {
  n_effects   : int;
  n_skipped   : int;
}

(** [load ~db_path ic] reads NDJSON from [ic], writes effect records to
    [db_path] (which must already have the effects tables from the migration).
    Returns [Ok result] or [Error msg]. *)
val load : db_path:string -> in_channel -> (load_result, string) result
