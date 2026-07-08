(** Capability database writer — Phase 2 implementation. *)

open Capability_types

(* ── SQL helpers (mirrors Effects_db style) ─────────────────────────────── *)

let exec_exn db sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> ()
  | rc ->
    failwith (Printf.sprintf "SQL error (%s): %s\nQuery: %s"
      (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db) sql)

let bind_text st i s = ignore (Sqlite3.bind st i (Sqlite3.Data.TEXT s))
let bind_null st i   = ignore (Sqlite3.bind st i Sqlite3.Data.NULL)

let bind_opt st i = function
  | Some s -> bind_text st i s
  | None   -> bind_null st i

(** Read and split a SQL migration file (reuses the logic from Effects_db). *)
let strip_comments sql =
  String.split_on_char '\n' sql
  |> List.map (fun line ->
    let len = String.length line in
    let in_str = ref false in
    let buf = Buffer.create len in
    let i = ref 0 in
    while !i < len do
      let c = line.[!i] in
      if c = '\'' then (in_str := not !in_str; Buffer.add_char buf c; incr i)
      else if (not !in_str) && c = '-' && !i + 1 < len && line.[!i + 1] = '-' then
        i := len
      else (Buffer.add_char buf c; incr i)
    done;
    Buffer.contents buf)
  |> String.concat "\n"

let split_sql sql =
  strip_comments sql
  |> String.split_on_char ';'
  |> List.map String.trim
  |> List.filter (fun s -> s <> "")

(* ── migrate ─────────────────────────────────────────────────────────────── *)

(** Execute one SQL statement; for ALTER TABLE ADD COLUMN, silently ignore
    "duplicate column name" errors so the migration is idempotent. *)
let exec_idempotent db sql =
  let is_alter_add = (* case-insensitive prefix check *)
    let lc = String.lowercase_ascii (String.trim sql) in
    let has_prefix p s = String.length s >= String.length p &&
      String.sub s 0 (String.length p) = p in
    has_prefix "alter table" lc && (
      let contains sub s =
        let ls = String.length s and lsub = String.length sub in
        let rec go i = if i > ls - lsub then false
          else if String.sub s i lsub = sub then true else go (i+1) in
        if lsub > ls then false else go 0 in
      contains "add column" lc)
  in
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> ()
  | rc ->
    let msg = Sqlite3.errmsg db in
    let is_dup = String.length msg >= 15 &&
      String.sub (String.lowercase_ascii msg) 0 15 = "duplicate colum" in
    if is_alter_add && is_dup then ()  (* idempotent: column already exists *)
    else failwith (Printf.sprintf "SQL error (%s): %s\nQuery: %s"
      (Sqlite3.Rc.to_string rc) msg sql)

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
    let stmts = split_sql (Bytes.to_string buf) in
    let db = Sqlite3.db_open db_path in
    (* Run each statement individually without a wrapping transaction so that
       ALTER TABLE errors on already-existing columns can be handled per-stmt. *)
    (try
      List.iter (exec_idempotent db) stmts;
      ignore (Sqlite3.db_close db);
      Ok ()
    with Failure msg ->
      ignore (Sqlite3.db_close db);
      Error msg)

(** Idempotently add a column to [table] if absent (uses pragma_table_info).
    Mirrors the inline check in [write_capabilities] but is reusable across
    tables (used for the attack_edges G2 discriminator columns). *)
let ensure_table_column db table col_name col_type =
  let q = Printf.sprintf
    "SELECT 1 FROM pragma_table_info('%s') WHERE name='%s' LIMIT 1"
    table col_name in
  let exists = ref false in
  (match Sqlite3.exec_no_headers db ~cb:(fun _ -> exists := true) q with _ -> ());
  if not !exists then begin
    let stmt = Printf.sprintf
      "ALTER TABLE %s ADD COLUMN %s %s" table col_name col_type in
    try exec_exn db stmt with Failure _ -> ()
  end

let ensure_attack_edge_column db col_name col_type =
  ensure_table_column db "attack_edges" col_name col_type

(* ── encode capability fields ────────────────────────────────────────────── *)

let encode_value_touched vts =
  match vts with
  | [] -> None
  | _  ->
    let items = List.map (fun vt ->
      Printf.sprintf {|{"kind":"%s","direction":"%s"}|} vt.vt_kind vt.vt_direction
    ) vts in
    Some ("[" ^ String.concat "," items ^ "]")

(* ── write_capabilities ─────────────────────────────────────────────────── *)

(** Check whether a function_effects row already exists for this function.
    When [file_path] is [Some], the match is scoped to (function_name, file_path)
    so a sidecar for one component does not collide with a same-named function in
    another component/language; when [None], it matches on the name alone. *)
