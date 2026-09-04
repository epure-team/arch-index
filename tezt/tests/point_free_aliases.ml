(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Point-free value aliases — [let f = g] transfers a body without applying it,
    and the walker used to emit nothing at all for that binding.

    The bug is quiet in the way that matters. A point-free binding peels to a
    bare [Texp_ident], so [walk_function_root] finds no application anywhere in
    the body and the expression iterator's catch-all drops it. The node for [f]
    is created (it has a [functions] row, named from the binder) and then has no
    outgoing edge, so the exception fixpoint reports its raise-set as empty —
    [BOUNDED: {}]. That verdict is indistinguishable from "this function
    genuinely raises nothing", which is what makes it worse than a ⊤: ⊤ is a
    stated unknown, and this is a stated certainty about a body nobody read.

    What is asserted here is the producer contract for the WHOLE emission rule
    (specs/point-free-aliases.md): the edge exists, it is MAY_ENUMERATED and
    never MUST, it is marked [edge_form='value_alias'], the excluded classes
    stay excluded, and the three query readers that must not count an alias as
    a caller do not.

    All three slices are present, not just the local one. S3 (the qualified
    alias, [let f = M.g] / [Path.Pdot]) and S2 ([open]-mediated, which the
    fixture shows is the SAME path shape post-resolution and therefore not a
    distinct case) both ship here — an earlier revision of this docstring said
    the qualified slice was "deliberately absent" while the fixture below
    already contained [qualified_alias] and [via_open] and asserted on them.

    Also asserted, because they are the two ways this feature degrades quietly:
    an alias whose RHS is ITSELF an alias binder must emit its own edge (the
    chain, [hop1]/[hop2]/[hop3] — without it two names for one function return
    contradictory raise-sets), and an under-saturated application through an
    alias must never be MUST ([arity_partial] — which pins WHY alias binders
    are kept out of [local_fn_stamps]). *)

open Arch_tezt

