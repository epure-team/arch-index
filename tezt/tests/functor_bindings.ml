open Arch_tezt
open Lwt.Infix

let files =
  [ Fixture.dune_project;
    ("dune", "(library (name binding_fixture) (wrapped false) (modules fixture))\n");
    ("fixture.ml", {ocaml|module type S = sig val n : int end
module F (X : S) = struct let n = X.n end
module A = struct let n = 1 end
module M = F(A)
|ocaml}) ]

let location =
  {|{"file":"fixture.ml","start_line":1,"start_col":0,"end_line":1,"end_col":1,"ghost":true}|}

let non_ghost_location =
  {|{"file":"fixture.ml","start_line":1,"start_col":0,"end_line":1,"end_col":1,"ghost":false}|}

let path name =
  Printf.sprintf
    {|{"kind":"path","compiler":"%s","source":"%s","contains_apply":false}|}
    name name

let application ordinal =
  Printf.sprintf {|{"kind":"application","ordinal":%d}|} ordinal

let formals =
  {|[{"position":1,"kind":"named","binder_key":"X","name":"X"},{"position":2,"kind":"named","binder_key":"Y","name":"Y"}]|}

let seed_bindings ?(declaration_location = location) ~applications ~bindings () =
  Printf.sprintf
    {|
INSERT INTO producer_runs(id,producer) VALUES (1,'test');
INSERT INTO modules(id,path) VALUES (1,'fixture.ml');
INSERT INTO functor_catalogue_runs(producer_run_id,selected_inputs) VALUES (1,1);
INSERT INTO functor_catalogue_inputs(producer_run_id,artifact,source,compiler_unit,module_id,outcome,expected_applications)
  VALUES (1,'fixture.cmt','fixture.ml','Fixture',1,'collected',%d);
%s
INSERT INTO functor_binding_inputs(producer_run_id,artifact,outcome,expected_declarations,expected_bindings)
  VALUES (1,'fixture.cmt','collected',1,%d);
INSERT INTO functor_declarations(producer_run_id,artifact,declaration_key,name,location,formals)
  VALUES (1,'fixture.cmt','F','F','%s','%s');
%s
INSERT INTO comment_db_meta(key,value) VALUES
  ('functor_catalogue_contract','v1'),('functor_binding_contract','v1');
|}
    (List.length applications)
    (String.concat "\n"
       (List.mapi
          (fun i (kind, head) ->
            Printf.sprintf
              "INSERT INTO functor_applications(producer_run_id,artifact,ordinal,application_kind,location,head,argument,diagnostics) VALUES (1,'fixture.cmt',%d,'%s','%s','%s','%s','[]');"
              (i + 1) kind location head (path "A"))
          applications))
    (List.length bindings) declaration_location formals (String.concat "\n" bindings)

let binding ?(position = 1) ?head ordinal =
  Printf.sprintf
    "INSERT INTO functor_bindings(producer_run_id,artifact,ordinal,status,reason,declaration_key,formal_position,head_application_ordinal,actual_root_key) VALUES (1,'fixture.cmt',%d,'matched',NULL,'F',%d,%s,NULL);"
    ordinal position
    (match head with None -> "NULL" | Some n -> string_of_int n)

let query path =
  run_command_split ~env:[("ARCH_QUERY_FORMAT", "json")] (arch_query ())
    [path; "functor-bindings"; "0"]

let require_valid_control path =
  let code, stdout, stderr = query path in
  Check.((code = 0) int
    ~error_msg:("positive binding control exit %L, expected %R: " ^ stdout ^ stderr))

let require_inconsistent path =
  let code, stdout, stderr = query path in
  Check.((code = 3) int
    ~error_msg:("corrupt binding query exit %L, expected %R: " ^ stdout ^ stderr)) ;
  Check.((stdout = "") string
    ~error_msg:"corrupt binding query leaked stdout %L, expected %R") ;
  Check.((contains ~needle:"INCONSISTENT_BINDINGS" stderr = true) bool
    ~error_msg:"corrupt binding refusal absent from stderr: %L")

let register_reader_duplicate () =
  Test.register ~__FILE__
    ~title:"functor bindings reader: duplicate result cannot replace a missing occurrence"
    ~tags:["functor"; "bindings"; "query"]
  @@ fun () ->
  let db = Fixture.main ~name:"functor_binding_duplicate_reader"
      ~seed:(seed_bindings
        ~applications:[("apply", path "F"); ("apply", path "F")]
        ~bindings:[binding 1; binding 2] ()) () in
  require_valid_control db ;
  Db.with_db_rw db (fun conn -> Db.exec conn
    {|
ALTER TABLE functor_bindings RENAME TO valid_functor_bindings;
CREATE TABLE functor_bindings AS SELECT * FROM valid_functor_bindings WHERE 0;
INSERT INTO functor_bindings SELECT * FROM valid_functor_bindings WHERE ordinal=1;
INSERT INTO functor_bindings SELECT * FROM valid_functor_bindings WHERE ordinal=1;
DROP TABLE valid_functor_bindings;
|}) ;
  require_inconsistent db ;
  Lwt.return_unit

let register_reader_direct_position () =
  Test.register ~__FILE__
    ~title:"functor bindings reader: direct match starts at formal position one"
    ~tags:["functor"; "bindings"; "query"]
  @@ fun () ->
  let db = Fixture.main ~name:"functor_binding_direct_position_reader"
      ~seed:(seed_bindings ~applications:[("apply", path "F")]
        ~bindings:[binding 1] ()) () in
  require_valid_control db ;
  Db.with_db_rw db (fun conn -> Db.exec conn
    "UPDATE functor_bindings SET formal_position=2") ;
  require_inconsistent db ;
  Lwt.return_unit

let register_reader_head_ordinal () =
  Test.register ~__FILE__
    ~title:"functor bindings reader: head ordinal equals the stripped catalogue head"
    ~tags:["functor"; "bindings"; "query"]
  @@ fun () ->
  let db = Fixture.main ~name:"functor_binding_head_ordinal_reader"
      ~seed:(seed_bindings
        ~applications:[("apply", application 2); ("apply", path "F")]
        ~bindings:[binding ~position:2 ~head:2 1; binding 2] ()) () in
  require_valid_control db ;
  Db.with_db_rw db (fun conn -> Db.exec conn
    "UPDATE functor_bindings SET head_application_ordinal=NULL WHERE ordinal=1") ;
  require_inconsistent db ;
  Lwt.return_unit

let register_reader_non_ghost_location () =
  Test.register ~__FILE__
    ~title:"functor bindings reader: valid declaration location may be non-ghost"
    ~tags:["functor"; "bindings"; "query"]
  @@ fun () ->
  let db = Fixture.main ~name:"functor_binding_non_ghost_location_reader"
      ~seed:(seed_bindings ~declaration_location:non_ghost_location
        ~applications:[("apply", path "F")] ~bindings:[binding 1] ()) () in
  require_valid_control db ;
  Lwt.return_unit

let register_reader_commit_rollback () =
  Test.register ~__FILE__
    ~title:"functor bindings reader: commit failure rolls back its snapshot"
    ~tags:["functor"; "bindings"; "query"; "transaction"; "regression"]
  @@ fun () ->
  let db = Fixture.main ~name:"functor_binding_reader_commit_failure"
      ~seed:(seed_bindings ~applications:[("apply", path "F")]
        ~bindings:[binding 1] ()) () in
  let module A = Arch_tools.Arch_db in
  let opened = A.open_ro db in
  let module Real = (val opened.conn : A.C.CONNECTION) in
  let rollback_count = ref 0 in
  let module Fault = struct
    include Real
    let commit () = raise (A.Broken "injected commit failure")
    let rollback () = incr rollback_count; Real.rollback ()
  end in
  Fun.protect ~finally:(fun () -> ignore (Real.disconnect ())) (fun () ->
    let faulted = {opened with conn=(module Fault : A.C.CONNECTION)} in
    let failed =
      try ignore (Arch_tools.Arch_functor_bindings.read faulted ~limit:0); false
      with A.Broken message -> String.equal message "injected commit failure"
    in
    Check.((failed = true) bool
      ~error_msg:"injected reader commit failure surfaced %R, got %L") ;
    Check.((!rollback_count = 1) int
      ~error_msg:"reader commit failure rollback count %L, expected %R")) ;
  Lwt.return_unit

let register_reader_start_failure () =
  Test.register ~__FILE__
    ~title:"functor bindings reader: begin-snapshot failure is operational without rollback"
    ~tags:["functor"; "bindings"; "query"; "transaction"; "direct_api"]
  @@ fun () ->
  let db = Fixture.main ~name:"functor_binding_reader_start_failure"
      ~seed:(seed_bindings ~applications:[("apply", path "F")]
        ~bindings:[binding 1] ()) () in
  let module A = Arch_tools.Arch_db in
  let opened = A.open_ro db in
  let module Real = (val opened.conn : A.C.CONNECTION) in
  let rollback_count = ref 0 in
  let module Fault = struct
    include Real
    let start () = raise (A.Broken "injected begin-snapshot failure")
    let rollback () = incr rollback_count; Real.rollback ()
  end in
  Fun.protect ~finally:(fun () -> ignore (Real.disconnect ())) (fun () ->
    let faulted = {opened with conn=(module Fault : A.C.CONNECTION)} in
    let failed =
      try ignore (Arch_tools.Arch_functor_bindings.read faulted ~limit:0); false
      with A.Broken message -> String.equal message "injected begin-snapshot failure"
    in
    Check.((failed = true) bool
      ~error_msg:"injected begin-snapshot failure surfaced %R, got %L") ;
    Check.((!rollback_count = 0) int
      ~error_msg:"failed begin attempted rollback %L time(s), expected %R")) ;
  Lwt.return_unit

