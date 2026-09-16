(******************************************************************************)
(* Native regressions for singleton local recursive literal self-invocations. *)

open Arch_tezt

let files =
  [ Fixture.dune_project;
    ( "dune",
      "(library (name local_recursion_fixture) (wrapped false) (modules local_recursion) (flags (:standard -w -8-26-39)))\n" );
    ( "local_recursion.ml",
      {|let basic n =
  let rec aux x = if x = 0 then 0 else aux (x - 1) in
  aux n

let annotated n =
  let rec aux = (fun x -> if x = 0 then 0 else aux (x - 1) : int -> int) in
  aux n

let pattern_annotated n =
  let rec aux : int -> int = fun x -> if x = 0 then 0 else aux (x - 1) in
  aux n

let nested n =
  let rec aux x =
    let invoke y = if y = 0 then 0 else aux (y - 1) in
    invoke x
  in
  aux n

let optional n =
  let rec aux ?bonus x y =
    if x = 0 then y + Option.value ~default:0 bonus else aux (x - 1) y
  in
  aux n 1

let defaulted n =
  let rec aux ?(seed = if n = 0 then 0 else aux ~seed:0 0) x = seed + x in
  aux n

let refutable n =
  let rec aux (Some x) = if x = 0 then 0 else aux (Some (x - 1)) in
  aux (Some n)

let partial n =
  let rec aux x y =
    if x = 0 then y else
      let deferred = aux (x - 1) in
      deferred y
  in
  aux n 1

let overapplied n =
  let rec aux x =
    if x = 0 then (fun y -> y) else (fun y -> aux (x - 1) y)
  in
  aux n 1

let mutual n =
  let rec left x = if x = 0 then 0 else right (x - 1)
  and right x = if x = 0 then 0 else left (x - 1) in
  left n

let nonrecursive n =
  let local x = x + 1 in
  local n

let shadowed n =
  let rec aux x =
    let aux = fun y -> y + 1 in
    aux x
  in
  aux n

let wrapped n =
  let rec aux = if n < 0 then (fun x -> x) else (fun x -> x + 1) in
  aux n

let escaped n =
  let rec aux x = if x = 0 then 0 else aux (x - 1) in
  let saved = (aux, n) in
  ignore saved;
  aux n

let rhs_escape n =
  let rec aux x =
    let saved = aux in
    ignore saved;
    if x = 0 then 0 else aux (x - 1)
  in
  aux n

let stacked n =
  let rec outer x =
    let rec inner y = if y = 0 then 0 else outer (y - 1) in
    inner x
  in
  outer n

let drop_body n =
  let rec aux x =
    let nested_call y = if y = 0 then 0 else aux (y - 1) in
    nested_call x
  in
  aux n

let drop_parent n =
  let rec aux x = if x = 0 then 0 else aux (x - 1) in
  aux n
|} ) ]

(* Keep the flat oracle on the exact fixture shape whose predecessor count was
   measured before the richer RHS-scope cases were added above. *)
let flat_files =
  [ Fixture.dune_project;
    ( "dune",
      "(library (name local_recursion_flat_fixture) (wrapped false) (modules local_recursion) (flags (:standard -w -8-26-39)))\n" );
    ( "local_recursion.ml",
      {|let basic n = let rec aux x = if x = 0 then 0 else aux (x - 1) in aux n
let annotated n = let rec aux : int -> int = fun x -> if x = 0 then 0 else aux (x - 1) in aux n
let nested n = let rec aux x = let invoke y = if y = 0 then 0 else aux (y - 1) in invoke x in aux n
let optional n = let rec aux ?bonus x y = if x = 0 then y + Option.value ~default:0 bonus else aux (x - 1) y in aux n 1
let partial n = let rec aux x y = if x = 0 then y else let deferred = aux (x - 1) in deferred y in aux n 1
let overapplied n = let rec aux x = if x = 0 then (fun y -> y) else (fun y -> aux (x - 1) y) in aux n 1
let mutual n = let rec left x = if x = 0 then 0 else right (x - 1) and right x = if x = 0 then 0 else left (x - 1) in left n
let nonrecursive n = let local x = x + 1 in local n
let shadowed n = let rec aux x = let aux = fun y -> y + 1 in aux x in aux n
let wrapped n = let rec aux = if n < 0 then (fun x -> x) else (fun x -> x + 1) in aux n
let escaped n = let rec aux x = if x = 0 then 0 else aux (x - 1) in let saved = (aux, n) in ignore saved; aux n
let drop_body n = let rec aux x = let nested_call y = if y = 0 then 0 else aux (y - 1) in nested_call x in aux n
let drop_parent n = let rec aux x = if x = 0 then 0 else aux (x - 1) in aux n
|} ) ]