let fixture_files =
  [
    Fixture.dune_project;
    ( "dune",
      "(library\n\
      \ (name pfa_fixture)\n\
      \ (wrapped false)\n\
      \ (modules pfa_a pfa_b)\n\
      \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
    ( "pfa_b.ml",
      {|let cross_helper n = if n > 0 then raise Not_found else n

(* Non-arrow QUALIFIED values. These exist so FR-003's [is_arrow] guard has a
   fixture that actually reaches it: a BARE non-arrow ident ([let k = pi]) is
   stopped earlier and by a different rule, so it cannot witness this guard.
   See [kq]/[kt] in pfa_a.ml. *)
let zero = 0
let table = [1; 2; 3]
|} );
    ( "pfa_a.ml",
      {|open Pfa_b

exception Boom

let raiser n = if n > 0 then raise Boom else n

(* THE SUBJECT: point-free, arrow-typed, same-module top-level target. *)
let alias = raiser

(* An ordinary application of the same callee. Its edge must NOT be marked —
   without this row the edge_form assertions below would pass just as well if
   the producer marked every edge in the database. *)
let caller n = raiser n

(* EXCLUDED (FR-003): not arrow-typed. A value alias transfers no body.

   [k] is a WEAK witness and is kept only for completeness: [pi] is a bare
   [Pident] that is not in [local_fn_stamps] and not an alias binder either, so
   [k] is stopped by that exclusion before [is_arrow] is ever consulted. A test
   that only asserted "k emits nothing" would pass with the arrow guard
   deleted. [kq]/[kt] below are the real witnesses. *)
let pi = 3
let k = pi

(* EXCLUDED (FR-003), and THE witnesses for it: qualified non-arrow values.
   [Path.Pdot] skips the [local_fn_stamps] exclusion entirely and lands on
   [add_path_call], so [is_arrow] is the ONLY thing standing between these
   bindings and a call edge to an int and to an int list. Verified by mutation:
   with [is_arrow] deleted from the guard, both acquire a
   [MAY_ENUMERATED value_alias] edge and the assertion below goes red. *)
let kq = Pfa_b.zero
let kt = Pfa_b.table

(* EXCLUDED: not point-free. [make] is a combinator that RETURNS [raiser];
   nothing is applied here and [make] does not inherit [raiser]'s body. The
   walker peels parameters before looking at the body, so without an explicit
   guard this shape is indistinguishable from [let alias = raiser] — and it was
   not: the first implementation of this feature marked it as an alias, and the
   dominance corpus failed because the spurious edge made a deliberately-⊤
   island REACHABLE. Pinned here so the next regression fails in the file that
   owns the rule. *)
let make () = raiser

(* THE QUALIFIED SLICE (S3): an explicitly qualified point-free alias. *)
let qualified_alias = Pfa_b.cross_helper

(* THE S2 QUESTION. [cross_helper] is brought into scope by [open Pfa_b] and is
   therefore SYNTACTICALLY bare here — it looks exactly like [let alias = raiser].
   Whether it is a distinct case depends on something no amount of reading the
   source can settle: typedtree paths are POST-resolution, so the walker may see
   [Path.Pdot (Pfa_b, cross_helper)] and never a [Pident] at all. *)
let via_open = cross_helper

(* THE ALIAS CHAIN. An alias whose RHS is ITSELF an alias binder. [hop2]'s RHS
   is a bare [Pident] naming [hop1], which has no function BODY and so is not
   in [local_fn_stamps] — the shape that used to emit nothing at all, leaving
   [hop2] and [hop3] reading BOUNDED: {} beside [hop1]'s correct
   BOUNDED: {Chain_boom}. One edge per hop; the chain closes because consumers
   traverse the edges, not because the producer iterates. *)
exception Chain_boom

let chain_target n = if n > 0 then raise Chain_boom else n
let hop1 = chain_target
let hop2 = hop1
let hop3 = hop2

(* WHY THE ALIAS TABLE IS SEPARATE FROM [local_fn_stamps], pinned.

   The obvious way to close the chain above is to put alias binders into
   [local_fn_stamps] itself. Measured, that is UNSOUND, and this fixture is the
   witness. [unary] is a type-alias-hidden arrow: on a .cmt-restored env it does
   not expand, so [is_arrow] is FALSE for a value of that type and the SYNTACTIC
   arity in [local_fn_stamps] is the only thing that can see an under-saturated
   application. An alias binder's syntactic arity is 0 ([fn_arity] of a bare
   ident), so admitting it there makes [nargs < head_arity] false for every
   application, and [arity_partial] — two arguments to a 3-ary target, whose
   body has NOT run — was emitted as MUST. Verified by building it that way:
   [arity_partial -> arity_alias] came out [MUST]; with the tables kept separate
   it is [MAY_TOP]. *)
type unary = int -> int

let arity_mk (a : int) (b : int) : unary = fun c -> a + b + c
let arity_alias = arity_mk
let arity_partial = arity_alias 1 2

(* EXCLUDED: the binder is a wildcard, so no [functions] row exists to hang an
   edge on. Nothing special guards this — a pending call whose caller is absent
   from [fn_lookup] is dropped at arch_index.ml's [| None -> ()]. The assertion
   is that the structural guarantee holds, not that a check fires. *)
let _ = raiser
|} );
  ]

(* Every value_alias row, as (caller, callee, kind, callee_id-is-set). *)
let alias_rows db =
  Db.with_db db (fun conn ->
      Db.rows
        conn
        "SELECT cf.name, c.callee_name, COALESCE(c.kind,'NULL'), \
         CASE WHEN c.callee_id IS NULL THEN 0 ELSE 1 END \
         FROM calls c JOIN functions cf ON c.caller_id=cf.id \
         WHERE c.edge_form='value_alias' ORDER BY cf.name")
  |> List.map (function
       | [caller; callee; kind; resolved] ->
           ( Db.to_string ~sql:"alias_rows" caller,
             Db.to_string ~sql:"alias_rows" callee,
             Db.to_string ~sql:"alias_rows" kind,
             Db.to_int ~sql:"alias_rows" resolved = 1 )
       | _ -> Test.fail "alias_rows: unexpected row shape")

