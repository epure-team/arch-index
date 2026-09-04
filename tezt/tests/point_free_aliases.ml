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

    What is asserted here is the producer contract for the LOCAL slice
    (specs/point-free-aliases.md S1): the edge exists, it is MAY_ENUMERATED and
    never MUST, it is marked [edge_form='value_alias'], and the three excluded
    classes stay excluded. The qualified slice ([let f = M.g], [Path.Pdot]) is
    S3 and is deliberately absent — it resolves through [resolve_qualified],
    which roadmap 1.6 is rewriting. *)

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

(* EXCLUDED (FR-003): not arrow-typed. A value alias transfers no body. *)
let pi = 3
let k = pi

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
      Batch.eq_int b
        ~msg:
          (Printf.sprintf
             "three point-free aliases are recognised — local, qualified, open-mediated (got: %s)"
             (String.concat ", " (List.map (fun (a, c, _, _) -> a ^ "->" ^ c) rows)))
        (List.length rows) 3 ;
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
      (* FR-003: the non-arrow binding transfers a value, not a body. *)
      Batch.eq_int b ~msg:"the non-arrow binding k = pi emits no edge"
        (Db.with_db db (fun c ->
             Db.int c
               "SELECT count(*) FROM calls c JOIN functions cf ON c.caller_id=cf.id \
                WHERE cf.name='k'"))
        0) ;
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

let register () =
  register_local_slice () ;
  register_fan_in_excludes ()
