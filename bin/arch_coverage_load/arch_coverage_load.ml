(** arch-coverage-load — persist coverage SNAPSHOTS into the main-schema [coverage] table.

    {1 Not arch-coverage --write}

    [arch-coverage --write] REPLACES the table wholesale from a single LCOV tracefile, read
    against the reachability graph it just computed — that is arch-coverage's own bookkeeping for
    its own report, and this loader does not touch it.

    This loader APPENDS one dated snapshot per invocation from a NAME-KEYED NDJSON stream, so any
    CI coverage tool that can emit [{"function":"NAME","covered_lines":N,"total_lines":M}] can
    feed the curation ledger, independent of arch-coverage's LCOV/reachability machinery. Running
    it repeatedly (e.g. once per CI run) builds HISTORY rather than replacing it: [arch-query
    low-coverage] reads the latest snapshot per function ("last instantané par fonction"), so an
    old row is never overwritten or destroyed, only superseded for reads.

    {1 Strictness, modelled on arch-load}

    The WHOLE input is read and validated before a single row is written — an unknown field, a
    missing field, a non-integer count, [covered_lines > total_lines], the same (function, module)
    pair twice, or a function named both bare and with a "module" elsewhere in the input (they may
    be the same function — ambiguous, see below) all ABORT before touching the DB. Once validation
    passes, the write is one transaction: it all lands, or (on an unexpected SQL error) none of it
    does.

    Every row of one invocation shares ONE UTC timestamp, computed once via {!Unix.gmtime} (never
    localtime) rather than sampled per-row from sqlite's own [CURRENT_TIMESTAMP] default — so "the
    coverage as of this run" is one well-defined instant every function in the batch shares,
    needed for "last snapshot per function" to mean the same run across functions. *)

let usage =
  {|arch-coverage-load — append a coverage snapshot into the main-schema `coverage` table.

Usage: arch-coverage-load <db> [input.ndjson]      (input defaults to stdin)

NDJSON records (one JSON object per line, one per function):
  {"function":"install_node","covered_lines":12,"total_lines":20}
  {"function":"run","module":"lib/a/dup.ml","covered_lines":3,"total_lines":5}

"function", "covered_lines" and "total_lines" are required; "module" (a modules.path value) is
OPTIONAL and disambiguates a function name shared by more than one module. No field outside this
set is allowed. covered_lines/total_lines must be integers with 0 <= covered_lines <= total_lines.
A (function, module) pair may appear at most once per invocation — one snapshot, one row per
function; run the loader again for the next snapshot.

Name resolution: a name absent from the index (in the given module, if one was given) is SKIPPED
(the coverage tool ran over more than this index covers, which is normal). Without a "module"
field, a name shared by more than one function (ambiguous across modules) is IGNORED — never
guessed at; give "module" to disambiguate instead. Both SKIPPED and IGNORED are counted and
reported, never silently dropped.

Any malformed record (bad JSON, missing/unknown field, wrong type, covered_lines > total_lines,
or a duplicate (function, module) pair within this input) ABORTS THE WHOLE LOAD before any row is
written.|}

let die ?line fmt =
  Printf.ksprintf
    (fun s ->
      (match line with
      | Some n -> Printf.eprintf "arch-coverage-load: %s (line %d)\n" s n
      | None -> Printf.eprintf "arch-coverage-load: %s\n" s) ;
      exit 2)
    fmt

let required_fields = [ "function"; "covered_lines"; "total_lines" ]

let optional_fields = [ "module" ]

let allowed_fields = required_fields @ optional_fields

type rec_t = { r_function : string; r_module : string option; r_covered : int; r_total : int }

(* ------------------------------------------------------------------ *)
(* phase 1: read the WHOLE input and validate before touching the DB    *)
(* ------------------------------------------------------------------ *)