let register_reader_rollback_failure () =
  Test.register ~__FILE__
    ~title:"functor bindings reader: rollback failure supersedes a consistency refusal operationally"
    ~tags:["functor"; "bindings"; "query"; "transaction"; "direct_api"]
  @@ fun () ->
  let db = Fixture.main ~name:"functor_binding_reader_rollback_failure"
      ~seed:(seed_bindings ~applications:[("apply", path "F")]
        ~bindings:[binding 1] ()) () in
  Db.with_db_rw db (fun conn ->
    Db.exec conn "DELETE FROM comment_db_meta WHERE key='functor_binding_contract'") ;
  let module A = Arch_tools.Arch_db in
  let opened = A.open_ro db in
  let module Real = (val opened.conn : A.C.CONNECTION) in
  let rollback_count = ref 0 in
  let module Fault = struct
    include Real
    let rollback () =
      incr rollback_count ;
      raise (A.Broken "injected snapshot rollback failure")
  end in
  Fun.protect ~finally:(fun () -> ignore (Real.disconnect ())) (fun () ->
    let faulted = {opened with conn=(module Fault : A.C.CONNECTION)} in
    let failed =
      try ignore (Arch_tools.Arch_functor_bindings.read faulted ~limit:0); false
      with A.Broken message -> String.equal message "injected snapshot rollback failure"
    in
    Check.((failed = true) bool
      ~error_msg:"injected rollback failure surfaced operationally %R, got %L") ;
    Check.((!rollback_count = 1) int
      ~error_msg:"reader rollback failure count %L, expected %R")) ;
  Lwt.return_unit

let finalize db =
  Db.with_db_rw db (fun conn ->
    Arch_index__Arch_index_bindings.finalize_contract conn ~selected_inputs:1)

let register_finalizer_parity () =
  let mutations =
    [ "missing result", "DELETE FROM functor_bindings WHERE ordinal=1";
      "missing input", "DELETE FROM functor_binding_inputs";
      "failed input", "UPDATE functor_binding_inputs SET outcome='collection_failed',expected_declarations=0,expected_bindings=0";
      "expected bindings", "UPDATE functor_binding_inputs SET expected_bindings=3";
      "expected declarations", "UPDATE functor_binding_inputs SET expected_declarations=2";
      "missing declaration", "DELETE FROM functor_declarations";
      "empty declaration key", "UPDATE functor_declarations SET declaration_key=''";
      "empty declaration name", "UPDATE functor_declarations SET name=''";
      "empty formals", "UPDATE functor_declarations SET formals='[]'";
      "malformed formals", "UPDATE functor_declarations SET formals='['";
      "formal extra key", "UPDATE functor_declarations SET formals=json_set(formals,'$[0].extra',1)";
      "formal duplicate key", {|UPDATE functor_declarations SET formals='[{"position":1,"kind":"named","kind":"named","binder_key":"X","name":"X"}]'|};
      "formal empty name", "UPDATE functor_declarations SET formals=json_set(formals,'$[0].name','')";
      "formal noncontiguous", "UPDATE functor_declarations SET formals=json_set(formals,'$[1].position',3)";
      "declaration location", "UPDATE functor_declarations SET location=json_set(location,'$.ghost','true')";
      "declaration coordinates", "UPDATE functor_declarations SET location=json_set(location,'$.start_line',0)";
      "binding storage class", "UPDATE functor_bindings SET actual_root_key=x'41' WHERE ordinal=2";
      "binding position", "UPDATE functor_bindings SET formal_position=2 WHERE ordinal=2";
      "binding head", "UPDATE functor_bindings SET head_application_ordinal=NULL WHERE ordinal=1";
      "binding kind", "UPDATE functor_declarations SET formals=json_set(formals,'$[0].kind','unit','$[0].binder_key',NULL,'$[0].name',NULL)";
      "unresolved reason", "UPDATE functor_bindings SET status='unresolved',reason='unknown',declaration_key=NULL,formal_position=NULL WHERE ordinal=1";
      "catalogue selected count", "UPDATE functor_catalogue_runs SET selected_inputs=2";
      "catalogue count", "UPDATE functor_catalogue_inputs SET expected_applications=3";
      "catalogue source", "UPDATE functor_catalogue_inputs SET source='elsewhere.ml'";
      "catalogue producer", "DELETE FROM producer_runs";
      "catalogue input storage class", "UPDATE functor_catalogue_inputs SET source=x'41'";
      "catalogue ordinal", "UPDATE functor_applications SET ordinal=3 WHERE ordinal=2";
      "catalogue descriptor", "UPDATE functor_applications SET head=json_set(head,'$.extra',1) WHERE ordinal=2";
      "catalogue diagnostics", "UPDATE functor_applications SET diagnostics='[\"opaque_functor_head\"]' WHERE ordinal=2";
      "catalogue forward reference", "UPDATE functor_applications SET head=json_set(head,'$.ordinal',1) WHERE ordinal=1";
      "catalogue location", "UPDATE functor_applications SET location=json_set(location,'$.start_col',-1)" ]
  in
  List.iteri (fun i (label, mutation) ->
    Test.register ~__FILE__ ~title:("functor binding finalizer parity: " ^ label)
      ~tags:["functor"; "bindings"; "lifecycle"; "parity"]
    @@ fun () ->
    let db = Fixture.main ~name:("binding_parity_" ^ string_of_int i)
        ~seed:(seed_bindings
          ~applications:[("apply", application 2); ("apply", path "F")]
          ~bindings:[binding ~position:2 ~head:2 1; binding 2] ()) () in
    require_valid_control db ;
    Check.((finalize db = true) bool ~error_msg:"valid finalizer control %L, expected %R") ;
    Db.with_db_rw db (fun conn ->
      (* Disable only SQL guards to test the validator on persisted corruption.
         Each initial database above was accepted by the independent reader. *)
      Db.exec conn "PRAGMA foreign_keys=OFF; PRAGMA ignore_check_constraints=ON" ;
      Db.exec conn mutation) ;
    Check.((finalize db = false) bool ~error_msg:"corrupt finalizer accepted %L, expected %R") ;
    Db.with_db_rw db (fun conn ->
      Check.((Db.string_opt conn "SELECT value FROM comment_db_meta WHERE key='functor_binding_contract'" = None)
        (option string) ~error_msg:"invalid finalization retained marker %L, expected %R") ;
      (* Deliberately forged marker tests the separate reader boundary. *)
      Db.exec conn "INSERT INTO comment_db_meta(key,value) VALUES('functor_binding_contract','v1')") ;
    require_inconsistent db ;
    Lwt.return_unit) mutations

let register_finalizer_zero () =
  Test.register ~__FILE__ ~title:"functor binding finalizer: collected zero applications is valid"
    ~tags:["functor"; "bindings"; "lifecycle"]
  @@ fun () ->
  let db = Fixture.main ~name:"binding_zero_finalizer"
      ~seed:(seed_bindings ~applications:[] ~bindings:[] ()) () in
  Check.((finalize db = true) bool ~error_msg:"unused declaration finalizer %L, expected %R") ;
  require_valid_control db ;
  Db.with_db_rw db (fun conn ->
    Db.exec conn "DELETE FROM functor_declarations; UPDATE functor_binding_inputs SET expected_declarations=0") ;
  Check.((finalize db = true) bool ~error_msg:"zero declaration finalizer %L, expected %R") ;
  require_valid_control db ;
  Lwt.return_unit

let register_finalizer_write_failure () =
  Test.register ~__FILE__ ~title:"functor binding finalizer: marker write failure rolls back its transaction"
    ~tags:["functor"; "bindings"; "lifecycle"]
  @@ fun () ->
  let db = Fixture.main ~name:"binding_finalizer_write_failure"
      ~seed:(seed_bindings ~applications:[("apply", path "F")]
        ~bindings:[binding 1] ()) () in
  require_valid_control db ;
  Db.with_db_rw db (fun conn ->
    Db.exec conn {|CREATE TRIGGER reject_binding_marker BEFORE INSERT ON comment_db_meta
      WHEN NEW.key='functor_binding_contract'
      BEGIN SELECT RAISE(ABORT,'injected binding marker failure'); END|} ;
    let raised =
      try ignore (Arch_index__Arch_index_bindings.finalize_contract conn ~selected_inputs:1); false
      with Failure _ -> true
    in
    Check.((raised = true) bool ~error_msg:"marker write failure must raise %R, got %L") ;
    Check.((Db.string_opt conn "SELECT value FROM comment_db_meta WHERE key='functor_binding_contract'" = None)
      (option string) ~error_msg:"failed marker write retained %L, expected %R") ;
    Check.((Sqlite3.Rc.to_string (Sqlite3.exec conn "BEGIN") = "OK") string
      ~error_msg:"failed finalizer left transaction active: %L, expected %R") ;
    Db.exec conn "ROLLBACK") ;
  Lwt.return_unit

