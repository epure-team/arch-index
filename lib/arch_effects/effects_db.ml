(** Effects database writer — implementation. *)

open Extractor_intf

(* ── helpers ─────────────────────────────────────────────────────────────── *)

let exec_exn db sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> ()
  | rc ->
    failwith (Printf.sprintf "SQL error (%s): %s\nQuery: %s"
      (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db) sql)

let bind_text st i s = ignore (Sqlite3.bind st i (Sqlite3.Data.TEXT s))
let bind_null st i   = ignore (Sqlite3.bind st i Sqlite3.Data.NULL)
let bind_int  st i v = ignore (Sqlite3.bind st i (Sqlite3.Data.INT (Int64.of_int v)))

let bind_opt st i = function
  | Some s -> bind_text st i s
  | None   -> bind_null st i

(* ── migrate ─────────────────────────────────────────────────────────────── *)

(** Strip single-line SQL comments (-- to end of line) from a string.
    Also strips inline comments.  Block comments are not used in our DDL. *)
let strip_sql_comments sql =
  let lines = String.split_on_char '\n' sql in
  List.map (fun line ->
    (* Find the first '--' not inside a string literal (simple heuristic:
       we count single-quotes to determine if we're inside a literal) *)
    let len = String.length line in
    let in_str = ref false in
    let result = Buffer.create len in
    let i = ref 0 in
    while !i < len do
      let c = line.[!i] in
      if c = '\'' then (in_str := not !in_str; Buffer.add_char result c; incr i)
      else if (not !in_str) && c = '-' && !i + 1 < len && line.[!i + 1] = '-' then
        i := len  (* skip rest of line *)
      else (Buffer.add_char result c; incr i)
    done;
    Buffer.contents result
  ) lines
  |> String.concat "\n"

(** Split a SQL file into individual statements (split on ';').  Blank and
    comment-only chunks are dropped.  Comments are stripped first. *)
let split_sql sql =
  let stripped = strip_sql_comments sql in
  String.split_on_char ';' stripped
  |> List.map String.trim
  |> List.filter (fun s -> s <> "")

let migrate ~db_path ~migration_sql_path =
  match Sys.file_exists migration_sql_path with
  | false ->
    Error (Printf.sprintf "migration SQL not found: %s" migration_sql_path)
  | true ->
    let ic = open_in migration_sql_path in
    let n = in_channel_length ic in
    let buf = Bytes.create n in
    really_input ic buf 0 n;
    close_in ic;
    let sql = Bytes.to_string buf in
    let stmts = split_sql sql in
    let db = Sqlite3.db_open db_path in
    (try
      exec_exn db "BEGIN";
      List.iter (exec_exn db) stmts;
      exec_exn db "COMMIT";
      ignore (Sqlite3.db_close db);
      Ok ()
    with Failure msg ->
      (try exec_exn db "ROLLBACK" with _ -> ());
      ignore (Sqlite3.db_close db);
      Error msg)

(* ── write_effects ───────────────────────────────────────────────────────── *)

(** Look up function_id from functions.name (best-effort; NULL if not found).
    Returns [None] on any error, including when the flat callgraph schema is
    used (which has no [id] column on [functions]). *)
let lookup_fn_id db name =
  match Sqlite3.prepare db "SELECT id FROM functions WHERE name=? LIMIT 1" with
  | exception Sqlite3.Error _ -> None
  | st ->
    bind_text st 1 name;
    let result = match Sqlite3.step st with
      | Sqlite3.Rc.ROW ->
        (match Sqlite3.column st 0 with
         | Sqlite3.Data.INT v -> Some (Int64.to_int v)
         | _ -> None)
      | _ -> None
    in
    ignore (Sqlite3.finalize st);
    result

let write_effects ~db_path records =
  if not (Sys.file_exists db_path) then
    Error (Printf.sprintf "database not found: %s" db_path)
  else
    let db = Sqlite3.db_open db_path in
    (* Ensure the effects table exists (migration may not have been run yet;
       we create a minimal version here for robustness in tests). *)
    let guard_stmts = [
      "CREATE TABLE IF NOT EXISTS function_effects (\
        id INTEGER PRIMARY KEY AUTOINCREMENT,\
        function_id INTEGER,\
        function_name TEXT NOT NULL,\
        file_path TEXT,\
        value_kind_id INTEGER,\
        value_kind TEXT NOT NULL,\
        target TEXT,\
        is_direct BOOLEAN NOT NULL DEFAULT 1,\
        soundness TEXT NOT NULL DEFAULT 'candidate',\
        producer TEXT,\
        created_at TEXT DEFAULT CURRENT_TIMESTAMP)";
      "CREATE INDEX IF NOT EXISTS idx_fn_effects_fname ON function_effects(function_name)";
      "CREATE INDEX IF NOT EXISTS idx_fn_effects_kind  ON function_effects(value_kind)";
    ] in
    List.iter (fun s -> try exec_exn db s with Failure _ -> ()) guard_stmts;
    let st = Sqlite3.prepare db
      "INSERT INTO function_effects\
        (function_id, function_name, file_path, value_kind, target,\
         is_direct, soundness, producer)\
       VALUES (?,?,?,?,?,1,?,?)" in
    let n_inserted = ref 0 in
    let n_skipped  = ref 0 in
    (try
      exec_exn db "BEGIN";
      List.iter (fun er ->
        try
          let fn_id = lookup_fn_id db er.er_function_name in
          (match fn_id with
           | Some id -> bind_int st 1 id
           | None    -> bind_null st 1);
          bind_text st 2 er.er_function_name;
          bind_opt  st 3 er.er_file_path;
          bind_text st 4 (value_kind_to_string er.er_value_kind);
          bind_opt  st 5 er.er_target;
          bind_text st 6 (soundness_to_string er.er_soundness);
          bind_text st 7 er.er_producer;
          (match Sqlite3.step st with
           | Sqlite3.Rc.DONE -> incr n_inserted
           | _ -> incr n_skipped);
          ignore (Sqlite3.reset st)
        with Failure _ -> incr n_skipped
      ) records;
      exec_exn db "COMMIT";
      ignore (Sqlite3.finalize st);
      ignore (Sqlite3.db_close db);
      Ok (!n_inserted, !n_skipped)
    with Failure msg ->
      (try exec_exn db "ROLLBACK" with _ -> ());
      ignore (Sqlite3.finalize st);
      ignore (Sqlite3.db_close db);
      Error msg)
