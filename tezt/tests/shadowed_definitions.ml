(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Issue #41 / roadmap item 0.6: two top-level bindings of the same name in
    one compilation unit ("same-level shadowing") previously produced only
    ONE [functions] row — [INSERT OR REPLACE] on [UNIQUE(module_id, name)]
    silently dropped the earlier definition (cascading, via
    [ON DELETE CASCADE], to every row that referenced it), and both bodies'
    outbound calls, resolved post-hoc by (module, name), landed on whichever
    definition survived.

    The fix gives each same-level binding its own row: the LAST
    (source-order-final, i.e. live/reachable) binding keeps the bare name,
    every earlier one takes a [#N] suffix. This is the direction that matters
    most in this test file, and the one place a wrong choice hides
    undetected by a same-module-only test: a cross-module qualified call
    (module [B] calling [A.f]) can only ever spell the bare name, so the bare
    name MUST denote the live definition — never the shadowed one. *)

open Arch_tezt

let count db name =
  Db.int db (Printf.sprintf "SELECT count(*) FROM functions WHERE name = '%s'" name)

let callee_names db ~caller =
  Db.strings db
    (Printf.sprintf
       "SELECT f2.name FROM calls c \
        JOIN functions f1 ON f1.id = c.caller_id \
        JOIN functions f2 ON f2.id = c.callee_id \
        WHERE f1.name = '%s' ORDER BY f2.name"
       caller)

(* ------------------------------------------------------------------ *)
(* Fixture 1 — no collision: pins byte-identical-to-before naming when
   there is nothing to disambiguate. *)
(* ------------------------------------------------------------------ *)

let clean_files =
  [
    Fixture.dune_project;
    ("dune", "(library\n (name clean)\n (modules clean)\n (flags (:standard -w -32)))\n");
    ( "clean.ml",
      {ocaml|let helper (x : int) : int = x + 1
let f (x : int) : int = helper x
let use () : int = f 1
|ocaml} );
  ]

let register_clean () =
  Test.register ~__FILE__ ~title:"shadowed-definitions: no collision keeps the bare name"
    ~tags:["cmt"; "shadowing"]
  @@ fun () ->
  with_fixture ~name:"arch_tezt_shadow_clean" ~files:clean_files @@ fun fixture ->
  let db_path = index fixture in
  Db.with_db db_path (fun db ->
      Check.((count db "f" = 1) int ~error_msg:"clean.ml's 'f': %L row(s), expected %R") ;
      Check.((count db "f#1" = 0) int
               ~error_msg:"clean.ml's 'f' unexpectedly gained a #1 suffix: %L, expected %R") ;
      Check.((callee_names db ~caller:"f" = ["helper"]) (list string)
               ~error_msg:"'f' calls %L, expected %R")) ;
  Lwt.return_unit

(* ------------------------------------------------------------------ *)
(* Fixture 2 — same-module, same-level shadow: two top-level [f], each
   calling a distinct helper. Both must survive as distinct rows, each
   keeping its own outbound edges — not merely "no statement failures"
   (that gate already exists, from #37). *)
(* ------------------------------------------------------------------ *)

let shadow_files =
  [
    Fixture.dune_project;
    ("dune", "(library\n (name shadow)\n (modules shadow)\n (flags (:standard -w -32)))\n");
    ( "shadow.ml",
      {ocaml|let helper_one (x : int) : int = x + 1
let helper_two (x : int) : int = x + 2
let f (x : int) : int = helper_one x
let mid_caller (x : int) : int = f x
let f (x : int) : int = helper_two x
|ocaml} );
  ]

let register_shadow () =
  Test.register ~__FILE__
    ~title:"shadowed-definitions: same-level shadow keeps two rows with distinct edges (#41)"
    ~tags:["cmt"; "shadowing"]
  @@ fun () ->
  with_fixture ~name:"arch_tezt_shadow_shadow" ~files:shadow_files @@ fun fixture ->
  let db_path = index fixture in
  Db.with_db db_path (fun db ->
      (* two rows, not one merged row *)
      Check.((count db "f" = 1) int ~error_msg:"live 'f': %L row(s), expected %R") ;
      Check.((count db "f#1" = 1) int
               ~error_msg:"shadowed 'f#1': %L row(s), expected %R") ;
      (* the LAST binding (the one every caller — same-module or cross-module
         — actually reaches) keeps the bare name and its own edges *)
      Check.((callee_names db ~caller:"f" = ["helper_two"]) (list string)
               ~error_msg:
                 "bare 'f' (expected: the live, LAST binding) calls %L, expected %R — \
                  if this lists 'helper_one' the ordinal direction is inverted") ;
      (* the earlier (shadowed, dead) binding keeps ITS OWN edges too — not
         merged onto the survivor, and not dropped *)
      Check.((callee_names db ~caller:"f#1" = ["helper_one"]) (list string)
               ~error_msg:"shadowed 'f#1' calls %L, expected %R") ;
      (* the intra-module direction: 'mid_caller' is lexically BETWEEN the two
         'f' bindings, so it must resolve to the FIRST (shadowed) one, not the
         last — this is the inbound half of the same misattribution class #41
         fixes on the outbound side. A call target is named by the same
         Ident.stamp -> bind_name mapping build_binding_names produces, so
         this must land on 'f#1', never on 'f'. *)
      Check.((callee_names db ~caller:"mid_caller" = ["f#1"]) (list string)
               ~error_msg:
                 "'mid_caller' (defined between the two 'f' bindings) calls %L, expected \
                  %R — a resolution to 'f' means an intra-module call is attributed to \
                  the wrong (unrelated) definition")) ;
  Lwt.return_unit

(* ------------------------------------------------------------------ *)
(* Fixture 2b — three-way shadow: the #N ordinal scheme must stay coherent
   past a single collision. *)
(* ------------------------------------------------------------------ *)

let three_way_files =
  [
    Fixture.dune_project;
    ("dune", "(library\n (name shadow3)\n (modules shadow3)\n (flags (:standard -w -32)))\n");
    ( "shadow3.ml",
      {ocaml|let h1 (x : int) : int = x + 1
let h2 (x : int) : int = x + 2
let h3 (x : int) : int = x + 3
let f (x : int) : int = h1 x
let f (x : int) : int = h2 x
let f (x : int) : int = h3 x
|ocaml} );
  ]

let register_three_way () =
  Test.register ~__FILE__
    ~title:"shadowed-definitions: a 3-way same-level shadow numbers and attributes correctly (#41)"
    ~tags:["cmt"; "shadowing"]
  @@ fun () ->
  with_fixture ~name:"arch_tezt_shadow_3way" ~files:three_way_files @@ fun fixture ->
  let db_path = index fixture in
  Db.with_db db_path (fun db ->
      Check.((count db "f" = 1) int ~error_msg:"live 'f': %L row(s), expected %R") ;
      Check.((count db "f#1" = 1) int ~error_msg:"first shadowed 'f#1': %L row(s), expected %R") ;
      Check.((count db "f#2" = 1) int ~error_msg:"second shadowed 'f#2': %L row(s), expected %R") ;
      Check.((callee_names db ~caller:"f#1" = ["h1"]) (list string)
               ~error_msg:"'f#1' calls %L, expected %R") ;
      Check.((callee_names db ~caller:"f#2" = ["h2"]) (list string)
               ~error_msg:"'f#2' calls %L, expected %R") ;
      Check.((callee_names db ~caller:"f" = ["h3"]) (list string)
               ~error_msg:"bare 'f' (the live, last binding) calls %L, expected %R")) ;
  Lwt.return_unit

(* ------------------------------------------------------------------ *)
(* Fixture 2c — exposed/doc attribution: only the live (bare-named) row may
   be exposed, since only it corresponds to what an .mli entry describes. *)
(* ------------------------------------------------------------------ *)

let exposed_files =
  [
    Fixture.dune_project;
    ("dune", "(library\n (name shadowexp)\n (modules shadowexp)\n (flags (:standard -w -32)))\n");
    ("shadowexp.mli", "val f : int -> int\n");
    ( "shadowexp.ml",
      {ocaml|let helper_one (x : int) : int = x + 1
let helper_two (x : int) : int = x + 2
let f (x : int) : int = helper_one x
let f (x : int) : int = helper_two x
|ocaml} );
  ]

let exposed db name =
  Db.int_opt db (Printf.sprintf "SELECT exposed FROM functions WHERE name = '%s'" name)

let register_exposed () =
  Test.register ~__FILE__
    ~title:"shadowed-definitions: only the live binding is exposed via the .mli (#41)"
    ~tags:["cmt"; "shadowing"]
  @@ fun () ->
  with_fixture ~name:"arch_tezt_shadow_exposed" ~files:exposed_files @@ fun fixture ->
  let db_path = index fixture in
  Db.with_db db_path (fun db ->
      Check.((exposed db "f" = Some 1) (option int)
               ~error_msg:"live 'f': exposed = %L, expected %R") ;
      Check.((exposed db "f#1" = Some 0) (option int)
               ~error_msg:"shadowed 'f#1': exposed = %L, expected %R")) ;
  Lwt.return_unit

(* ------------------------------------------------------------------ *)
(* Fixture 2d — nested-module shadow: the ordinal mechanism must qualify
   the same way ordinary nested definitions already do. *)
(* ------------------------------------------------------------------ *)

let nested_files =
  [
    Fixture.dune_project;
    ("dune", "(library\n (name shadownest)\n (modules shadownest)\n (flags (:standard -w -32)))\n");
    ( "shadownest.ml",
      {ocaml|let h1 (x : int) : int = x + 1
let h2 (x : int) : int = x + 2

module Inner = struct
  let g (x : int) : int = h1 x
  let g (x : int) : int = h2 x
end
|ocaml} );
  ]

let register_nested () =
  Test.register ~__FILE__
    ~title:"shadowed-definitions: a nested-module same-level shadow is qualified and numbered (#41)"
    ~tags:["cmt"; "shadowing"]
  @@ fun () ->
  with_fixture ~name:"arch_tezt_shadow_nested" ~files:nested_files @@ fun fixture ->
  let db_path = index fixture in
  Db.with_db db_path (fun db ->
      Check.((count db "Inner.g" = 1) int ~error_msg:"live 'Inner.g': %L row(s), expected %R") ;
      Check.((count db "Inner.g#1" = 1) int
               ~error_msg:"shadowed 'Inner.g#1': %L row(s), expected %R") ;
      Check.((callee_names db ~caller:"Inner.g" = ["h2"]) (list string)
               ~error_msg:"bare 'Inner.g' calls %L, expected %R") ;
      Check.((callee_names db ~caller:"Inner.g#1" = ["h1"]) (list string)
               ~error_msg:"shadowed 'Inner.g#1' calls %L, expected %R")) ;
  Lwt.return_unit

(* ------------------------------------------------------------------ *)
(* Fixture 3 — cross-module: the fixture that would have caught the
   previous (unfixed / wrongly-directed) draft. Module [A] has the same
   same-level shadow as fixture 2; module [B] calls [A.f] by qualified
   name. A cross-module caller can only ever spell the bare name — so this
   is the only fixture that actually exercises the ordinal-direction
   decision end to end. *)
(* ------------------------------------------------------------------ *)

let cross_module_files =
  [
    Fixture.dune_project;
    ("dune", "(library\n (name xshadow)\n (modules a b)\n (flags (:standard -w -32)))\n");
    ( "a.ml",
      {ocaml|let helper_one (x : int) : int = x + 1
let helper_two (x : int) : int = x + 2
let f (x : int) : int = helper_one x
let f (x : int) : int = helper_two x
|ocaml} );
    ("b.ml", "let use_a (x : int) : int = A.f x\n");
  ]

let register_cross_module () =
  Test.register ~__FILE__
    ~title:
      "shadowed-definitions: a cross-module qualified call reaches the live \
       definition, not the shadowed one (#41)"
    ~tags:["cmt"; "shadowing"]
  @@ fun () ->
  with_fixture ~name:"arch_tezt_shadow_cross" ~files:cross_module_files @@ fun fixture ->
  let db_path = index fixture in
  Db.with_db db_path (fun db ->
      Check.((count db "f" = 1) int ~error_msg:"a.ml's live 'f': %L row(s), expected %R") ;
      Check.((count db "f#1" = 1) int
               ~error_msg:"a.ml's shadowed 'f#1': %L row(s), expected %R") ;
      (* Resolution-liveness check: B.use_a calls A.f by qualified name, which
         can only ever spell the bare "f" (resolve_qualified has no ordinal
         awareness) — so this can only ever return ["f"] or [] (unresolved).
         It does NOT by itself distinguish the ordinal direction: an inverted
         implementation would still name the bare row "f" and this assertion
         would still pass. The direction is actually pinned by the NEXT
         assertion below, which confirms the resolved row is genuinely the
         live one (still calling helper_two, not helper_one). *)
      Check.((callee_names db ~caller:"use_a" = ["f"]) (list string)
               ~error_msg:
                 "cross-module caller 'use_a' resolved A.f to %L, expected %R (the bare \
                  name) — an empty result means qualified cross-module resolution is \
                  broken") ;
      (* THE load-bearing direction check: if the ordinal direction were
         inverted, the bare-named row would be the FIRST (shadowed) binding,
         which calls helper_one, not helper_two — this assertion is what
         actually fails under an inverted implementation. *)
      Check.((callee_names db ~caller:"f" = ["helper_two"]) (list string)
               ~error_msg:"a.ml's bare 'f' calls %L, expected %R")) ;
  Lwt.return_unit

let register () =
  register_clean () ;
  register_shadow () ;
  register_three_way () ;
  register_exposed () ;
  register_nested () ;
  register_cross_module ()
