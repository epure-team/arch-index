(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Database helpers for architecture indexing.

    Low-level SQLite utilities and insert functions for populating
    the architecture database. *)

(* -------------------------------------------------------------------------- *)
(* Default paths                                                              *)
(* -------------------------------------------------------------------------- *)

let db_path =
  match Sys.getenv_opt "ARCH_DB_PATH" with
  | Some p -> p
  | None -> "docs/architecture.db"

let schema_path =
  match Sys.getenv_opt "ARCH_SCHEMA_PATH" with
  | Some p -> p
  | None -> "docs/architecture-schema.sql"

(* -------------------------------------------------------------------------- *)
(* Low-level helpers                                                          *)
(* -------------------------------------------------------------------------- *)

let exec_exn db sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> ()
  | rc ->
      Arch_io.eprintf
        "SQL error (%s): %s\nQuery: %s\n"
        (Sqlite3.Rc.to_string rc)
        (Sqlite3.errmsg db)
        sql ;
      exit 1

let exec_stmt db stmt =
  match Sqlite3.step stmt with
  | Sqlite3.Rc.DONE -> ignore (Sqlite3.reset stmt)
  | rc ->
      Arch_io.eprintf
        "Statement error (%s): %s\n"
        (Sqlite3.Rc.to_string rc)
        (Sqlite3.errmsg db) ;
      ignore (Sqlite3.reset stmt)

let last_insert_rowid db = Int64.to_int (Sqlite3.last_insert_rowid db)

let bind_text stmt idx v = ignore (Sqlite3.bind stmt idx (Sqlite3.Data.TEXT v))

let bind_int stmt idx v =
  ignore (Sqlite3.bind stmt idx (Sqlite3.Data.INT (Int64.of_int v)))

let bind_bool stmt idx v =
  ignore (Sqlite3.bind stmt idx (Sqlite3.Data.INT (if v then 1L else 0L)))

let bind_text_opt stmt idx = function
  | Some v -> bind_text stmt idx v
  | None -> ignore (Sqlite3.bind stmt idx Sqlite3.Data.NULL)

(* -------------------------------------------------------------------------- *)
(* Insert helpers                                                             *)
(* -------------------------------------------------------------------------- *)

let insert_module db stmt_mod ~path ~lines ~has_mli ?(quint_module_raw = None)
    () =
  let now =
    Printf.sprintf
      "%04d-%02d-%02dT%02d:%02d:%02d"
      (let t = Unix.gmtime (Unix.gettimeofday ()) in
       t.tm_year + 1900)
      (let t = Unix.gmtime (Unix.gettimeofday ()) in
       t.tm_mon + 1)
      (let t = Unix.gmtime (Unix.gettimeofday ()) in
       t.tm_mday)
      (let t = Unix.gmtime (Unix.gettimeofday ()) in
       t.tm_hour)
      (let t = Unix.gmtime (Unix.gettimeofday ()) in
       t.tm_min)
      (let t = Unix.gmtime (Unix.gettimeofday ()) in
       t.tm_sec)
  in
  bind_text stmt_mod 1 path ;
  bind_int stmt_mod 2 lines ;
  bind_text stmt_mod 3 now ;
  bind_bool stmt_mod 4 has_mli ;
  bind_text_opt stmt_mod 5 quint_module_raw ;
  exec_stmt db stmt_mod ;
  last_insert_rowid db

let bind_int_opt stmt idx = function
  | Some v -> bind_int stmt idx v
  | None -> ignore (Sqlite3.bind stmt idx Sqlite3.Data.NULL)