let read_records ic =
  let recs = ref [] in
  let seen : (string * string option, unit) Hashtbl.t = Hashtbl.create 256 in
  (* A bare record and a module-qualified record naming the SAME function are not necessarily
     two distinct coverage facts — they may resolve to one function_id, which phase 2 would
     then hit as a UNIQUE(function_id, recorded_at) collision reported as "a snapshot already
     exists", an unactionable diagnosis for something this input alone caused (#35 review
     finding). Catch the ambiguity here, where it is knowable without touching the DB: mixing
     a bare and a scoped record for one name in one input is always rejected. Multiple SCOPED
     records for the same name across different modules remain legitimate — that is the whole
     point of the "module" field — and are still governed by [seen] above. *)
  let seen_bare : (string, unit) Hashtbl.t = Hashtbl.create 256 in
  let seen_scoped : (string, unit) Hashtbl.t = Hashtbl.create 256 in
  let lineno = ref 0 in
  (try
     while true do
       let raw = String.trim (input_line ic) in
       incr lineno ;
       if raw <> "" then (
         let json =
           try Yojson.Safe.from_string raw with Yojson.Json_error e -> die ~line:!lineno "invalid JSON: %s" e
         in
         let assoc = match json with `Assoc a -> a | _ -> die ~line:!lineno "record is not a JSON object" in
         List.iter
           (fun (k, _) ->
             if not (List.mem k allowed_fields) then
               die ~line:!lineno "unknown field %S; the contract is [%s]" k
                 (String.concat "; " allowed_fields))
           assoc ;
         List.iter
           (fun k -> if not (List.mem_assoc k assoc) then die ~line:!lineno "record missing field %S" k)
           required_fields ;
         let fn =
           match List.assoc "function" assoc with
           | `String s when s <> "" -> s
           | _ -> die ~line:!lineno "\"function\" must be a non-empty string"
         in
         let module_ =
           match List.assoc_opt "module" assoc with
           | None -> None
           | Some (`String s) when s <> "" -> Some s
           | Some _ -> die ~line:!lineno "\"module\" must be a non-empty string"
         in
         let int_field k =
           match List.assoc k assoc with `Int n -> n | _ -> die ~line:!lineno "%S must be an integer" k
         in
         let covered = int_field "covered_lines" and total = int_field "total_lines" in
         if covered < 0 || total < 0 then
           die ~line:!lineno "covered_lines/total_lines must be >= 0 (got %d/%d)" covered total ;
         if covered > total then
           die ~line:!lineno "covered_lines (%d) > total_lines (%d) for %S" covered total fn ;
         if Hashtbl.mem seen (fn, module_) then
           die ~line:!lineno "function %S%s appears more than once in this input — one snapshot, \
                               one row per function"
             fn
             (match module_ with Some m -> Printf.sprintf " (module %S)" m | None -> "") ;
         (match module_ with
         | None ->
             if Hashtbl.mem seen_scoped fn then
               die ~line:!lineno
                 "function %S appears both bare and with a \"module\" elsewhere in this input — \
                  ambiguous: they may name the same function. Give \"module\" on every record for \
                  this name, or none"
                 fn
         | Some _ ->
             if Hashtbl.mem seen_bare fn then
               die ~line:!lineno
                 "function %S appears both bare and with a \"module\" elsewhere in this input — \
                  ambiguous: they may name the same function. Give \"module\" on every record for \
                  this name, or none"
                 fn) ;
         Hashtbl.replace seen (fn, module_) () ;
         Hashtbl.replace (match module_ with None -> seen_bare | Some _ -> seen_scoped) fn () ;
         recs := { r_function = fn; r_module = module_; r_covered = covered; r_total = total } :: !recs)
     done
   with End_of_file -> ()) ;
  List.rev !recs

(* ------------------------------------------------------------------ *)
(* phase 2: name resolution + transactional write                      *)
(* ------------------------------------------------------------------ *)

let has_table db name =
  let stmt = Sqlite3.prepare db "SELECT count(*) FROM sqlite_master WHERE type IN ('table','view') AND name=?" in
  ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT name)) ;
  let r =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW -> ( match Sqlite3.column stmt 0 with Sqlite3.Data.INT n -> n > 0L | _ -> false)
    | _ -> false
  in
  ignore (Sqlite3.finalize stmt) ;
  r

(** Every [functions.id] matching [name] (and [module_path], if given, via a join on
    [modules.path]) — the caller decides skip/ignore/use from the shape of the list, so "no
    match" and "ambiguous" can never be conflated. A record naming its module resolves scoped
    to it, so a name shared by two modules never falls into the ambiguous/IGNORED path when the
    caller already told us which one they meant (#35: coverage for any same-named function was
    silently unattributable). A durable fix — a stable qualified identity shared by every loader,
    not scoped resolution one loader at a time — is tracked as roadmap item 1.6. *)
