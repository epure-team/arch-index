(* Direct-API lifecycle evidence for functor binding provenance.  This probe uses
   the production schema and Arch_index_bindings storage/finalization functions;
   it is deliberately not evidence for full arch-index/arch-query orchestration. *)

module Bindings = Arch_index__Arch_index_bindings

exception Setup_error of string
exception Assertion_failure of string

let setup fmt = Printf.ksprintf (fun message -> raise (Setup_error message)) fmt

let read_file path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel) @@ fun () ->
  really_input_string channel (in_channel_length channel)

let exec db sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> ()
  | rc -> setup "SQL failed (%s): %s" (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db)

let scalar db sql =
  let statement = Sqlite3.prepare db sql in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize statement)) @@ fun () ->
  match Sqlite3.step statement with
  | Sqlite3.Rc.ROW -> Sqlite3.column_int statement 0
  | rc -> setup "scalar query failed (%s): %s" (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db)

let text_opt db sql =
  let statement = Sqlite3.prepare db sql in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize statement)) @@ fun () ->
  match Sqlite3.step statement with
  | Sqlite3.Rc.ROW ->
      (match Sqlite3.column statement 0 with
       | Sqlite3.Data.TEXT value -> Some value
       | Sqlite3.Data.NULL -> None
       | _ -> setup "text query returned a non-text value")
  | Sqlite3.Rc.DONE -> None
  | rc -> setup "text query failed (%s): %s" (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db)

let require condition fmt =
  if not condition then Printf.ksprintf (fun message -> raise (Assertion_failure message)) fmt
  else Printf.ksprintf (fun _ -> ()) fmt

let contains ~needle haystack =
  let needle_length = String.length needle and haystack_length = String.length haystack in
  let rec search offset =
    offset + needle_length <= haystack_length
    && (String.sub haystack offset needle_length = needle || search (offset + 1))
  in
  search 0

let with_db schema f =
  let db = Sqlite3.db_open ":memory:" in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.db_close db)) @@ fun () ->
  exec db schema ;
  f db

let location =
  {|{"file":"fixture.ml","start_line":1,"start_col":0,"end_line":1,"end_col":1,"ghost":false}|}

let path name =
  Printf.sprintf
    {|{"kind":"path","compiler":"%s","source":"%s","contains_apply":false}|}
    name name

let seed_old_facts db ~applications =
  exec db "INSERT INTO producer_runs(id,producer) VALUES(1,'lifecycle-probe')" ;
  exec db "INSERT INTO modules(id,path) VALUES(1,'fixture.ml')" ;
  exec db
    "INSERT INTO functions(id,module_id,name,line_start,line_end) VALUES(1,1,'graph_sentinel',1,1)" ;
  exec db
    (Printf.sprintf
       "INSERT INTO functor_catalogue_runs(producer_run_id,selected_inputs) VALUES(1,1);\
        INSERT INTO functor_catalogue_inputs(producer_run_id,artifact,source,compiler_unit,module_id,outcome,expected_applications) \
        VALUES(1,'fixture.cmt','fixture.ml','Fixture',1,'collected',%d)"
       applications) ;
  for ordinal = 1 to applications do
    exec db
      (Printf.sprintf
         "INSERT INTO functor_applications(producer_run_id,artifact,ordinal,application_kind,location,head,argument,diagnostics) \
          VALUES(1,'fixture.cmt',%d,'apply','%s','%s','%s','[]')"
         ordinal location (path "F") (path "A"))
  done ;
  exec db
    "INSERT INTO comment_db_meta(key,value) VALUES('functor_catalogue_contract','v1')"

let collection () =
  let formal : Bindings.formal =
    {position = 1; kind = Bindings.Named; binder_key = Some "X"; name = Some "X"}
  in
  let declaration : Bindings.declaration =
    {declaration_key = "F"; name = "F"; location; formals = [formal]}
  in
  let result ordinal : Bindings.result =
    { ordinal;
      status = "matched";
      reason = None;
      declaration_key = Some "F";
      formal_position = Some 1;
      head_application_ordinal = None;
      actual_root_key = Some "A" }
  in
  {Bindings.declarations = [declaration]; results = [result 1; result 2]}