let count db sql = Db.with_db db (fun conn -> Db.int conn sql)

let register_resolution () =
  Test.register ~__FILE__
    ~title:"local recursion: exact singleton self-head targets and exclusions"
    ~tags:["cmt"; "calls"; "local_recursion"]
  @@ fun () ->
  with_fixture ~name:"local_recursion_targets" ~files @@ fun fixture ->
  let db = index fixture in
  Batch.run (fun b ->
      List.iter
        (fun owner ->
          Batch.eq_int b
            ~msg:("LOCAL_RECURSION_ASSERTION: " ^ owner ^ " has one stored recursive root")
            (count db
               (Printf.sprintf
                  "SELECT count(*) FROM functions WHERE name LIKE '%s.<fun:%%' AND name NOT LIKE '%s.<fun:%%.<fun:%%'"
                  owner owner))
            1 ;
          Batch.eq_int b
            ~msg:("LOCAL_RECURSION_ASSERTION: " ^ owner ^ " self-head stages reach their own stored root as MAY_ENUMERATED only")
            (count db
               (Printf.sprintf
                  "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name LIKE '%s.<fun:%%' AND f.name NOT LIKE '%s.<fun:%%.<fun:%%' AND c.callee_id=f.id AND c.kind='MAY_ENUMERATED' AND c.top_reason IS NULL AND c.top_anchor IS NULL"
                  owner owner))
            (if owner = "partial" then 2 else 1) ;
          Batch.eq_int b
            ~msg:("LOCAL_RECURSION_ASSERTION: " ^ owner ^ " self-head never becomes MUST")
            (count db
               (Printf.sprintf
                  "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name LIKE '%s.<fun:%%' AND c.callee_id=f.id AND c.kind='MUST'"
                  owner))
            0)
        ["basic"; "annotated"; "optional"; "defaulted"; "refutable"; "partial";
         "rhs_escape"] ;
      Batch.eq_int b
        ~msg:"LOCAL_RECURSION_ASSERTION: nested callable keeps its own caller while targeting the enclosing recursive root"
        (count db
           "SELECT count(*) FROM calls c JOIN functions caller ON caller.id=c.caller_id JOIN functions target ON target.id=c.callee_id WHERE caller.name LIKE 'nested.<fun:%.<fun:%' AND target.name LIKE 'nested.<fun:%' AND target.name NOT LIKE 'nested.<fun:%.<fun:%' AND c.kind='MAY_ENUMERATED' AND c.top_reason IS NULL")
        1 ;
      Batch.eq_int b
        ~msg:"LOCAL_RECURSION_ASSERTION: overapplied self-head keeps nested caller and reaches the recursive root as MAY_ENUMERATED"
        (count db
           "SELECT count(*) FROM calls c JOIN functions caller ON caller.id=c.caller_id JOIN functions target ON target.id=c.callee_id WHERE caller.name LIKE 'overapplied.<fun:%.<fun:%' AND target.name LIKE 'overapplied.<fun:%' AND target.name NOT LIKE 'overapplied.<fun:%.<fun:%' AND c.kind='MAY_ENUMERATED' AND c.top_reason IS NULL AND c.top_anchor IS NULL")
        1 ;
      Batch.eq_int b
        ~msg:"LOCAL_RECURSION_ASSERTION: overapplication retains exactly one returned-call TOP residual"
        (count db
           "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name LIKE 'overapplied.<fun:%.<fun:%' AND c.callee_id IS NULL AND c.callee_name='*TOP*' AND c.kind='MAY_TOP' AND c.top_reason='callback_param'")
        1 ;
      Batch.eq_int b
        ~msg:"LOCAL_RECURSION_ASSERTION: nested recursive scope can call its still-active outer recursive binder"
        (count db
           "SELECT count(*) FROM calls c JOIN functions caller ON caller.id=c.caller_id JOIN functions target ON target.id=c.callee_id WHERE caller.name LIKE 'stacked.<fun:%.<fun:%' AND target.name LIKE 'stacked.<fun:%' AND target.name NOT LIKE 'stacked.<fun:%.<fun:%' AND c.kind='MAY_ENUMERATED' AND c.top_reason IS NULL")
        1 ;
      List.iter
        (fun owner ->
          Batch.eq_int b
            ~msg:("LOCAL_RECURSION_ASSERTION: excluded " ^ owner ^ " creates no recursive-root self target")
            (count db
               (Printf.sprintf
                  "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name LIKE '%s.<fun:%%' AND c.callee_id=f.id AND c.kind='MAY_ENUMERATED'"
                  owner))
            0)
        ["mutual"; "nonrecursive"; "shadowed"; "wrapped"; "pattern_annotated"] ;
      Batch.eq_int b
        ~msg:"LOCAL_RECURSION_ASSERTION: binder annotation lowered to alias-pattern retains recursive callback TOP"
        (count db
           "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name LIKE 'pattern_annotated.<fun:%' AND c.callee_name='aux' AND c.callee_id IS NULL AND c.top_reason='callback_param'")
        1 ;
      Batch.eq_int b
        ~msg:"LOCAL_RECURSION_ASSERTION: supported mutual RHS invocations no longer remain callback TOP"
        (count db
           "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name LIKE 'mutual.<fun:%' AND c.callee_id IS NULL AND c.kind='MAY_TOP' AND c.top_reason='callback_param'")
        0 ;
      Batch.eq_int b
        ~msg:"LOCAL_RECURSION_ASSERTION: mutual traversal resolves both bounded cross-literal edges"
        (count db
           "SELECT count(*) FROM calls c JOIN functions caller ON caller.id=c.caller_id JOIN functions target ON target.id=c.callee_id WHERE caller.name LIKE 'mutual.<fun:%' AND target.name LIKE 'mutual.<fun:%' AND caller.id<>target.id AND c.kind='MAY_ENUMERATED'")
        2 ;
      Batch.eq_int b
        ~msg:"LOCAL_RECURSION_ASSERTION: nonrecursive continuation call keeps its existing resolved literal target"
        (count db
           "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name='nonrecursive' AND t.name LIKE 'nonrecursive.<fun:%' AND c.kind='MUST'")
        1 ;
      Batch.eq_int b
        ~msg:"LOCAL_RECURSION_ASSERTION: shadowed invocation targets only the inner literal, never the recursive root"
        (count db
           "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name LIKE 'shadowed.<fun:%' AND f.name NOT LIKE 'shadowed.<fun:%.<fun:%' AND t.name LIKE 'shadowed.<fun:%.<fun:%' AND c.kind='MUST'")
        1 ;
      Batch.eq_int b
        ~msg:"LOCAL_RECURSION_ASSERTION: computed recursive RHS invocation remains callback TOP"
        (count db
           "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='wrapped' AND c.callee_name='aux' AND c.callee_id IS NULL AND c.kind='MAY_TOP' AND c.top_reason='callback_param'")
        1 ;
      Batch.eq_int b
        ~msg:"LOCAL_RECURSION_ASSERTION: a non-head escape remains its existing enumerated occurrence"
        (count db
           "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name='escaped' AND t.name LIKE 'escaped.<fun:%' AND c.kind='MAY_ENUMERATED'")
        1 ;
      Batch.eq_int b
        ~msg:"LOCAL_RECURSION_ASSERTION: recursive binder non-head use inside its RHS does not add a second root-self edge"
        (count db
           "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name LIKE 'rhs_escape.<fun:%' AND f.name NOT LIKE 'rhs_escape.<fun:%.<fun:%' AND c.callee_id=f.id AND c.kind='MAY_ENUMERATED'")
        1) ;
  Lwt.return_unit

