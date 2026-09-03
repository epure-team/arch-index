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
  | None -> "architecture-schema.sql"

(* -------------------------------------------------------------------------- *)
(* Schema version and shipped schema text (#51 part 1)                        *)
(* -------------------------------------------------------------------------- *)

(* [current_schema_version] is a "<major>.<minor>" string, bumped by hand at
   every schema change — bump the minor component for an additive change
   (new nullable column/table/index; every migration so far has been this
   kind), the major component for a breaking one (a column/table removal or
   type change an existing consumer's query could not survive unmodified).
   History and the table/column set each version added: docs/schema.md.
   Describes THIS module's [schema_path]/[schema_sql] — the "main" schema
   (architecture-schema.sql, 16 tables, grown by two migrations so far) that
   [Arch_index.run] (the CMT-based path) writes. There is exactly one source
   of truth for "what version does the main schema promise", not one
   hardcoded literal per call site.

   FIX (review, HIGH): a second, STRUCTURALLY DIFFERENT schema exists —
   runner.ml's own inline 3-table flat schema (comment_db_meta, functions,
   calls — the LSP-based path, the actual production entry point via
   `arch_index_cli`). It shares comment_db_meta's key/value store but has
   never had, and cannot have, any of the tables the migrations above added
   (function_effects, attack_edges, ...). It MUST NOT be stamped with this
   constant — a consumer reading schema_version="1.2" off a flat-schema
   database would wrongly conclude those tables exist. See
   [current_flat_schema_version] below, which runner.ml now uses instead. *)
let current_schema_version = "1.2"

(* The flat schema (runner.ml's own inline 3-table [schema_sql]) has never
   changed since it was introduced — it stays "1.0" until it does. Distinct
   version identity from [current_schema_version] above: the two schemas are
   structurally incomparable, and conflating them under one version number is
   exactly the bug a fresh review round caught in this same PR. *)
let current_flat_schema_version = "1.0"

(* FIX (review): [current_schema_version] is a raw string, so a naive consumer
   is tempted to write [Arch_index.schema_version = "1.2"] — brittle against
   any future reformatting and gives no way to ask "at least 1.1" without
   re-parsing by hand. Give consumers a real comparison instead of pushing
   them toward string equality. *)
let parse_schema_version v =
  match String.split_on_char '.' v with
  | [ major; minor ] -> (
      match (int_of_string_opt major, int_of_string_opt minor) with
      | Some ma, Some mi -> Some (ma, mi)
      | _ -> None)
  | _ -> None

let schema_version_at_least ~major ~minor =
  match parse_schema_version current_schema_version with
  | Some (cur_major, cur_minor) ->
      cur_major > major || (cur_major = major && cur_minor >= minor)
  | None -> false

let%test "schema_version_at_least: current version satisfies itself" =
  match parse_schema_version current_schema_version with
  | Some (major, minor) -> schema_version_at_least ~major ~minor
  | None -> false

let%test "schema_version_at_least: a future minor version is not satisfied" =
  match parse_schema_version current_schema_version with
  | Some (major, minor) -> not (schema_version_at_least ~major ~minor:(minor + 1))
  | None -> false

(* FIX (review, HIGH): a fresh review round found a first draft of this fix
   stamped EVERY database (both the main schema and the structurally
   different flat schema) with [current_schema_version] — a flat-schema
   consumer would then read "1.2" and wrongly conclude function_effects/
   attack_edges exist. The two version identities must stay distinct and
   well-formed regardless of what either constant is bumped to later. *)
let%test "main and flat schema versions are distinct identities" =
  current_schema_version <> current_flat_schema_version

let%test "current_flat_schema_version is a well-formed major.minor string" =
  parse_schema_version current_flat_schema_version <> None

(* [schema_sql] embeds architecture-schema.sql's contents at compile time via
   ppx_blob (same mechanism ts_enricher.ml already uses for ts_shim.js) — a
   consumer that depends on the arch-index library can diff against the exact
   schema text a given build promises without opening a database or resolving
   an install-time filesystem path (#51: "ship the schema... so a consumer
   compiles against it rather than guessing"). This does NOT replace the
   runtime schema-loading path above ([schema_path]/[ARCH_SCHEMA_PATH]), which
   still reads from a file at run time — the two are independent, and this one
   exists for out-of-band inspection only. *)
let schema_sql : string = [%blob "../../architecture-schema.sql"]

let%test "current_schema_version is a well-formed major.minor string" =
  match String.split_on_char '.' current_schema_version with
  | [ major; minor ] ->
      let is_digits s =
        s <> "" && String.for_all (fun c -> c >= '0' && c <= '9') s
      in
      is_digits major && is_digits minor
  | _ -> false

let%test "schema_sql is non-empty and defines the base tables" =
  String.length schema_sql > 0
  && (let contains needle =
        let nlen = String.length needle and hlen = String.length schema_sql in
        let rec go i =
          i + nlen <= hlen
          && (String.sub schema_sql i nlen = needle || go (i + 1))
        in
        go 0
      in
      contains "CREATE TABLE IF NOT EXISTS functions"
      && contains "CREATE TABLE IF NOT EXISTS calls"
      && contains "CREATE TABLE IF NOT EXISTS comment_db_meta")

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

(* Statement failures were printed and forgotten. [exec] immediately above
   exits 1 on a failed script; [exec_stmt] did not, and nothing in this
   repository ever gated on its message — `grep -rn "Statement error"` over
   every .ml/.yml/.sh found exactly one hit, the eprintf itself. So a run could
   reject rows and still exit 0, reporting counts it had not stored.

   Measured before this counter existed: indexing épure's src/ produced 238
   "FOREIGN KEY constraint failed" statement errors, reported 25151 type usages,
   stored 24913 — and exited 0. The loss equalled the error count exactly.

   The counter is the cheap general guard. It catches the wildcard-binding case
   this commit fixes, the top-level-shadowing case it deliberately does not, and
   any future route to reported <> stored — none of which a per-symptom test can
   enumerate in advance.

   The ref is private to this module and read through [statement_failures ()].
   It was published as a bare [int ref], and it is the exact value the CMT CLI's
   completeness gate exits 1 on: any consumer of the library could set it to 0
   and turn a truncated index into a silent success. A run's own reset is a
   deliberate, named operation ([reset_all]), not a side effect anyone can
   perform on the counter by hand. *)
let n_statement_failures = ref 0

(* Per-table tally of rejected rows. The scalar [statement_failures] answers
   "did this run lose rows"; this answers "which table lost them", which is the
   question a consumer of the database actually needs. *)
let rejections_by_table : (string, int) Hashtbl.t = Hashtbl.create 8

let incr_rejection what =
  Hashtbl.replace
    rejections_by_table
    what
    (1 + Option.value ~default:0 (Hashtbl.find_opt rejections_by_table what))

let reset_rejections () = Hashtbl.reset rejections_by_table
let statement_failures () = !n_statement_failures

(* The scalar and the per-table breakdown are two views of one tally and must
   agree -- [rejections_by_table]'s counts are documented as summing to the
   scalar. Resetting them together, through one name, is what keeps that true:
   two separate resets is two places for a caller to clear one and keep the
   other. *)
let reset_all () =
  n_statement_failures := 0 ;
  reset_rejections ()

let rejections_by_table () =
  Hashtbl.fold (fun k v acc -> (k, v) :: acc) rejections_by_table []
  |> List.sort (fun (a, _) (b, _) -> String.compare a b)

(* [~what] names the table the rejected row was destined for. Without it the
   diagnostic is "Statement error (CONSTRAINT): FOREIGN KEY constraint failed"
   repeated N times, which identifies neither the table nor the pipeline stage
   -- so a reader cannot tell whether the lost rows were type usages (a metric
   input) or calls (a graph edge, and therefore a reachability answer). The
   sqlite3 OCaml bindings expose no accessor for a prepared statement's SQL
   text (checked: sqlite3.mli 5.4.1 has no `val sql`), so the label cannot be
   recovered from the statement and must be passed in. It is a REQUIRED
   argument rather than an optional one precisely so no future insert site can
   silently opt back out of the diagnostic. *)
let exec_stmt_ok db ~what stmt =
  match Sqlite3.step stmt with
  | Sqlite3.Rc.DONE ->
      ignore (Sqlite3.reset stmt) ;
      true
  | rc ->
      incr n_statement_failures ;
      incr_rejection what ;
      Arch_io.eprintf
        "Statement error (%s) writing to %s: %s\n"
        (Sqlite3.Rc.to_string rc)
        what
        (Sqlite3.errmsg db) ;
      ignore (Sqlite3.reset stmt) ;
      false

(* [exec_stmt] is [exec_stmt_ok] with the verdict dropped, not a second copy of
   it: the tally, the diagnostic and the reset stay in exactly one place. Insert
   sites whose row mints no id for anyone else to reference — fields,
   constructors, calls, deps, usages — keep using it. *)
let exec_stmt db ~what stmt = ignore (exec_stmt_ok db ~what stmt : bool)

let last_insert_rowid db = Int64.to_int (Sqlite3.last_insert_rowid db)

(* An insert whose rowid other rows will reference.

   [last_insert_rowid] is per-CONNECTION and across all tables: it is not
   cleared by a failed step. After a rejected insert it still returns whatever
   the last SUCCESSFUL insert on this connection produced — a [types] or
   [type_fields] rowid, or worse, a perfectly valid [functions] rowid belonging
   to a DIFFERENT function. Handing that back as "the id of the row I just
   wrote" makes every dependent insert satisfy its foreign key against the
   wrong parent: no rejection, no count, silent misattribution. [None] is the
   only honest answer, and it forces the caller to skip the dependents. *)
let exec_stmt_rowid db ~what stmt =
  if exec_stmt_ok db ~what stmt then Some (last_insert_rowid db) else None

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
  exec_stmt_rowid db ~what:"modules" stmt_mod

let bind_int_opt stmt idx = function
  | Some v -> bind_int stmt idx v
  | None -> ignore (Sqlite3.bind stmt idx Sqlite3.Data.NULL)

let insert_function db stmt_fn ~module_id ~name ~signature ~line_start ~line_end
    ~exposed ~intent ?(comment_quality_score = None) ?(has_pre = false)
    ?(has_post = false) ?(has_violators = false) ?(has_violates = false)
    ?(violators_raw = None) ?(violates_raw = None) ?(tests_raw = None)
    ?(quint_raw = None) ?(mutation_sites = None) ?(deref_sites = None) () =
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
  bind_int_opt stmt_fn 17 mutation_sites ;
  bind_int_opt stmt_fn 18 deref_sites ;
  exec_stmt_rowid db ~what:"functions" stmt_fn

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
  exec_stmt_rowid db ~what:"types" stmt_ty

let insert_field db stmt_fld ~type_id ~field_name ~field_type ~position =
  bind_int stmt_fld 1 type_id ;
  bind_text stmt_fld 2 field_name ;
  bind_text stmt_fld 3 field_type ;
  bind_int stmt_fld 4 position ;
  exec_stmt db ~what:"type_fields" stmt_fld

let insert_constructor db stmt_ctor ~type_id ~constructor_name ~position
    ~arg_types =
  bind_int stmt_ctor 1 type_id ;
  bind_text stmt_ctor 2 constructor_name ;
  bind_int stmt_ctor 3 position ;
  bind_text_opt stmt_ctor 4 arg_types ;
  exec_stmt db ~what:"type_constructors" stmt_ctor

let insert_call db stmt_call ~caller_id ~callee_id ~callee_name ~call_site ~kind =
  bind_int stmt_call 1 caller_id ;
  bind_text stmt_call 3 callee_name ;
  bind_text_opt stmt_call 4 call_site ;
  bind_text stmt_call 5 kind ;
  (match callee_id with
  | Some id -> bind_int stmt_call 2 id
  | None -> ignore (Sqlite3.bind stmt_call 2 Sqlite3.Data.NULL)) ;
  exec_stmt db ~what:"calls" stmt_call

(* Same binds as [insert_call], but the rowid is handed back so a dependent
   row ([call_exn_scopes]) can reference THIS call — [None] on rejection, so
   nothing links to another call's id. *)
let insert_call_rowid db stmt_call ~caller_id ~callee_id ~callee_name ~call_site ~kind =
  bind_int stmt_call 1 caller_id ;
  bind_text stmt_call 3 callee_name ;
  bind_text_opt stmt_call 4 call_site ;
  bind_text stmt_call 5 kind ;
  (match callee_id with
  | Some id -> bind_int stmt_call 2 id
  | None -> ignore (Sqlite3.bind stmt_call 2 Sqlite3.Data.NULL)) ;
  exec_stmt_rowid db ~what:"calls" stmt_call

let insert_call_exn_scope db stmt ~call_id ~scope_id =
  bind_int stmt 1 call_id ;
  bind_int stmt 2 scope_id ;
  exec_stmt db ~what:"call_exn_scopes" stmt

let insert_exn_scope db stmt ~function_id ~parent_id ~form ~line ~col ~catch_all =
  bind_int stmt 1 function_id ;
  bind_int_opt stmt 2 parent_id ;
  bind_text stmt 3 form ;
  bind_int stmt 4 line ;
  bind_int stmt 5 col ;
  bind_bool stmt 6 catch_all ;
  exec_stmt_rowid db ~what:"exn_scopes" stmt

let insert_exn_scope_catch db stmt ~scope_id ~exn_path =
  bind_int stmt 1 scope_id ;
  bind_text stmt 2 exn_path ;
  exec_stmt db ~what:"exn_scope_catches" stmt

let insert_exn_origin db stmt ~function_id ~scope_id ~form ~exn_path ~escapes ~line ~col =
  bind_int stmt 1 function_id ;
  bind_int_opt stmt 2 scope_id ;
  bind_text stmt 3 form ;
  bind_text_opt stmt 4 exn_path ;
  bind_bool stmt 5 escapes ;
  bind_int stmt 6 line ;
  bind_int stmt 7 col ;
  exec_stmt db ~what:"exn_origins" stmt

let insert_exn_rebind db stmt ~alias_path ~target_path =
  bind_text stmt 1 alias_path ;
  bind_text stmt 2 target_path ;
  exec_stmt db ~what:"exn_rebinds" stmt

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
  exec_stmt db ~what:"module_deps" stmt_dep

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
  exec_stmt db ~what:"type_usage" stmt_usage

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