let register_finalizer_schema () =
  List.iter (fun (label, mutation) ->
    Test.register ~__FILE__ ~title:("functor binding finalizer schema: " ^ label)
      ~tags:["functor"; "bindings"; "lifecycle"; "parity"]
    @@ fun () ->
    let db = Fixture.main ~name:("binding_schema_" ^ label)
        ~seed:(seed_bindings ~applications:[("apply", path "F")]
          ~bindings:[binding 1] ()) () in
    require_valid_control db ;
    Check.((finalize db = true) bool ~error_msg:"valid schema control %L, expected %R") ;
    Db.with_db_rw db (fun conn -> Db.exec conn mutation) ;
    Check.((finalize db = false) bool ~error_msg:"unsupported schema finalized %L, expected %R") ;
    Db.with_db_rw db (fun conn ->
      Check.((Db.string_opt conn "SELECT value FROM comment_db_meta WHERE key='functor_binding_contract'" = None)
        (option string) ~error_msg:"unsupported schema retained marker %L, expected %R") ;
      Db.exec conn "INSERT INTO comment_db_meta(key,value) VALUES('functor_binding_contract','v1')") ;
    let code, stdout, stderr = query db in
    Check.((code = 3) int ~error_msg:"unsupported schema query exit %L, expected %R") ;
    Check.((stdout = "") string ~error_msg:"unsupported schema leaked %L, expected %R") ;
    Check.((contains ~needle:"UNSUPPORTED_SCHEMA" stderr = true) bool
      ~error_msg:"unsupported schema category absent: %L") ;
    Lwt.return_unit)
    ["flat_discriminator", "ALTER TABLE calls ADD COLUMN caller_name TEXT";
     "missing_column", "ALTER TABLE functor_bindings RENAME COLUMN actual_root_key TO missing_root_key"]

let native_files source =
  [ Fixture.dune_project;
    ("dune", "(library (name binding_fixture) (wrapped false) (modules fixture))\n");
    ("fixture.ml", source) ]

let require_native_query path ~matched =
  let code, stdout, stderr =
    run_command_split ~env:[("ARCH_QUERY_FORMAT", "json")] (arch_query ())
      [path; "functor-bindings"; "10"]
  in
  Check.((code = 0) int
    ~error_msg:("native binding query exit %L, expected %R: " ^ stderr)) ;
  Check.((contains ~needle:(Printf.sprintf {|"matched":%d|} matched) stdout = true) bool
    ~error_msg:"native binding query matched summary absent: %L")

let register_native_alias_chain () =
  Test.register ~__FILE__
    ~title:"functor bindings: local identity alias chain resolves the terminal declaration"
    ~tags:["functor"; "bindings"; "inventory"; "alias"]
  @@ fun () ->
  let source = {ocaml|module type S = sig val n : int end
module F (X : S) = struct let n = X.n end
module A = struct let n = 1 end
module Alias = F
module Shadow = struct
  module Alias = F
end
module Alias2 = Alias
module M = Alias2(A)
|ocaml} in
  with_fixture ~name:"functor_binding_alias_chain" ~files:(native_files source) @@ fun fixture ->
  let db = index fixture in
  Db.with_db db (fun conn ->
    Check.((Db.int conn "SELECT count(*) FROM functor_applications" = 1) int
      ~error_msg:"alias catalogue premise count %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM functor_declarations WHERE name='F'" = 1) int
      ~error_msg:"alias terminal declaration count %L, expected %R") ;
    Check.((Db.int conn
      "SELECT count(*) FROM functor_bindings b JOIN functor_declarations d ON d.producer_run_id=b.producer_run_id AND d.artifact=b.artifact AND d.declaration_key=b.declaration_key WHERE b.status='matched' AND b.reason IS NULL AND b.formal_position=1 AND b.head_application_ordinal IS NULL AND d.name='F'" = 1) int
      ~error_msg:"identity alias chain terminal match count %L, expected %R") ;
    Check.((Db.string_opt conn "SELECT value FROM comment_db_meta WHERE key='functor_binding_contract'" = Some "v1")
      (option string) ~error_msg:"alias binding marker %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM calls" = 0) int
      ~error_msg:"alias provenance changed graph calls %L, expected %R") ;
    Lwt.return_unit) >>= fun () ->
  require_native_query db ~matched:1 ;
  Lwt.return_unit

let register_native_direct_target_resolution () =
  Test.register ~__FILE__
    ~title:"functor targets: direct local application resolves a formal member call"
    ~tags:["functor"; "targets"; "cfa"; "native"]
  @@ fun () ->
  let source = {ocaml|module type S = sig val target : int -> int end
module F (X : S) = struct let run x = X.target x end
module A = struct let target x = x + 1 end
module M = F(A)
|ocaml} in
  with_fixture ~name:"functor_target_direct" ~files:(native_files source) @@ fun fixture ->
  let db = index fixture in
  Db.with_db db (fun conn ->
    Check.((Db.int conn
      "SELECT count(*) FROM calls c JOIN functions target ON target.id=c.callee_id \
       WHERE target.name='A.target' AND c.kind='MAY_ENUMERATED'" = 1) int
      ~error_msg:"FUNCTOR_TARGET_RED: direct F(A) target count is %L, expected %R") ;
    Check.((Db.int conn
      "SELECT count(*) FROM calls c WHERE c.callee_name='X.target' \
       AND c.kind='MAY_TOP' AND c.top_reason='module_param'" = 1) int
      ~error_msg:"FUNCTOR_TARGET_ASSERTION: original formal frontier count is %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM functions WHERE name LIKE 'M.%'" = 0) int
      ~error_msg:"FUNCTOR_TARGET_ASSERTION: instantiated definitions were cloned: %L, expected %R") ;
    Check.((Db.int conn
      "SELECT count(*) FROM functor_target_witnesses w \
       JOIN functor_bindings b ON b.producer_run_id=w.producer_run_id \
         AND b.artifact=w.artifact AND b.ordinal=w.application_ordinal \
       JOIN functor_declarations d ON d.producer_run_id=w.producer_run_id \
         AND d.artifact=w.artifact AND d.declaration_key=w.declaration_key \
       JOIN calls c ON c.id=w.candidate_call_id \
       JOIN functions target ON target.id=w.target_function_id \
       WHERE b.status='matched' AND b.formal_position=1 \
         AND json_extract(d.formals,'$[0].binder_key')=w.formal_key \
         AND target.name='A.target' AND c.kind='MAY_ENUMERATED'" = 1) int
      ~error_msg:"FUNCTOR_TARGET_RED: authenticated durable witness count is %L, expected %R") ;
    Check.((Db.string_opt conn
      "SELECT value FROM comment_db_meta WHERE key='functor_target_contract'" = Some "v2")
      (option string) ~error_msg:"FUNCTOR_TARGET_RED: target contract is %L, expected %R") ;
    Lwt.return_unit) >>= fun () ->
  let code, stdout, stderr =
    run_command_split ~env:[("ARCH_QUERY_FORMAT", "json")] (arch_query ())
      [db; "callees-of"; "F.run"]
  in
  Check.((code = 0) int
    ~error_msg:("FUNCTOR_TARGET_QUERY_RED: callees query exit is %L, expected %R: " ^ stderr)) ;
  Check.((contains ~needle:"A.target" stdout = true) bool
    ~error_msg:"FUNCTOR_TARGET_QUERY_RED: concrete target absent from consumer output: %L") ;
  let target_code, target_stdout, target_stderr =
    run_command_split ~env:[("ARCH_QUERY_FORMAT", "json")] (arch_query ())
      [db; "functor-targets"; "10"]
  in
  Check.((target_code = 0) int
    ~error_msg:(("FUNCTOR_TARGET_EXPLAINED_QUERY: query exit is %L, expected %R: ") ^ target_stderr)) ;
  Check.((contains ~needle:{|"target":"A.target"|} target_stdout = true) bool
    ~error_msg:"FUNCTOR_TARGET_EXPLAINED_QUERY: concrete target absent: %L") ;
  let target_has_frontier =
    contains ~needle:{|"edge_kind":"MAY_ENUMERATED"|} target_stdout
    && contains ~needle:{|"top_frontier":"MAY_TOP:module_param"|} target_stdout
  in
  Check.((target_has_frontier = true) bool
    ~error_msg:("FUNCTOR_TARGET_EXPLAINED_QUERY: retained module-parameter frontier absent: %L; output=" ^ target_stdout)) ;
  let zero_code, _zero_stdout, zero_stderr =
    run_command_split ~env:[("ARCH_QUERY_FORMAT", "json")] (arch_query ())
      [db; "functor-targets"; "0"]
  in
  Check.((zero_code = 0) int
    ~error_msg:("FUNCTOR_TARGET_EXPLAINED_QUERY: zero limit must be computed, got %L: " ^ zero_stderr)) ;
  let frontier_code, frontier_stdout, frontier_stderr =
    run_command_split ~env:[("ARCH_QUERY_FORMAT", "json")] (arch_query ())
      [db; "unknown-frontier"; "F.run"]
  in
  Check.((frontier_code = 0) int
    ~error_msg:("FUNCTOR_TARGET_FRONTIER_QUERY: query exit is %L, expected %R: " ^ frontier_stderr)) ;
  let frontier_has =
    contains ~needle:{|"frontier_fn":"F.run"|} frontier_stdout
    && contains ~needle:{|"edge_kind":"MAY_TOP"|} frontier_stdout
  in
  Check.((frontier_has = true) bool
    ~error_msg:("FUNCTOR_TARGET_FRONTIER_QUERY: MAY_TOP frontier absent: %L" ^ frontier_stdout)) ;
  let frontier_bad_code, _ = run_command (arch_query ()) [db; "unknown-frontier"] in
  Check.((frontier_bad_code = 2) int
    ~error_msg:"FUNCTOR_TARGET_FRONTIER_QUERY: missing root exit expected %R, got %L") ;
  Lwt.return_unit

