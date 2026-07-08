(* arch-body-compare — per-name body-hash comparison CLI over
   Arch_index.Arch_index_compare (specs/arch-health-queries.md US-3).
   Informational, never a gate. Requires source files on disk.
   Exit: 0 verdict rendered; 1 name not found; 2 usage; 3 DB lacks the
   line-range/modules data (flat NDJSON indexes). *)

module Compare = Arch_index.Arch_index_compare

let usage = "usage: arch-body-compare --db DB --project-root DIR <function-name>"

let die msg =
  prerr_endline ("arch-body-compare: " ^ msg);
  prerr_endline usage;
  exit 2

let has_column db table col =
  let stmt =
    Sqlite3.prepare db
      (Printf.sprintf "SELECT 1 FROM pragma_table_xinfo('%s') WHERE name=? LIMIT 1" table)
  in
  ignore (Sqlite3.bind_text stmt 1 col);
  let r = Sqlite3.step stmt = Sqlite3.Rc.ROW in
  ignore (Sqlite3.finalize stmt);
  r

let table_exists db name =
  let stmt =
    Sqlite3.prepare db "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1"
  in
  ignore (Sqlite3.bind_text stmt 1 name);
  let r = Sqlite3.step stmt = Sqlite3.Rc.ROW in
  ignore (Sqlite3.finalize stmt);
  r

(* The library collapses missing files, NULL ranges, and genuinely empty
   bodies into the same empty normalized body (same digest) — disambiguate
   here so identical-empty groups are not mistaken for real duplicates. *)
let occurrence_flag ~project_root (o : Compare.occurrence) =
  if o.body <> "" then ""
  else
    let abs = if project_root = "" then o.path else Filename.concat project_root o.path in
    if not (Sys.file_exists abs) then "  (empty body — source missing?)"
    else if o.line_start <= 0 || o.line_end <= 0 then "  (empty body — no line range)"
    else "  (empty body)"

let print_occurrence ~project_root (o : Compare.occurrence) =
  Printf.printf "    %s:%d-%d%s\n" o.path o.line_start o.line_end
    (occurrence_flag ~project_root o)

let () =
  let db_path = ref None and root = ref None and name = ref None in
  let rec parse = function
    | [] -> ()
    | "--db" :: v :: rest ->
        db_path := Some v;
        parse rest
    | "--project-root" :: v :: rest ->
        root := Some v;
        parse rest
    | ("--db" | "--project-root") :: [] -> die "missing value for option"
    | arg :: _ when String.length arg > 1 && arg.[0] = '-' ->
        die (Printf.sprintf "unknown option %s" arg)
    | arg :: rest ->
        if !name <> None then die "exactly one function name expected";
        name := Some arg;
        parse rest
  in
  parse (List.tl (Array.to_list Sys.argv));
  let db_path = match !db_path with Some p -> p | None -> die "--db is required" in
  let root = match !root with Some p -> p | None -> die "--project-root is required" in
  let name = match !name with Some n -> n | None -> die "function name required" in
  if not (Sys.file_exists db_path) then die (Printf.sprintf "no such db: %s" db_path);
  let db = Sqlite3.db_open ~mode:`READONLY db_path in
  (* non-SQLite files only fail on the first statement — die cleanly, no backtrace *)
  (try ignore (Sqlite3.prepare db "SELECT 1 FROM sqlite_master LIMIT 1")
   with Sqlite3.Error m -> die (Printf.sprintf "not a SQLite database: %s (%s)" db_path m));
  let schema_ok =
    table_exists db "modules"
    && List.for_all (has_column db "modules") ["id"; "path"]
    && List.for_all (has_column db "functions")
         ["name"; "module_id"; "line_start"; "line_end"]
  in
  if not schema_ok then begin
    prerr_endline
      "arch-body-compare: REFUSED — this DB lacks line ranges / modules (flat NDJSON index); \
       body comparison needs a main-schema index built from sources.";
    exit 3
  end;
  match Compare.compare_bodies db ~project_root:root name with
  | exception Sqlite3.Error m ->
      (* residual schema mismatch the preflight missed: refuse, never backtrace *)
      prerr_endline ("arch-body-compare: REFUSED — schema mismatch: " ^ m);
      exit 3
  | Compare.Not_found ->
      Printf.printf "NOT FOUND: no function named %s in %s\n" name db_path;
      exit 1
  | Compare.Identical occs ->
      Printf.printf "IDENTICAL: %d occurrence(s) of %s share one body\n" (List.length occs) name;
      Printf.printf "  digest: %s\n"
        (match occs with o :: _ -> o.digest | [] -> "-");
      List.iter (print_occurrence ~project_root:root) occs
  | Compare.Differs groups ->
      let groups = List.sort (fun (a, _) (b, _) -> String.compare a b) groups in
      Printf.printf "DIFFERS: %s has %d distinct bodies\n" name (List.length groups);
      List.iter
        (fun (digest, occs) ->
          Printf.printf "  digest %s (%d occurrence(s)):\n" digest (List.length occs);
          List.iter (print_occurrence ~project_root:root) occs)
        groups