let register_local_slice () =
  Test.register ~__FILE__
    ~title:"point-free aliases: a local alias emits a MAY_ENUMERATED value_alias edge"
    ~tags:["cmt"; "calls"; "alias"; "edge_form"]
  @@ fun () ->
  with_fixture ~name:"pfa_local" ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "pfa_local" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  Batch.run (fun b ->
      (* Premise guard: if the fixture indexed nothing, every assertion that
         counts rows would pass by being vacuous. *)
      Batch.check b
        ~msg:"the fixture indexed its functions at all"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM functions WHERE name IN ('raiser','alias','caller')")
        = 3) ;
      (* S2, SETTLED EMPIRICALLY (probe, 2026-09-04): [open Pfa_b] followed by a
         bare [cross_helper] produces [Path.Pdot "Pfa_b.cross_helper"], NOT a
         [Pident] — typedtree paths are post-resolution, so an [open]-mediated
         alias is indistinguishable from an explicitly qualified one. It is
         therefore NOT a distinct case: the qualified slice covers it by
         construction. [via_open] appearing in this list, next to
         [qualified_alias] and resolved the same way, is that finding pinned. *)
      let rows = alias_rows db in
      (* The EXACT set, not a count. A count says "six things happened"; this
         says which six, so a row that silently retargets or a seventh that
         appears from a shape nobody meant to admit both fail here rather than
         cancelling out. [alias_rows] orders by caller name. *)
      Batch.eq_string b
        ~msg:"the alias edge set is exactly the six point-free bindings, each to its own target"
        (String.concat ", " (List.map (fun (a, c, _, _) -> a ^ "->" ^ c) rows))
        "alias->raiser, arity_alias->arity_mk, hop1->chain_target, hop2->hop1, hop3->hop2, \
         qualified_alias->Pfa_b.cross_helper, via_open->Pfa_b.cross_helper" ;
      (* The separate-tables invariant, as an assertion rather than a comment.
         [arity_partial = arity_alias 1 2] is under-saturated behind a type
         alias; if alias binders ever get folded into [local_fn_stamps] this
         becomes MUST — a proof-carrying claim that a body ran when it did
         not. *)
      Batch.eq_string b
        ~msg:"an under-saturated application THROUGH an alias is never MUST (alias binders stay out of local_fn_stamps)"
        (String.concat ","
           (Db.with_db db (fun c ->
                Db.rows c
                  "SELECT COALESCE(c.kind,'NULL') FROM calls c \
                   JOIN functions cf ON c.caller_id=cf.id \
                   WHERE cf.name='arity_partial' AND c.callee_name='arity_alias'")
            |> List.map (function
                 | [x] -> Db.to_string ~sql:"arity_partial" x
                 | _ -> Test.fail "unexpected row shape")))
        "MAY_TOP" ;
      List.iter
        (fun (caller, callee, kind, resolved) ->
          Batch.check b
            ~msg:(Printf.sprintf "%s: MAY_ENUMERATED, never MUST (got %s)" caller kind)
            (kind = "MAY_ENUMERATED") ;
          Batch.check b
            ~msg:(Printf.sprintf "%s: resolved to a callee_id (-> %s)" caller callee)
            resolved)
        rows ;
      (match List.find_opt (fun (c, _, _, _) -> c = "alias") rows with
      | Some (caller, callee, kind, resolved) ->
          Batch.check b ~msg:"the alias edge is attributed to the BINDER, not the target"
            (caller = "alias") ;
          Batch.check b
            ~msg:(Printf.sprintf "the alias edge points at raiser (got %s)" callee)
            (callee = "raiser") ;
          (* FR-005: MAY_ENUMERATED, never MUST. The kind matrix demotes on
             [cond || partial], and an alias is neither — so routing it through
             [Head_local] would have emitted MUST, a proof-carrying claim that
             [alias] always CALLS [raiser], at a site where no call happens. *)
          Batch.check b
            ~msg:(Printf.sprintf "the alias edge is MAY_ENUMERATED (got %s)" kind)
            (kind = "MAY_ENUMERATED") ;
          Batch.check b ~msg:"the alias edge resolved to a callee_id" resolved ;
          ignore kind
      | None -> Batch.check b ~msg:"the local alias row is present" false) ;
      (* Both cross-module forms must name the SAME callee — that is what says
         [open] resolution and explicit qualification arrive at one target. *)
      Batch.check b
        ~msg:"via_open and qualified_alias resolve to the same callee"
        (match
           ( List.find_opt (fun (c, _, _, _) -> c = "via_open") rows,
             List.find_opt (fun (c, _, _, _) -> c = "qualified_alias") rows )
         with
        | Some (_, c1, _, _), Some (_, c2, _, _) -> c1 = c2
        | _ -> false) ;
      (* The marker discriminates. An ordinary application of the same callee
         must be unmarked, or the column carries no information. *)
      Batch.eq_int b ~msg:"an ordinary call to the same callee is NOT marked"
        (Db.with_db db (fun c ->
             Db.int c
               "SELECT count(*) FROM calls c JOIN functions cf ON c.caller_id=cf.id \
                WHERE cf.name='caller' AND c.callee_name='raiser' AND c.edge_form IS NULL"))
        1 ;
      (* FR-005b, stated as a database-wide invariant rather than about this
         one row: a MUST alias edge is the specific unsound outcome. *)
      Batch.eq_int b ~msg:"no value_alias edge anywhere carries kind='MUST'"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM calls WHERE edge_form='value_alias' AND kind='MUST'"))
        0 ;
      (* Not point-free: parameters were peeled, so this is a combinator. *)
      Batch.eq_int b ~msg:"a parameterised body that is a bare ident is NOT an alias"
        (Db.with_db db (fun c ->
             Db.int c
               "SELECT count(*) FROM calls c JOIN functions cf ON c.caller_id=cf.id \
                WHERE cf.name='make' AND c.edge_form='value_alias'"))
        0 ;
      (* FR-003, THE REAL WITNESS. [kq = Pfa_b.zero] (an int) and
         [kt = Pfa_b.table] (an int list) are QUALIFIED, so they reach
         [add_path_call] and [is_arrow] is the only guard between them and a
         call edge to a non-function. Mutation-verified: deleting [is_arrow]
         from the emission guard gives both a MAY_ENUMERATED value_alias edge
         and reddens this assertion. Asserted over ALL calls rows, not just
         value_alias ones, so a bogus edge that arrives unmarked is caught
         too. *)
      Batch.eq_string b
        ~msg:"FR-003: a qualified NON-ARROW binding emits no edge — not to an int, not to a list"
        (String.concat ","
           (Db.with_db db (fun c ->
                Db.rows c
                  "SELECT cf.name || '->' || c.callee_name FROM calls c \
                   JOIN functions cf ON c.caller_id=cf.id \
                   WHERE cf.name IN ('kq','kt') ORDER BY 1")
            |> List.map (function
                 | [x] -> Db.to_string ~sql:"non-arrow" x
                 | _ -> Test.fail "unexpected row shape")))
        "" ;
      (* Kept for completeness; a WEAK witness — [k] is stopped by the
         not-in-[local_fn_stamps] exclusion before [is_arrow] is consulted. *)
      Batch.eq_int b ~msg:"the bare non-arrow binding k = pi emits no edge either"
        (Db.with_db db (fun c ->
             Db.int c
               "SELECT count(*) FROM calls c JOIN functions cf ON c.caller_id=cf.id \
                WHERE cf.name='k'"))
        0 ;
      (* HIGH-1: the alias slice is closed under its own construct. Each hop is
         one edge to its IMMEDIATE predecessor — no transitive shortcut, which
         is what makes the closure a property of the graph rather than of a
         producer-side fixpoint. *)
      Batch.eq_string b
        ~msg:"an alias whose RHS is itself an alias binder emits its own edge, one hop at a time"
        (String.concat ","
           (List.filter_map
              (fun (caller, callee, kind, resolved) ->
                if String.length caller >= 3 && String.sub caller 0 3 = "hop" then
                  Some
                    (Printf.sprintf "%s->%s/%s/%s" caller callee kind
                       (if resolved then "resolved" else "unresolved"))
                else None)
              rows))
        "hop1->chain_target/MAY_ENUMERATED/resolved,hop2->hop1/MAY_ENUMERATED/resolved,hop3->hop2/MAY_ENUMERATED/resolved") ;
  Lwt.return_unit