let register_flat_target_non_inference () =
  Test.register ~__FILE__
    ~title:"functor targets: flat mode infers and persists no Stage 4 target or witness"
    ~tags:["functor"; "targets"; "cfa"; "flat"; "regression"]
  @@ fun () ->
  let source = {ocaml|module type S = sig val target : int -> int end
module F (X : S) = struct let run x = X.target x end
module A = struct let target x = x + 1 end
module M = F(A)
|ocaml} in
  with_fixture ~name:"functor_target_flat_non_inference" ~files:(native_files source)
  @@ fun fixture ->
  let db = index_project ~name:"functor_target_flat_non_inference" fixture.root in
  Db.with_db db (fun conn ->
    Check.((Db.int conn
      "SELECT count(*) FROM calls WHERE callee_name='A.target'" = 0) int
      ~error_msg:"FUNCTOR_TARGET_FLAT: inferred Stage 4 targets are %L, expected %R") ;
    Check.((Db.int conn
      "SELECT count(*) FROM sqlite_master \
       WHERE type='table' AND name='functor_target_witnesses'" = 0) int
      ~error_msg:"FUNCTOR_TARGET_FLAT: persisted Stage 4 witness tables are %L, expected %R") ;
    Lwt.return_unit) >>= fun () ->
  let code, _stdout, stderr = run_command_split (arch_query ()) [db; "functor-targets"] in
  Check.((code = 3) int
    ~error_msg:("FUNCTOR_TARGET_FLAT_QUERY: unsupported flat query exit is %L, expected %R: " ^ stderr)) ;
  Lwt.return_unit

let register_native_target_union_witnesses () =
  Test.register ~__FILE__
    ~title:"functor targets: 0-CFA unions actuals and preserves every witness"
    ~tags:["functor"; "targets"; "cfa"; "native"; "witness"]
  @@ fun () ->
  let source = {ocaml|module type S = sig val target : int -> int end
module F (X : S) = struct let run x = X.target x + X.target x end
module A = struct let target x = x + 1 end
module B = struct let target x = x - 1 end
module MA = F(A)
module MB = F(B)
module MA2 = F(A)
|ocaml} in
  with_fixture ~name:"functor_target_union" ~files:(native_files source) @@ fun fixture ->
  let db = index fixture in
  Db.with_db db (fun conn ->
    Check.((Db.int conn
      "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.callee_id \
       WHERE f.name IN ('A.target','B.target') AND c.kind='MAY_ENUMERATED'" = 4) int
      ~error_msg:"FUNCTOR_TARGET_UNION: candidate rows are %L, expected %R") ;
    Check.((Db.int conn
      "SELECT count(*) FROM calls WHERE callee_name='X.target' \
       AND kind='MAY_TOP' AND top_reason='module_param'" = 2) int
      ~error_msg:"FUNCTOR_TARGET_UNION: retained TOP rows are %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM functor_target_witnesses" = 6) int
      ~error_msg:"FUNCTOR_TARGET_UNION: witness rows are %L, expected %R") ;
    Check.((Db.int conn
      "SELECT count(DISTINCT occurrence_ordinal) FROM functor_target_witnesses" = 2) int
      ~error_msg:"FUNCTOR_TARGET_UNION: physical occurrences are %L, expected %R") ;
    Check.((Db.int conn
      "SELECT max(occurrence_ordinal)-min(occurrence_ordinal) \
       FROM functor_target_witnesses" = 1) int
      ~error_msg:"FUNCTOR_TARGET_OCCURRENCE_RED: physical ordinal gap is %L, expected %R") ;
    Check.((Db.int conn
      "SELECT count(DISTINCT target_function_id) FROM functor_target_witnesses" = 2) int
      ~error_msg:"FUNCTOR_TARGET_UNION: target union cardinality is %L, expected %R") ;
    Lwt.return_unit)

let register_native_target_variant_local_proofs () =
  Test.register ~__FILE__
    ~title:"functor targets: nonidentical variants retain artifact-local proofs"
    ~tags:["functor"; "targets"; "variant"; "provenance"; "ratchet"]
  @@ fun () ->
  let source = {ocaml|module type S = sig val target : int -> int end
module F (X : S) = struct let run x = X.target x end
module A = struct let target x = x + 1 end
module M = F(A)
|ocaml} in
  with_fixture ~name:"functor_target_variant_proofs" ~files:(native_files source)
  @@ fun fixture ->
  let variant_dir = Filename.concat fixture.build_dir "variant" in
  let mkdir_code, mkdir_output = run_command "mkdir" ["-p"; variant_dir] in
  Check.((mkdir_code = 0) int
    ~error_msg:("variant directory exit %L, expected %R: " ^ mkdir_output)) ;
  let variant_cmo = Filename.concat variant_dir "fixture.cmo" in
  let compile_code, compile_output =
    run_command ~cwd:fixture.root "ocamlc"
      ["-bin-annot"; "-g"; "-open"; "Stdlib"; "-c"; "-o"; variant_cmo;
       "fixture.ml"]
  in
  Check.((compile_code = 0) int
    ~error_msg:("variant compilation exit %L, expected %R: " ^ compile_output)) ;
  let db = index fixture in
  Db.with_db db (fun conn ->
    Check.((Db.int conn
      "SELECT count(*) FROM functor_target_inputs WHERE outcome='collected'" = 2) int
      ~error_msg:"FUNCTOR_TARGET_VARIANT_RED: collected target inputs are %L, expected %R") ;
    Check.((Db.int conn
      "SELECT count(DISTINCT artifact) FROM functor_target_witnesses" = 2) int
      ~error_msg:"FUNCTOR_TARGET_VARIANT_RED: local witness artifacts are %L, expected %R") ;
    Check.((Db.int conn
      "SELECT coalesce(sum(reconciliation_refusals),0) FROM functor_target_inputs" = 0) int
      ~error_msg:"FUNCTOR_TARGET_VARIANT_RED: reconciliation refusals are %L, expected %R") ;
    Check.((Db.int conn
      "SELECT count(*) FROM calls WHERE callee_name='A.target' AND kind='MAY_ENUMERATED'" = 1) int
      ~error_msg:"FUNCTOR_TARGET_VARIANT_RED: canonical candidate calls are %L, expected %R") ;
    Lwt.return_unit)

let register_target_validator_null_callee () =
  Test.register ~__FILE__
    ~title:"functor targets: finalizer rejects a witness whose candidate lost its callee"
    ~tags:["functor"; "targets"; "lifecycle"; "corruption"]
  @@ fun () ->
  let source = {ocaml|module type S = sig val target : int -> int end
module F (X : S) = struct let run x = X.target x end
module A = struct let target x = x + 1 end
module M = F(A)
|ocaml} in
  with_fixture ~name:"functor_target_null_callee" ~files:(native_files source) @@ fun fixture ->
  let db = index fixture in
  Db.with_db_rw db (fun conn ->
    Db.exec conn "PRAGMA foreign_keys=OFF" ;
    Db.exec conn
      "UPDATE calls SET callee_id=NULL WHERE id IN \
       (SELECT candidate_call_id FROM functor_target_witnesses)" ;
    Check.((Arch_index__Arch_index_bindings.finalize_target_contract conn
              ~selected_inputs:1 = false) bool
      ~error_msg:"FUNCTOR_TARGET_VALIDATOR_RED: NULL callee verdict is %L, expected %R") ;
    Check.((Db.string_opt conn
      "SELECT value FROM comment_db_meta WHERE key='functor_target_contract'" = None)
      (option string) ~error_msg:"corrupt target marker is %L, expected %R") ;
    Lwt.return_unit)

