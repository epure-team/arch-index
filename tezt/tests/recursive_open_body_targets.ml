(******************************************************************************)
(* Native SQL regressions for exact local recursive path-open function bodies. *)

open Arch_tezt

let files =
  [ Fixture.dune_project;
    ( "dune",
      "(library (name recursive_open_body_fixture) (wrapped false) (modules recursive_open_body) (flags (:standard -w -8-26-33-39)))\n" );
    ( "recursive_open_body.ml",
      {|module M = struct end

let exact n =
  let rec aux = let open M in fun x -> if x = 0 then 0 else aux (x - 1) in
  aux n

let nested_caller n =
  let rec aux =
    let open M in
    fun x ->
      let invoke y = if y = 0 then 0 else aux (y - 1) in
      invoke x
  in
  aux n

let escape n =
  let rec aux =
    let open M in
    fun x ->
      let saved = aux in
      ignore saved;
      if x = 0 then 0 else aux (x - 1)
  in
  aux n

let direct n =
  let rec aux x = if x = 0 then 0 else aux (x - 1) in
  aux n

let optional n =
  let rec aux =
    let open M in
    fun ?bonus x y ->
      if x = 0 then y + Option.value ~default:0 bonus
      else aux (x - 1) y
  in
  aux n 1

let defaulted n =
  let rec aux =
    let open M in
    fun ?(seed = if n = 0 then 0 else aux ~seed:0 0) x -> seed + x
  in
  aux n

let refutable n =
  let rec aux =
    let open M in
    function Some x -> if x = 0 then 0 else aux (Some (x - 1))
  in
  aux (Some n)

let partial n =
  let rec aux =
    let open M in
    fun x y ->
      if x = 0 then y
      else
        let deferred = aux (x - 1) in
        deferred y
  in
  aux n 1

let overapplied n =
  let rec aux =
    let open M in
    fun x ->
      if x = 0 then (fun y -> y)
      else (fun y -> aux (x - 1) y)
  in
  aux n 1

let nested_open n =
  let rec aux =
    let open M in
    let open M in
    fun x -> if x = 0 then 0 else aux (x - 1)
  in
  aux n

let annotated_pattern n =
  let rec (aux : int -> int) =
    let open M in
    fun x -> if x = 0 then 0 else aux (x - 1)
  in
  aux n

let drop_body n =
  let rec aux =
    let open M in
    fun x ->
      let invoke y = if y = 0 then 0 else aux (y - 1) in
      invoke x
  in
  aux n
|} ) ]

let count db sql = Db.with_db db (fun conn -> Db.int conn sql)

let root_name owner =
  Printf.sprintf "%s.<fun:%%" owner

let root_only owner =
  Printf.sprintf
    "name LIKE '%s' AND name NOT LIKE '%s.<fun:%%'"
    (root_name owner) (root_name owner)

let bounded_self db owner =
  count db
    (Printf.sprintf
       "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE %s AND c.callee_id=f.id AND c.kind='MAY_ENUMERATED' AND c.top_reason IS NULL AND c.top_anchor IS NULL"
       (root_only owner))

let callback_self db owner =
  count db
    (Printf.sprintf
       "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE %s AND c.callee_id IS NULL AND c.callee_name='aux' AND c.kind='MAY_TOP' AND c.top_reason='callback_param'"
       (root_only owner))

