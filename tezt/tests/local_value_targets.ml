(******************************************************************************)
(* Local one-hop value aliases: invocation consumers may resolve the body,    *)
(* while point-free emission keeps its existing refusal/edge semantics.      *)
(******************************************************************************)

open Arch_tezt

let files =
  [ Fixture.dune_project;
    ("dune", "(library (name local_value_targets_fixture) (wrapped false) (modules local_value_targets) (flags (:standard -w -21)))\n");
    ("local_value_targets.ml", {|
module Owned = struct
  let base ?(a=0) ~b x = a + b + x
  let alias = base
  let alias2 = alias
end
let applied () = Owned.alias ~b:2 1
let partial () = Owned.alias ~b:2
module Over = struct
  let body a b = if a > 0 then (fun c -> a + b + c) else (fun c -> c)
  let alias = body
end
let over () = Over.alias 1 2 3
module Callback = struct let base x = x let alias = base end
let callback xs = List.map Callback.alias xs
module Inline = struct
  include struct let body x = x let alias = body end
end
let inline_include x = Inline.alias x
module Shadow = struct
  let base x = x
  let alias = base
  let base x = x + 1
  let run x = alias x
end
let shadowed x = Shadow.alias x
module Refuse = struct
  let base x = x
  let alias = base
  let chain = alias
  let computed = if true then base else base
  let persistent = Stdlib.Fun.id
  let qualified = Callback.alias
  let partial_rhs = Over.body 1
end
let chain x = Refuse.chain x
let computed x = Refuse.computed x
let persistent x = Refuse.persistent x
let qualified x = Refuse.qualified x
let partial_rhs x y = Refuse.partial_rhs x y
let local_base x = x
let local_alias = local_base
let unqualified x = local_alias x
let point_free = Owned.alias
let next_alias = point_free
let third_alias = next_alias
let conditional b x = if b then Owned.alias ~b:1 x else x
let dead x = raise Exit; Owned.alias ~b:1 x
module Ops = struct
  let bind o f = match o with None -> None | Some x -> f x
  let ( let* ) = bind
end
let letop x = let open Ops in let* v = x in Some (v + 1)
module Mask = struct
  let body x = x
  let alias = body
  let before x = alias x
  let alias = (fun x -> x + 1)
end
let masked x = Mask.alias x
module Rejected = struct
  let body x = x
  let alias = body
end
let rejected x = Rejected.alias x
|}) ]

let resolved count caller target =
  count (Printf.sprintf
    "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id \
     WHERE f.name='%s' AND t.name='%s' AND f.module_id=t.module_id \
       AND c.kind='MAY_ENUMERATED' AND c.edge_form IS NULL \
       AND c.top_reason IS NULL AND c.top_anchor IS NULL" caller target)