let register_fan_in_excludes () =
  Test.register ~__FILE__
    ~title:"point-free aliases: fan-in does not count an alias as a caller"
    ~tags:["cmt"; "query"; "alias"; "edge_form"; "fan_in"]
  @@ fun () ->
  with_fixture ~name:"pfa_fanin" ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "pfa_fanin" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  (* FR-006. An alias is not a caller: nobody invokes anything at that site.
     Counting it inflates precisely the measure this query reports, and does so
     silently — which is why the exclusion is asserted through the QUERY, not by
     re-deriving the count in SQL here. Re-deriving would test this test. *)
  (* [list] format, not the default box: the box renderer's own help/legend text
     contains the word "raiser", so a substring search over box output finds a
     usage line and asserts against it. It did, on the first run of this test. *)
  let qcode, qout =
    Arch_tezt.run_command
      ~env:[("ARCH_QUERY_FORMAT", "list")]
      (Arch_tezt.arch_query ())
      [db; "fan-in"]
  in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"arch-query fan-in exits 0" qcode 0 ;
      if qcode <> 0 then Batch.note b "fan-in output:\n%s" qout ;
      (* PREMISE GUARD. The expected fan-in below is 1, and a TOTAL ABSENCE of
         alias edges also produces 1 — so without this the test stays green
         with the whole feature deleted, and measures nothing. Verified: with
         the emission guard neutralised the two sibling tests in this file fail
         and this one did not. What must exist for the assertion to mean
         anything is the alias edge whose exclusion is being asserted. *)
      Batch.eq_int b
        ~msg:"premise: the alias edge that must be EXCLUDED was actually emitted"
        (Db.with_db db (fun c ->
             Db.int c
               "SELECT count(*) FROM calls c JOIN functions cf ON c.caller_id=cf.id \
                WHERE cf.name='alias' AND c.callee_name='raiser' \
                AND c.edge_form='value_alias'"))
        1 ;
      (* Two syntactic references to [raiser] exist — [caller]'s application and
         [alias]'s binding — and exactly one of them is a call. *)
      let count =
        String.split_on_char '\n' qout
        |> List.filter_map (fun l ->
               match String.split_on_char '|' (String.trim l) with
               | [name; n] when String.trim name = "raiser" -> int_of_string_opt (String.trim n)
               | _ -> None)
        |> function
        | [n] -> Some n
        | _ -> None
      in
      match count with
      | None ->
          Batch.check b
            ~msg:("fan-in reported exactly one raiser row; output was:\n" ^ qout)
            false
      | Some n ->
          Batch.eq_int b
            ~msg:"raiser's fan-in counts the application but not the alias binding"
            n
            1) ;
  Lwt.return_unit