let register_target_rejected_candidate_lifecycle () =
  Test.register ~__FILE__
    ~title:"functor targets: rejected positive candidate prevents completion"
    ~tags:["functor"; "targets"; "lifecycle"; "rejection"]
  @@ fun () ->
  let source = {ocaml|module type S = sig val target : int -> int end
module F (X : S) = struct let run x = X.target x end
module A = struct let target x = x + 1 end
module M = F(A)
|ocaml} in
  with_fixture ~name:"functor_target_rejected" ~files:(native_files source) @@ fun fixture ->
  let schema_path = Temp.file "functor-target-rejection.sql" in
  write_file schema_path (read_file (schema ()) ^
    "\nCREATE TRIGGER reject_functor_target BEFORE INSERT ON calls \
     WHEN NEW.callee_name='A.target' AND NEW.kind='MAY_ENUMERATED' \
     BEGIN SELECT RAISE(ABORT,'injected functor target rejection'); END;\n") ;
  let db = temp_db "functor_target_rejected" in
  let code, _output = run_command (callgraph_ocaml ())
      ["--build-dir"; fixture.build_dir; "--db-path"; db; "--schema-path"; schema_path] in
  Check.((code = 1) int ~error_msg:"rejected candidate index exit is %L, expected %R") ;
  Db.with_db db (fun conn ->
    Check.((Db.int conn
      "SELECT count(*) FROM functor_target_inputs \
       WHERE outcome='collection_failed' AND expected_occurrences=0 \
         AND expected_candidates=0 AND expected_witnesses=0" = 1) int
      ~error_msg:"FUNCTOR_TARGET_COMPLETION_RED: atomic failed inputs are %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM calls WHERE callee_name='A.target' \
       AND kind='MAY_ENUMERATED'" = 0) int
      ~error_msg:"FUNCTOR_TARGET_ATOMIC_RED: rejected candidate left %L usable calls, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM functor_target_witnesses" = 0) int
      ~error_msg:"rejected candidate stored %L witnesses, expected %R") ;
    Check.((Db.string_opt conn
      "SELECT value FROM comment_db_meta WHERE key='functor_target_contract'" = None)
      (option string)
      ~error_msg:"FUNCTOR_TARGET_COMPLETION_RED: rejected candidate marker is %L, expected %R") ;
    Lwt.return_unit)

let register_target_validator_occurrence_identity () =
  Test.register ~__FILE__
    ~title:"functor targets: finalizer authenticates the physical occurrence"
    ~tags:["functor"; "targets"; "lifecycle"; "corruption"; "ratchet"]
  @@ fun () ->
  let source = {ocaml|module type S = sig val target : int -> int end
module F (X : S) = struct let run x = X.target x + X.target x end
module A = struct let target x = x + 1 end
module M = F(A)
|ocaml} in
  with_fixture ~name:"functor_target_occurrence_identity" ~files:(native_files source)
  @@ fun fixture ->
  let db = index fixture in
  Db.with_db_rw db (fun conn ->
    Db.exec conn "PRAGMA foreign_keys=OFF" ;
    Db.exec conn
      "UPDATE functor_target_witnesses SET occurrence_ordinal=97 \
       WHERE rowid=(SELECT min(rowid) FROM functor_target_witnesses)" ;
    Check.((Arch_index__Arch_index_bindings.finalize_target_contract conn
              ~selected_inputs:1 = false) bool
      ~error_msg:"FUNCTOR_TARGET_OCCURRENCE_AUTH_RED: corrupted ordinal verdict is %L, expected %R") ;
    Check.((Db.string_opt conn
      "SELECT value FROM comment_db_meta WHERE key='functor_target_contract'" = None)
      (option string) ~error_msg:"corrupt occurrence marker is %L, expected %R") ;
    Lwt.return_unit)

let register_target_validator_member_candidate_identity () =
  Test.register ~__FILE__
    ~title:"functor targets: finalizer authenticates actual member to candidate"
    ~tags:["functor"; "targets"; "lifecycle"; "corruption"; "ratchet"]
  @@ fun () ->
  let source = {ocaml|module type S = sig val target : int -> int end
module F (X : S) = struct let run x = X.target x end
module A = struct let target x = x + 1 end
module B = struct let target x = x - 1 end
module MA = F(A)
module MB = F(B)
|ocaml} in
  with_fixture ~name:"functor_target_member_candidate_identity"
    ~files:(native_files source) @@ fun fixture ->
  let db = index fixture in
  Db.with_db_rw db (fun conn ->
    Db.exec conn "PRAGMA foreign_keys=OFF" ;
    Db.exec conn
      "UPDATE functor_target_witnesses \
       SET target_key=(SELECT c.target_key FROM functor_target_candidates c \
                       WHERE c.occurrence_ordinal=functor_target_witnesses.target_occurrence_ordinal \
                         AND c.actual_path='[\"B\"]'), \
           target_function_id=(SELECT c.target_function_id FROM functor_target_candidates c \
                       WHERE c.occurrence_ordinal=functor_target_witnesses.target_occurrence_ordinal \
                         AND c.actual_path='[\"B\"]'), \
           candidate_call_id=(SELECT c.candidate_call_id FROM functor_target_candidates c \
                       WHERE c.occurrence_ordinal=functor_target_witnesses.target_occurrence_ordinal \
                         AND c.actual_path='[\"B\"]') \
       WHERE rowid=(SELECT min(rowid) FROM functor_target_witnesses \
                    WHERE actual_path='[\"A\"]')" ;
    Check.((Arch_index__Arch_index_bindings.finalize_target_contract conn
              ~selected_inputs:1 = false) bool
      ~error_msg:"FUNCTOR_TARGET_MEMBER_AUTH_RED: swapped candidate verdict is %L, expected %R") ;
    Check.((Db.string_opt conn
      "SELECT value FROM comment_db_meta WHERE key='functor_target_contract'" = None)
      (option string) ~error_msg:"swapped member marker is %L, expected %R") ;
    Lwt.return_unit)

let register_native_target_positions_and_refusals () =
  Test.register ~__FILE__
    ~title:"functor targets: curried slots nested members and refusals stay separated"
    ~tags:["functor"; "targets"; "cfa"; "native"; "refusal"]
  @@ fun () ->
  let source = {ocaml|module type S = sig
  val target : int -> int
  val alias : int -> int
  module N : sig val target : int -> int end
end
module G (X : S) (Y : S) = struct
  let run n = X.target n + Y.target n + Y.N.target n + X.alias n
end
module A = struct
  let target n = n + 1
  let alias = target
  module N = struct let target n = n + 2 end
end
module B = struct
  let target n = n - 1
  let alias = target
  module N = struct let target n = n - 2 end
end
module M = G(A)(B)
module Alias = A
module Refused = G(Alias)(B)
|ocaml} in
  with_fixture ~name:"functor_target_positions" ~files:(native_files source) @@ fun fixture ->
  let db = index fixture in
  Db.with_db db (fun conn ->
    Check.((Db.int conn
      "SELECT count(*) FROM functor_bindings WHERE status='matched' \
       AND formal_position=2 AND actual_root_key IS NOT NULL" = 2) int
      ~error_msg:"FUNCTOR_TARGET_CURRIED_PREMISE: matched position-two bindings are %L, expected %R") ;
    Check.((Db.int conn
      "SELECT count(*) FROM calls WHERE kind='MAY_ENUMERATED' \
       AND callee_name LIKE '%N.target'" = 1) int
      ~error_msg:"FUNCTOR_TARGET_NESTED_DIAGNOSTIC: nested candidate rows are %L, expected %R") ;
    Check.((Db.int conn
      "SELECT count(*) FROM functor_target_witnesses WHERE formal_position=2" = 4) int
      ~error_msg:"FUNCTOR_TARGET_CURRIED_RED: position-two witness total is %L, expected %R") ;
    Check.((Db.int conn
      "SELECT count(*) FROM functor_target_witnesses w \
       JOIN functions f ON f.id=w.target_function_id \
       WHERE w.formal_position=1 AND f.name='A.target'" = 2) int
      ~error_msg:"FUNCTOR_TARGET_CURRIED: position-one witnesses are %L, expected %R") ;
    Check.((Db.int conn
      "SELECT count(*) FROM functor_target_witnesses w \
       JOIN functions f ON f.id=w.target_function_id \
       WHERE w.formal_position=2 AND w.actual_path='[\"B\"]' \
         AND w.member_path='[\"target\"]' AND f.name='B.target'" = 2) int
      ~error_msg:"FUNCTOR_TARGET_CURRIED: position-two witnesses are %L, expected %R") ;
    Check.((Db.int conn
      "SELECT count(*) FROM functor_target_witnesses w \
       JOIN functions f ON f.id=w.target_function_id \
       WHERE w.formal_position=2 AND w.actual_path='[\"B\"]' \
         AND w.member_path='[\"N\",\"target\"]' AND f.name='B.N.target'" = 2) int
      ~error_msg:"FUNCTOR_TARGET_NESTED_RED: nested-member witnesses are %L, expected %R") ;
    Check.((Db.int conn
      "SELECT count(*) FROM functor_target_witnesses w \
       JOIN functions f ON f.id=w.target_function_id \
       WHERE f.name LIKE 'Alias.%'" = 0) int
      ~error_msg:"FUNCTOR_TARGET_REFUSAL: module alias invented %L witnesses, expected %R") ;
    Check.((Db.int conn
      "SELECT count(*) FROM calls WHERE kind='MAY_TOP' AND top_reason='module_param' \
       AND callee_name IN ('X.target','Y.target','Y.N.target','X.alias')" = 4) int
      ~error_msg:"FUNCTOR_TARGET_CURRIED: original formal frontiers are %L, expected %R") ;
    Lwt.return_unit)

