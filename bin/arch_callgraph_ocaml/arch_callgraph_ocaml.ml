open Cmdliner

let run build_dir db_path schema_path =
  let result =
    Arch_index.run
      ?db_path
      ?schema_path
      ~build_dir
      ()
  in
  Printf.printf "Indexed: %d modules, %d functions, %d types, %d calls\n%!"
    result.Arch_index.n_modules
    result.Arch_index.n_functions
    result.Arch_index.n_types
    result.Arch_index.n_calls

let build_dir_arg =
  let doc = "Path to the dune build directory (e.g., _build/default)." in
  Arg.(required & opt (some dir) None & info ["build-dir"; "b"] ~docv:"DIR" ~doc)

let db_path_arg =
  let doc = "Path to the output SQLite database." in
  Arg.(value & opt (some string) None & info ["db-path"; "d"] ~docv:"FILE" ~doc)

let schema_path_arg =
  let doc = "Path to the SQL schema file." in
  Arg.(value & opt (some string) None & info ["schema-path"; "s"] ~docv:"FILE" ~doc)

let cmd =
  let doc = "Index OCaml call graph from CMT files." in
  let info = Cmd.info "arch_callgraph_ocaml" ~doc in
  Cmd.v info Term.(const run $ build_dir_arg $ db_path_arg $ schema_path_arg)

let () = exit (Cmd.eval cmd)
