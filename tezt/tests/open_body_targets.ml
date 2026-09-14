(******************************************************************************)
(* Native regression coverage for invocation-only open-wrapped function bodies. *)

open Arch_tezt

let files =
  [ Fixture.dune_project;
    ( "dune",
      "(library (name open_body_fixture) (wrapped false) (modules open_body) (flags (:standard -w -33)))\n" );
    ( "open_body.ml",
      {|module M = struct let tick x = x + 1 end

let wrapped = let open M in fun x -> tick x
let call_one x = wrapped x
let call_two x = wrapped x

let pair = let open M in fun ?(bonus=0) x y -> tick (bonus + x + y)
let partial x = pair x
let omitted x y = pair x y
let maker = let open M in fun x -> if x > 0 then (fun y -> tick (x + y)) else (fun y -> y)
let over x y = maker x y
let maker_opt = let open M in fun ?bonus x -> let n = Option.value ~default:0 bonus in if x > 0 then (fun y -> tick (n + x + y)) else (fun y -> n + y)
let omitted_over x y = maker_opt x y

let shadow = let open M in fun x -> tick (x + 10)
let old_shadow = shadow
let shadow = let open M in fun x -> tick (x + 20)
let call_shadow x = shadow x
let call_old x = old_shadow x

let nested = let open M in (let open M in fun x -> tick x)
let call_nested x = nested x
let local_user x = let local = let open M in fun y -> tick y in local x
let alias = wrapped
let call_alias x = alias x
let callback xs = List.map wrapped xs
|} ) ]

