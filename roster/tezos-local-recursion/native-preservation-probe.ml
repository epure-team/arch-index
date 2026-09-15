module C = Native_collector

let read p =
  let i = open_in_bin p in
  Fun.protect ~finally:(fun () -> close_in_noerr i) (fun () -> really_input_string i (in_channel_length i))

let prep db sql = Sqlite3.prepare db sql

let rows db sql columns =
  let q = prep db sql and found = ref [] in
  let rc = ref (Sqlite3.step q) in
  while !rc = Sqlite3.Rc.ROW do
    found :=
      `List (List.init columns (fun i -> `String (Sqlite3.column_text q i))) :: !found ;
    rc := Sqlite3.step q
  done ;
  if !rc <> Sqlite3.Rc.DONE then (
    let message = Sqlite3.Rc.to_string !rc in
    ignore (Sqlite3.finalize q) ;
    failwith ("query failed: " ^ message)) ;
  ignore (Sqlite3.finalize q) ;
  List.rev !found

let owner_of_function_id db id =
  let q =
    prep db
      "SELECT m.path,f.name FROM functions f JOIN modules m ON m.id=f.module_id WHERE f.id=?"
  in
  ignore (Sqlite3.bind q 1 (Sqlite3.Data.INT (Int64.of_int id))) ;
  let result =
    match Sqlite3.step q with
    | Sqlite3.Rc.ROW ->
        let owner = (Sqlite3.column_text q 0, Sqlite3.column_text q 1) in
        (match Sqlite3.step q with
        | Sqlite3.Rc.DONE -> owner
        | rc -> failwith ("owner lookup cardinality: " ^ Sqlite3.Rc.to_string rc))
    | rc -> failwith ("owner lookup failed: " ^ Sqlite3.Rc.to_string rc)
  in
  ignore (Sqlite3.finalize q) ;
  result

let starts prefix value =
  String.length value >= String.length prefix
  && String.sub value 0 (String.length prefix) = prefix

let normalized_pending (p : C.pending_call) =
  let callee, callee_module = C.pending_display p in
  let head =
    match p.head with
    | C.Head_local n -> "local:" ^ n
    | C.Head_enumerated n -> "enumerated:" ^ n
    | C.Head_qualified (m, n) -> "qualified:" ^ Option.value ~default:"<null>" m ^ ":" ^ n
    | C.Head_unknown (n, r) -> "unknown:" ^ n ^ ":" ^ C.top_reason_to_string r
  in
  `List
    [ `String p.caller_module; `String p.caller_name; `String head;
      `String callee;
      (match callee_module with None -> `Null | Some s -> `String s);
      `Bool p.local_module_invocation; `Bool p.partial; `Bool p.cond; `Bool p.dead;
      `String p.call_site;
      (match p.exn_scope with None -> `Null | Some n -> `Int n);
      (match p.errch_scope with None -> `Null | Some n -> `Int n);
      (match p.errch_propagates with None -> `Null | Some s -> `String s);
      (match p.edge_form with None -> `Null | Some s -> `String s) ]

let admission_row (p : C.pending_call) =
  let callee, _ = C.pending_display p in
  if callee = "aux" || callee = "outer"
     || starts "basic.<fun:" callee || starts "annotated.<fun:" callee
     || starts "nested.<fun:" callee || starts "default_self.<fun:" callee
     || starts "optional.<fun:" callee || starts "refutable.<fun:" callee
     || starts "partial.<fun:" callee || starts "overapplied.<fun:" callee
     || starts "rhs_escape.<fun:" callee || starts "stacked.<fun:" callee
     || starts "structural_nonfunction.<fun:" callee || starts "collision.<fun:" callee
  then
    let classification = match p.head with
      | C.Head_enumerated _ -> "enumerated"
      | C.Head_unknown (_, r) -> "top:" ^ C.top_reason_to_string r
      | C.Head_local _ -> "local"
      | C.Head_qualified _ -> "qualified"
    in
    Some (`List [`String p.caller_name; `String p.call_site; `String callee;
                  `String classification; `Bool p.partial; `Bool p.cond; `Bool p.dead])
  else None