let storage_rollback schema =
  with_db schema @@ fun db ->
  seed_old_facts db ~applications:2 ;
  exec db
    {|CREATE TRIGGER reject_second_binding BEFORE INSERT ON functor_bindings
      WHEN NEW.ordinal=2 BEGIN
        SELECT CASE WHEN
          (SELECT count(*) FROM functor_bindings)=1 AND
          (SELECT count(*) FROM functor_declarations)=1 AND
          (SELECT count(*) FROM functor_binding_inputs)=1
        THEN RAISE(ABORT,'injected second-result failure')
        ELSE RAISE(ABORT,'wrong partial-insertion premise') END;
      END|} ;
  let raised =
    try Bindings.store_collected db ~producer_run_id:1 ~artifact:"fixture.cmt" (collection ()); false
    with Failure message -> contains ~needle:"injected second-result failure" message
  in
  require raised "second-result storage failure did not surface" ;
  require (scalar db "SELECT count(*) FROM functor_binding_inputs" = 0)
    "partial rollback retained a binding input" ;
  require (scalar db "SELECT count(*) FROM functor_declarations" = 0)
    "partial rollback retained a declaration" ;
  require (scalar db "SELECT count(*) FROM functor_bindings" = 0)
    "partial rollback retained a result" ;
  require (scalar db "SELECT count(*) FROM functor_applications" = 2)
    "partial rollback changed catalogue facts" ;
  require (scalar db "SELECT count(*) FROM functions WHERE name='graph_sentinel'" = 1)
    "partial rollback changed graph facts" ;
  Bindings.store_failed db ~producer_run_id:1 ~artifact:"fixture.cmt" ;
  require
    (text_opt db "SELECT outcome FROM functor_binding_inputs WHERE artifact='fixture.cmt'"
     = Some "collection_failed")
    "failed-row success did not record collection_failed" ;
  require
    (scalar db
       "SELECT count(*) FROM functor_binding_inputs WHERE expected_declarations=0 AND expected_bindings=0"
     = 1)
    "failed-row success did not record zero counts" ;
  exec db "DELETE FROM functor_binding_inputs" ;
  exec db
    {|CREATE TRIGGER reject_failed_row BEFORE INSERT ON functor_binding_inputs
      WHEN NEW.outcome='collection_failed'
      BEGIN SELECT RAISE(ABORT,'injected failed-row failure'); END|} ;
  let failed_row_raised =
    try Bindings.store_failed db ~producer_run_id:1 ~artifact:"fixture.cmt"; false
    with Failure message -> contains ~needle:"injected failed-row failure" message
  in
  require failed_row_raised "failed-row storage failure did not surface" ;
  require (scalar db "SELECT count(*) FROM functor_binding_inputs" = 0)
    "failed-row failure fabricated an input" ;
  `Assoc
    ["partial_failure_raised", `Bool raised;
     "binding_rows_after_rollback", `Int 0;
     "catalogue_rows_preserved", `Int 2;
     "graph_sentinel_preserved", `Bool true;
     "failed_row_success", `Bool true;
     "failed_row_rejection_raised", `Bool failed_row_raised]

let rollback_uncertainty schema =
  with_db schema @@ fun db ->
  seed_old_facts db ~applications:2 ;
  exec db
    {|CREATE TRIGGER rollback_second_binding BEFORE INSERT ON functor_bindings
      WHEN NEW.ordinal=2 BEGIN SELECT RAISE(ROLLBACK,'injected outer rollback'); END|} ;
  exec db "BEGIN" ;
  let uncertainty =
    try Bindings.store_collected db ~producer_run_id:1 ~artifact:"fixture.cmt" (collection ()); false
    with Failure message ->
      contains ~needle:"rollback uncertain" message
  in
  require uncertainty "RAISE(ROLLBACK) did not surface rollback uncertainty" ;
  require (scalar db "SELECT count(*) FROM functor_binding_inputs" = 0)
    "uncertain rollback retained binding input" ;
  require (scalar db "SELECT count(*) FROM functor_applications" = 2)
    "uncertain rollback changed committed catalogue facts" ;
  require (scalar db "SELECT count(*) FROM functions WHERE name='graph_sentinel'" = 1)
    "uncertain rollback changed committed graph facts" ;
  `Assoc
    ["raised_rollback_uncertainty", `Bool uncertainty;
     "binding_input_absent", `Bool true;
     "old_facts_preserved", `Bool true]

let marker_lifecycle schema =
  let zero_valid = with_db schema @@ fun db ->
    exec db "BEGIN" ;
    seed_old_facts db ~applications:0 ;
    exec db
      "INSERT INTO functor_binding_inputs(producer_run_id,artifact,outcome,expected_declarations,expected_bindings) VALUES(1,'fixture.cmt','collected',0,0)" ;
    require
      (text_opt db "SELECT value FROM comment_db_meta WHERE key='functor_binding_contract'" = None)
      "binding marker existed before data commit" ;
    exec db "COMMIT" ;
    require
      (text_opt db "SELECT value FROM comment_db_meta WHERE key='functor_binding_contract'" = None)
      "binding marker existed after data commit but before finalization" ;
    require (Bindings.finalize_contract db ~selected_inputs:1)
      "valid zero-result input did not finalize" ;
    require
      (text_opt db "SELECT value FROM comment_db_meta WHERE key='functor_binding_contract'"
       = Some "v1")
      "valid zero-result finalization did not write marker" ;
    exec db
      {|CREATE TRIGGER reject_binding_marker BEFORE INSERT ON comment_db_meta
        WHEN NEW.key='functor_binding_contract'
        BEGIN SELECT RAISE(ABORT,'injected marker failure'); END|} ;
    let marker_failure =
      try ignore (Bindings.finalize_contract db ~selected_inputs:1); false
      with Failure message -> contains ~needle:"injected marker failure" message
    in
    require marker_failure "marker-write failure did not surface" ;
    require
      (text_opt db "SELECT value FROM comment_db_meta WHERE key='functor_binding_contract'" = None)
      "marker-write failure revived or retained marker" ;
    require (Sqlite3.exec db "BEGIN" = Sqlite3.Rc.OK)
      "marker-write failure left finalizer transaction active" ;
    exec db "ROLLBACK" ;
    marker_failure
  in
  let empty_ineligible = with_db schema @@ fun db ->
    exec db "INSERT INTO producer_runs(id,producer) VALUES(1,'lifecycle-probe')" ;
    exec db
      "INSERT INTO comment_db_meta(key,value) VALUES('functor_catalogue_contract','v1')" ;
    let complete = Bindings.finalize_contract db ~selected_inputs:0 in
    require (not complete) "empty selection unexpectedly finalized" ;
    require
      (text_opt db "SELECT value FROM comment_db_meta WHERE key='functor_binding_contract'" = None)
      "empty selection earned a binding marker" ;
    true
  in
  `Assoc
    ["zero_result_finalized", `Bool true;
     "marker_absent_before_finalize", `Bool true;
     "marker_write_failure_raised", `Bool zero_valid;
     "marker_absent_after_write_failure", `Bool true;
     "empty_selection_ineligible", `Bool empty_ineligible]

let run schema_path =
  let schema = read_file schema_path in
  `Assoc
    ["ok", `Bool true;
     "evidence", `String "direct-api-not-full-cli-orchestration";
     "storage", storage_rollback schema;
     "rollback_uncertainty", rollback_uncertainty schema;
     "marker_lifecycle", marker_lifecycle schema]

let () =
  try
    let schema_path =
      match Array.to_list Sys.argv with
      | [_; path] -> path
      | _ -> setup "usage: lifecycle_probe ARCHITECTURE_SCHEMA_SQL"
    in
    Yojson.Safe.to_channel stdout (run schema_path) ;
    output_char stdout '\n'
  with
  | Assertion_failure message -> prerr_endline ("lifecycle_probe assertion: " ^ message); exit 1
  | Setup_error message -> prerr_endline ("lifecycle_probe setup: " ^ message); exit 2
  | Sys_error message -> prerr_endline ("lifecycle_probe setup: " ^ message); exit 2
  | exn ->
      prerr_endline ("lifecycle_probe unexpected: " ^ Printexc.to_string exn);
      exit 2
