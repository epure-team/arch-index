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
    "unsafe_params";
    "coverage";
    "gardening_tasks";
    "gardening_log";
    "module_deps";
    "type_usage";
    "type_constructors";
    "type_fields";
    "types";
    "calls";
    "functions";
    "modules";
  ]

let has_table db name =
  let stmt = Sqlite3.prepare db "SELECT count(*) FROM sqlite_master WHERE type='table' AND name=?" in
  bind_text stmt 1 name ;
  let found =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW -> (
        match Sqlite3.column stmt 0 with Sqlite3.Data.INT n -> n > 0L | _ -> false)
    | _ -> false
  in
  ignore (Sqlite3.finalize stmt) ;
  found

let backup_curation db =
  let copy name select empty =
    let backup = "curation_backup_" ^ name in
    exec_exn db ("DROP TABLE IF EXISTS temp." ^ backup) ;
    exec_exn db ("CREATE TEMP TABLE " ^ backup ^ " AS " ^ if has_table db name then select else empty)
  in
  copy "unsafe_params"
    "SELECT u.id,u.param_name,u.current_type,u.target_type,u.fixed,u.fixed_at,u.github_issue,\
     COALESCE(u.target_module_path,m.path) AS target_module_path,\
     COALESCE(u.target_function_name,f.name) AS target_function_name FROM unsafe_params u \
     LEFT JOIN functions f ON f.id=u.function_id LEFT JOIN modules m ON m.id=f.module_id"
    "SELECT NULL id,NULL param_name,NULL current_type,NULL target_type,NULL fixed,NULL fixed_at,\
     NULL github_issue,NULL target_module_path,NULL target_function_name WHERE 0" ;
  copy "coverage"
    "SELECT c.id,c.covered_lines,c.total_lines,c.recorded_at,\
     COALESCE(c.target_module_path,m.path) AS target_module_path,\
     COALESCE(c.target_function_name,f.name) AS target_function_name FROM coverage c \
     LEFT JOIN functions f ON f.id=c.function_id LEFT JOIN modules m ON m.id=f.module_id"
    "SELECT NULL id,NULL covered_lines,NULL total_lines,NULL recorded_at,NULL target_module_path,\
     NULL target_function_name WHERE 0" ;
  copy "gardening_tasks"
    "SELECT t.id,t.github_issue,t.category,t.title,t.status,t.created_at,t.completed_at,\
     COALESCE(t.target_module_path,m.path) AS target_module_path,\
     COALESCE(t.target_function_module_path,fm.path) AS target_function_module_path,\
     COALESCE(t.target_function_name,f.name) AS target_function_name FROM gardening_tasks t \
     LEFT JOIN modules m ON m.id=t.target_module_id LEFT JOIN functions f ON f.id=t.target_function_id \
     LEFT JOIN modules fm ON fm.id=f.module_id"
    "SELECT NULL id,NULL github_issue,NULL category,NULL title,NULL status,NULL created_at,\
     NULL completed_at,NULL target_module_path,NULL target_function_module_path,\
     NULL target_function_name WHERE 0" ;
  copy "gardening_log"
    "SELECT id,date,contributor,category,description,pr_number,issue_number,created_at FROM gardening_log"
    "SELECT NULL id,NULL date,NULL contributor,NULL category,NULL description,NULL pr_number,\
     NULL issue_number,NULL created_at WHERE 0"

let invalidate_analysis db =
  let delete_if_present table =
    if has_table db table then exec_exn db ("DELETE FROM " ^ table)
  in
  List.iter delete_if_present
    [ "conditions"; "decisions"; "decision_analysis_files";
      "function_effects"; "effect_analysis_functions" ] ;
  if has_table db "comment_db_meta" then
    exec_exn db
      "DELETE FROM comment_db_meta WHERE key LIKE 'decision_%' OR key LIKE 'effect_%'"

let restore_curation db =
  exec_exn db
    "INSERT INTO unsafe_params(id,function_id,target_module_path,target_function_name,param_name,\
     current_type,target_type,fixed,fixed_at,github_issue) SELECT b.id,f.id,b.target_module_path,\
     b.target_function_name,b.param_name,b.current_type,b.target_type,b.fixed,b.fixed_at,b.github_issue \
     FROM temp.curation_backup_unsafe_params b LEFT JOIN modules m ON m.path=b.target_module_path \
     LEFT JOIN functions f ON f.module_id=m.id AND f.name=b.target_function_name" ;
  exec_exn db
    "INSERT INTO coverage(id,function_id,target_module_path,target_function_name,covered_lines,\
     total_lines,recorded_at) SELECT b.id,f.id,b.target_module_path,b.target_function_name,\
     b.covered_lines,b.total_lines,b.recorded_at FROM temp.curation_backup_coverage b \
     LEFT JOIN modules m ON m.path=b.target_module_path \
     LEFT JOIN functions f ON f.module_id=m.id AND f.name=b.target_function_name" ;
  exec_exn db
    "INSERT INTO gardening_tasks(id,github_issue,category,title,target_module_id,target_function_id,\
     target_module_path,target_function_module_path,target_function_name,status,created_at,completed_at) \
     SELECT b.id,b.github_issue,b.category,b.title,m.id,f.id,b.target_module_path,\
     b.target_function_module_path,b.target_function_name,b.status,b.created_at,b.completed_at \
     FROM temp.curation_backup_gardening_tasks b LEFT JOIN modules m ON m.path=b.target_module_path \
     LEFT JOIN modules fm ON fm.path=b.target_function_module_path \
     LEFT JOIN functions f ON f.module_id=fm.id AND f.name=b.target_function_name" ;
  exec_exn db
    "INSERT INTO gardening_log(id,date,contributor,category,description,pr_number,issue_number,created_at) \
     SELECT id,date,contributor,category,description,pr_number,issue_number,created_at \
     FROM temp.curation_backup_gardening_log"

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
