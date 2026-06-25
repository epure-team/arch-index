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
    "module_deps";
    "type_usage";
    "type_constructors";
    "type_fields";
    "types";
    "calls";
    "functions";
    "modules";
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
      exec_stmt db stmt_mod)
    backup.module_intents ;
  List.iter
    (fun (path, name, intent) ->
      bind_text stmt_fn 1 intent ;
      bind_text stmt_fn 2 name ;
      bind_text stmt_fn 3 path ;
      exec_stmt db stmt_fn)
    backup.function_intents ;
  List.iter
    (fun (path, name, intent) ->
      bind_text stmt_ty 1 intent ;
      bind_text stmt_ty 2 name ;
      bind_text stmt_ty 3 path ;
      exec_stmt db stmt_ty)
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