let insert_function db stmt_fn ~module_id ~name ~signature ~line_start ~line_end
    ~exposed ~intent ?(comment_quality_score = None) ?(has_pre = false)
    ?(has_post = false) ?(has_violators = false) ?(has_violates = false)
    ?(violators_raw = None) ?(violates_raw = None) ?(tests_raw = None)
    ?(quint_raw = None) () =
  bind_int stmt_fn 1 module_id ;
  bind_text stmt_fn 2 name ;
  bind_text_opt stmt_fn 3 signature ;
  bind_int stmt_fn 4 line_start ;
  bind_int stmt_fn 5 line_end ;
  bind_bool stmt_fn 6 exposed ;
  bind_text_opt stmt_fn 7 intent ;
  bind_int_opt stmt_fn 8 comment_quality_score ;
  bind_bool stmt_fn 9 has_pre ;
  bind_bool stmt_fn 10 has_post ;
  bind_bool stmt_fn 11 has_violators ;
  bind_bool stmt_fn 12 has_violates ;
  bind_text_opt stmt_fn 13 violators_raw ;
  bind_text_opt stmt_fn 14 violates_raw ;
  bind_text_opt stmt_fn 15 tests_raw ;
  bind_text_opt stmt_fn 16 quint_raw ;
  exec_stmt db stmt_fn ;
  last_insert_rowid db

let insert_type db stmt_ty ~module_id ~name ~kind ~line_start ~line_end ~exposed
    ~manifest ~intent =
  bind_int stmt_ty 1 module_id ;
  bind_text stmt_ty 2 name ;
  bind_text stmt_ty 3 kind ;
  bind_int stmt_ty 4 line_start ;
  bind_int stmt_ty 5 line_end ;
  bind_bool stmt_ty 6 exposed ;
  bind_text_opt stmt_ty 7 manifest ;
  bind_text_opt stmt_ty 8 intent ;
  exec_stmt db stmt_ty ;
  last_insert_rowid db

let insert_field db stmt_fld ~type_id ~field_name ~field_type ~position =
  bind_int stmt_fld 1 type_id ;
  bind_text stmt_fld 2 field_name ;
  bind_text stmt_fld 3 field_type ;
  bind_int stmt_fld 4 position ;
  exec_stmt db stmt_fld

let insert_constructor db stmt_ctor ~type_id ~constructor_name ~position
    ~arg_types =
  bind_int stmt_ctor 1 type_id ;
  bind_text stmt_ctor 2 constructor_name ;
  bind_int stmt_ctor 3 position ;
  bind_text_opt stmt_ctor 4 arg_types ;
  exec_stmt db stmt_ctor

let insert_call db stmt_call ~caller_id ~callee_id ~callee_name ~call_site ~kind =
  bind_int stmt_call 1 caller_id ;
  bind_text stmt_call 3 callee_name ;
  bind_text_opt stmt_call 4 call_site ;
  bind_text stmt_call 5 kind ;
  (match callee_id with
  | Some id -> bind_int stmt_call 2 id
  | None -> ignore (Sqlite3.bind stmt_call 2 Sqlite3.Data.NULL)) ;
  exec_stmt db stmt_call

let insert_module_dep db stmt_dep ~source_module ~target_module ~target_path
    ~dep_kind ~alias_name ~line_number =
  bind_int stmt_dep 1 source_module ;
  bind_text stmt_dep 3 target_path ;
  bind_text stmt_dep 4 dep_kind ;
  bind_text_opt stmt_dep 5 alias_name ;
  bind_int stmt_dep 6 line_number ;
  (match target_module with
  | Some id -> bind_int stmt_dep 2 id
  | None -> ignore (Sqlite3.bind stmt_dep 2 Sqlite3.Data.NULL)) ;
  exec_stmt db stmt_dep

let insert_type_usage db stmt_usage ~function_id ~type_id ~type_name ~usage_role
    ~position =
  bind_int stmt_usage 1 function_id ;
  bind_text stmt_usage 3 type_name ;
  bind_text stmt_usage 4 usage_role ;
  (match type_id with
  | Some id -> bind_int stmt_usage 2 id
  | None -> ignore (Sqlite3.bind stmt_usage 2 Sqlite3.Data.NULL)) ;
  (match position with
  | Some p -> bind_int stmt_usage 5 p
  | None -> ignore (Sqlite3.bind stmt_usage 5 Sqlite3.Data.NULL)) ;
  exec_stmt db stmt_usage

