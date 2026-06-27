(** arch-sidecar-load — load a .capabilities.yaml sidecar into an arch-index SQLite DB.

    Usage: arch-sidecar-load <db> <sidecar.capabilities.yaml> [--migration <sql>]

    Reads a sidecar YAML file, writes capability attributes to function_effects,
    and inserts attack_edges.  Applies the Phase-2 capabilities migration first
    (idempotent) if requested or if the reachability_class column is absent. *)

open Cmdliner

module CE = Arch_effects.Capability_extractor
module CD = Arch_effects.Capability_db

let run db_path sidecar_path migration_path =
  (* Probe for Phase-2 columns; apply migration if absent *)
  let needs_migration =
    match migration_path with
    | Some _ -> true
    | None ->
      let probe = Sqlite3.db_open db_path in
      let has = match Sqlite3.exec probe
        "SELECT 1 FROM pragma_table_info('function_effects') \
         WHERE name='reachability_class' LIMIT 1"
        with Sqlite3.Rc.OK -> true | _ -> false in
      ignore (Sqlite3.db_close probe);
      not has
  in
  if needs_migration then begin
    let sql_path = match migration_path with
      | Some p -> p
      | None ->
        let here = Filename.dirname Sys.argv.(0) in
        Filename.concat here "capabilities-schema-migration.sql"
    in
    match CD.migrate ~db_path ~migration_sql_path:sql_path with
    | Error msg ->
      Printf.eprintf "arch-sidecar-load: migration failed: %s\n%!" msg;
      exit 1
    | Ok () ->
      Printf.printf "arch-sidecar-load: Phase-2 schema migration applied\n%!"
  end;
  (* Parse sidecar *)
  let sc = CE.load_sidecar sidecar_path in
  List.iter (fun e ->
    Printf.eprintf "arch-sidecar-load: parse warning: %s\n%!" e
  ) sc.CE.sc_errors;
  (* Write capabilities *)
  (match CD.write_capabilities ~db_path sc.CE.sc_capabilities with
   | Error msg ->
     Printf.eprintf "arch-sidecar-load: write_capabilities failed: %s\n%!" msg;
     exit 1
   | Ok (n_upd, n_ins, n_skip) ->
     Printf.printf "arch-sidecar-load: capabilities: %d updated, %d inserted, %d skipped\n%!"
       n_upd n_ins n_skip);
  (* Write attack edges *)
  (match CD.write_attack_edges ~db_path sc.CE.sc_edges with
   | Error msg ->
     Printf.eprintf "arch-sidecar-load: write_attack_edges failed: %s\n%!" msg;
     exit 1
   | Ok (n_ins, n_skip) ->
     Printf.printf "arch-sidecar-load: attack_edges: %d inserted, %d skipped\n%!"
       n_ins n_skip)

let db_arg =
  let doc = "Path to the SQLite database." in
  Arg.(required & pos 0 (some file) None & info [] ~docv:"DB" ~doc)

let sidecar_arg =
  let doc = "Path to the .capabilities.yaml sidecar file." in
  Arg.(required & pos 1 (some string) None & info [] ~docv:"SIDECAR" ~doc)

let migration_arg =
  let doc = "Path to capabilities-schema-migration.sql. Auto-applied if Phase-2 columns are absent." in
  Arg.(value & opt (some string) None & info ["migration"; "m"] ~docv:"SQL" ~doc)

let cmd =
  let doc = "Load a .capabilities.yaml sidecar into an arch-index SQLite database." in
  let info = Cmd.info "arch_sidecar_load" ~doc in
  Cmd.v info Term.(const run $ db_arg $ sidecar_arg $ migration_arg)

let () = exit (Cmd.eval cmd)