let register_rich () =
  Test.register ~__FILE__
    ~title:"local value aliases: qualified invocation reaches the one-hop body"
    ~tags:["cmt"; "calls"; "local_value_alias"; "resolution"]
  @@ fun () ->
  with_fixture ~name:"local_value_targets" ~files @@ fun fixture ->
  let db = temp_db "local_value_targets" in
  let code, output = index_raw_into ~db fixture in
  if code <> 0 then Test.fail "LOCAL_VALUE_SETUP: index exit %d: %s" code output ;
  let count sql = Db.with_db db (fun c -> Db.int c sql) in
  Batch.run (fun b ->
    List.iter (fun (caller, target) ->
      Batch.eq_int b ~msg:("LOCAL_VALUE_ASSERTION: " ^ caller ^ " resolves body " ^ target)
        (resolved count caller target) 1)
      ["applied", "Owned.base"; "callback", "Callback.base";
       "inline_include", "Inline.body"; "letop", "Ops.bind"] ;
    Batch.eq_int b ~msg:"LOCAL_VALUE_ASSERTION: partial preserves body target and no invented residual"
      (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='partial' AND c.callee_name='Owned.base' AND c.kind='MAY_ENUMERATED'") 1 ;
    Batch.eq_int b ~msg:"LOCAL_VALUE_ASSERTION: partial has no return residual"
      (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='partial' AND c.callee_name='*TOP*'") 0 ;
    Batch.eq_int b ~msg:"LOCAL_VALUE_ASSERTION: exact overapplication has one existing TOP residual"
      (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='over' AND c.callee_name='*TOP*' AND c.kind='MAY_TOP' AND c.top_reason='callback_param' AND c.edge_form IS NULL") 1 ;
    Batch.eq_int b ~msg:"LOCAL_VALUE_ASSERTION: point-free alias remains unchanged"
      (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='point_free' AND c.callee_name='Owned.alias' AND c.callee_id IS NULL AND c.kind='MAY_TOP' AND c.top_reason='module_param' AND c.edge_form='value_alias'") 1 ;
    List.iter (fun (caller, target) ->
      Batch.eq_int b ~msg:("LOCAL_VALUE_ASSERTION: immediate predecessor remains " ^ caller ^ " -> " ^ target)
        (count (Printf.sprintf "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name='%s' AND t.name='%s' AND f.module_id=t.module_id AND c.kind='MAY_ENUMERATED' AND c.edge_form='value_alias' AND c.top_reason IS NULL" caller target)) 1)
      ["next_alias", "point_free"; "third_alias", "next_alias"; "Owned.alias", "Owned.base"] ;
    List.iter (fun caller ->
      Batch.eq_int b ~msg:("LOCAL_VALUE_ASSERTION: conditional/dead invocation keeps body target " ^ caller)
        (resolved count caller "Owned.base") 1)
      ["conditional"; "dead"] ;
    Batch.eq_int b ~msg:"LOCAL_VALUE_ASSERTION: dead alias call retains its dead-site fact"
      (count "SELECT count(*) FROM dead_code_sites d JOIN functions f ON f.id=d.function_id WHERE f.name='dead' AND d.callee_name='Owned.base'") 1 ;
    Batch.eq_int b ~msg:"LOCAL_VALUE_ASSERTION: qualified alias keeps its original ordinal body"
      (resolved count "shadowed" "Shadow.base#1") 1 ;
    List.iter (fun caller ->
      Batch.eq_int b ~msg:("LOCAL_VALUE_ASSERTION: refused form remains TOP " ^ caller)
        (count (Printf.sprintf "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='%s' AND c.kind='MAY_TOP' AND c.callee_id IS NULL" caller)) 1)
      ["chain"; "computed"; "persistent"; "qualified"; "partial_rhs"; "Shadow.run"] ;
    (* Stage2 CFA refines the root-level plain-variable alias only.  The
       nested-module and computed forms above retain their existing refusals. *)
    Batch.eq_int b ~msg:"LOCAL_VALUE_ASSERTION: root alias invocation reaches its actual CFA target"
      (resolved count "unqualified" "local_base") 1 ;
    Batch.eq_int b ~msg:"LOCAL_VALUE_ASSERTION: root CFA refinement adds neither MUST nor an old TOP"
      (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='unqualified' AND c.edge_form IS NULL AND c.kind IN ('MUST','MAY_TOP')") 0 ;
    Batch.eq_int b ~msg:"LOCAL_VALUE_ASSERTION: root alias keeps its immediate predecessor independently"
      (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name='local_alias' AND t.name='local_base' AND f.module_id=t.module_id AND c.kind='MAY_ENUMERATED' AND c.edge_form='value_alias'") 1 ;
    Batch.eq_int b ~msg:"LOCAL_VALUE_ASSERTION: later mask resolves only its direct replacement body"
      (resolved count "masked" "Mask.alias") 1) ;
  Lwt.return_unit

let register_rejection_and_flat () =
  Test.register ~__FILE__
    ~title:"local value aliases: rejection and flat attribution use the actual body"
    ~tags:["cmt"; "flat"; "local_value_alias"; "rejections"]
  @@ fun () ->
  with_fixture ~name:"local_value_targets_rejection" ~files @@ fun fixture ->
  let schema_path = Temp.file "local-value-rejection.sql" in
  write_file schema_path (read_file (schema ()) ^
    "\nCREATE TRIGGER reject_alias_body BEFORE INSERT ON functions WHEN NEW.name='Rejected.body' BEGIN SELECT RAISE(ABORT,'body refused'); END;\n") ;
  let rich = temp_db "local_value_targets_rejection" in
  let code, output = run_command (callgraph_ocaml ())
    ["--build-dir"; fixture.build_dir; "--db-path"; rich; "--schema-path"; schema_path] in
  if code <> 1 || not (contains ~needle:"functions: 1 row(s) rejected" output) then
    Test.fail "LOCAL_VALUE_SETUP: rejection injection did not run: exit %d: %s" code output ;
  let count db sql = Db.with_db db (fun c -> Db.int c sql) in
  Batch.run (fun b ->
    Batch.eq_int b ~msg:"LOCAL_VALUE_ASSERTION: rejected alias body is dropped_node"
      (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='rejected' AND c.kind='MAY_TOP' AND c.callee_id IS NULL AND c.top_reason='dropped_node'") 1 ;
    Batch.eq_int b ~msg:"LOCAL_VALUE_ASSERTION: unrelated body still resolves during rejection"
      (resolved (count rich) "applied" "Owned.base") 1) ;
  let flat = index_project ~name:"local_value_targets_flat" fixture.root in
  Batch.run (fun b ->
    Batch.eq_int b ~msg:"LOCAL_VALUE_ASSERTION: flat CMT path emits the actual alias body"
      (count flat "SELECT count(*) FROM calls WHERE caller_name='applied' AND callee_name='Owned.base'") 1 ;
    Batch.eq_int b ~msg:"LOCAL_VALUE_ASSERTION: flat body is same-file only when the flat symbol exists"
      (count flat "SELECT count(*) FROM calls c WHERE caller_name='applied' AND callee_name='Owned.base' AND callee_file IS NOT (CASE WHEN EXISTS (SELECT 1 FROM functions f WHERE f.file_path=c.caller_file AND f.name=c.callee_name) THEN c.caller_file ELSE NULL END)") 0) ;
  Lwt.return_unit

let register () =
  register_rich () ;
  register_rejection_and_flat () ;
  List.iter (fun (title, script, args) ->
  Test.register ~__FILE__ ~title
    ~tags:["cmt"; "local_value_alias"; "independent_checker"]
  @@ fun () ->
  let checker = Filename.concat (repo_root ())
      ("roster/tezos-residual-targets/" ^ script) in
  let code, stdout, stderr = run_command_split "node" (checker :: args) in
  if code = 1 then Test.fail "LOCAL_VALUE_ASSERTION: pending metadata\n%s\n%s" stdout stderr
  else if code <> 0 then Test.fail "LOCAL_VALUE_SETUP: pending metadata exit %d\n%s\n%s" code stdout stderr ;
  Lwt.return_unit)
    ["local value aliases: native pending metadata", "check-native.js", ["--probe-only"];
     "local value aliases: forced CMT flat attribution", "check-flat.js", [];
     "local value aliases: comparison and witness refusals", "check-comparison.js", []]