let fn_exists db ~file_path name =
  match Sqlite3.prepare db
    (* Sidecars may use the historical qualified form ("Module.f") while the
       OCaml effects extractor now emits unqualified names matching the
       callgraph convention — accept either: exact, or the sidecar name's
       unqualified suffix (?3). *)
    "SELECT 1 FROM function_effects \
     WHERE (function_name=?1 OR function_name=?3) \
       AND (?2 IS NULL OR file_path=?2) LIMIT 1" with
  | exception Sqlite3.Error _ -> false
  | st ->
    let unqualified =
      match String.rindex_opt name '.' with
      | Some i -> String.sub name (i + 1) (String.length name - i - 1)
      | None -> name
    in
    bind_text st 1 name;
    bind_opt  st 2 file_path;
    bind_text st 3 unqualified;
    let found = match Sqlite3.step st with
      | Sqlite3.Rc.ROW -> true
      | _ -> false
    in
    ignore (Sqlite3.finalize st);
    found

let write_capabilities ~db_path records =
  if not (Sys.file_exists db_path) then
    Error (Printf.sprintf "database not found: %s" db_path)
  else begin
    let db = Sqlite3.db_open db_path in
    (* Ensure the Phase-2 columns exist (guard against un-migrated DB).
       We try each ALTER TABLE; if it fails (column already exists or IF NOT EXISTS
       is unsupported), we silently continue — the column is already there. *)
    let ensure_column = ensure_table_column db "function_effects" in
    ensure_column "reachability_class" "TEXT";
    ensure_column "actor_role" "TEXT";
    ensure_column "temporal_class" "TEXT";
    ensure_column "gating" "TEXT";
    ensure_column "value_touched" "TEXT";
    ensure_column "precondition" "TEXT";
    (* Also ensure attack_edges table exists *)
    (try exec_exn db
      "CREATE TABLE IF NOT EXISTS attack_edges (\
        id INTEGER PRIMARY KEY, from_action TEXT NOT NULL, \
        to_action TEXT NOT NULL, \
        edge_type TEXT NOT NULL, \
        evidence TEXT, source TEXT, created_at TEXT DEFAULT (datetime('now')))"
    with Failure _ -> ());

    (* WHERE is scoped by file_path when the sidecar supplies one (?9): a sidecar
       for component A no longer overwrites a same-named function in component B.
       When file_path is NULL the guard degrades to name-only matching. *)
    let update_st = Sqlite3.prepare db
      "UPDATE function_effects SET \
         file_path          = COALESCE(?1, file_path), \
         reachability_class = COALESCE(?2, reachability_class), \
         actor_role         = COALESCE(?3, actor_role), \
         temporal_class     = COALESCE(?4, temporal_class), \
         gating             = COALESCE(?5, gating), \
         value_touched      = COALESCE(?6, value_touched), \
         precondition       = COALESCE(?7, precondition) \
       WHERE function_name = ?8 AND (?9 IS NULL OR file_path = ?9)" in
    (* Capability-only functions (no prior effect row) get a synthetic row that
       carries just the attributes. It is marked is_direct=0 with a non-mutating
       value_kind so it never registers as a (direct or transitive) mutation in
       pure-fns / mutators-of / effects-of — those queries key on is_direct=1
       effect rows. *)
    let insert_st = Sqlite3.prepare db
      "INSERT INTO function_effects \
         (function_name, value_kind, is_direct, soundness, producer, file_path, \
          reachability_class, actor_role, temporal_class, gating, \
          value_touched, precondition) \
       VALUES (?, 'NoEffect', 0, 'manual', ?, ?, ?,?,?,?,?,?)" in
    let n_updated  = ref 0 in
    let n_inserted = ref 0 in
    let n_skipped  = ref 0 in
    (try
      exec_exn db "BEGIN";
      List.iter (fun r ->
        try
          let rclass_s = match r.cap_reachability with
            | Some rc -> Some (reachability_class_to_string rc)
            | None    -> None
          in
          let vt_s = encode_value_touched r.cap_value_touched in
          if fn_exists db ~file_path:r.cap_file_path r.cap_function_name then begin
            (* UPDATE: COALESCE ensures existing non-NULL values are kept *)
            bind_opt  update_st 1 r.cap_file_path;
            bind_opt  update_st 2 rclass_s;
            bind_opt  update_st 3 r.cap_actor_role;
            bind_opt  update_st 4 r.cap_temporal_class;
            bind_opt  update_st 5 r.cap_gating;
            bind_opt  update_st 6 vt_s;
            bind_opt  update_st 7 r.cap_precondition;
            bind_text update_st 8 r.cap_function_name;
            bind_opt  update_st 9 r.cap_file_path;
            (match Sqlite3.step update_st with
             | Sqlite3.Rc.DONE -> incr n_updated
             | _ -> incr n_skipped);
            ignore (Sqlite3.reset update_st)
          end else begin
            (* INSERT new row *)
            bind_text insert_st 1 r.cap_function_name;
            bind_text insert_st 2 r.cap_source;
            bind_opt  insert_st 3 r.cap_file_path;
            bind_opt  insert_st 4 rclass_s;
            bind_opt  insert_st 5 r.cap_actor_role;
            bind_opt  insert_st 6 r.cap_temporal_class;
            bind_opt  insert_st 7 r.cap_gating;
            bind_opt  insert_st 8 vt_s;
            bind_opt  insert_st 9 r.cap_precondition;
            (match Sqlite3.step insert_st with
             | Sqlite3.Rc.DONE -> incr n_inserted
             | _ -> incr n_skipped);
            ignore (Sqlite3.reset insert_st)
          end
        with Failure _ -> incr n_skipped
      ) records;
      exec_exn db "COMMIT";
      ignore (Sqlite3.finalize update_st);
      ignore (Sqlite3.finalize insert_st);
      ignore (Sqlite3.db_close db);
      Ok (!n_updated, !n_inserted, !n_skipped)
    with Failure msg ->
      (try exec_exn db "ROLLBACK" with _ -> ());
      ignore (Sqlite3.finalize update_st);
      ignore (Sqlite3.finalize insert_st);
      ignore (Sqlite3.db_close db);
      Error msg)
  end

