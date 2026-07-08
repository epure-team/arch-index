(* arch-coverage-load — NDJSON → coverage snapshots (specs/arch-gardening-queries.md).
   Exit: 0 loaded (skips allowed); 2 usage / malformed input (transaction rolled
   back, nothing written); 3 DB lacks functions/modules/coverage tables. *)

let usage = "usage: arch-coverage-load --db DB [--stamp YYYY-MM-DDTHH:MM:SSZ] < records.ndjson"

let die msg =
  prerr_endline ("arch-coverage-load: " ^ msg);
  prerr_endline usage;
  exit 2

let table_exists db name =
  let stmt =
    Sqlite3.prepare db "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1"
  in
  ignore (Sqlite3.bind_text stmt 1 name);
  let r = Sqlite3.step stmt = Sqlite3.Rc.ROW in
  ignore (Sqlite3.finalize stmt);
  r

let () =
  let db_path = ref None and stamp = ref None in
  let rec parse = function
    | [] -> ()
    | "--db" :: v :: rest ->
        db_path := Some v;
        parse rest
    | "--stamp" :: v :: rest ->
        if not (Arch_coverage.valid_stamp v) then
          die (Printf.sprintf "invalid --stamp %S (want strict UTC YYYY-MM-DDTHH:MM:SSZ)" v);
        stamp := Some v;
        parse rest
    | ("--db" | "--stamp") :: [] -> die "missing value for option"
    | arg :: _ -> die (Printf.sprintf "unknown argument %s" arg)
  in
  parse (List.tl (Array.to_list Sys.argv));
  let db_path = match !db_path with Some p -> p | None -> die "--db is required" in
  if not (Sys.file_exists db_path) then die (Printf.sprintf "no such db: %s" db_path);
  let db = Sqlite3.db_open db_path in
  (try ignore (Sqlite3.prepare db "SELECT 1 FROM sqlite_master LIMIT 1")
   with Sqlite3.Error m -> die (Printf.sprintf "not a SQLite database: %s (%s)" db_path m));
  if not (table_exists db "functions" && table_exists db "modules" && table_exists db "coverage")
  then begin
    prerr_endline
      "arch-coverage-load: REFUSED — DB lacks functions/modules/coverage tables (flat NDJSON \
       index?); build a main-schema index first (architecture-schema.sql).";
    exit 3
  end;
  let stamp = match !stamp with Some s -> s | None -> Arch_coverage.now_stamp () in
  let lines = ref [] in
  (try
     while true do
       lines := input_line stdin :: !lines
     done
   with End_of_file -> ());
  match
    Arch_coverage.load db ~stamp ~warn:(fun m -> prerr_endline ("arch-coverage-load: " ^ m))
      (List.rev !lines)
  with
  | Ok {written; skipped; ignored} ->
      Printf.printf "arch-coverage-load: %d written, %d skipped, %d ignored (stamp %s)\n" written
        skipped ignored stamp
  | Error msg ->
      prerr_endline ("arch-coverage-load: ABORT — " ^ msg ^ " (rolled back, nothing written)");
      exit 2
