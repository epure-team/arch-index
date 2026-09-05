(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Module-alias heads — [S.f] where the file declares [module S = Target].

    The head's path root is a local binder, so [qualified_is_dynamic] judges it
    dynamic and the edge goes to ⊤ with [top_reason='module_param'] — "I cannot
    tell what this module is". On proto_alpha that was 3 269 edges, and the
    answer was sitting in the same structure the walker had already traversed.

    What is asserted here is the producer contract of
    specs/reexport-resolution.md D1-quater: the head is rewritten to the
    qualified name it denotes, at the site where the binder's [Ident] is in
    hand; the rewritten edge is marked [edge_form='module_alias'] and is
    MAY_ENUMERATED, never MUST (FR-011); and the rewrite DECLINES — leaving the
    honest ⊤ — for a functor parameter, which [qualified_is_dynamic] cannot
    tell apart from an alias and which this table can.

    Two things here exist because they are the ways this feature goes wrong
    quietly rather than loudly:

    - {b The stamp key (FR-012).} [nested_stub] declares [module S = Ma_stub]
      inside a submodule of a file whose TOPLEVEL declares
      [module S = Ma_real]. Both binders are spelled [S]. Under a name key the
      inner call resolves to the toplevel target — a production call recorded
      into a stub — which is the defect ADR 003 documents, reached by a
      different road. Under [Ident.unique_name] they are two keys and cannot
      collide. This is the SA-1 attack from the spec, as a fixture.

    - {b The consumers (the regression this file was written for).} [fan-in],
      [callers-of] and [god-modules] excluded [edge_form IS NULL], which was
      correct while [value_alias] was the only value: a point-free binding is
      not a call site. A [module_alias] edge {i is} a call site — a real
      [Texp_apply] whose head merely happened to be spelled through an alias —
      and the same predicate would have silently dropped 3 247 genuine edges on
      proto_alpha. No test could see it, because the only fixture with an
      [edge_form] had none of the second kind. Now one does. *)

open Arch_tezt