let register_resolution () =
  Test.register ~__FILE__
    ~title:"open-wrapped structural bodies: exact rich invocation targets and boundaries"
    ~tags:["cmt"; "calls"; "open_body"]
  @@ fun () ->
  with_fixture ~name:"open_body_targets" ~files @@ fun fixture ->
  let db = temp_db "open_body_targets" in
  let code, output = index_raw_into ~db fixture in
  if code <> 0 then Test.fail "OPEN_BODY_SETUP: index exit %d: %s" code output ;
  let count sql = Db.with_db db (fun c -> Db.int c sql) in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"OPEN_BODY_ASSERTION: wrapped owns one persisted root lambda"
        (count "SELECT count(*) FROM functions WHERE name LIKE 'wrapped.<fun:%'") 1 ;
      Batch.eq_int b ~msg:"OPEN_BODY_ASSERTION: both direct uses reach that actual lambda as MAY_ENUMERATED"
        (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name IN ('call_one','call_two') AND t.name LIKE 'wrapped.<fun:%' AND c.kind='MAY_ENUMERATED' AND c.top_reason IS NULL") 2 ;
      Batch.eq_int b ~msg:"OPEN_BODY_ASSERTION: direct uses add no MUST and retain no callback TOP"
        (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name IN ('call_one','call_two') AND (c.kind='MUST' OR c.top_reason='callback_param')") 0 ;
      Batch.eq_int b ~msg:"OPEN_BODY_ASSERTION: underapplication is enumerated but partial"
        (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name='partial' AND t.name LIKE 'pair.<fun:%' AND c.kind='MAY_ENUMERATED'") 1 ;
      Batch.eq_int b ~msg:"OPEN_BODY_ASSERTION: omitted optional slot uses supplied expressions"
        (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name='omitted' AND t.name LIKE 'pair.<fun:%' AND c.kind='MAY_ENUMERATED'") 1 ;
      Batch.eq_int b ~msg:"OPEN_BODY_ASSERTION: overapplication has one target and one returned-call residual"
        (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='over' AND ((c.callee_id IS NOT NULL AND c.callee_name LIKE 'maker.<fun:%') OR (c.callee_id IS NULL AND c.callee_name='*TOP*' AND c.top_reason='callback_param'))") 2 ;
      Batch.eq_int b ~msg:"OPEN_BODY_ASSERTION: omitted optional slot keeps exactly one returned-call residual"
        (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='omitted_over' AND (c.callee_name LIKE 'maker_opt.<fun:%' OR c.callee_name='*TOP*')") 2 ;
      Batch.eq_int b ~msg:"OPEN_BODY_ASSERTION: current shadow resolves only to its own root body"
        (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name='call_shadow' AND t.name LIKE 'shadow.<fun:%' AND t.name NOT LIKE 'shadow#1.%' AND c.kind='MAY_ENUMERATED'") 1 ;
      List.iter (fun caller ->
          Batch.eq_int b ~msg:("OPEN_BODY_ASSERTION: unsupported " ^ caller ^ " remains callback TOP")
            (count (Printf.sprintf "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='%s' AND c.kind='MAY_TOP' AND c.top_reason='callback_param'" caller)) 1)
        ["call_nested"; "call_alias"] ;
      Batch.eq_int b ~msg:"OPEN_BODY_ASSERTION: callback use remains legacy callback TOP"
        (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='callback' AND c.callee_name='wrapped' AND c.kind='MAY_TOP' AND c.top_reason='callback_param'") 1) ;
  Lwt.return_unit

let register_dropped () =
  Test.register ~__FILE__
    ~title:"open-wrapped structural bodies: rejected actual body stays dropped_node TOP"
    ~tags:["cmt"; "calls"; "open_body"; "rejections"]
  @@ fun () ->
  with_fixture ~name:"open_body_dropped" ~files @@ fun fixture ->
  let schema_path = Temp.file "open-body-rejection.sql" in
  write_file schema_path
    (read_file (schema ())
     ^ "\nCREATE TRIGGER reject_open_body BEFORE INSERT ON functions WHEN NEW.name LIKE 'wrapped.<fun:%' BEGIN SELECT RAISE(ABORT,'open body refused'); END;\n") ;
  let db = temp_db "open_body_dropped" in
  let code, output = run_command (callgraph_ocaml ())
      ["--build-dir"; fixture.build_dir; "--db-path"; db; "--schema-path"; schema_path] in
  if code <> 1 || not (contains ~needle:"functions: 1 row(s) rejected" output) then
    Test.fail "OPEN_BODY_SETUP: rejection injection did not run: exit %d %s" code output ;
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"OPEN_BODY_ASSERTION: rejected body cannot become a dangling enumerated leaf"
        (Db.with_db db (fun c -> Db.int c "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='call_one' AND c.callee_id IS NULL AND c.kind='MAY_TOP' AND c.top_reason='dropped_node'")) 1) ;
  Lwt.return_unit

let register_dropped_parent () =
  Test.register ~__FILE__
    ~title:"open-wrapped structural bodies: rejected parent makes its body unavailable"
    ~tags:["cmt"; "calls"; "open_body"; "rejections"]
  @@ fun () ->
  with_fixture ~name:"open_body_parent_dropped" ~files @@ fun fixture ->
  let schema_path = Temp.file "open-body-parent-rejection.sql" in
  write_file schema_path
    (read_file (schema ())
     ^ "\nCREATE TRIGGER reject_open_parent BEFORE INSERT ON functions WHEN NEW.name='wrapped' BEGIN SELECT RAISE(ABORT,'open parent refused'); END;\n") ;
  let db = temp_db "open_body_parent_dropped" in
  let code, output = run_command (callgraph_ocaml ())
      ["--build-dir"; fixture.build_dir; "--db-path"; db; "--schema-path"; schema_path] in
  if code <> 1 || not (contains ~needle:"functions: 1 row(s) rejected" output) then
    Test.fail "OPEN_BODY_SETUP: parent rejection injection did not run: exit %d %s" code output ;
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"OPEN_BODY_ASSERTION: rejected parent records unavailable root body as dropped_node"
        (Db.with_db db (fun c -> Db.int c "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='call_one' AND c.callee_id IS NULL AND c.callee_name LIKE 'wrapped.<fun:%' AND c.kind='MAY_TOP' AND c.top_reason='dropped_node'")) 1) ;
  Lwt.return_unit

let register_flat_compatibility () =
  Test.register ~__FILE__
    ~title:"open-wrapped structural bodies: flat collector remains legacy-compatible"
    ~tags:["cmt"; "flat"; "open_body"]
  @@ fun () ->
  with_fixture ~name:"open_body_flat" ~files @@ fun fixture ->
  let db = index_project ~name:"open_body_flat" fixture.root in
  Batch.run (fun b ->
      let count sql = Db.with_db db (fun c -> Db.int c sql) in
      Batch.eq_int b ~msg:"OPEN_BODY_ASSERTION: flat direct calls keep the source binder spelling"
        (count "SELECT count(*) FROM calls WHERE caller_name IN ('call_one','call_two') AND callee_name='wrapped'") 2 ;
      Batch.eq_int b ~msg:"OPEN_BODY_ASSERTION: flat output retains only the pre-existing parent-to-lambda row"
        (count "SELECT count(*) FROM calls WHERE callee_name LIKE 'wrapped.<fun:%'") 1) ;
  Lwt.return_unit

let register () =
  register_resolution () ;
  register_dropped () ;
  register_dropped_parent () ;
  register_flat_compatibility ()
