(* arch-mcp — MCP stdio server binary (specs/arch-mcp-server.md).
   Exit codes: 0 clean EOF shutdown; 2 usage / DB not openable.
   stdout carries ONLY JSON-RPC lines — all diagnostics go to stderr. *)

let usage = "usage: arch-mcp --db PATH"

let die msg =
  prerr_endline ("arch-mcp: " ^ msg);
  prerr_endline usage;
  exit 2

let () =
  let db_path = ref None in
  let rec parse = function
    | [] -> ()
    | "--db" :: path :: rest ->
        db_path := Some path;
        parse rest
    | "--db" :: [] -> die "--db requires a PATH argument"
    | arg :: _ -> die (Printf.sprintf "unknown argument %s" arg)
  in
  parse (List.tl (Array.to_list Sys.argv));
  let path = match !db_path with Some p -> p | None -> die "--db is required" in
  if not (Sys.file_exists path) then die (Printf.sprintf "no such db: %s" path);
  if Sys.is_directory path then die (Printf.sprintf "%s is a directory" path);
  let db =
    try Sqlite3.db_open ~mode:`READONLY path
    with Sqlite3.Error m -> die (Printf.sprintf "cannot open %s: %s" path m)
  in
  (* Probe: a non-SQLite file only fails on first statement (SQLITE_NOTADB). *)
  (try ignore (Sqlite3.prepare db "SELECT 1 FROM sqlite_master LIMIT 1")
   with Sqlite3.Error m -> die (Printf.sprintf "not a SQLite database: %s (%s)" path m));
  let ctx = {Arch_mcp.db; si = Arch_mcp.detect_schema db} in
  prerr_endline (Printf.sprintf "arch-mcp: serving %s (read-only)" path);
  let rec loop () =
    match input_line stdin with
    | exception End_of_file -> ()
    | line ->
        (match Arch_mcp.handle_line ctx line with
        | Some response ->
            print_string (Yojson.Safe.to_string response ^ "\n");
            flush stdout
        | None -> ());
        loop ()
  in
  loop ()