let register_dropped_body () =
  Test.register ~__FILE__
    ~title:"local recursion: rejected root remains dropped-node TOP from a surviving nested caller"
    ~tags:["cmt"; "calls"; "local_recursion"; "rejections"]
  @@ fun () ->
  with_fixture ~name:"local_recursion_dropped_body" ~files @@ fun fixture ->
  let schema_path = Temp.file "local-recursion-body-rejection.sql" in
  write_file schema_path
    (read_file (schema ())
     ^ "\nCREATE TRIGGER reject_local_recursive_root BEFORE INSERT ON functions WHEN NEW.name LIKE 'drop_body.<fun:%' AND NEW.name NOT LIKE 'drop_body.<fun:%.<fun:%' BEGIN SELECT RAISE(ABORT,'local recursive root refused'); END;\n") ;
  let db = temp_db "local_recursion_dropped_body" in
  let code, output =
    run_command (callgraph_ocaml ())
      ["--build-dir"; fixture.build_dir; "--db-path"; db; "--schema-path"; schema_path]
  in
  if code <> 1 || not (contains ~needle:"functions: 1 row(s) rejected" output) then
    Test.fail "LOCAL_RECURSION_SETUP: body rejection did not run: exit %d %s" code output ;
  Batch.run (fun b ->
      Batch.eq_int b
        ~msg:"LOCAL_RECURSION_ASSERTION: nested caller survives rejected recursive root"
        (count db "SELECT count(*) FROM functions WHERE name LIKE 'drop_body.<fun:%.<fun:%'")
        1 ;
      Batch.eq_int b
        ~msg:"LOCAL_RECURSION_ASSERTION: surviving nested self-call records dropped_node TOP, not a dangling bounded leaf"
        (count db
           "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name LIKE 'drop_body.<fun:%.<fun:%' AND c.callee_id IS NULL AND c.kind='MAY_TOP' AND c.top_reason='dropped_node'")
        1) ;
  Lwt.return_unit