(* S4 — the reason the alias belongs in [calls] at all.

   Every assertion above is about rows in a table. This one is about the
   VERDICT, and it is a separate test rather than another batch because
   [Arch_exn] is a SEPARATE LOADER: it re-reads the database from scratch, so
   nothing the producer tests prove says the fixpoint actually walks these
   edges. A feature whose whole rationale is "the raise-set chain will now
   follow aliases" is not delivered until something asserts the chain follows
   them. *)
let register_raise_sets_propagate () =
  Test.register ~__FILE__
    ~title:"point-free aliases: an alias inherits its target's raise set"
    ~tags:["cmt"; "exn"; "alias"; "edge_form"; "raises"]
  @@ fun () ->
  with_fixture ~name:"pfa_raises" ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "pfa_raises" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  let raises fn =
    let c, out =
      Arch_tezt.run_command
        ~env:[("ARCH_QUERY_FORMAT", "list")]
        (Arch_tezt.arch_query ())
        [db; "raises"; fn]
    in
    if c <> 0 then Test.fail "arch-query raises %s failed (exit %d):\n%s" fn c out ;
    out
  in
  Batch.run (fun b ->
      (* The premise. If [raiser] itself did not carry Boom, every assertion
         below would be about an empty set being empty. *)
      Batch.check b
        ~msg:"premise: the target function raises at all"
        (Arch_tezt.contains ~needle:"Boom" (raises "raiser")) ;
      (* THE BUG THIS FEATURE EXISTS FOR. Before it, [alias] had no outgoing
         edge and its verdict was BOUNDED: {} — indistinguishable from "raises
         nothing", which is why it was worse than a ⊤. *)
      Batch.check b
        ~msg:"a local alias inherits its target's exception (was BOUNDED: {})"
        (Arch_tezt.contains ~needle:"Boom" (raises "alias")) ;
      (* Cross-module, both spellings. These travel through the qualified
         resolver, so they also demonstrate that the alias edge carries a real
         callee_id rather than an external leaf. *)
      Batch.check b
        ~msg:"an explicitly qualified alias inherits across modules"
        (Arch_tezt.contains ~needle:"Not_found" (raises "qualified_alias")) ;
      Batch.check b
        ~msg:"an open-mediated alias inherits across modules (S2: same path shape)"
        (Arch_tezt.contains ~needle:"Not_found" (raises "via_open")) ;
      (* HIGH-1, THROUGH THE SEPARATE LOADER. The producer test proves the three
         chain EDGES exist; this proves the fixpoint actually walks them, which
         is a different claim — [Arch_exn] re-reads the database from scratch.
         And it is the claim that matters: the defect was never "a row is
         missing", it was that [hop1] answered BOUNDED: {Chain_boom} while
         [hop2] and [hop3], naming the identical function, answered
         BOUNDED: {} — a stated certainty about a body nobody read, sitting
         beside the correct answer for the same code. *)
      let premise = raises "chain_target" in
      Batch.check b
        ~msg:"premise: the chain's target raises at all"
        (Arch_tezt.contains ~needle:"Chain_boom" premise) ;
      List.iter
        (fun hop ->
          Batch.check b
            ~msg:
              (Printf.sprintf
                 "%s inherits through the alias chain — every hop, not just the first" hop)
            (Arch_tezt.contains ~needle:"Chain_boom" (raises hop)))
        ["hop1"; "hop2"; "hop3"] ;
      (* The exclusions must not leak into the verdict either: [make] returns
         [raiser] without calling it, so [make]'s own raise set is empty. *)
      Batch.check b
        ~msg:"a combinator that RETURNS the raiser does not inherit its exception"
        (not (Arch_tezt.contains ~needle:"Boom" (raises "make")))) ;
  Lwt.return_unit

(* FR-006's other two readers, and the column's own vocabulary.

   [fan-in] had a test; [god-modules] and [callers-of] did not, and a query
   exclusion nothing invokes is an exclusion nobody will notice losing.
   [callers-of] was not excluded at all until this review round — it answered
   [alias] as a caller of [raiser], which is the exact claim FR-006 exists to
   deny, on the one command whose whole purpose is naming callers. *)
let register_query_readers () =
  Test.register ~__FILE__
    ~title:"point-free aliases: callers-of and god-modules exclude alias edges"
    ~tags:["cmt"; "query"; "alias"; "edge_form"; "callers_of"; "god_modules"]
  @@ fun () ->
  with_fixture ~name:"pfa_readers" ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "pfa_readers" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  let query args =
    let c, out =
      Arch_tezt.run_command ~env:[("ARCH_QUERY_FORMAT", "list")] (Arch_tezt.arch_query ()) (db :: args)
    in
    if c <> 0 then Test.fail "arch-query %s failed (exit %d):\n%s" (String.concat " " args) c out ;
    out
  in
  Batch.run (fun b ->
      (* PREMISE GUARD, same reason as the fan-in test: "alias is absent from
         this output" is also what a total absence of alias edges produces. *)
      Batch.eq_int b
        ~msg:"premise: the alias edges that must be EXCLUDED were actually emitted"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM calls WHERE edge_form='value_alias'"))
        7 ;
      (* MEDIUM-4. [caller] applies [raiser]; [alias] merely binds it. *)
      let co = query ["callers-of"; "raiser"] in
      Batch.check b
        ~msg:("callers-of names the real caller (output:\n" ^ co ^ ")")
        (Arch_tezt.contains ~needle:"caller" co) ;
      Batch.check b
        ~msg:("callers-of does NOT name the alias binder (output:\n" ^ co ^ ")")
        (not (Arch_tezt.contains ~needle:"alias" co)) ;
      (* The chain, where the distortion compounds: [hop2] binds [hop1], so
         without the exclusion [hop1] acquires a "caller" that calls nothing. *)
      let ch = query ["callers-of"; "hop1"] in
      Batch.check b
        ~msg:("callers-of hop1 reports no caller at all — only an alias binds it (output:\n" ^ ch ^ ")")
        (not (Arch_tezt.contains ~needle:"hop2" ch)) ;
      (* LOW-2. [god-modules] states in its own preamble that it REUSES
         [fan-in]'s measure; if only one of the two excludes aliases that claim
         is false. Nothing invoked this command before. *)
      let gm = query ["god-modules"] in
      Batch.check b ~msg:"god-modules produces output at all" (String.length gm > 0) ;
      let module_fan_in =
        String.split_on_char '\n' gm
        |> List.filter_map (fun l ->
               match String.split_on_char '|' (String.trim l) with
               | [path; n] when Arch_tezt.contains ~needle:"pfa_a" path ->
                   int_of_string_opt (String.trim n)
               | _ -> None)
        |> function
        | [n] -> Some n
        | _ -> None
      in
      (* Derived by hand BEFORE running, from the fixture: the only edges into
         pfa_a functions with a resolved callee_id and edge_form IS NULL are
         [caller]->[raiser] and [via_open]/[qualified_alias]... which are
         aliases. So exactly one non-alias resolved in-module edge remains.
         Six alias edges are excluded; counting them would give 5 (raiser gains
         [alias], chain_target gains [hop1], hop1 gains [hop2], hop2 gains
         [hop3], plus [caller]->[raiser] already counted under raiser). *)
      (match module_fan_in with
      | None ->
          Batch.check b ~msg:("god-modules reported a pfa_a row; output was:\n" ^ gm) false
      | Some n ->
          Batch.eq_int b
            ~msg:"god-modules counts the application but none of the six alias bindings"
            n 1) ;
      (* LOW-3 / CHECK-2. The vocabulary is closed by a CHECK constraint, and a
         constraint nothing tries to violate is a constraint nobody knows is
         armed. Precedent: the identical assertion for an out-of-vocabulary
         [top_reason]. *)
      Batch.eq_int b ~msg:"CHECK-2: no row carries an out-of-vocabulary edge_form"
        (Db.with_db db (fun c ->
             Db.int c
               "SELECT count(*) FROM calls WHERE edge_form IS NOT NULL AND \
                edge_form <> 'value_alias'"))
        0 ;
      (* The constraint is armed, proved by trying to violate it. [module_alias]
         is the specific wrong value C-15 warns about — [deps.dep_kind='alias']
         already means MODULE alias, and the whole point of naming this column
         [edge_form] was to stop the two relations sharing one word. Written
         LAST in this batch: it mutates the database, so anything reading rows
         afterwards would read a half-updated one. *)
      Batch.check b
        ~msg:"the edge_form CHECK constraint actually REFUSES an out-of-vocabulary value"
        (Db.with_db_rw db (fun c ->
             match
               Db.exec_result c
                 "UPDATE calls SET edge_form='module_alias' WHERE edge_form='value_alias'"
             with
             | Ok () -> false (* accepted — the constraint is NOT armed *)
             | Error _ -> true))) ;
  Lwt.return_unit

let register () =
  register_local_slice () ;
  register_fan_in_excludes () ;
  register_query_readers () ;
  register_raise_sets_propagate ()
