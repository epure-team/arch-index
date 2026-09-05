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

module Sub = struct
  let g n = n + 1
end
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

module type HAS_SUB = sig
  module Sub : sig
    val g : int -> int
  end
end

module Make (S : HAS_F) = struct
  let through_param n = S.f n
end

(* THE CRITICAL CASE, and the one the first version of this fixture could not
   see. Above, [S] is a functor parameter used DIRECTLY: no [module _ = S]
   exists, so the alias table is empty and the decline proves nothing — it
   measures the ABSENCE of a binding, not the correctness of one.

   Here the parameter is ALIASED. [module M = Ma_other] inside [Aliased] is an
   ordinary Tstr_module/Tmod_ident, and so is [module M = P]: [P] is an [Ident]
   like any other and [Path.name] renders it "P" exactly as it would render a
   library module. Recording it rewrites [M.f] to [P.f] — and had any unit in
   this fixture been called [P], the edge would have RESOLVED to it, turning an
   honest ⊤ into a proof-carrying pointer at an unrelated function that merely
   shares the parameter's name. *)
module Aliased (P : HAS_F) = struct
  module M = P

  let through_alias n = M.f n
end

(* THE OTHER ROUTES TO THE SAME DEFECT. Round 1 proved only the plain case, and
   "the guard tests the root so it should cover the rest" is not a measurement.
   Each of these binds a module to something that is NOT a compilation unit, by
   a different syntactic road. *)
module Routes (P : HAS_F) = struct
  (* Through a SIGNATURE CONSTRAINT: Tmod_constraint wrapping Tmod_ident, which
     [module_target_path] unwraps — so the constraint does not hide the root. *)
  module R2 : HAS_F = P

  let r2 n = R2.f n

  (* NESTED inside a submodule: iter_structure_items descends, so this reaches
     the table under a deeper prefix. *)
  module Inner = struct
    module R3 = P

    let r3 n = R3.f n
  end

  (* An alias TO an alias to a parameter — two hops, where the first hop is
     itself refused, so the second has nothing to chase. *)
  module R1 = P
  module R5 = R1

  let r5 n = R5.f n

  (* An EXPRESSION-level binding. This one is safe for a DIFFERENT reason and
     the difference matters: [iter_structure_items] walks structure items, and
     [Texp_letmodule] is not one, so it never reaches the table at all. If the
     walker is ever taught to visit it, the guard is what will have to catch it
     — this line is here so that change fails loudly rather than silently. *)
  let r4 n =
    let module R4 = P in
    R4.f n
end

(* A FIRST-CLASS MODULE. [Tmod_unpack] makes [module_target_path] return None,
   so like [let module] it never reaches the table — again a different reason
   from the guard's. *)
let r6 (x : (module HAS_F)) n =
  let module R6 = (val x : HAS_F) in
  R6.f n

(* R8 — INCLUDE of a functor parameter, and R9 — a RECURSIVE binding to one.
   Both were named in the review's list of other roads and both were missing
   from the first battery, which is itself the layer-up version of the defect
   the battery exists to close.

   Measured: both are safe ONLY because [Tstr_include] and [Tstr_recmodule] are
   not [Tstr_module], so neither reaches the table. And [Tstr_recmodule] is the
   sharp one: the [unit_declared] pre-pass in this same file ALREADY handles it
   beside [Tstr_module], so anyone extending this table to mirror that pre-pass
   makes R9 live in one edit — at which point the persistent-root guard becomes
   its only protection. The expiry is not hypothetical; the precedent to copy is
   thirty lines away. *)
module Inc (P : HAS_SUB) = struct
  include P

  let r8 n = Sub.g n
end

module RecM (P : HAS_F) = struct
  module rec R9 : HAS_F = P

  let r9 n = R9.f n
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
        "Internal_for_tests.nested_stub->Ma_stub.f, via_alias->Ma_other.f, \
         via_alias->Ma_real.f" ;
      (* An alias to a UNIT-LOCAL module ([module D = Deep]) is DECLINED, and
         the ⊤ stands. An earlier revision rewrote it and shipped the result as
         a "declared limitation" — an edge that rewrote but could not resolve,
         because [Path.name] of a unit-local target carries no unit.

         The persistent-root guard that closes the functor-parameter CRITICAL
         subsumes it: a unit-local module's root is a local [Ident] too. So the
         limitation is not worked around, it is gone, and the rewrite may only
         ever move a head from one persistent spelling to another. *)
      Batch.eq_int b
        ~msg:"an alias to a UNIT-LOCAL module is declined, not rewritten into something unresolvable"
        (Db.with_db db (fun c ->
             Db.int c
               "SELECT count(*) FROM calls WHERE edge_form='module_alias' \
                AND callee_name LIKE 'Deep.%'"))
        0 ;
      (* Every rewritten edge must RESOLVE. Not a nicety: an unresolvable
         rewrite is a head we changed without being able to say to what, which
         is strictly less honest than the ⊤ it replaced. *)
      Batch.eq_int b
        ~msg:"no rewritten edge is left unresolvable"
        (Db.with_db db (fun c ->
             Db.int c
               "SELECT count(*) FROM calls WHERE edge_form='module_alias' AND callee_id IS NULL"))
        0 ;
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
        "MAY_TOP/module_param/unmarked" ;
      (* THE CRITICAL. A parameter that is ALIASED, which the direct-use case
         above cannot witness: there the table is empty, so the decline measures
         the absence of a binding rather than the correctness of one. Here a
         binding exists and names a functor parameter, and the guard must refuse
         it on the ground that its root is not a compilation unit.

         Without the guard this reads MAY_ENUMERATED/-/module_alias with a
         callee_id pointing at whatever unit happens to share the parameter's
         name. *)
      Batch.eq_string b
        ~msg:"an alias BOUND TO a functor parameter keeps its ⊤ — the head is not a real unit"
        (String.concat ","
           (Db.with_db db (fun c ->
                Db.rows c
                  "SELECT COALESCE(c.kind,'?')||'/'||COALESCE(c.top_reason,'?')||'/'\
                   ||CASE WHEN c.edge_form IS NULL THEN 'unmarked' ELSE c.edge_form END \
                   ||'/'||CASE WHEN c.callee_id IS NULL THEN 'unresolved' ELSE 'RESOLVED' END \
                   FROM calls c JOIN functions cf ON c.caller_id=cf.id \
                   WHERE cf.name='Aliased.through_alias' AND c.callee_name LIKE '%.f'")
            |> List.map (function
                 | [x] -> Db.to_string ~sql:"aliased" x
                 | _ -> Test.fail "aliased: unexpected row shape")))
        "MAY_TOP/module_param/unmarked/unresolved" ;
      (* THE BATTERY. Every road to a module bound to something that is not a
         compilation unit must leave its ⊤ standing. Measured against the
         unguarded producer, four of these are DECLINED BY THE GUARD (plain,
         signature-constrained, nested, two-hop) and two NEVER REACH THE TABLE
         (let module, first-class unpack) — stated because they are different
         guarantees, and the second kind stops holding the day the walker learns
         to visit expression-level module bindings. *)
      List.iter
        (fun (caller, callee_pat, road) ->
          Batch.eq_string b
            ~msg:(Printf.sprintf "%s: %s keeps its ⊤" caller road)
            (String.concat ","
               (Db.with_db db (fun c ->
                    Db.rows c
                      (Printf.sprintf
                         "SELECT COALESCE(c.kind,'?')||'/'\
                          ||CASE WHEN c.edge_form IS NULL THEN 'unmarked' ELSE c.edge_form END \
                          ||'/'||CASE WHEN c.callee_id IS NULL THEN 'unresolved' ELSE 'RESOLVED' END \
                          FROM calls c JOIN functions cf ON c.caller_id=cf.id \
                          WHERE cf.name='%s' AND c.callee_name LIKE '%s'"
                         caller callee_pat))
                |> List.map (function
                     | [x] -> Db.to_string ~sql:"route" x
                     | _ -> Test.fail "route: unexpected row shape")))
            "MAY_TOP/unmarked/unresolved")
        [
          ("Routes.r2", "%.f", "an alias to a parameter behind a signature constraint");
          ("Routes.Inner.r3", "%.f", "a nested alias to a parameter");
          ("Routes.r5", "%.f", "an alias to an alias to a parameter");
          ("Routes.r4", "%.f", "a let module binding (never reaches the table)");
          ("r6", "%.f", "a first-class module unpack (never reaches the table)");
          (* The callee pattern is per-route rather than a hardcoded [%.f]: the
             include route calls [Sub.g], and a battery whose selector matched
             only [.f] reported an EMPTY result for it — the selector filtering
             out exactly the row it was added to observe, in the battery written
             to close that class. *)
          ("Inc.r8", "%.g", "an include of a parameter (never reaches the table)");
          ("RecM.r9", "%.f", "a recursive binding to a parameter (never reaches the table)");
        ]) ;
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
    ~title:"module-alias heads: callers-of, fan-in and god-modules all COUNT a rewritten edge"
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
        (Arch_tezt.contains ~needle:"via_alias" co) ;
      (* THE TWO SITES THE FIRST VERSION OF THIS TEST DID NOT COVER, and their
         absence was not visible from the title — which said "callers-of and
         fan-in" while asserting only the first. A reviewer's mutants found it:
         reverting `callers-of` was KILLED, reverting `fan-in` and
         `god-modules` both SURVIVED. Two of the three fixes this branch exists
         for could have been undone in silence. *)
      let fi = query ["fan-in"] in
      Batch.check b
        ~msg:("fan-in counts a call reached through a module alias (output:\n" ^ fi ^ ")")
        (Arch_tezt.contains ~needle:"Ma_real.f" fi || Arch_tezt.contains ~needle:"\tf" fi
       || Arch_tezt.contains ~needle:"f " fi) ;
      (* The numeric form of the same claim, derived by hand from the fixture
         BEFORE running: [Ma_real.f] is called by ma_a's [via_alias] (through
         the alias) and by nothing else. A "contains" assertion would pass on a
         report that listed the name with a count of zero. *)
      let fan_in_of name =
        Db.with_db db (fun c ->
            Db.int c
              (Printf.sprintf
                 "SELECT count(*) FROM calls c JOIN functions f ON c.callee_id=f.id \
                  JOIN modules m ON f.module_id=m.id \
                  WHERE f.name='f' AND m.path LIKE '%%%s' \
                  AND COALESCE(c.edge_form,'') <> 'value_alias'"
                 name))
      in
      Batch.eq_int b
        ~msg:"the alias-mediated edge into Ma_real.f is counted, not excluded"
        (fan_in_of "ma_real.ml") 1 ;
      (* god-modules states in its own preamble that it REUSES fan-in's measure;
         if only one of the two counts alias-mediated edges that claim is false.
         Nothing invoked it on this fixture before. *)
      let gm = query ["god-modules"] in
      Batch.check b ~msg:"god-modules produces output at all" (String.length gm > 0) ;
      (* THE NUMBER, not the presence. A [contains "ma_real"] assertion here
         SURVIVED the mutant that reverts god-modules to the broad exclusion —
         ma_real still appears, just with a smaller count, because it also has
         one ordinary in-edge. The assertion measured its own selector rather
         than the behaviour, which is the failure this file's own docstring
         warns about, reproduced while fixing it.

         Derived by hand from the fixture BEFORE running: ma_real.ml receives
         [direct -> Ma_real.g] (ordinary) and [via_alias -> Ma_real.f]
         (alias-mediated) = 2. ma_stub.ml and ma_other.ml each receive exactly
         ONE in-edge and it is alias-mediated, so under the broad exclusion they
         do not merely shrink — they VANISH from the report. *)
      let gm_of path =
        String.split_on_char '\n' gm
        |> List.filter_map (fun l ->
               match String.split_on_char '|' (String.trim l) with
               | [ p; n ] when Arch_tezt.contains ~needle:path p ->
                   int_of_string_opt (String.trim n)
               | _ -> None)
        |> function
        | [ n ] -> n
        | _ -> 0
      in
      Batch.eq_int b
        ~msg:("god-modules counts BOTH of ma_real's in-edges, the alias-mediated one \
               included (output:\n" ^ gm ^ ")")
        (gm_of "ma_real.ml") 2 ;
      Batch.eq_int b
        ~msg:"a module whose ONLY in-edge is alias-mediated still appears (ma_stub)"
        (gm_of "ma_stub.ml") 1 ;
      Batch.eq_int b
        ~msg:"and the same across files (ma_other)"
        (gm_of "ma_other.ml") 1) ;
  Lwt.return_unit

let register () =
  register_rewrite () ;
  register_stamp_key () ;
  register_consumers_count_it ()