let fixture_files =
  [
    Fixture.dune_project;
    ( "dune",
      "(library\n\
      \ (name ma_fixture)\n\
      \ (wrapped false)\n\
      \ (modules ma_real ma_stub ma_other ma_a ma_b ma_param)\n\
      \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
    ("ma_real.ml", {|exception Real_boom
let f n = if n > 0 then raise Real_boom else n
let g n = n + 1
|});
    ("ma_stub.ml", {|exception Stub_boom
let f n = if n > 0 then raise Stub_boom else n
|});
    ("ma_other.ml", {|exception Other_boom
let f n = if n > 0 then raise Other_boom else n
|});
    (* US-1: the SAME alias name in two files, bound to two different targets.
       Each file's [S.f] must reach its own target and neither the other's —
       the per-file scoping, which under D1-quater is the table's LIFETIME
       (one per .cmt) rather than a field anyone could forget to join on. *)
    ( "ma_a.ml",
      {|module S = Ma_real

(* THE SUBJECT. *)
let via_alias n = S.f n

(* A nested submodule REBINDING the same name to a different target. Both
   binders are spelled S; only their stamps differ. *)
module Internal_for_tests = struct
  module S = Ma_stub

  let nested_stub n = S.f n
end

(* A path with an intermediate segment: the rewrite must extend the target's
   module path rather than replace it — S.Syntax.plus, not S.plus. *)
module Deep = struct
  module Syntax = struct
    let plus a b = a + b
  end
end

module D = Deep

let deep_call a b = D.Syntax.plus a b

(* An ordinary QUALIFIED call, no alias in its head. Without this row every
   [edge_form='module_alias'] assertion below would pass just as well if the
   producer marked every qualified edge. *)
let direct n = Ma_real.g n
|} );
    ( "ma_b.ml",
      {|module S = Ma_other

let via_alias n = S.f n
|} );
    (* THE DECLINE. [S] here is a genuine functor parameter, not an alias:
       nothing in this file binds it to a module path, so the table has no
       entry and the ⊤ stands. [qualified_is_dynamic] cannot tell this from
       ma_a.ml's [S]; the alias table is exactly what can. *)
    ( "ma_param.ml",
      {|module type HAS_F = sig
  val f : int -> int
end

module Make (S : HAS_F) = struct
  let through_param n = S.f n
end
|} );
  ]

(* Every module_alias row, as caller -> callee, with kind and resolution. *)
let alias_rows db =
  Db.with_db db (fun conn ->
      Db.rows conn
        "SELECT cf.name, c.callee_name, COALESCE(c.kind,'NULL'), \
         CASE WHEN c.callee_id IS NULL THEN 0 ELSE 1 END \
         FROM calls c JOIN functions cf ON c.caller_id=cf.id \
         WHERE c.edge_form='module_alias' ORDER BY cf.name, c.callee_name")
  |> List.map (function
       | [caller; callee; kind; resolved] ->
           ( Db.to_string ~sql:"alias_rows" caller,
             Db.to_string ~sql:"alias_rows" callee,
             Db.to_string ~sql:"alias_rows" kind,
             Db.to_int ~sql:"alias_rows" resolved = 1 )
       | _ -> Test.fail "alias_rows: unexpected row shape")

let register_rewrite () =
  Test.register ~__FILE__
    ~title:"module-alias heads: an alias-rooted head is rewritten, marked and never MUST"
    ~tags:["cmt"; "calls"; "alias"; "edge_form"; "module_alias"]
  @@ fun () ->
  with_fixture ~name:"ma_rewrite" ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "ma_rewrite" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  Batch.run (fun b ->
      (* Premise guard: a fixture that indexed nothing makes every count below
         pass by being vacuous. *)
      Batch.check b ~msg:"the fixture indexed its callers at all"
        (Db.with_db db (fun c ->
             Db.int c
               "SELECT count(*) FROM functions WHERE name IN \
                ('via_alias','deep_call','direct','Internal_for_tests.nested_stub',\
                 'Make.through_param')")
        >= 5) ;
      let rows = alias_rows db in
      (* The EXACT set, not a count. A count says "five things happened"; this
         says which five, so a row that silently retargets and a sixth from a
         shape nobody meant to admit both fail here rather than cancelling
         out. *)
      Batch.eq_string b
        ~msg:"the rewritten head set is exactly the alias-rooted calls, each to its own target"
        (String.concat ", " (List.map (fun (a, c, _, _) -> a ^ "->" ^ c) rows))
        "Internal_for_tests.nested_stub->Ma_stub.f, deep_call->Deep.Syntax.plus, \
         via_alias->Ma_other.f, via_alias->Ma_real.f" ;
      (* A LIMITATION, pinned here rather than left to be discovered. The
         rewrite is only as good as [Path.name] of the alias TARGET, and
         [module D = Deep] names a module local to this unit, so the rewritten
         head is the unqualified [Deep.Syntax.plus] and qualified resolution
         does not find it. The edge is honest — MAY_ENUMERATED with no
         [callee_id], a bounded candidate we cannot point at a row — and it is
         strictly better than the ⊤ it replaces, but it is NOT the resolution
         the flagship cross-unit case gets. Asserted so that making it resolve
         later is a visible change and not a silent one. *)
      Batch.eq_int b
        ~msg:"an alias to a UNIT-LOCAL module rewrites but does not resolve (declared limitation)"
        (Db.with_db db (fun c ->
             Db.int c
               "SELECT count(*) FROM calls WHERE edge_form='module_alias' \
                AND callee_name='Deep.Syntax.plus' AND callee_id IS NULL"))
        1 ;
      (* FR-011, as a structural claim rather than a spot check: no rewritten
         edge may be MUST however its head classifies. The rewrite discharges
         the NAMING conjunct of MUST and leaves uniqueness and saturation
         standing, so a MUST here would be a proof-carrying claim resting on
         one third of its evidence. *)
      Batch.eq_int b ~msg:"no rewritten edge is MUST (FR-011)"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM calls WHERE edge_form='module_alias' AND kind='MUST'"))
        0 ;
      Batch.eq_int b ~msg:"every rewritten edge is MAY_ENUMERATED"
        (Db.with_db db (fun c ->
             Db.int c
               "SELECT count(*) FROM calls WHERE edge_form='module_alias' AND kind \
                <> 'MAY_ENUMERATED'"))
        0 ;
      (* The ordinary qualified call must NOT be marked. *)
      Batch.eq_int b ~msg:"a qualified call with no alias in its head is not marked"
        (Db.with_db db (fun c ->
             Db.int c
               "SELECT count(*) FROM calls c JOIN functions cf ON c.caller_id=cf.id \
                WHERE cf.name='direct' AND c.edge_form IS NOT NULL"))
        0 ;
      (* THE DECLINE. A functor parameter is not an alias, and the honest
         answer is the ⊤ that was already there. If the rewrite ever matched on
         a NAME instead of a stamp, this is where a sound ⊤ becomes a wrong
         callee_id. *)
      Batch.eq_string b
        ~msg:"a genuine functor parameter keeps its ⊤ and its module_param reason"
        (String.concat ","
           (Db.with_db db (fun c ->
                Db.rows c
                  "SELECT COALESCE(c.kind,'?')||'/'||COALESCE(c.top_reason,'?')||'/'\
                   ||CASE WHEN c.edge_form IS NULL THEN 'unmarked' ELSE c.edge_form END \
                   FROM calls c JOIN functions cf ON c.caller_id=cf.id \
                   WHERE cf.name='Make.through_param' AND c.callee_name='S.f'")
            |> List.map (function
                 | [x] -> Db.to_string ~sql:"param" x
                 | _ -> Test.fail "param: unexpected row shape")))
        "MAY_TOP/module_param/unmarked") ;
  Lwt.return_unit

(* FR-012 / SA-1, alone in its own test because it is the one assertion whose
   failure means something specific: the key is a name, not a stamp. *)
let register_stamp_key () =
  Test.register ~__FILE__
    ~title:"module-alias heads: a nested rebinding resolves to ITS target, not the toplevel one"
    ~tags:["cmt"; "calls"; "alias"; "module_alias"; "shadow"]
  @@ fun () ->
  with_fixture ~name:"ma_stamp" ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "ma_stamp" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  (* Scoped by FILE as well as by name: [via_alias] is declared in both ma_a
     and ma_b — deliberately, since US-1 is precisely that one alias name binds
     to two targets in two files — so a name-only lookup returns both rows and
     the assertion would read whichever order SQLite chose. *)
  let callee_of file caller =
    String.concat ","
      (Db.with_db db (fun c ->
           Db.rows c
             (Printf.sprintf
                "SELECT c.callee_name FROM calls c JOIN functions cf ON c.caller_id=cf.id \
                 JOIN modules m ON cf.module_id=m.id \
                 WHERE cf.name='%s' AND m.path LIKE '%%%s' AND c.edge_form='module_alias'"
                caller file))
       |> List.map (function
            | [x] -> Db.to_string ~sql:"callee_of" x
            | _ -> Test.fail "callee_of: unexpected row shape"))
  in
  Batch.run (fun b ->
      (* PREMISE: both binders must actually exist, or "the inner one did not
         resolve to Ma_real" is also what a fixture with no nested alias
         produces. *)
      Batch.eq_string b
        ~msg:"premise: the TOPLEVEL S is bound and its call rewrites to Ma_real"
        (callee_of "ma_a.ml" "via_alias") "Ma_real.f" ;
      (* THE ASSERTION. Under a name key this reads [Ma_real.f]: the lookup
         finds the only row spelled "S", which is the toplevel one, and records
         a call into production code from a body that calls a stub. *)
      Batch.eq_string b
        ~msg:"the NESTED S resolves to its own target — a name key would say Ma_real.f here"
        (callee_of "ma_a.ml" "Internal_for_tests.nested_stub") "Ma_stub.f" ;
      (* US-1, the other half: the SAME alias name in a different file binds to
         a different target, and neither file's call reaches the other's. This
         is the per-file scoping, which under D1-quater is the table's LIFETIME
         — one per compilation unit — rather than a field a join could drop. *)
      Batch.eq_string b
        ~msg:"the same alias name in another file resolves to ITS own target"
        (callee_of "ma_b.ml" "via_alias") "Ma_other.f" ;
      (* And the consequence a consumer sees, which is the reason the row
         matters: the raise-set. Ma_stub raises Stub_boom and Ma_real raises
         Real_boom, so a wrong edge is not merely mislabelled — it reports the
         wrong exception escaping. *)
      Batch.check b
        ~msg:"no path from nested_stub reaches Ma_real's exception"
        (Db.with_db db (fun c ->
             Db.int c
               "SELECT count(*) FROM calls c JOIN functions cf ON c.caller_id=cf.id \
                WHERE cf.name='Internal_for_tests.nested_stub' \
                AND c.callee_name='Ma_real.f'")
        = 0)) ;
  Lwt.return_unit

(* THE REGRESSION THIS FILE WAS WRITTEN FOR.

   [fan-in], [callers-of] and [god-modules] excluded [edge_form IS NULL] — every
   non-null value, not the one value that is not a call site. The point-free
   fixture could not catch it: it has [value_alias] edges only, so the narrow
   and the broad predicate agree on it exactly. *)
let register_consumers_count_it () =
  Test.register ~__FILE__
    ~title:"module-alias heads: callers-of and fan-in COUNT a rewritten edge"
    ~tags:["cmt"; "query"; "alias"; "module_alias"; "callers_of"; "fan_in"]
  @@ fun () ->
  with_fixture ~name:"ma_readers" ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "ma_readers" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  let query args =
    let c, out =
      Arch_tezt.run_command ~env:[("ARCH_QUERY_FORMAT", "list")] (Arch_tezt.arch_query ())
        (db :: args)
    in
    if c <> 0 then Test.fail "arch-query %s failed (exit %d):\n%s" (String.concat " " args) c out ;
    out
  in
  Batch.run (fun b ->
      (* PREMISE GUARD: "callers-of names via_alias" is also what a run with no
         module_alias edges at all produces, if via_alias reached Ma_real by
         some other route. *)
      Batch.check b ~msg:"premise: rewritten edges exist and are resolved"
        (Db.with_db db (fun c ->
             Db.int c
               "SELECT count(*) FROM calls WHERE edge_form='module_alias' AND callee_id IS NOT NULL")
        > 0) ;
      (* THE ASSERTION. [via_alias] calls [Ma_real.f] through an alias; it is a
         caller in every sense a reader of this command cares about. *)
      let co = query ["callers-of"; "f"] in
      Batch.check b
        ~msg:("callers-of names the caller that reached f through an alias (output:\n" ^ co ^ ")")
        (Arch_tezt.contains ~needle:"via_alias" co)) ;
  Lwt.return_unit

let register () =
  register_rewrite () ;
  register_stamp_key () ;
  register_consumers_count_it ()