let register_resolution () =
  Test.register ~__FILE__
    ~title:"recursive open bodies: exact self-heads and conservative boundaries"
    ~tags:["cmt"; "calls"; "local_recursion"; "open_body"]
  @@ fun () ->
  with_fixture ~name:"recursive_open_body_targets" ~files @@ fun fixture ->
  let db = temp_db "recursive_open_body_targets" in
  let code, output = index_raw_into ~db fixture in
  if code <> 0 then
    Test.fail "RECURSIVE_OPEN_SETUP: index exit %d: %s" code output ;
  Batch.run (fun b ->
      List.iter
        (fun owner ->
          Batch.eq_int b
            ~msg:("RECURSIVE_OPEN_ASSERTION: " ^ owner ^ " stores one immediate inner root")
            (count db
               (Printf.sprintf "SELECT count(*) FROM functions WHERE %s" (root_only owner)))
            1 ;
          Batch.eq_int b
            ~msg:("RECURSIVE_OPEN_ASSERTION: " ^ owner ^ " self-head reaches its root as MAY_ENUMERATED")
            (bounded_self db owner) 1 ;
          Batch.eq_int b
            ~msg:("RECURSIVE_OPEN_ASSERTION: " ^ owner ^ " self-head is never MUST")
            (count db
               (Printf.sprintf
                  "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE %s AND c.callee_id=f.id AND c.kind='MUST'"
                  (root_only owner)))
            0)
        ["exact"; "optional"; "defaulted"; "refutable"; "partial"] ;
      Batch.eq_int b
        ~msg:"RECURSIVE_OPEN_ASSERTION: nested self-call keeps the nested function as caller and reaches the original root"
        (count db
           "SELECT count(*) FROM calls c JOIN functions caller ON caller.id=c.caller_id JOIN functions target ON target.id=c.callee_id WHERE caller.name LIKE 'nested_caller.<fun:%.<fun:%' AND target.name LIKE 'nested_caller.<fun:%' AND target.name NOT LIKE 'nested_caller.<fun:%.<fun:%' AND c.kind='MAY_ENUMERATED' AND c.top_reason IS NULL AND c.top_anchor IS NULL")
        1 ;
      Batch.eq_int b
        ~msg:"RECURSIVE_OPEN_ASSERTION: continuation remains callback TOP"
        (count db
           "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='exact' AND c.callee_id IS NULL AND c.callee_name='aux' AND c.kind='MAY_TOP' AND c.top_reason='callback_param'")
        1 ;
      Batch.eq_int b
        ~msg:"RECURSIVE_OPEN_ASSERTION: parent-to-inner-root occurrence remains present"
        (count db
           "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions target ON target.id=c.callee_id WHERE f.name='exact' AND target.name LIKE 'exact.<fun:%' AND c.kind='MAY_ENUMERATED'")
        1 ;
      Batch.eq_int b
        ~msg:"RECURSIVE_OPEN_ASSERTION: non-head RHS escape does not create another root-self target"
        (bounded_self db "escape") 1 ;
      Batch.eq_int b
        ~msg:"RECURSIVE_OPEN_ASSERTION: direct recursive control retains its bounded self-head"
        (bounded_self db "direct") 1 ;
      Batch.eq_int b
        ~msg:"RECURSIVE_OPEN_ASSERTION: overapplied self-head reaches the original root from the returned function"
        (count db
           "SELECT count(*) FROM calls c JOIN functions caller ON caller.id=c.caller_id JOIN functions target ON target.id=c.callee_id WHERE caller.name LIKE 'overapplied.<fun:%.<fun:%' AND target.name LIKE 'overapplied.<fun:%' AND target.name NOT LIKE 'overapplied.<fun:%.<fun:%' AND c.kind='MAY_ENUMERATED' AND c.top_reason IS NULL AND c.top_anchor IS NULL")
        1 ;
      Batch.eq_int b
        ~msg:"RECURSIVE_OPEN_ASSERTION: overapplication retains exactly one returned-call callback TOP"
        (count db
           "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name LIKE 'overapplied.<fun:%.<fun:%' AND c.callee_id IS NULL AND c.callee_name='*TOP*' AND c.kind='MAY_TOP' AND c.top_reason='callback_param'")
        1 ;
      List.iter
        (fun owner ->
          Batch.eq_int b
            ~msg:("RECURSIVE_OPEN_ASSERTION: excluded " ^ owner ^ " has no bounded recursive self-head")
            (bounded_self db owner) 0 ;
          Batch.eq_int b
            ~msg:("RECURSIVE_OPEN_ASSERTION: excluded " ^ owner ^ " remains callback TOP")
            (callback_self db owner) 1)
        ["nested_open"; "annotated_pattern"]) ;
  Lwt.return_unit

let register_dropped_body () =
  Test.register ~__FILE__
    ~title:"recursive open bodies: rejected root becomes dropped-node TOP"
    ~tags:["cmt"; "calls"; "local_recursion"; "open_body"; "rejections"]
  @@ fun () ->
  with_fixture ~name:"recursive_open_body_dropped" ~files @@ fun fixture ->
  let schema_path = Temp.file "recursive-open-body-rejection.sql" in
  write_file schema_path
    (read_file (schema ())
     ^ "\nCREATE TRIGGER reject_recursive_open_root BEFORE INSERT ON functions WHEN NEW.name LIKE 'drop_body.<fun:%' AND NEW.name NOT LIKE 'drop_body.<fun:%.<fun:%' BEGIN SELECT RAISE(ABORT,'recursive open root refused'); END;\n") ;
  let db = temp_db "recursive_open_body_dropped" in
  let code, output =
    run_command (callgraph_ocaml ())
      ["--build-dir"; fixture.build_dir; "--db-path"; db; "--schema-path"; schema_path]
  in
  if code <> 1 || not (contains ~needle:"functions: 1 row(s) rejected" output) then
    Test.fail
      "RECURSIVE_OPEN_SETUP: body rejection did not run: exit %d %s"
      code output ;
  Batch.run (fun b ->
      Batch.eq_int b
        ~msg:"RECURSIVE_OPEN_ASSERTION: nested caller survives rejected open-recursive root"
        (count db "SELECT count(*) FROM functions WHERE name LIKE 'drop_body.<fun:%.<fun:%'")
        1 ;
      Batch.eq_int b
        ~msg:"RECURSIVE_OPEN_ASSERTION: surviving nested self-call records dropped_node TOP"
        (count db
           "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name LIKE 'drop_body.<fun:%.<fun:%' AND c.callee_id IS NULL AND c.kind='MAY_TOP' AND c.top_reason='dropped_node'")
        1) ;
  Lwt.return_unit

let register () =
  register_resolution () ;
  register_dropped_body ()