let resolve db ~module_path name =
  let sql =
    match module_path with
    | None -> "SELECT id FROM functions WHERE name=?"
    | Some _ -> "SELECT f.id FROM functions f JOIN modules m ON f.module_id=m.id WHERE f.name=? \
                 AND m.path=?"
  in
  let stmt = Sqlite3.prepare db sql in
  ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT name)) ;
  (match module_path with
  | Some p -> ignore (Sqlite3.bind stmt 2 (Sqlite3.Data.TEXT p))
  | None -> ()) ;
  let ids = ref [] in
  let rec loop () =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        (match Sqlite3.column stmt 0 with Sqlite3.Data.INT n -> ids := n :: !ids | _ -> ()) ;
        loop ()
    | _ -> ()
  in
  loop () ;
  ignore (Sqlite3.finalize stmt) ;
  !ids

let utc_stamp () =
  let tm = Unix.gmtime (Unix.time ()) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1)
    tm.Unix.tm_mday tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  let db_path, input =
    match args with
    | [] ->
        prerr_endline usage ;
        exit 2
    | [ d ] -> (d, None)
    | d :: i :: _ -> (d, if i = "-" then None else Some i)
  in
  let ic = match input with None -> stdin | Some f -> ( try open_in f with Sys_error e -> die "cannot open input: %s" e) in
  let recs = read_records ic in
  if input <> None then close_in ic ;

  if not (Sys.file_exists db_path) then die "no such db: %s" db_path ;
  let db = Sqlite3.db_open db_path in
  if not (has_table db "functions") then
    die "%s has no `functions` table — not an arch-index DB" db_path ;
  if (not (has_table db "coverage")) || not (has_table db "modules") then
    die
      "%s: requires the main schema's `coverage` table (a flat arch-load index has none) — build \
       from architecture-schema.sql"
      db_path ;

  let stamp = utc_stamp () in
  let exec sql =
    match Sqlite3.exec db sql with
    | Sqlite3.Rc.OK -> ()
    | rc -> die "SQL error (%s) running %s: %s" (Sqlite3.Rc.to_string rc) sql (Sqlite3.errmsg db)
  in
  exec "BEGIN" ;
  let ins =
    Sqlite3.prepare db "INSERT INTO coverage(function_id,covered_lines,total_lines,recorded_at) \
                         VALUES(?,?,?,?)"
  in
  let written = ref 0 and skipped = ref 0 and ignored = ref 0 in
  List.iter
    (fun r ->
      match resolve db ~module_path:r.r_module r.r_function with
      | [] -> incr skipped
      | [ id ] -> (
          ignore (Sqlite3.reset ins) ;
          ignore (Sqlite3.bind ins 1 (Sqlite3.Data.INT id)) ;
          ignore (Sqlite3.bind ins 2 (Sqlite3.Data.INT (Int64.of_int r.r_covered))) ;
          ignore (Sqlite3.bind ins 3 (Sqlite3.Data.INT (Int64.of_int r.r_total))) ;
          ignore (Sqlite3.bind ins 4 (Sqlite3.Data.TEXT stamp)) ;
          match Sqlite3.step ins with
          | Sqlite3.Rc.DONE -> incr written
          | Sqlite3.Rc.CONSTRAINT ->
              ignore (Sqlite3.finalize ins) ;
              exec "ROLLBACK" ;
              die
                "a coverage snapshot for %S already exists at this UTC second (%s) — run the \
                 loader again in a moment, or once per second at most"
                r.r_function stamp
          | rc ->
              ignore (Sqlite3.finalize ins) ;
              exec "ROLLBACK" ;
              die "insert failed for %S: %s (%s)" r.r_function (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db))
      | _ :: _ :: _ -> incr ignored)
    recs ;
  ignore (Sqlite3.finalize ins) ;
  exec "COMMIT" ;
  ignore (Sqlite3.db_close db) ;
  Printf.eprintf "arch-coverage-load: wrote %d, skipped %d (not in index), ignored %d (ambiguous \
                   name), recorded_at=%s\n"
    !written !skipped !ignored stamp
