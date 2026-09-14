(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** The smallest real CMT witness for identity-backed local structured-module
    resolution.  The functor parameter alias is a refusal decoy: it must never
    justify treating a same-spelled local module as an owner. *)

open Arch_tezt

let fixture_files =
  [
    Fixture.dune_project;
    ( "dune",
      "(library\n\
      \ (name local_module_targets_fixture)\n\
      \ (wrapped false)\n\
      \ (modules local_module_targets)\n\
      \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
    ( "local_module_targets.ml",
      {|module Local = struct
  let f x = x
end

let run x = Local.f x

module type HAS_F = sig
  val f : int -> int
end

module Decoy (P : HAS_F) = struct
  module Alias = P
  let run_param x = Alias.f x
end
module Deep = struct
  module Inner = struct let f x = x end
end
let nested x = Deep.Inner.f x
module Shadow = struct
  module Local = struct let f x = x + 1 end
  let call x = Local.f x
end
module Values = struct
  let f x = x + 1
  let old x = f x
  let f x = x + 2
end
let value_shadow x = Values.f x
module Pattern = struct
  let f x = x
  let (f, _) = ((fun x -> x + 2), 0)
end
let pattern_call x = Pattern.f x
module Value_alias = struct
  let base x = x
  let f = base
end
let value_alias_call x = Value_alias.f x
module Imported = struct let f x = x + 1 end
module Opaque = struct
  let f x = x
  include Imported
end
let opaque_call x = Opaque.f x
module Replacement = struct
  let f x = x
  include Imported
  let f x = x + 3
end
let replaced x = Replacement.f x
module Included = struct
  include struct
    let f x = x
    module Nested = struct let g x = x end
  end
  let use_nested x = Nested.g x
end
let included x = Included.f x
let included_nested x = Included.Nested.g x
module Constrained : HAS_F = struct let f x = x end
let constrained x = Constrained.f x
module rec Recursive : HAS_F = struct let f x = x end
let recursive_call x = Recursive.f x
module Make (P : HAS_F) = struct
  module Body = struct let f x = P.f x end
  let call x = Body.f x
  let param_call x = P.f x
end
module Applied = Make(Local)
let applied_call x = Applied.Body.f x
module Alias = Local
let alias_call x = Alias.f x
let unpack_call (m : (module HAS_F)) x =
  let module Unpacked = (val m : HAS_F) in Unpacked.f x
let callback xs = List.map Local.f xs
let point_free = Local.f
module Ops = struct
  let ( let* ) o f = match o with None -> None | Some x -> f x
end
let letop x = let open Ops in let* v = x in Some (v + 1)
module Arity = struct
  let add a b = a + b
  let make a = if a > 0 then (fun b -> a + b) else (fun b -> b)
end
let partial a = Arity.add a
let over a b = Arity.make a b
let conditional b x = if b then Local.f x else x
let dead x = raise Exit; Local.f x
|} );
  ]

let register_basic () =
  Test.register ~__FILE__
    ~title:"local structured module: run resolves to its same-file Local.f body"
    ~tags:["cmt"; "calls"; "local_module"; "resolution"]
  @@ fun () ->
  with_fixture ~name:"local_module_targets" ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "local_module_targets" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then
    Test.fail "LOCAL_MODULE_SETUP: index failed (exit %d):\n%s" code output ;
  Batch.run (fun b ->
      let count sql = Db.with_db db (fun c -> Db.int c sql) in
      Batch.eq_int b
        ~msg:"LOCAL_MODULE_ASSERTION: nonvacuous caller [run] exists"
        (count "SELECT count(*) FROM functions WHERE name='run'") 1 ;
      Batch.eq_int b
        ~msg:"LOCAL_MODULE_ASSERTION: nonvacuous local target [Local.f] exists"
        (count "SELECT count(*) FROM functions WHERE name='Local.f'") 1 ;
      Batch.eq_int b
        ~msg:"LOCAL_MODULE_ASSERTION: exact same-file run -> Local.f callee_id is MAY_ENUMERATED with no TOP or edge_form"
        (count
           "SELECT count(*) FROM calls c \
            JOIN functions caller ON caller.id=c.caller_id \
            JOIN modules caller_module ON caller_module.id=caller.module_id \
            JOIN functions callee ON callee.id=c.callee_id \
            JOIN modules callee_module ON callee_module.id=callee.module_id \
            WHERE caller.name='run' AND callee.name='Local.f' \
              AND caller_module.id=callee_module.id \
              AND c.callee_name='Local.f' AND c.kind='MAY_ENUMERATED' \
              AND c.top_reason IS NULL AND c.top_anchor IS NULL \
              AND c.edge_form IS NULL")
        1 ;
      Batch.eq_int b
        ~msg:"LOCAL_MODULE_ASSERTION: run retains no TOP fallback"
        (count
           "SELECT count(*) FROM calls c JOIN functions caller ON caller.id=c.caller_id \
            WHERE caller.name='run' AND c.kind='MAY_TOP'")
        0 ;
      Batch.eq_int b
        ~msg:"LOCAL_MODULE_ASSERTION: run's resolved local edge has no edge_form"
        (count
           "SELECT count(*) FROM calls c JOIN functions caller ON caller.id=c.caller_id \
            WHERE caller.name='run' AND c.edge_form IS NOT NULL")
        0) ;
  Lwt.return_unit

let register_boundaries () =
  Test.register ~__FILE__
    ~title:"local structured modules: ownership, masks, arity and emission forms"
    ~tags:["cmt"; "calls"; "local_module"; "resolution"]
  @@ fun () ->
  with_fixture ~name:"local_module_boundaries" ~files:fixture_files @@ fun fixture ->
  let db = temp_db "local_module_boundaries" in
  let code, output = index_raw_into ~db fixture in
  if code <> 0 then Test.fail "LOCAL_MODULE_SETUP: index exit %d: %s" code output ;
  let count sql = Db.with_db db (fun c -> Db.int c sql) in
  Batch.run (fun b ->
      List.iter (fun (caller, target) ->
          Batch.eq_int b ~msg:("LOCAL_MODULE_ASSERTION: exact owned body " ^ caller ^ " -> " ^ target)
            (count (Printf.sprintf
              "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name='%s' AND t.name='%s' AND f.module_id=t.module_id AND c.kind='MAY_ENUMERATED' AND c.top_reason IS NULL AND c.top_anchor IS NULL AND c.edge_form IS NULL"
              caller target)) 1)
        [ "nested", "Deep.Inner.f"; "Shadow.call", "Shadow.Local.f";
          "value_shadow", "Values.f"; "replaced", "Replacement.f";
          "included", "Included.f"; "included_nested", "Included.Nested.g";
          "Included.use_nested", "Included.Nested.g";
          "constrained", "Constrained.f"; "recursive_call", "Recursive.f";
          "Make.call", "Make.Body.f"; "callback", "Local.f";
          "letop", "Ops.let*"; "partial", "Arity.add";
          "over", "Arity.make"; "conditional", "Local.f"; "dead", "Local.f" ] ;
      List.iter (fun caller ->
          Batch.eq_int b ~msg:("LOCAL_MODULE_ASSERTION: unsupported owner retains module_param " ^ caller)
            (count (Printf.sprintf
              "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='%s' AND c.kind='MAY_TOP' AND c.callee_id IS NULL AND c.top_reason='module_param' AND c.top_anchor IS NOT NULL" caller)) 1)
        [ "Decoy.run_param"; "pattern_call"; "value_alias_call"; "opaque_call";
          "Make.param_call"; "Make.Body.f"; "applied_call"; "alias_call"; "unpack_call" ] ;
      Batch.eq_int b ~msg:"LOCAL_MODULE_ASSERTION: earlier direct value binding retains its ordinal identity"
        (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name='Values.old' AND t.name='Values.f#1' AND f.module_id=t.module_id") 1 ;
      Batch.eq_int b ~msg:"LOCAL_MODULE_ASSERTION: point-free target is a value_alias, not a call gain"
        (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name='point_free' AND t.name='Local.f' AND c.kind='MAY_ENUMERATED' AND c.edge_form='value_alias' AND c.top_reason IS NULL") 1 ;
      Batch.eq_int b ~msg:"LOCAL_MODULE_ASSERTION: overapplication retains computed-return TOP"
        (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='over' AND c.kind='MAY_TOP' AND c.callee_name='*TOP*' AND c.top_reason='callback_param'") 1 ;
      Batch.eq_int b ~msg:"LOCAL_MODULE_ASSERTION: dead local call retains its dead-site fact"
        (count "SELECT count(*) FROM dead_code_sites d JOIN functions f ON f.id=d.function_id WHERE f.name='dead' AND d.callee_name='Local.f'") 1) ;
  Lwt.return_unit

let register_dropped () =
  Test.register ~__FILE__
    ~title:"local structured module: rejected owned body remains dropped_node TOP"
    ~tags:["cmt"; "calls"; "local_module"; "rejections"]
  @@ fun () ->
  with_fixture ~name:"local_module_dropped" ~files:fixture_files @@ fun fixture ->
  let schema_path = Temp.file "local-module-rejection.sql" in
  write_file schema_path (read_file (schema ()) ^
    "\nCREATE TRIGGER reject_local_body BEFORE INSERT ON functions WHEN NEW.name='Local.f' BEGIN SELECT RAISE(ABORT,'local body refused'); END;\n") ;
  let db = temp_db "local_module_dropped" in
  let code, output = run_command (callgraph_ocaml ())
      ["--build-dir"; fixture.build_dir; "--db-path"; db; "--schema-path"; schema_path] in
  if code <> 1 || not (contains ~needle:"functions: 1 row(s) rejected" output) then
    Test.fail "LOCAL_MODULE_SETUP: rejection injection did not run: exit %d %s" code output ;
  Batch.run (fun b ->
      let count sql = Db.with_db db (fun c -> Db.int c sql) in
      Batch.eq_int b ~msg:"LOCAL_MODULE_ASSERTION: rejected owned target is not an enumerated external leaf"
        (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='run' AND c.callee_id IS NULL AND c.kind='MAY_TOP' AND c.top_reason='dropped_node'") 1 ;
      Batch.eq_int b ~msg:"LOCAL_MODULE_ASSERTION: rejection control still resolves an unrelated body"
        (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name='nested' AND t.name='Deep.Inner.f' AND c.kind='MAY_ENUMERATED'") 1) ;
  Lwt.return_unit

let register_cross_cmt_and_flat () =
  Test.register ~__FILE__
    ~title:"local structured modules: CMT identities and flat attribution stay file-local"
    ~tags:["cmt"; "flat"; "local_module"; "resolution"]
  @@ fun () ->
  let files = [ Fixture.dune_project;
    ("dune", "(library (name local_cross_fixture) (wrapped false) (modules foreign_a foreign_b))\n");
    ("foreign_a.ml", "module Local = struct let f x = x + 1 end\nlet run_a x = Local.f x\n");
    ("foreign_b.ml", "module Local = struct let f x = x + 2 end\nlet run_b x = Local.f x\n") ] in
  with_fixture ~name:"local_module_cross" ~files @@ fun fixture ->
  let rich = temp_db "local_module_cross" in
  let code, output = index_raw_into ~db:rich fixture in
  if code <> 0 then Test.fail "LOCAL_MODULE_SETUP: cross-CMT index exit %d: %s" code output ;
  Batch.run (fun b ->
      let count sql = Db.with_db rich (fun c -> Db.int c sql) in
      Batch.eq_int b ~msg:"LOCAL_MODULE_ASSERTION: both homonymous CMT targets retain their own bodies"
        (count "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name IN ('run_a','run_b') AND t.name='Local.f' AND t.module_id=f.module_id AND c.kind='MAY_ENUMERATED'") 2) ;
  let flat = index_project ~name:"local_module_cross_flat" fixture.root in
  Batch.run (fun b ->
      let count sql = Db.with_db flat (fun c -> Db.int c sql) in
      Batch.eq_int b ~msg:"LOCAL_MODULE_ASSERTION: flat CMT path received the same target context"
        (count "SELECT count(*) FROM calls WHERE caller_name IN ('run_a','run_b') AND callee_name='Local.f'") 2 ;
      Batch.eq_int b ~msg:"LOCAL_MODULE_ASSERTION: flat target attribution requires an actual same-file symbol"
        (count "SELECT count(*) FROM calls c WHERE caller_name IN ('run_a','run_b') AND callee_name='Local.f' AND callee_file IS NOT (CASE WHEN EXISTS (SELECT 1 FROM functions f WHERE f.file_path=c.caller_file AND f.name=c.callee_name) THEN c.caller_file ELSE NULL END)") 0 ;
      Batch.eq_int b ~msg:"LOCAL_MODULE_ASSERTION: flat path does not invent nested caller coverage"
        (count "SELECT count(*) FROM calls WHERE caller_name='Local.f'") 0) ;
  Lwt.return_unit

let register () =
  register_basic () ;
  register_boundaries () ;
  register_dropped () ;
  register_cross_cmt_and_flat () ;
  List.iter (fun (name, script) ->
      Test.register ~__FILE__ ~title:("local structured modules: " ^ name)
        ~tags:["cmt"; "local_module"; "independent_checker"]
      @@ fun () ->
      let checker = Filename.concat (repo_root ())
          ("roster/tezos-call-resolution/" ^ script) in
      let code, stdout, stderr = run_command_split "node" [checker] in
      if code = 1 then
        Test.fail "LOCAL_MODULE_ASSERTION: %s\n%s\n%s" name stdout stderr
      else if code <> 0 then
        Test.fail "LOCAL_MODULE_SETUP: %s exit %d\n%s\n%s" name code stdout stderr ;
      Lwt.return_unit)
    ["labeled arity ratchet", "check-labeled-arity.js";
     "verifier refusal coverage", "check-verifier-inputs.js";
     "self-index golden ratchet", "check-self-index-smoke.js"]