let register_native_curried () =
  Test.register ~__FILE__
    ~title:"functor bindings: literal curried application links both formal positions"
    ~tags:["functor"; "bindings"; "inventory"; "curried"]
  @@ fun () ->
  let source = {ocaml|module type S = sig val n : int end
module F (X : S) (Y : S) = struct let n = X.n end
module A = struct let n = 1 end
module B = struct let n = 2 end
module M = F(A)(B)
|ocaml} in
  with_fixture ~name:"functor_binding_curried" ~files:(native_files source) @@ fun fixture ->
  let db = index fixture in
  Db.with_db db (fun conn ->
    Check.((Db.int conn "SELECT count(*) FROM functor_applications" = 2) int
      ~error_msg:"curried catalogue premise count %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM functor_bindings WHERE status='matched'" = 2) int
      ~error_msg:"curried matched result count %L, expected %R") ;
    Check.((Db.int conn
      "SELECT count(*) FROM functor_bindings outer_b JOIN functor_bindings inner_b ON inner_b.producer_run_id=outer_b.producer_run_id AND inner_b.artifact=outer_b.artifact AND inner_b.ordinal=outer_b.head_application_ordinal WHERE outer_b.ordinal=1 AND outer_b.formal_position=2 AND inner_b.ordinal=2 AND inner_b.formal_position=1 AND outer_b.declaration_key=inner_b.declaration_key AND inner_b.head_application_ordinal IS NULL" = 1) int
      ~error_msg:"curried exact forward inner-head link count %L, expected %R") ;
    Check.((Db.string_opt conn "SELECT value FROM comment_db_meta WHERE key='functor_binding_contract'" = Some "v1")
      (option string) ~error_msg:"curried binding marker %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM calls" = 0) int
      ~error_msg:"curried provenance changed graph calls %L, expected %R") ;
    Lwt.return_unit) >>= fun () ->
  require_native_query db ~matched:2 ;
  Lwt.return_unit

let register_native_traversal () =
  Test.register ~__FILE__
    ~title:"functor bindings: native traversal keeps shadowed identities and deferred binders distinct"
    ~tags:["functor"; "bindings"; "inventory"; "identity"; "traversal"]
  @@ fun () ->
  let source = {ocaml|module type S = sig val n : int end
module A = struct let n = 1 end
module F (X : S) = struct let n = X.n end
module Top = F(A)
module Scope = struct
  module F (X : S) = struct let n = X.n end
  module Inner = F(A)
end
let local_n =
  let module F (X : S) = struct let n = X.n end in
  let module M = F(A) in M.n
class c = object
  method n =
    let module F (X : S) = struct let n = X.n end in
    let module M = F(A) in M.n
end
module Deferred (X : S) = struct
  module InnerF (Y : S) = struct let n = Y.n end
  module M = InnerF(X)
end
module rec RF : functor (X : S) -> S = functor (X : S) -> struct let n = X.n end
module RM = RF(A)
|ocaml} in
  with_fixture ~name:"functor_binding_traversal" ~files:(native_files source) @@ fun fixture ->
  let db = index fixture in
  Db.with_db db (fun conn ->
    Check.((Db.int conn "SELECT count(*) FROM functor_applications" = 6) int
      ~error_msg:"traversal catalogue premise count %L, expected %R") ;
    Check.((Db.int conn "SELECT count(DISTINCT declaration_key) FROM functor_declarations WHERE name='F'" = 4) int
      ~error_msg:"four same-spelled F identities count %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM functor_declarations WHERE name IN ('InnerF','RF')" = 2) int
      ~error_msg:"deferred/recmodule declaration count %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM functor_bindings WHERE status='matched' AND formal_position=1" = 6) int
      ~error_msg:"traversal matched slot-one count %L, expected %R") ;
    Check.((Db.int conn
      "SELECT count(DISTINCT b.declaration_key) FROM functor_bindings b JOIN functor_declarations d ON d.producer_run_id=b.producer_run_id AND d.artifact=b.artifact AND d.declaration_key=b.declaration_key WHERE d.name='F'" = 4) int
      ~error_msg:"shadowed F applications retained distinct identities %L, expected %R") ;
    Check.((Db.string_opt conn "SELECT value FROM comment_db_meta WHERE key='functor_binding_contract'" = Some "v1")
      (option string) ~error_msg:"traversal marker %L, expected %R") ;
    Lwt.return_unit) >>= fun () ->
  require_native_query db ~matched:6 ;
  Lwt.return_unit

let register_native_formals_roots_refusals () =
  Test.register ~__FILE__
    ~title:"functor bindings: native unit anonymous roots and refusal shapes are explicit"
    ~tags:["functor"; "bindings"; "inventory"; "formals"; "refusals"; "roots"]
  @@ fun () ->
  let source = {ocaml|module type S = sig val n : int end
module A = struct let n = 1 end
module UnitF () = struct let n = 0 end
module UM = UnitF()
module Anon (_ : S) = struct let n = 0 end
module AM = Anon(A)
module ASM = Anon(struct let n = 2 end)
module Curried (X : S) (Y : S) = struct let n = X.n end
module Applied = Curried(A)
module Bad = Applied(A)
module Param (H : functor (X : S) -> S) = struct module PM = H(A) end
module Projected = Set.Make(struct type t = int let compare = compare end)
|ocaml} in
  with_fixture ~name:"functor_binding_shapes" ~files:(native_files source) @@ fun fixture ->
  let db = index fixture in
  Db.with_db db (fun conn ->
    Check.((Db.int conn "SELECT count(*) FROM functor_applications" = 7) int
      ~error_msg:"shape catalogue premise count %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM functor_declarations WHERE formals LIKE '%\"kind\":\"unit\"%'" = 1) int
      ~error_msg:"unit formal declaration count %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM functor_declarations WHERE name='Anon' AND formals LIKE '%\"binder_key\":null%'" = 1) int
      ~error_msg:"anonymous named formal declaration count %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM functor_bindings WHERE actual_root_key IS NOT NULL" = 4) int
      ~error_msg:"eligible native actual-root count %L, expected %R") ;
    Check.((Db.int conn
      "SELECT count(*) FROM functor_bindings b JOIN functor_applications a USING(producer_run_id,artifact,ordinal) WHERE a.argument LIKE '%\"kind\":\"structure\"%' AND b.actual_root_key IS NULL" = 2) int
      ~error_msg:"anonymous operands with null roots count %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM functor_bindings WHERE reason='unsupported_alias_rhs'" = 1) int
      ~error_msg:"application-valued alias refusal count %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM functor_bindings WHERE reason='parameter_supplied_head'" = 1) int
      ~error_msg:"parameter-head refusal count %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM functor_bindings WHERE reason='unsupported_path'" = 1) int
      ~error_msg:"projected-head refusal count %L, expected %R") ;
    Lwt.return_unit) >>= fun () ->
  require_native_query db ~matched:4 ;
  Lwt.return_unit

let register_storage_failure_lifecycle () =
  Test.register ~__FILE__
    ~title:"functor bindings: storage failure rolls back partial rows and failed-row failure stays absent"
    ~tags:["functor"; "bindings"; "lifecycle"; "rollback"]
  @@ fun () ->
  let db = Fixture.main ~name:"functor_binding_storage_failure"
      ~seed:{|
INSERT INTO producer_runs(id,producer) VALUES (1,'test');
INSERT INTO modules(id,path) VALUES (1,'fixture.ml');
INSERT INTO functions(id,module_id,name,line_start,line_end) VALUES(1,1,'sentinel',1,1);
INSERT INTO functor_catalogue_runs(producer_run_id,selected_inputs) VALUES (1,1);
INSERT INTO functor_catalogue_inputs(producer_run_id,artifact,source,compiler_unit,module_id,outcome,expected_applications)
 VALUES(1,'fixture.cmt','fixture.ml','Fixture',1,'collected',2);
INSERT INTO functor_applications(producer_run_id,artifact,ordinal,application_kind,location,head,argument,diagnostics)
 VALUES(1,'fixture.cmt',1,'apply','{"file":"fixture.ml","start_line":1,"start_col":0,"end_line":1,"end_col":1,"ghost":false}','{"kind":"path","compiler":"F","source":"F","contains_apply":false}','{"kind":"path","compiler":"A","source":"A","contains_apply":false}','[]'),
 (1,'fixture.cmt',2,'apply','{"file":"fixture.ml","start_line":2,"start_col":0,"end_line":2,"end_col":1,"ghost":false}','{"kind":"path","compiler":"F","source":"F","contains_apply":false}','{"kind":"path","compiler":"A","source":"A","contains_apply":false}','[]');
|} () in
  let module B = Arch_index__Arch_index_bindings in
  let formal =
    {B.position=1; kind=B.Named; binder_key=Some "X"; name=Some "X"}
  in
  let declaration key =
    {B.declaration_key=key; name=key; location; formals=[formal]}
  in
  let result ordinal =
    {B.ordinal; status="matched"; reason=None; declaration_key=Some "F";
     formal_position=Some 1; head_application_ordinal=None; actual_root_key=Some "A"}
  in
  let collection =
    {B.declarations=[declaration "F"]; results=[result 1; result 2]}
  in
  Db.with_db_rw db (fun conn ->
    Db.exec conn {|CREATE TRIGGER fail_second_result BEFORE INSERT ON functor_bindings
      WHEN NEW.ordinal=2 BEGIN
        SELECT CASE WHEN (SELECT count(*) FROM functor_bindings)<>1
          OR (SELECT count(*) FROM functor_declarations)<>1
          OR (SELECT count(*) FROM functor_binding_inputs)<>1
          THEN RAISE(ABORT,'wrong partial-storage premise') END;
        SELECT RAISE(ABORT,'injected second-result failure');
      END|} ;
    let failed =
      try B.store_collected conn ~producer_run_id:1 ~artifact:"fixture.cmt" collection; false
      with Failure message -> contains ~needle:"injected second-result failure" message
    in
    Check.((failed = true) bool ~error_msg:"partial storage failure raised %R, got %L") ;
    Check.((Db.int conn "SELECT count(*) FROM functor_binding_inputs" = 0) int
      ~error_msg:"rolled-back binding input rows %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM functor_declarations" = 0) int
      ~error_msg:"rolled-back declaration rows %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM functor_bindings" = 0) int
      ~error_msg:"rolled-back result rows %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM functor_applications" = 2) int
      ~error_msg:"binding rollback changed catalogue rows %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM functions WHERE name='sentinel'" = 1) int
      ~error_msg:"binding rollback changed graph sentinel %L, expected %R") ;
    B.store_failed conn ~producer_run_id:1 ~artifact:"fixture.cmt" ;
    Check.((Db.string_opt conn "SELECT outcome FROM functor_binding_inputs" = Some "collection_failed")
      (option string) ~error_msg:"successful failed-row outcome %L, expected %R") ;
    Db.exec conn "DELETE FROM functor_binding_inputs" ;
    Db.exec conn {|CREATE TRIGGER fail_failed_input BEFORE INSERT ON functor_binding_inputs
      WHEN NEW.outcome='collection_failed' BEGIN SELECT RAISE(ABORT,'failed-row failure'); END|} ;
    let failed_row = try B.store_failed conn ~producer_run_id:1 ~artifact:"fixture.cmt"; false
      with Failure message -> contains ~needle:"failed-row failure" message in
    Check.((failed_row = true) bool ~error_msg:"failed-row storage raised %R, got %L") ;
    Check.((Db.int conn "SELECT count(*) FROM functor_binding_inputs" = 0) int
      ~error_msg:"failed-row failure fabricated input rows %L, expected %R")) ;
  Lwt.return_unit

