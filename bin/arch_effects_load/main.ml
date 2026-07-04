(** arch-effects-load — NDJSON effects stream → SQLite effects tables.

    Usage: arch-effects-load <db> [--migration <sql>]

    Reads effect records from stdin (NDJSON, one per line):
      {"type":"effect","function_name":"pkg.Fn","file_path":"x.go",
       "value_kind":"HashTbl","target":"myMap","soundness":"sound",
       "producer":"arch-effects-go"}

    Writes to the effects tables in <db>.  If [--migration] is given,
    applies the effects schema migration DDL first (idempotent). *)

open Cmdliner

let run db_path migration_path allow_skip =
  (* Apply migration if requested (or if the table is missing) *)
  let needs_migration =
    match migration_path with
    | Some _ -> true
    | None ->
      (* Probe: if function_effects table absent, look for the default migration.
         NB: Sqlite3.exec returns OK on a zero-row result, so we must detect an
         actual row via the callback rather than the return code. *)
      let probe = Sqlite3.db_open db_path in
      let has = ref false in
      (match Sqlite3.exec_no_headers probe ~cb:(fun _ -> has := true)
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='function_effects' LIMIT 1"
       with _ -> ());
      ignore (Sqlite3.db_close probe);
      not !has
  in
  if needs_migration then begin
    let sql_path = match migration_path with
      | Some p -> p
      | None ->
        (* Try relative to the binary location *)
        let here = Filename.dirname Sys.argv.(0) in
        Filename.concat here "effects-schema-migration.sql"
    in
    match Arch_effects.Effects_db.migrate ~db_path ~migration_sql_path:sql_path with
    | Error msg ->
      Printf.eprintf "arch-effects-load: migration failed: %s\n%!" msg;
      exit 1
    | Ok () -> ()
  end;
  match Arch_effects.Effects_load.load ~allow_skip ~db_path stdin with
  | Error msg ->
    Printf.eprintf "arch-effects-load: %s\n%!" msg;
    exit 1
  | Ok r ->
    Printf.printf "arch-effects-load: %d effects written, %d skipped\n%!"
      r.Arch_effects.Effects_load.n_effects
      r.Arch_effects.Effects_load.n_skipped

let db_arg =
  let doc = "Path to the SQLite database (must exist; created by arch-load or arch_callgraph_ocaml)." in
  Arg.(required & pos 0 (some file) None & info [] ~docv:"DB" ~doc)

let migration_arg =
  let doc = "Path to the effects schema migration SQL file. \
             Auto-applied if the function_effects table is absent." in
  Arg.(value & opt (some string) None & info ["migration"; "m"] ~docv:"SQL" ~doc)

let allow_skip_arg =
  let doc = "Load the parseable records even if some NDJSON lines are malformed. \
             By default a malformed line aborts the load with a non-zero exit." in
  Arg.(value & flag & info ["allow-skip"] ~doc)

let cmd =
  let doc = "Load NDJSON effect records into an arch-index SQLite database." in
  let info = Cmd.info "arch_effects_load" ~doc in
  Cmd.v info Term.(const run $ db_arg $ migration_arg $ allow_skip_arg)

let () = exit (Cmd.eval cmd)
