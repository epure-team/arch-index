open Cmdliner

let run build_dir db_path schema_path errors_config errors_profile errors_strict =
  let result =
    Arch_index.run
      ?db_path
      ?schema_path
      ?errors_config
      ?errors_profile
      ~errors_strict
      ~build_dir
      ()
  in
  Printf.printf "Indexed: %d modules, %d functions, %d types, %d calls\n%!"
    result.Arch_index.n_modules
    result.Arch_index.n_functions
    result.Arch_index.n_types
    result.Arch_index.n_calls ;
  (* Fail on a run that rejected rows. [exec_stmt] prints a statement failure
     and continues, so before this check the indexer could reject 238 inserts,
     print 238 lines nobody reads, report the rejected rows as written, and
     exit 0. A summary that overstates what it stored is worse than a crash:
     every consumer downstream believes it. *)
  if result.Arch_index.n_statement_failures > 0 then (
    (* The counts above used to be described here as "ATTEMPTS, not stored
       rows". That was true of the six [incr]-kept counters and is no longer
       true of any of them: every number [Arch_index.run] reports is now a
       COUNT over the table it names, taken after the writing transaction
       committed (tezt/tests/reported_counts_are_row_counts.ml pins that).
       Saying otherwise told a reader to distrust the one number that is
       reliable, and to look for the loss in the wrong place — the counts are
       accurate, the DATABASE is short of what the source contains, and the
       per-table breakdown below is where the missing rows are named. *)
    Printf.eprintf
      "ERROR: %d statement(s) failed during indexing. The counts above are the \
       rows actually stored — the database is incomplete relative to the \
       sources scanned.\n\
       %!"
      result.Arch_index.n_statement_failures ;
    (* Name the destination tables. "437 statements failed" does not say
       whether the run lost type usages (a metric input) or calls (a graph
       edge, hence a reachability answer), and those have very different
       consequences for anything reading the database afterwards. *)
    List.iter
      (fun (table, n) -> Printf.eprintf "ERROR:   %s: %d row(s) rejected\n%!" table n)
      result.Arch_index.rejections_by_table ;
    exit 1)

let build_dir_arg =
  let doc = "Path to the dune build directory (e.g., _build/default)." in
  Arg.(required & opt (some dir) None & info ["build-dir"; "b"] ~docv:"DIR" ~doc)

let db_path_arg =
  let doc = "Path to the output SQLite database." in
  Arg.(value & opt (some string) None & info ["db-path"; "d"] ~docv:"FILE" ~doc)

let schema_path_arg =
  let doc = "Path to the SQL schema file." in
  Arg.(value & opt (some string) None & info ["schema-path"; "s"] ~docv:"FILE" ~doc)

let errors_config_arg =
  let doc =
    "Path to an arch-errors.toml error-channels config. Overrides discovery \
     of arch-errors.toml at the project root."
  in
  Arg.(value & opt (some string) None & info ["errors-config"] ~docv:"FILE" ~doc)

let errors_profile_arg =
  let doc =
    "Name of a shipped error-channels profile (resolves \
     profiles/<name>-errors.toml)."
  in
  Arg.(value & opt (some string) None & info ["errors-profile"] ~docv:"NAME" ~doc)

let errors_strict_arg =
  let doc = "Make every error-channels declaration miss fatal, not just a warning." in
  Arg.(value & flag & info ["errors-strict"] ~doc)

let cmd =
  let doc = "Index OCaml call graph from CMT files." in
  let info = Cmd.info "arch_callgraph_ocaml" ~doc in
  Cmd.v
    info
    Term.(
      const run
      $ build_dir_arg
      $ db_path_arg
      $ schema_path_arg
      $ errors_config_arg
      $ errors_profile_arg
      $ errors_strict_arg)

let () = exit (Cmd.eval cmd)