let register_storage_rollback_uncertainty () =
  Test.register ~__FILE__
    ~title:"functor bindings: SQLite transaction rollback makes savepoint recovery uncertain"
    ~tags:["functor"; "bindings"; "lifecycle"; "rollback"; "synthetic"]
  @@ fun () ->
  let db = Fixture.main ~name:"functor_binding_rollback_uncertain"
      ~seed:{|
INSERT INTO producer_runs(id,producer) VALUES(1,'test');
INSERT INTO modules(id,path) VALUES(1,'fixture.ml');
INSERT INTO functions(id,module_id,name,line_start,line_end) VALUES(1,1,'sentinel',1,1);
INSERT INTO functor_catalogue_runs VALUES(1,1);
INSERT INTO functor_catalogue_inputs VALUES(1,'fixture.cmt','fixture.ml','Fixture',1,'collected',2);
INSERT INTO functor_applications VALUES
(1,'fixture.cmt',1,'apply','{}','{}','{}','[]'),
(1,'fixture.cmt',2,'apply','{}','{}','{}','[]');
|} () in
  let module B = Arch_index__Arch_index_bindings in
  let formal = {B.position=1; kind=B.Named; binder_key=Some "X"; name=Some "X"} in
  let declaration = {B.declaration_key="F"; name="F"; location; formals=[formal]} in
  let result ordinal = {B.ordinal; status="matched"; reason=None; declaration_key=Some "F";
    formal_position=Some 1; head_application_ordinal=None; actual_root_key=None} in
  let collection = {B.declarations=[declaration]; results=[result 1; result 2]} in
  Db.with_db_rw db (fun conn ->
    Db.exec conn {|CREATE TRIGGER rollback_second_result BEFORE INSERT ON functor_bindings
      WHEN NEW.ordinal=2 BEGIN SELECT RAISE(ROLLBACK,'forced outer rollback'); END|} ;
    let uncertain =
      try B.store_collected conn ~producer_run_id:1 ~artifact:"fixture.cmt" collection; false
      with Failure message -> contains ~needle:"rollback uncertain" message
    in
    Check.((uncertain = true) bool ~error_msg:"rollback uncertainty surfaced %R, got %L") ;
    Check.((Db.int conn "SELECT count(*) FROM functor_binding_inputs" = 0) int
      ~error_msg:"uncertain rollback retained binding input %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM functions WHERE name='sentinel'" = 1) int
      ~error_msg:"uncertain rollback changed committed graph sentinel %L, expected %R") ;
    Check.((Db.int conn "SELECT count(*) FROM functor_applications" = 2) int
      ~error_msg:"uncertain rollback changed committed catalogue %L, expected %R")) ;
  Lwt.return_unit

let rec find_named_file root name =
  Sys.readdir root |> Array.to_list |> List.find_map (fun entry ->
    let candidate = Filename.concat root entry in
    if Sys.is_directory candidate then find_named_file candidate name
    else if entry = name then Some candidate else None)

let implementation_cmt fixture =
  let path =
    match find_named_file fixture.build_dir "fixture.cmt" with
    | Some path -> path
    | None -> Test.fail "native synthetic premise: fixture.cmt is absent"
  in
  match Cmt_format.read path with
  | _, Some {Cmt_format.cmt_annots=Cmt_format.Implementation structure; _} -> structure
  | _ -> Test.fail "native synthetic premise: fixture.cmt is not an implementation"