(* ── write_attack_edges ──────────────────────────────────────────────────── *)

let write_attack_edges ~db_path edges =
  if not (Sys.file_exists db_path) then
    Error (Printf.sprintf "database not found: %s" db_path)
  else begin
    let db = Sqlite3.db_open db_path in
    (try exec_exn db
      "CREATE TABLE IF NOT EXISTS attack_edges (\
        id INTEGER PRIMARY KEY, from_action TEXT NOT NULL, \
        to_action TEXT NOT NULL, \
        edge_type TEXT NOT NULL \
          CHECK(edge_type IN ('sequence','removes_guard','shares_resource','actor_distinct')), \
        evidence TEXT, source TEXT, created_at TEXT DEFAULT (datetime('now')))"
    with Failure _ -> ());
    (* Gap G2: endpoint component/file discriminators.  Added idempotently so
       cross-component edges (e.g. bare Rust kernel names vs qualified OCaml
       names) are unambiguous.  Pre-existing tables are upgraded in place. *)
    ensure_attack_edge_column db "from_path" "TEXT";
    ensure_attack_edge_column db "to_path" "TEXT";
    (* Idempotency index (mirrors capabilities-schema-migration.sql): without it
       the INSERT OR IGNORE below has no conflict target and every re-load
       duplicates edges. Best-effort — a pre-existing table with duplicate rows
       would reject the unique index; that is a legacy-DB edge case. *)
    (try exec_exn db
      "CREATE UNIQUE INDEX IF NOT EXISTS attack_edges_identity \
        ON attack_edges(from_action, to_action, edge_type, \
                        COALESCE(from_path,''), COALESCE(to_path,''))"
    with Failure _ -> ());
    let st = Sqlite3.prepare db
      "INSERT OR IGNORE INTO attack_edges \
         (from_action, from_path, to_action, to_path, edge_type, evidence, source) \
       VALUES (?,?,?,?,?,?,?)" in
    let n_inserted = ref 0 in
    let n_skipped  = ref 0 in
    (try
      exec_exn db "BEGIN";
      List.iter (fun ae ->
        try
          bind_text st 1 ae.ae_from;
          bind_opt  st 2 ae.ae_from_path;
          bind_text st 3 ae.ae_to;
          bind_opt  st 4 ae.ae_to_path;
          bind_text st 5 (edge_type_to_string ae.ae_type);
          bind_opt  st 6 ae.ae_evidence;
          bind_text st 7 ae.ae_source;
          (match Sqlite3.step st with
           (* INSERT OR IGNORE returns DONE on conflict too; changes()=0 means the
              edge already existed (idempotent re-load) → count as skipped. *)
           | Sqlite3.Rc.DONE ->
             if Sqlite3.changes db > 0 then incr n_inserted else incr n_skipped
           | _ -> incr n_skipped);
          ignore (Sqlite3.reset st)
        with Failure _ -> incr n_skipped
      ) edges;
      exec_exn db "COMMIT";
      ignore (Sqlite3.finalize st);
      ignore (Sqlite3.db_close db);
      Ok (!n_inserted, !n_skipped)
    with Failure msg ->
      (try exec_exn db "ROLLBACK" with _ -> ());
      ignore (Sqlite3.finalize st);
      ignore (Sqlite3.db_close db);
      Error msg)
  end