(* -------------------------------------------------------------------------- *)
(* Inline tests — happy paths only (exec_exn calls exit 1 on errors;         *)
(* error paths cannot be tested without process-level isolation)              *)
(* -------------------------------------------------------------------------- *)

(* Open an in-memory DB with a scratch table and run [f] against it. *)
let with_mem_db f =
  let db = Sqlite3.db_open ":memory:" in
  ignore
    (Sqlite3.exec db
       "CREATE TABLE t (a TEXT, b INTEGER, c INTEGER, d TEXT)") ;
  let result = f db in
  ignore (Sqlite3.db_close db) ;
  result

let column_text stmt col =
  match Sqlite3.column stmt col with
  | Sqlite3.Data.TEXT v -> Some v
  | _ -> None

let column_int64 stmt col =
  match Sqlite3.column stmt col with
  | Sqlite3.Data.INT v -> Some v
  | _ -> None

let%test "bind_text: stores and reads back" =
  with_mem_db (fun db ->
      let ins = Sqlite3.prepare db "INSERT INTO t (a) VALUES (?)" in
      bind_text ins 1 "hello" ;
      ignore (Sqlite3.step ins) ;
      let sel = Sqlite3.prepare db "SELECT a FROM t" in
      ignore (Sqlite3.step sel) ;
      column_text sel 0 = Some "hello")

let%test "bind_int: stores and reads back as INT" =
  with_mem_db (fun db ->
      let ins = Sqlite3.prepare db "INSERT INTO t (b) VALUES (?)" in
      bind_int ins 1 42 ;
      ignore (Sqlite3.step ins) ;
      let sel = Sqlite3.prepare db "SELECT b FROM t" in
      ignore (Sqlite3.step sel) ;
      column_int64 sel 0 = Some 42L)

let%test "bind_bool: true → 1" =
  with_mem_db (fun db ->
      let ins = Sqlite3.prepare db "INSERT INTO t (c) VALUES (?)" in
      bind_bool ins 1 true ;
      ignore (Sqlite3.step ins) ;
      let sel = Sqlite3.prepare db "SELECT c FROM t" in
      ignore (Sqlite3.step sel) ;
      column_int64 sel 0 = Some 1L)

let%test "bind_bool: false → 0" =
  with_mem_db (fun db ->
      let ins = Sqlite3.prepare db "INSERT INTO t (c) VALUES (?)" in
      bind_bool ins 1 false ;
      ignore (Sqlite3.step ins) ;
      let sel = Sqlite3.prepare db "SELECT c FROM t" in
      ignore (Sqlite3.step sel) ;
      column_int64 sel 0 = Some 0L)

let%test "bind_text_opt: Some → text" =
  with_mem_db (fun db ->
      let ins = Sqlite3.prepare db "INSERT INTO t (a) VALUES (?)" in
      bind_text_opt ins 1 (Some "world") ;
      ignore (Sqlite3.step ins) ;
      let sel = Sqlite3.prepare db "SELECT a FROM t" in
      ignore (Sqlite3.step sel) ;
      column_text sel 0 = Some "world")

let%test "bind_text_opt: None → NULL" =
  with_mem_db (fun db ->
      let ins = Sqlite3.prepare db "INSERT INTO t (a) VALUES (?)" in
      bind_text_opt ins 1 None ;
      ignore (Sqlite3.step ins) ;
      let sel = Sqlite3.prepare db "SELECT a FROM t" in
      ignore (Sqlite3.step sel) ;
      Sqlite3.column sel 0 = Sqlite3.Data.NULL)

let%test "last_insert_rowid: increments" =
  with_mem_db (fun db ->
      let ins = Sqlite3.prepare db "INSERT INTO t (a) VALUES (?)" in
      bind_text ins 1 "r1" ;
      ignore (Sqlite3.step ins) ;
      ignore (Sqlite3.reset ins) ;
      let r1 = last_insert_rowid db in
      bind_text ins 1 "r2" ;
      ignore (Sqlite3.step ins) ;
      let r2 = last_insert_rowid db in
      r2 = r1 + 1)
