(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

open Arch_index_db

type intent_backup = {
  module_intents : (string * string) list; (* path -> intent *)
  function_intents : (string * string * string) list; (* path, name -> intent *)
  type_intents : (string * string * string) list; (* path, name -> intent *)
}

(* The keys whose PRESENCE is a claim that an analysis RAN to completion.

   They are listed here, beside the drop lists, because they belong to the same
   contract: a re-index must leave a database in a state where nothing asserts
   more than the current run actually produced. [comment_db_meta] is
   deliberately NOT dropped (see the [self_managed] allowlist in
   tezt/tests/schema_drop_list.ml), so these keys survive a re-index unless
   something removes them explicitly — which is what [Arch_index.run] does,
   twice: once before the schema is demolished, once after it is recreated.

   ONE list, consulted by the deletion, because the failure mode is silent. A
   fourth marker spelled only at its producer site would survive a killed
   re-index and answer for a run that produced nothing, and no existing test
   would fail. [tezt/tests/completion_markers.ml] pins that mechanically: every
   comment_db_meta key a producer writes is either in this list or explicitly
   declared non-load-bearing. *)
let completion_marker_keys = ["error_contract"; "exn_contract"; "callgraph_contract"]

let schema_views_to_drop =
  [
    "v_large_files";
    "v_large_functions";
    "v_undocumented";
    "v_unsafe_params";
    "v_low_coverage";
    "v_most_called";
    "v_open_tasks";
    "v_type_fields";
    "v_types_with_field_type";
    "v_variant_constructors";
    "v_callers";
    "v_callees";
    "v_module_deps";
    "v_high_deps";
    "v_types_used_by";
    "v_functions_using";
    "v_common_param_types";
    "v_common_return_types";
  ]

let schema_tables_to_drop =
  [
    (* Exception / error-channel tables (specs/error-channels.md). FIX
       (review round 1, HIGH): none of these were listed, so re-indexing an
       EXISTING database left every previous run's rows in place. The
       damage was not merely "stale rows": [exn_scopes]/[exn_origins]
       DOUBLED, and [call_exn_scopes] — whose primary key is [call_id] —
       rejected every link of the second run on the unique constraint while
       KEEPING the first run's rows, now pointing at scope ids that belong
       to a different walk of the tree. Since call ids are reused across
       runs, those survivors close call sites they never covered: an
       UNSOUND subtraction (a raise silently dropped from an answer), in a
       database the rejection accounting only ever reports as "incomplete".
       Ordered dependents-first like the entries below.

       On [PRAGMA foreign_keys = OFF] (set by the caller around this loop,
       see the comment at arch_index.ml's [DROP] site): with enforcement
       off SQLite does not refuse a [DROP TABLE] on a still-referenced
       table, so this ordering is not what makes the drop succeed — it is
       kept dependents-first so the list stays correct if enforcement is
       ever left on, and so it reads the same way as the rest of the list.
       Nothing here depends on FK enforcement being off. *)
    (* FIX (review round 2, HIGH): [dead_code_sites] is producer-written
       ([arch_index.ml]'s [stmt_dead]), was never dropped and never deleted,
       so re-indexing an existing database appended a fresh copy of every
       dead-call row on top of the previous run's — TRIPLED after three runs
       — with the survivors pointing at [function_id]s that are reused across
       runs and so no longer name the function the row was recorded for.
       Before [calls]/[functions], which it FK-references.

       This was the THIRD omission from this list in a row ([producer_runs],
       then the seven exception/error-channel tables, then this), which is
       why [tezt/tests/schema_drop_list.ml] now cross-checks the list against
       the tables the producer actually writes. *)
    "dead_code_sites";
    "channel_carriers";
    "exn_edges";
    "call_exn_scopes";
    "exn_scope_catches";
    "exn_origins";
    "exn_scopes";
    "exn_rebinds";
    "module_deps";
    "type_usage";
    "type_constructors";
    "type_fields";
    "types";
    "calls";
    "functions";
    "modules";
    (* Must come after [calls]/[functions] (both FK-reference it) — otherwise
       a re-index of the same database accumulates one orphaned row per
       invocation, and [SELECT * FROM producer_runs] stops answering "what
       produced THIS index" (roadmap 1.2). *)
    "producer_runs";
  ]

let backup_intents db =
  let module_intents = ref [] in
  let function_intents = ref [] in
  let type_intents = ref [] in
  (* Modules *)
  ignore
    (Sqlite3.exec_not_null
       db
       ~cb:(fun row _headers ->
         module_intents := (row.(0), row.(1)) :: !module_intents)
       "SELECT path, intent FROM modules WHERE intent IS NOT NULL") ;
  (* Functions *)
  (try
     ignore
       (Sqlite3.exec_not_null
          db
          ~cb:(fun row _headers ->
            function_intents := (row.(0), row.(1), row.(2)) :: !function_intents)
          "SELECT m.path, f.name, f.intent FROM functions f JOIN modules m ON \
           f.module_id = m.id WHERE f.intent IS NOT NULL")
   with _ -> ()) ;
  (* Types *)
  (try
     ignore
       (Sqlite3.exec_not_null
          db
          ~cb:(fun row _headers ->
            type_intents := (row.(0), row.(1), row.(2)) :: !type_intents)
          "SELECT m.path, t.name, t.intent FROM types t JOIN modules m ON \
           t.module_id = m.id WHERE t.intent IS NOT NULL")
   with _ -> ()) ;
  {
    module_intents = !module_intents;
    function_intents = !function_intents;
    type_intents = !type_intents;
  }

let restore_intents db backup =
  (* Use prepared statements with parameter binding to avoid SQL injection *)
  let stmt_mod =
    Sqlite3.prepare db "UPDATE modules SET intent = ? WHERE path = ?"
  in
  let stmt_fn =
    Sqlite3.prepare
      db
      "UPDATE functions SET intent = ? WHERE name = ? AND module_id = (SELECT \
       id FROM modules WHERE path = ?)"
  in
  let stmt_ty =
    Sqlite3.prepare
      db
      "UPDATE types SET intent = ? WHERE name = ? AND module_id = (SELECT id \
       FROM modules WHERE path = ?)"
  in
  List.iter
    (fun (path, intent) ->
      bind_text stmt_mod 1 intent ;
      bind_text stmt_mod 2 path ;
      exec_stmt db ~what:"modules" stmt_mod)
    backup.module_intents ;
  List.iter
    (fun (path, name, intent) ->
      bind_text stmt_fn 1 intent ;
      bind_text stmt_fn 2 name ;
      bind_text stmt_fn 3 path ;
      exec_stmt db ~what:"functions" stmt_fn)
    backup.function_intents ;
  List.iter
    (fun (path, name, intent) ->
      bind_text stmt_ty 1 intent ;
      bind_text stmt_ty 2 name ;
      bind_text stmt_ty 3 path ;
      exec_stmt db ~what:"types" stmt_ty)
    backup.type_intents ;
  (* Finalize prepared statements *)
  ignore (Sqlite3.finalize stmt_mod) ;
  ignore (Sqlite3.finalize stmt_fn) ;
  ignore (Sqlite3.finalize stmt_ty)

let source_path_of_cmt ~project_root (info : Cmt_format.cmt_infos) =
  let try_strip_pp p =
    let dir = Filename.dirname p in
    let base = Filename.basename p in
    match String.split_on_char '.' base with
    | name :: "pp" :: rest ->
        let original = Filename.concat dir (String.concat "." (name :: rest)) in
        if Sys.file_exists original then Some original else None
    | _ -> None
  in
  let try_resolve p =
    if Sys.file_exists p then Some p
    else
      match try_strip_pp p with
      | Some _ as r -> r
      | None ->
          (* Try resolving relative to project root *)
          if project_root <> "" then
            let abs = Filename.concat project_root p in
            if Sys.file_exists abs then Some abs else try_strip_pp abs
          else None
  in
  match info.cmt_sourcefile with
  | Some path when String.length path > 0 -> try_resolve path
  | _ -> None