let register_dropped_parent () =
  Test.register ~__FILE__
    ~title:"local recursion: rejected structural parent performs no local-body collection"
    ~tags:["cmt"; "calls"; "local_recursion"; "rejections"]
  @@ fun () ->
  with_fixture ~name:"local_recursion_dropped_parent" ~files @@ fun fixture ->
  let schema_path = Temp.file "local-recursion-parent-rejection.sql" in
  write_file schema_path
    (read_file (schema ())
     ^ "\nCREATE TRIGGER reject_local_recursive_parent BEFORE INSERT ON functions WHEN NEW.name='drop_parent' BEGIN SELECT RAISE(ABORT,'local recursive parent refused'); END;\n") ;
  let db = temp_db "local_recursion_dropped_parent" in
  let code, output =
    run_command (callgraph_ocaml ())
      ["--build-dir"; fixture.build_dir; "--db-path"; db; "--schema-path"; schema_path]
  in
  if code <> 1 || not (contains ~needle:"functions: 1 row(s) rejected" output) then
    Test.fail "LOCAL_RECURSION_SETUP: parent rejection did not run: exit %d %s" code output ;
  Batch.run (fun b ->
      Batch.eq_int b
        ~msg:"LOCAL_RECURSION_ASSERTION: rejected structural parent leaves no synthetic local body or attributed calls"
        (count db
           "SELECT (SELECT count(*) FROM functions WHERE name LIKE 'drop_parent.<fun:%') + (SELECT count(*) FROM calls WHERE callee_name LIKE 'drop_parent.<fun:%')")
        0) ;
  Lwt.return_unit

let register_flat_compatibility () =
  Test.register ~__FILE__
    ~title:"local recursion: public flat collection retains legacy binder spelling"
    ~tags:["cmt"; "flat"; "local_recursion"]
  @@ fun () ->
  with_fixture ~name:"local_recursion_flat" ~files:flat_files @@ fun fixture ->
  let db = index_project ~name:"local_recursion_flat" fixture.root in
  Batch.run (fun b ->
      Batch.eq_int b
        ~msg:"LOCAL_RECURSION_ASSERTION: flat synthetic-lambda callee count retains its measured predecessor value"
        (count db "SELECT count(*) FROM calls WHERE callee_name LIKE '%<fun:%'")
        21 ;
      Batch.ge_int b
        ~msg:"LOCAL_RECURSION_ASSERTION: flat self-call rows remain present under source binder names"
        (count db "SELECT count(*) FROM calls WHERE callee_name IN ('aux','left','right')")
        1) ;
  Lwt.return_unit

let register () =
  register_resolution () ;
  register_dropped_body () ;
  register_dropped_parent () ;
  register_flat_compatibility ()