let () =
  let db = Sqlite3.db_open ":memory:" in
  (match Sqlite3.exec db (read Sys.argv.(1)) with
   | Sqlite3.Rc.OK -> () | rc -> failwith (Sqlite3.Rc.to_string rc)) ;
  let channels =
    List.filter
      (fun (c : Arch_index__Arch_errors_config.channel) -> c.type_paths <> [])
      Arch_index__Arch_errors_config.builtin.channels
  in
  let calls, deps, type_usages =
    C.process_cmt db ~project_root:Sys.argv.(2)
      ~source_path_of_cmt:(fun _ -> Some (Filename.concat Sys.argv.(2) "native.ml"))
      ~count_code_lines:(fun _ -> 1) ~exposed_tbl:(Hashtbl.create 0)
      ~doc_tbl:(Hashtbl.create 0) ~module_quint_tbl:(Hashtbl.create 0)
      ~stmt_mod:(prep db "INSERT INTO modules(path,lines,last_analyzed,has_mli,quint_module_raw,language) VALUES(?,?,?,?,?,?)")
      ~stmt_fn:(prep db "INSERT OR REPLACE INTO functions(module_id,name,signature,line_start,line_end,exposed,intent,comment_quality_score,has_pre,has_post,has_violators,has_violates,violators_raw,violates_raw,tests_raw,quint_raw,mutation_sites,deref_sites,language,producer_run_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
      ~stmt_ty:(prep db "INSERT OR REPLACE INTO types(module_id,name,kind,line_start,line_end,exposed,manifest,intent) VALUES(?,?,?,?,?,?,?,?)")
      ~stmt_fld:(prep db "INSERT INTO type_fields(type_id,field_name,field_type,position) VALUES(?,?,?,?)")
      ~stmt_ctor:(prep db "INSERT INTO type_constructors(type_id,constructor_name,position,arg_types) VALUES(?,?,?,?)")
      ~stmt_scope:(prep db "INSERT INTO exn_scopes(function_id,parent_id,form,line,col,catch_all,channel) VALUES(?,?,?,?,?,?,?)")
      ~stmt_catch:(prep db "INSERT INTO exn_scope_catches(scope_id,exn_path) VALUES(?,?)")
      ~stmt_origin:(prep db "INSERT INTO exn_origins(function_id,scope_id,form,exn_path,escapes,line,col,channel,operand_primitive,operand_slot,operand_category,operand_repr,operand_integer_kind,operand_unavailable_reason) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
      ~stmt_rebind:(prep db "INSERT OR IGNORE INTO exn_rebinds(alias_path,target_path) VALUES(?,?)")
      ~stmt_carrier:(prep db "INSERT OR IGNORE INTO channel_carriers(function_id,channel) VALUES(?,?)")
      ~value_channels:channels Sys.argv.(3)
  in
  let pending = List.map normalized_pending calls |> List.sort compare in
  let admissions = List.filter_map admission_row calls |> List.sort compare in
  let deps =
    List.map
      (fun (d : C.pending_dep) ->
        `List
          [ `String d.source_module; `String d.target_path; `String d.dep_kind;
            (match d.alias_name with None -> `Null | Some name -> `String name);
            `Int d.line_number ])
      deps
    |> List.sort compare
  in
  let type_usages =
    List.map
      (fun (u : C.pending_type_usage) ->
        let module_path, function_name = owner_of_function_id db u.function_id in
        `List
          [ `String module_path; `String function_name; `String u.type_path;
            `String u.usage_role;
            (match u.position with None -> `Null | Some position -> `Int position) ])
      type_usages
    |> List.sort compare
  in
  let modules =
    rows db
      "SELECT path,lines,coalesce(intent,'<null>'),has_mli,coalesce(quint_module_raw,'<null>'),coalesce(language,'<null>') FROM modules ORDER BY path"
      6
  in
  let functions = rows db "SELECT name,coalesce(signature,'<null>'),line_start,line_end,line_count,exposed,coalesce(intent,'<null>'),coalesce(comment_quality_score,'<null>'),has_pre,has_post,has_violators,has_violates,coalesce(violators_raw,'<null>'),coalesce(violates_raw,'<null>'),coalesce(tests_raw,'<null>'),coalesce(quint_raw,'<null>'),coalesce(mutation_sites,'<null>'),coalesce(deref_sites,'<null>'),coalesce(language,'<null>'),universe,coalesce(producer_run_id,'<null>') FROM functions ORDER BY name,line_start,line_end" 21 in
  let rebinds = rows db "SELECT alias_path,target_path FROM exn_rebinds ORDER BY alias_path,target_path" 2 in
  let types =
    rows db
      "SELECT m.path,t.name,t.kind,coalesce(t.line_start,'<null>'),coalesce(t.line_end,'<null>'),t.exposed,coalesce(t.manifest,'<null>'),coalesce(t.intent,'<null>') FROM types t JOIN modules m ON m.id=t.module_id ORDER BY m.path,t.name,t.line_start,t.line_end"
      8
  in
  let fields =
    rows db
      "SELECT m.path,t.name,f.field_name,f.field_type,f.position FROM type_fields f JOIN types t ON t.id=f.type_id JOIN modules m ON m.id=t.module_id ORDER BY m.path,t.name,f.position,f.field_name"
      5
  in
  let constructors =
    rows db
      "SELECT m.path,t.name,c.constructor_name,c.position,coalesce(c.arg_types,'<null>') FROM type_constructors c JOIN types t ON t.id=c.type_id JOIN modules m ON m.id=t.module_id ORDER BY m.path,t.name,c.position,c.constructor_name"
      5
  in
  let carriers = rows db "SELECT f.name,c.channel FROM channel_carriers c JOIN functions f ON f.id=c.function_id ORDER BY f.name,c.channel" 2 in
  let scopes = rows db "SELECT f.name,coalesce(p.form,'<root>'),coalesce(p.line,'<null>'),coalesce(p.col,'<null>'),s.form,s.line,s.col,s.catch_all,s.channel FROM exn_scopes s JOIN functions f ON f.id=s.function_id LEFT JOIN exn_scopes p ON p.id=s.parent_id ORDER BY f.name,s.line,s.col,s.channel" 9 in
  let catches = rows db "SELECT f.name,s.form,s.line,s.col,s.channel,c.exn_path FROM exn_scope_catches c JOIN exn_scopes s ON s.id=c.scope_id JOIN functions f ON f.id=s.function_id ORDER BY f.name,s.line,s.col,s.channel,c.exn_path" 6 in
  let origins = rows db "SELECT f.name,coalesce(s.form,'<root>'),coalesce(s.line,'<null>'),coalesce(s.col,'<null>'),o.form,coalesce(o.exn_path,'<null>'),o.escapes,o.line,o.col,o.channel,coalesce(o.operand_primitive,'<null>'),coalesce(o.operand_slot,'<null>'),coalesce(o.operand_category,'<null>'),coalesce(o.operand_repr,'<null>'),coalesce(o.operand_integer_kind,'<null>'),coalesce(o.operand_unavailable_reason,'<null>') FROM exn_origins o JOIN functions f ON f.id=o.function_id LEFT JOIN exn_scopes s ON s.id=o.scope_id ORDER BY f.name,o.line,o.col,o.channel,o.form" 16 in
  print_endline (Yojson.Basic.to_string (`Assoc
    [ "pending", `List pending; "admissions", `List admissions;
      "modules", `List modules; "deps", `List deps; "rebinds", `List rebinds;
      "type_usages", `List type_usages; "types", `List types;
      "fields", `List fields; "constructors", `List constructors;
      "functions", `List functions;
      "carriers", `List carriers; "scopes", `List scopes;
      "catches", `List catches; "origins", `List origins ])) ;
  ignore (Sqlite3.db_close db)