let register_synthetic_identity_refusals () =
  Test.register ~__FILE__
    ~title:"functor bindings: premise-checked typedtree identity mutations fail closed"
    ~tags:["functor"; "bindings"; "inventory"; "synthetic"; "identity"]
  @@ fun () ->
  let source = {ocaml|module type S = sig val n : int end
module F (X : S) = struct let n = X.n end
module A = struct let n = 1 end
module Alias = F
module M = Alias(A)
|ocaml} in
  with_fixture ~name:"functor_binding_synthetic_identity" ~files:(native_files source) @@ fun fixture ->
  let structure = implementation_cmt fixture in
  let module B = Arch_index__Arch_index_bindings in
  let open Typedtree in
  let bindings =
    List.filter_map (fun item -> match item.Typedtree.str_desc with
      | Typedtree.Tstr_module mb -> Some mb | _ -> None) structure.str_items
  in
  let named name =
    match List.find_opt (fun mb -> mb.Typedtree.mb_name.Location.txt = Some name) bindings with
    | Some mb -> mb | None -> Test.fail "synthetic premise: module %s absent" name
  in
  let f = named "F" and alias = named "Alias" and applied = named "M" in
  let f_id = Option.get f.mb_id and alias_id = Option.get alias.mb_id in
  let rec peel m = match m.mod_desc with
    | Tmod_constraint (inner, _, _, _) -> peel inner
    | _ -> m in
  let baseline = B.collect structure in
  Check.((List.map (fun (result : B.result) -> result.ordinal) baseline.results = [1])
    (list int) ~error_msg:"synthetic native ordinal premise %L, expected %R") ;
  let replace target replacement =
    {structure with str_items=List.map (fun item -> match item.str_desc with
      | Typedtree.Tstr_module mb when mb == target -> {item with str_desc=Tstr_module replacement}
      | _ -> item) structure.str_items}
  in
  let duplicate = replace alias {alias with mb_id=Some f_id} in
  let duplicate_premise = match (named "Alias").mb_id, f.mb_id with
    | Some alias_identity, Some f_identity -> not (Ident.same alias_identity f_identity)
    | _ -> false in
  let duplicate_after = match List.find_opt (fun item -> match item.str_desc with
    | Tstr_module mb -> mb.mb_name.Location.txt = Some "Alias" | _ -> false) duplicate.str_items with
    | Some {str_desc=Tstr_module mb; _} -> Option.fold ~none:false ~some:(Ident.same f_id) mb.mb_id
    | _ -> false in
  Check.((duplicate_premise = true) bool
    ~error_msg:"native distinct identity premise %R, got %L") ;
  Check.((duplicate_after = true) bool
    ~error_msg:"synthetic duplicate Ident.same premise %R, got %L") ;
  let duplicate_failed = try ignore (B.collect duplicate); false with Failure _ -> true in
  Check.((duplicate_failed = true) bool
    ~error_msg:"synthetic duplicate mb_id failed closed %R, got %L") ;
  let collision_expr = match f.mb_expr.mod_desc with
    | Tmod_functor (Named (_, name, mty), body) ->
        {f.mb_expr with mod_desc=Tmod_functor (Named (Some f_id, name, mty), body)}
    | _ -> Test.fail "synthetic premise: F is not a named functor" in
  let collision = replace f {f with mb_expr=collision_expr} in
  let collision_premise = match collision_expr.mod_desc with
    | Tmod_functor (Named (Some parameter_id, _, _), _) -> Ident.same parameter_id f_id
    | _ -> false in
  Check.((collision_premise = true) bool
    ~error_msg:"synthetic binder/parameter Ident.same premise %R, got %L") ;
  let collision_failed = try ignore (B.collect collision); false with Failure _ -> true in
  Check.((collision_failed = true) bool
    ~error_msg:"synthetic binder/parameter collision failed closed %R, got %L") ;
  let self_alias_expr = match alias.mb_expr.mod_desc with
    | Tmod_ident (_, lid) -> {alias.mb_expr with mod_desc=Tmod_ident (Path.Pident alias_id, lid)}
    | _ -> Test.fail "synthetic premise: Alias RHS is not an identifier" in
  let self_alias_premise = match self_alias_expr.mod_desc with
    | Tmod_ident (Path.Pident id, _) -> Ident.same id alias_id | _ -> false in
  (* The compiler wraps this native Alias head in Tmod_constraint. Verify the
     identity beneath that wrapper before exercising the synthetic self-cycle. *)
  let application_alias_premise = match applied.mb_expr.mod_desc with
    | Tmod_apply (head, _, _) ->
        (match (peel head).mod_desc with
         | Tmod_ident (Path.Pident id, _) -> Ident.same id alias_id
         | _ -> false)
    | _ -> false in
  Check.((self_alias_premise = true) bool
    ~error_msg:"synthetic self-alias Pident premise %R, got %L") ;
  Check.((application_alias_premise = true) bool
    ~error_msg:"native application-head Alias identity premise %R, got %L") ;
  let self_cycle = B.collect (replace alias {alias with mb_expr=self_alias_expr}) in
  let exact_unresolved reason (collection : B.collection) =
    match collection.results with
    | [result] -> result.ordinal = 1 && String.equal result.status "unresolved"
       && Option.equal String.equal result.reason (Some reason)
       && Option.is_none result.declaration_key && Option.is_none result.formal_position
       && Option.is_none result.head_application_ordinal
    | _ -> false
  in
  Check.((exact_unresolved "alias_cycle" self_cycle = true) bool
    ~error_msg:"synthetic self-cycle refusal present %R, got %L") ;
  let mutate_application make_head make_desc =
    match applied.mb_expr.mod_desc with
    | Tmod_apply (head, argument, coercion) ->
        let head = make_head (peel head) in
        replace applied {applied with mb_expr={applied.mb_expr with mod_desc=make_desc head argument coercion}}
    | _ -> Test.fail "synthetic premise: M RHS is not an application"
  in
  let missing_id = Ident.create_local "Missing" in
  let missing_premise = not (Ident.persistent missing_id)
    && List.for_all (fun mb -> match mb.mb_id with None -> true | Some id -> not (Ident.same id missing_id)) bindings in
  Check.((missing_premise = true) bool
    ~error_msg:"synthetic missing identity freshness premise %R, got %L") ;
  let missing = mutate_application
      (fun head -> match head.mod_desc with
        | Tmod_ident (_, lid) -> {head with mod_desc=Tmod_ident (Path.Pident missing_id, lid)}
        | _ -> Test.fail "synthetic premise: application head is not an identifier")
      (fun head argument coercion -> Tmod_apply (head, argument, coercion))
    |> B.collect in
  Check.((exact_unresolved "local_declaration_missing" missing = true) bool
    ~error_msg:"synthetic fresh-Pident refusal present %R, got %L") ;
  let persistent_id = Ident.create_persistent "External" in
  Check.((Ident.persistent persistent_id = true) bool
    ~error_msg:"synthetic persistent identity premise %R, got %L") ;
  let persistent = mutate_application
      (fun head -> match head.mod_desc with
        | Tmod_ident (_, lid) -> {head with mod_desc=Tmod_ident (Path.Pident persistent_id, lid)}
        | _ -> Test.fail "synthetic premise: application head is not an identifier")
      (fun head argument coercion -> Tmod_apply (head, argument, coercion))
    |> B.collect in
  Check.((exact_unresolved "cross_unit_head" persistent = true) bool
    ~error_msg:"synthetic persistent-Pident refusal present %R, got %L") ;
  let named_formal_premise = match f.mb_expr.mod_desc with
    | Tmod_functor (Named _, _) -> true | _ -> false in
  Check.((named_formal_premise = true) bool
    ~error_msg:"synthetic named-formal premise %R, got %L") ;
  let unit_structure = mutate_application Fun.id
      (fun head _argument _coercion -> Tmod_apply_unit head) in
  let unit_application_premise = match List.find_opt (fun item -> match item.str_desc with
    | Tstr_module mb -> mb.mb_name.Location.txt = Some "M" | _ -> false) unit_structure.str_items with
    | Some {str_desc=Tstr_module {mb_expr={mod_desc=Tmod_apply_unit _; _}; _}; _} -> true
    | _ -> false in
  Check.((unit_application_premise = true) bool
    ~error_msg:"synthetic Tmod_apply_unit premise %R, got %L") ;
  let unit_mismatch = B.collect unit_structure in
  Check.((exact_unresolved "formal_kind_mismatch" unit_mismatch = true) bool
    ~error_msg:"synthetic named-as-unit refusal present %R, got %L") ;
  Lwt.return_unit

let register_checkers () =
  List.iter (fun mode ->
    Test.register ~__FILE__
      ~title:("functor bindings independent checker: " ^ mode)
      ~tags:["functor"; "bindings"; "independent_checker"]
    @@ fun () ->
    let checker = Filename.concat (repo_root ()) "scripts/check-functor-bindings.js" in
    let code, stdout, stderr = run_command_split "node" [checker; mode] in
    if code <> 0 then
      Test.fail "binding checker %s exit %d (1=assertion, >=2=execution)\n%s\n%s"
        mode code stdout stderr ;
    Lwt.return_unit)
    ["inventory"; "lifecycle"; "query"; "compatibility"]

let register () =
  register_checkers () ;
  register_native_direct_target_resolution () ;
  register_flat_target_non_inference () ;
  register_native_target_union_witnesses () ;
  register_native_target_variant_local_proofs () ;
  register_target_validator_null_callee () ;
  register_target_validator_occurrence_identity () ;
  register_target_validator_member_candidate_identity () ;
  register_target_rejected_candidate_lifecycle () ;
  register_native_target_positions_and_refusals () ;
  register_native_traversal () ;
  register_native_formals_roots_refusals () ;
  register_storage_failure_lifecycle () ;
  register_storage_rollback_uncertainty () ;
  register_synthetic_identity_refusals () ;
  register_native_alias_chain () ;
  register_native_curried () ;
  register_finalizer_schema () ;
  register_finalizer_write_failure () ;
  register_finalizer_parity () ;
  register_finalizer_zero () ;
  register_reader_duplicate () ;
  register_reader_direct_position () ;
  register_reader_head_ordinal () ;
  register_reader_non_ghost_location () ;
  register_reader_start_failure () ;
  register_reader_rollback_failure () ;
  register_reader_commit_rollback () ;
  Test.register ~__FILE__
    ~title:"functor bindings: native direct application has formal provenance"
    ~tags:["functor"; "bindings"; "inventory"]
  @@ fun () ->
  with_fixture ~name:"functor_binding_direct" ~files @@ fun fixture ->
  let path = index fixture in
  Db.with_db path (fun db ->
    Check.((Db.int db "SELECT count(*) FROM functor_applications" = 1) int
      ~error_msg:"native catalogue premise: expected %R occurrence, got %L") ;
    Check.((Db.string_opt db "SELECT value FROM comment_db_meta WHERE key='functor_catalogue_contract'" = Some "v1")
      (option string) ~error_msg:"catalogue premise expected %R, got %L") ;
    Check.((Db.int db "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='functor_bindings'" = 1) int
      ~error_msg:"native input indexed successfully, but binding table count is %L, expected %R") ;
    Check.((Db.int db "SELECT count(*) FROM functor_bindings WHERE status='matched' AND formal_position=1 AND reason IS NULL" = 1) int
      ~error_msg:"direct formal match count is %L, expected %R") ;
    Check.((Db.int db "SELECT count(*) FROM functor_declarations WHERE name='F'" = 1) int
      ~error_msg:"direct declaration count is %L, expected %R") ;
    Check.((Db.string_opt db "SELECT value FROM comment_db_meta WHERE key='functor_binding_contract'" = Some "v1")
      (option string) ~error_msg:"binding completion expected %R, got %L") ;
    Check.((Db.int db "SELECT count(*) FROM calls" = 0) int
      ~error_msg:"binding provenance changed call facts: %L, expected %R") ;
    Check.((Db.int db "SELECT count(*) FROM functions WHERE name LIKE 'M.%'" = 0) int
      ~error_msg:"binding provenance cloned definitions: %L, expected %R") ;
    Lwt.return_unit) >>= fun () ->
  let code, stdout, stderr = run_command_split
      ~env:[("ARCH_QUERY_FORMAT", "json")] (arch_query ())
      [path; "functor-bindings"; "1"] in
  Check.((code = 0) int ~error_msg:("binding query exit %L, expected %R: " ^ stderr)) ;
  Check.((contains ~needle:{|"matched":1|} stdout = true) bool
    ~error_msg:"binding summary match absent: %L") ;
  Check.((contains ~needle:{|"formal_position":1|} stdout = true) bool
    ~error_msg:"binding formal position absent: %L") ;
  Lwt.return_unit
