(** arch-effects-load — NDJSON effects stream → SQLite effects tables.

    Usage: arch-effects-load <db> [--migration <sql>]

    Reads effect records from stdin (NDJSON, one per line):
      {"type":"effect","function_name":"pkg.Fn","file_path":"x.go",
       "value_kind":"HashTbl","target":"myMap","soundness":"sound",
       "producer":"arch-effects-go"}

    Writes to the effects tables in <db>.  If [--migration] is given,
    applies the effects schema migration DDL first (idempotent). *)

open Cmdliner

let run db_path migration_path allow_skip complete =
  if allow_skip && complete then begin
    Printf.eprintf "arch-effects-load: --complete is incompatible with --allow-skip\n%!";
    exit 2
  end;
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
  let run_id = Printf.sprintf "%d-%d" (int_of_float (Unix.time ())) (Unix.getpid ()) in
  let digest_query db sql =
    let rows = ref [] in
    let rc = Sqlite3.exec_not_null db ~cb:(fun row _ -> rows := row.(0) :: !rows) sql in
    if rc <> Sqlite3.Rc.OK then failwith (Sqlite3.errmsg db);
    "md5:" ^ Digest.to_hex (Digest.string (String.concat "\n" (List.rev !rows)))
  in
  let completion_stamp db ~n_inserted:_ ~n_skipped =
    let exec sql =
        match Sqlite3.exec db sql with
        | Sqlite3.Rc.OK -> ()
        | rc -> failwith (Sqlite3.Rc.to_string rc ^ ": " ^ Sqlite3.errmsg db)
    in
    if complete && n_skipped = 0 then begin
      let universe = ref 0 in
      exec "CREATE TABLE IF NOT EXISTS effect_analysis_functions(\
            run_id TEXT NOT NULL,function_id INTEGER NOT NULL,function_name TEXT NOT NULL,\
            module_path TEXT NOT NULL,PRIMARY KEY(run_id,function_id))";
      exec "DELETE FROM effect_analysis_functions";
      let insert_universe = Sqlite3.prepare db
        "INSERT INTO effect_analysis_functions(run_id,function_id,function_name,module_path) \
         SELECT ?,f.id,f.name,m.path FROM functions f JOIN modules m ON m.id=f.module_id" in
      ignore (Sqlite3.bind_text insert_universe 1 run_id);
      if Sqlite3.step insert_universe <> Sqlite3.Rc.DONE then failwith (Sqlite3.errmsg db);
      ignore (Sqlite3.finalize insert_universe);
      ignore (Sqlite3.exec_not_null db ~cb:(fun row _ -> universe := int_of_string row.(0))
        "SELECT count(*) FROM effect_analysis_functions");
      let index_digest = digest_query db
        "SELECT hex(m.path)||':'||hex(f.name)||':'||f.id FROM functions f \
         JOIN modules m ON m.id=f.module_id ORDER BY m.path,f.name,f.id" in
      let result_digest = digest_query db
        (Printf.sprintf
           "SELECT hex(function_name)||':'||hex(COALESCE(file_path,''))||':'||hex(value_kind)||':'||\
            hex(COALESCE(target,''))||':'||hex(soundness)||':'||hex(COALESCE(producer,''))||':'||is_direct \
            FROM function_effects WHERE analysis_run_id='%s' ORDER BY function_name,file_path,value_kind,target,producer,is_direct"
           run_id) in
      let stamp k v =
        let st = Sqlite3.prepare db "INSERT OR REPLACE INTO comment_db_meta(key,value) VALUES(?,?)" in
        ignore (Sqlite3.bind_text st 1 k); ignore (Sqlite3.bind_text st 2 v);
        if Sqlite3.step st <> Sqlite3.Rc.DONE then failwith (Sqlite3.errmsg db);
        ignore (Sqlite3.finalize st)
      in
      List.iter (fun (k,v) -> stamp k v)
        [("effect_contract","v1");("effect_outcome","complete");("effect_failures","0");
         ("effect_universe",string_of_int !universe);("effect_run_id",run_id);
         ("effect_producer_version","arch-effects-load-v1");
         ("effect_source_digest",result_digest);("effect_result_digest",result_digest);
         ("effect_index_digest",index_digest)]
    end else begin
      exec "DELETE FROM comment_db_meta WHERE key LIKE 'effect_%'";
      exec "DELETE FROM effect_analysis_functions"
    end
  in
  match Arch_effects.Effects_load.load ~allow_skip ~analysis_run_id:run_id
          ~replace_snapshot:complete ~before_commit:completion_stamp ~db_path stdin with
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

let complete_arg =
  let doc = "Assert that the input producer analyzed the complete indexed function universe. Stores a completion contract and per-function coverage; incompatible with --allow-skip." in
  Arg.(value & flag & info ["complete"] ~doc)

let cmd =
  let doc = "Load NDJSON effect records into an arch-index SQLite database." in
  let info = Cmd.info "arch_effects_load" ~doc in
  Cmd.v info Term.(const run $ db_arg $ migration_arg $ allow_skip_arg $ complete_arg)

let () = exit (Cmd.eval cmd)
