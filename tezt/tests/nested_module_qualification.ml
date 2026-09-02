(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Ratchet — nested-module qualified-name resolution.

    Migrated from the standalone `checks/nested-module-resolution.js` script
    into the tezt suite (roadmap item 0.2's follow-up) so it runs under
    `dune test` like every other invariant here, rather than as a disconnected
    Node runtime invisible to `dune build`/`dune test`.

    Guards two CRITICAL findings raised in review round 1 of the
    sound-qualified-name-resolution task (that review.json was never
    committed to main — see briefs/sound-qualified-name-resolution-
    {intake,plan}.md for the surviving trail; the finding text below is
    preserved verbatim from it):

      arch_index.ml:359 (dropped edges) — resolve_module_root's multi-segment
        arm only ever reconstructed [Root__File]. A reference into a nested
        module of a single-unit library ([Foo.Bar.baz] where [Foo] IS the
        compilation unit and [Bar] a module inside it) matched nothing, fell
        to [Unknown], and was emitted as kind=MUST with callee_id=NULL — a
        resolver miss dressed as a proven external leaf.

      arch_index.ml:344 (wrong target) — worse, if some UNRELATED library
        happens to produce the unit [Foo__Bar], that same reference was
        stamped MUST at the other library's function, which the caller does
        not even link.

    Scenario A (no decoy) pins the first: the edge must be MUST to
    [aaa/foo.ml]'s [Bar.baz]. Scenario B adds the decoy library and pins the
    second: the edge must NEVER point at the decoy. With both readings of
    [Foo.Bar] live and no link information in a .cmt, the honest answer is
    MAY_TOP (UNKNOWN is not "pick one"), so B accepts MAY_TOP or a resolution
    to the linked library, and rejects anything naming the decoy. *)

open Arch_tezt

let dune_project = Fixture.dune_project

(* aaalib is (wrapped false) with a single foo.ml, so its compilation unit is
   literally [Foo] and [Bar] is a module INSIDE that one unit. There is no
   [Foo__Bar] unit for this library — that is the whole point. *)
let aaa_dune =
  ( "aaa/dune",
    "(library\n (name aaalib)\n (wrapped false)\n (modules foo)\n (flags (:standard -w \
     -a)))\n" )

let aaa_foo =
  ("aaa/foo.ml", "module Bar = struct\n  type t = string\n\n  let baz () : int = 99\nend\n")

let caller_dune =
  ( "callerlib/dune",
    "(library\n (name callerlib)\n (libraries aaalib)\n (modules c)\n (flags (:standard -w \
     -a)))\n" )

let caller_c = ("callerlib/c.ml", "let go () : int = Foo.Bar.baz ()\n")

(* The decoy: an unrelated WRAPPED library named foo whose bar.ml compiles to
   the unit [Foo__Bar]. callerlib does not list it in (libraries). *)
let decoy_dune =
  ("foo/dune", "(library\n (name foo)\n (modules bar)\n (flags (:standard -w -a)))\n")

let decoy_bar = ("foo/bar.ml", "let baz () : int = 1\n")

let scenario_a_files = [dune_project; aaa_dune; aaa_foo; caller_dune; caller_c]

let scenario_b_files =
  [dune_project; aaa_dune; aaa_foo; decoy_dune; decoy_bar; caller_dune; caller_c]

(* A multi-row match is a fixture bug, not a value to pick arbitrarily from —
   the same reasoning [go_call] below applies: a fixture that grows a second
   matching row must not silently assert about whichever one comes back
   first. *)
let fn_id conn ~mod_like ~names b ~label =
  let list = String.concat "," (List.map (Printf.sprintf "'%s'") names) in
  let rows =
    Db.rows conn
      (Printf.sprintf
         "SELECT f.id FROM functions f JOIN modules m ON m.id = f.module_id WHERE m.path LIKE \
          '%s' AND f.name IN (%s)"
         mod_like list)
  in
  match rows with
  | [] -> None
  | [[id]] -> Some (Db.to_string ~sql:"fn_id" id)
  | _ ->
      Batch.note b "%s: fn_id(%s, [%s]) matched %d rows, expected at most 1 — fixture is ambiguous"
        label mod_like list (List.length rows) ;
      None

(* Exactly one call row for [go] is demanded: a fixture whose caller grew a
   second call would otherwise silently assert about whichever row came back
   first. *)
let go_call conn ~label =
  let rows =
    Db.rows conn
      "SELECT ifnull(c.callee_id, -1), c.kind FROM calls c JOIN functions f ON f.id = \
       c.caller_id WHERE f.name = 'go'"
  in
  match rows with
  | [[id; kind]] ->
      let id = Db.to_string ~sql:"go_call id" id and kind = Db.to_string ~sql:"go_call kind" kind in
      (if id = "-1" then None else Some id), kind
  | _ ->
      Test.fail "expected exactly one call row for `go` in %s, got %d" label (List.length rows)

let register () =
  Test.register ~__FILE__ ~title:"cmt: a nested-module reference resolves to the linked unit"
    ~tags:["cmt"; "nested"; "qualified_name"]
  @@ fun () ->
  Batch.run (fun b ->
      (* Scenario A — nested module of a single-unit library, no decoy present. *)
      with_fixture ~name:"nested-qual-a" ~files:scenario_a_files @@ fun fixture ->
      let db = index fixture in
      Db.with_db db (fun conn ->
          let linked = fn_id conn ~mod_like:"%aaa/foo.ml" ~names:["Bar.baz"; "baz"] b ~label:"A" in
          if linked = None then
            Batch.note b "A: aaa/foo.ml Bar.baz is not indexed at all" ;
          let callee, kind = go_call conn ~label:"A" in
          Batch.check b
            ~msg:
              (Printf.sprintf
                 "A: go -> Foo.Bar.baz must not be kind=MUST with a NULL callee — aaa/foo.ml IS \
                  indexed and holds Bar.baz. A NULL-callee MUST reads downstream as a proven \
                  external leaf with no TOP marker — a dropped edge presented as a fact (review \
                  CRITICAL :359)")
            (not (kind = "MUST" && callee = None)) ;
          Batch.check b
            ~msg:
              (Printf.sprintf
                 "A: go -> Foo.Bar.baz resolved kind=%s callee_id=%s, expected MUST to aaa/foo.ml \
                  Bar.baz (%s). The root IS the compilation unit and Bar a module inside it; \
                  nothing about this reference is ambiguous"
                 kind
                 (Option.value callee ~default:"<none>")
                 (Option.value linked ~default:"<none>"))
            (kind = "MUST" && callee = linked)) ;
      (* Scenario B — same reference, plus an unrelated library that DOES emit
         Foo__Bar. *)
      with_fixture ~name:"nested-qual-b" ~files:scenario_b_files @@ fun fixture ->
      let db = index fixture in
      Db.with_db db (fun conn ->
          let linked = fn_id conn ~mod_like:"%aaa/foo.ml" ~names:["Bar.baz"; "baz"] b ~label:"B" in
          let decoy = fn_id conn ~mod_like:"%foo/bar.ml" ~names:["baz"] b ~label:"B" in
          (match linked, decoy with
          | None, _ -> Batch.note b "B: aaa/foo.ml Bar.baz is not indexed"
          | _, None -> Batch.note b "B: decoy foo/bar.ml baz is not indexed"
          | Some l, Some d when l = d -> Batch.note b "B: fixture bug — both baz resolved to one row"
          | Some linked, Some decoy ->
              (* Both preconditions hold — only now do the assertions below say
                 something true about an actual attribution, rather than about
                 a precondition failure dressed up as one. *)
              let callee, kind = go_call conn ~label:"B" in
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "B: go -> Foo.Bar.baz was attributed to foo/bar.ml baz (%s, kind=%s), a \
                      library callerlib does not link. The caller links only aaalib, whose \
                      foo.ml defines module Bar (%s) — review CRITICAL :344"
                     decoy kind linked)
                (callee <> Some decoy) ;
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "B: go -> Foo.Bar.baz is kind=MUST with callee_id=%s. Both readings of \
                      Foo.Bar name an indexed unit here, so a MUST to anything other than the \
                      linked aaalib (%s) is a guess presented as a proof"
                     (Option.value callee ~default:"<none>")
                     linked)
                (kind <> "MUST" || callee = Some linked) ;
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "B: go -> Foo.Bar.baz resolved kind=%s callee_id=%s. With two live readings \
                      the only honest answers are MAY_TOP (carrying the TOP frontier marker \
                      downstream) or a resolution to the linked library"
                     kind
                     (Option.value callee ~default:"<none>"))
                (kind = "MAY_TOP" || (kind = "MUST" && callee = Some linked))))) ;
  Lwt.return_unit
