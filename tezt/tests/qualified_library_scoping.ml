(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Ratchet — qualified references scope to the library they name.

    Sibling of {!Nested_module_qualification}, which pins the shapes where one
    reading of [Root.File] is a DECOY the caller does not link. This file pins
    the complementary shape, which that file deliberately does not cover: two
    libraries the caller legitimately links BOTH of, each owning a module of the
    same basename. There is no decoy here and nothing unlinked — both candidates
    are real, linked, and correct for their own reference, so "reject the one
    that is not linked" cannot decide it.

    Lives in tezt rather than as a standalone [checks/*.js] script on purpose:
    this repository already migrated its soundness ratchets off that runtime
    (see the comment at .github/workflows/ci.yml, and the header of
    {!Nested_module_qualification}) precisely so they run under [dune test] in
    CI like every other invariant. A ratchet nothing runs is not a ratchet.

    {1 Scenario A — cross-library homonym (FR-001)}

    [liba] and [libb] each own an [api.ml] defining [run]; the caller links both
    and calls each explicitly. Today resolution keys on the capitalised file
    BASENAME ("Api") in a project-wide last-writer-wins table, so the owning
    library is erased and BOTH references resolve to whichever [api.ml] was
    indexed last — one of them silently attributed to the wrong library, and
    stamped [MUST].

    The [MUST] is what makes this a soundness defect rather than a precision
    one: a NULL-free [MUST] is consumed downstream as a proven fact, so a
    reachability query can turn a real violation into a PASS. Measured at corpus
    scale by the error-channels review: 540 of 14452 proto_alpha function names
    are shared this way, so this is the common case, not a contrived one.

    {1 Scenario B — alias passthrough (FR-002), a REGRESSION GUARD}

    One wrapped library [foo] owning BOTH [bar.ml] (unit [Foo__Bar]) and a main
    module [foo.ml] whose whole content is [module Bar = Bar] (unit [Foo]). Both
    readings of [Foo.Bar.baz] are live and both name THIS library, so scenario
    A's reasoning does not apply either.

    This passes today and must keep passing: the abandoned [rebase/sound-qual]
    branch broke exactly this case to MAY_TOP/NULL while fixing scenario A, and
    that regression (repo-wide MAY_TOP 660 -> 875) is what made its round 2 a
    NO-GO. What decides it is that an alias defines no function of its own, so
    only the [Foo__Bar] reading has a row to resolve against.

    Note for anyone tempted to decide these on [cmt_imports] interface digests
    (the abandoned branch's approved round-3 design): it does not work. The
    caller imports ALL of [Foo], [Foo__] and [Foo__Bar], because it genuinely
    depends on the alias AND on the implementation the alias forwards to.
    Verified with ocamlobjinfo — briefs/qualified-unit-resolution-research.md
    Finding 3. *)

open Arch_tezt

let dune_project = Fixture.dune_project

(* ------------------------------------------------------------------ *)
(* Scenario A — two linked libraries, same module basename            *)
(* ------------------------------------------------------------------ *)

let liba_dune =
  ("liba/dune", "(library\n (name liba)\n (modules api)\n (flags (:standard -w -a)))\n")

let liba_api = ("liba/api.ml", "let run () : int = 1\n")

let libb_dune =
  ("libb/dune", "(library\n (name libb)\n (modules api)\n (flags (:standard -w -a)))\n")

let libb_api = ("libb/api.ml", "let run () : int = 2\n")

(* The caller links BOTH and names each library explicitly. Each call site has
   exactly one correct answer, and they are different files. *)
let homonym_caller_dune =
  ( "callerlib/dune",
    "(library\n (name callerlib)\n (libraries liba libb)\n (modules c)\n (flags (:standard -w \
     -a)))\n" )

let homonym_caller_c =
  ("callerlib/c.ml", "let from_a () : int = Liba.Api.run ()\nlet from_b () : int = Libb.Api.run ()\n")

let scenario_a_files =
  [dune_project; liba_dune; liba_api; libb_dune; libb_api; homonym_caller_dune; homonym_caller_c]

(* ------------------------------------------------------------------ *)
(* Scenario B — one library, alias main module + real implementation   *)
(* ------------------------------------------------------------------ *)

let alias_lib_dune =
  ("foolib/dune", "(library\n (name foo)\n (modules foo bar)\n (flags (:standard -w -a)))\n")

(* bar.ml -> unit Foo__Bar. The real implementation. *)
let alias_bar = ("foolib/bar.ml", "let baz () : int = 42\n")

(* foo.ml is the library's MAIN module -> unit Foo. A pure alias: it defines no
   function of its own, which is exactly what breaks the tie. *)
let alias_foo = ("foolib/foo.ml", "module Bar = Bar\n")

let alias_caller_dune =
  ( "aliascaller/dune",
    "(library\n (name aliascaller)\n (libraries foo)\n (modules d)\n (flags (:standard -w -a)))\n"
  )

let alias_caller_d = ("aliascaller/d.ml", "let go () : int = Foo.Bar.baz ()\n")

let scenario_b_files =
  [dune_project; alias_lib_dune; alias_bar; alias_foo; alias_caller_dune; alias_caller_d]

(* ------------------------------------------------------------------ *)
(* helpers — deliberately refuse to guess when a fixture is ambiguous  *)
(* ------------------------------------------------------------------ *)

(* A multi-row match is a fixture bug, not a value to pick arbitrarily from: a
   fixture that grows a second matching row must not silently assert about
   whichever one came back first. Same reasoning as
   {!Nested_module_qualification.fn_id}, whose convention this follows. *)
let fn_id conn ~mod_like ~name b ~label =
  let rows =
    Db.rows conn
      (Printf.sprintf
         "SELECT f.id FROM functions f JOIN modules m ON m.id = f.module_id WHERE m.path LIKE \
          '%s' AND f.name = '%s'"
         mod_like name)
  in
  match rows with
  | [] -> None
  | [[id]] -> Some (Db.to_string ~sql:"fn_id" id)
  | _ ->
      Batch.note b "%s: fn_id(%s, %s) matched %d rows, expected at most 1 — fixture is ambiguous"
        label mod_like name (List.length rows) ;
      None

(* The (callee_id, kind) of the single call made by [caller_fn]. Demanding
   exactly one row keeps the assertions about a real attribution rather than
   about whichever row sorted first. *)
let single_call conn ~caller_fn ~label =
  let rows =
    Db.rows conn
      (Printf.sprintf
         "SELECT ifnull(c.callee_id, -1), c.kind FROM calls c JOIN functions f ON f.id = \
          c.caller_id WHERE f.name = '%s'"
         caller_fn)
  in
  match rows with
  | [[id; kind]] ->
      let id = Db.to_string ~sql:"call id" id
      and kind = Db.to_string ~sql:"call kind" kind in
      ((if id = "-1" then None else Some id), kind)
  | _ ->
      Test.fail "expected exactly one call row for `%s` in %s, got %d" caller_fn label
        (List.length rows)

let show = Option.value ~default:"<none>"

let register () =
  Test.register ~__FILE__
    ~title:"cmt: a qualified reference resolves within the library it names"
    ~tags:["cmt"; "qualified_name"; "library_scoping"]
  @@ fun () ->
  Batch.run (fun b ->
      (* Scenario A — the cross-library homonym. *)
      with_fixture ~name:"qual-scope-a" ~files:scenario_a_files @@ fun fixture ->
      let db = index fixture in
      Db.with_db db (fun conn ->
          let in_a = fn_id conn ~mod_like:"%liba/api.ml" ~name:"run" b ~label:"A" in
          let in_b = fn_id conn ~mod_like:"%libb/api.ml" ~name:"run" b ~label:"A" in
          match (in_a, in_b) with
          | None, _ -> Batch.note b "A: liba/api.ml run is not indexed at all"
          | _, None -> Batch.note b "A: libb/api.ml run is not indexed at all"
          | Some a, Some b_id when a = b_id ->
              Batch.note b "A: fixture bug — both run functions resolved to one row"
          | Some a_fn, Some b_fn ->
              (* Only now does an assertion say something about a real
                 attribution rather than about a precondition failure. *)
              let callee_a, kind_a = single_call conn ~caller_fn:"from_a" ~label:"A" in
              let callee_b, kind_b = single_call conn ~caller_fn:"from_b" ~label:"A" in
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "A: from_a -> Liba.Api.run resolved to %s (kind=%s), expected liba/api.ml \
                      run (%s). Both libraries are LINKED and each reference names its own \
                      explicitly, so nothing here is ambiguous — an attribution to libb is the \
                      basename key erasing which library owns the file"
                     (show callee_a) kind_a a_fn)
                (callee_a = Some a_fn) ;
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "A: from_b -> Libb.Api.run resolved to %s (kind=%s), expected libb/api.ml \
                      run (%s)"
                     (show callee_b) kind_b b_fn)
                (callee_b = Some b_fn) ;
              (* The confidence half. A wrong MUST is worse than an honest
                 MAY_TOP: it is consumed downstream as proof, so it can turn a
                 real violation into a PASS. If the resolver cannot tell these
                 apart it must say so, not guess. *)
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "A: from_a -> Liba.Api.run is kind=MUST pointing at %s, which is not \
                      liba/api.ml run (%s). A MUST is asserted as proven; guessing here makes a \
                      reachability query answer PASS on a real violation"
                     (show callee_a) a_fn)
                (kind_a <> "MUST" || callee_a = Some a_fn)) ;
      (* Scenario B — alias passthrough. Green today; guards the abandoned
         branch's round-2 regression. *)
      with_fixture ~name:"qual-scope-b" ~files:scenario_b_files @@ fun fixture ->
      let db = index fixture in
      Db.with_db db (fun conn ->
          let impl = fn_id conn ~mod_like:"%foolib/bar.ml" ~name:"baz" b ~label:"B" in
          match impl with
          | None -> Batch.note b "B: foolib/bar.ml baz is not indexed at all"
          | Some impl ->
              let callee, kind = single_call conn ~caller_fn:"go" ~label:"B" in
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "B: go -> Foo.Bar.baz resolved kind=%s callee_id=%s, expected MUST to \
                      foolib/bar.ml baz (%s). foo.ml is a pure alias defining no function, so \
                      only the Foo__Bar reading has a row to resolve against — degrading this to \
                      MAY_TOP is the round-2 regression of rebase/sound-qual, not honest caution"
                     kind (show callee) impl)
                (kind = "MUST" && callee = Some impl))) ;
  Lwt.return_unit

(* ------------------------------------------------------------------ *)
(* FR-007 — the shapes v1 of the spec omitted                          *)
(* ------------------------------------------------------------------ *)

(* Scenario C — (wrapped false), the DISCLOSED RESIDUAL.

   For an unwrapped library dune's compiled unit name IS the capitalised
   basename, so there is no library prefix to recover and unit-keying
   disambiguates nothing. FR-001's defect therefore PERSISTS here, and this test
   pins that boundary deliberately rather than leaving it to be discovered as
   "the fix sometimes doesn't work".

   Both libraries are (wrapped false) and both own an [Api] module, so both
   compile to a unit literally named [Api]. The registry maps that one name to
   two distinct paths; two distinct functions answer to it; and FR-003 therefore
   degrades to ⊤ rather than guessing. That is the honest outcome — the wrong
   MUST is gone — but it is NOT resolution, and calling it one would overstate
   what this change achieves. *)
let unwrapped_a_dune =
  ("uwa/dune", "(library\n (name uwa)\n (wrapped false)\n (modules api)\n (flags (:standard -w -a)))\n")

let unwrapped_a_api = ("uwa/api.ml", "let run () : int = 1\n")

let unwrapped_b_dune =
  ("uwb/dune", "(library\n (name uwb)\n (wrapped false)\n (modules api)\n (flags (:standard -w -a)))\n")

let unwrapped_b_api = ("uwb/api.ml", "let run () : int = 2\n")

let unwrapped_caller_dune =
  ( "uwcaller/dune",
    "(library\n (name uwcaller)\n (libraries uwa uwb)\n (modules e)\n (flags (:standard -w -a)))\n"
  )

let unwrapped_caller_e = ("uwcaller/e.ml", "let go () : int = Api.run ()\n")

let scenario_c_files =
  [
    dune_project; unwrapped_a_dune; unwrapped_a_api; unwrapped_b_dune; unwrapped_b_api;
    unwrapped_caller_dune; unwrapped_caller_e;
  ]

let register_unwrapped_residual () =
  Test.register ~__FILE__
    ~title:"cmt: two (wrapped false) libraries sharing a module name degrade to ⊤, never a guess"
    ~tags:["cmt"; "qualified_name"; "library_scoping"; "residual"]
  @@ fun () ->
  Batch.run (fun b ->
      with_fixture ~name:"qual-scope-c" ~files:scenario_c_files @@ fun fixture ->
      let db = index fixture in
      Db.with_db db (fun conn ->
          let a = fn_id conn ~mod_like:"%uwa/api.ml" ~name:"run" b ~label:"C" in
          let bb = fn_id conn ~mod_like:"%uwb/api.ml" ~name:"run" b ~label:"C" in
          match (a, bb) with
          | None, _ | _, None ->
              Batch.note b "C: one of the two unwrapped Api.run functions is not indexed"
          | Some _, Some _ ->
              let callee, kind = single_call conn ~caller_fn:"go" ~label:"C" in
              (* The boundary this pins: unit-keying cannot separate these,
                 because for (wrapped false) the unit name IS "Api" for both.
                 What it MUST NOT do is pick one and call it MUST. *)
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "C: go -> Api.run is kind=%s callee_id=%s. Two (wrapped false) libraries \
                      both compile a unit literally named Api, so nothing distinguishes them — \
                      a MUST here would be a coin flip presented as a proof"
                     kind (show callee))
                (kind <> "MUST") ;
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "C: go -> Api.run degraded to kind=%s but callee_id=%s is set. An \
                      unresolvable reference must carry no callee, or downstream reads it as \
                      resolved"
                     kind (show callee))
                (callee = None))) ;
  Lwt.return_unit

(* ------------------------------------------------------------------ *)
(* S7 — the cross-library RE-EXPORT FACADE                             *)
(* ------------------------------------------------------------------ *)

(* Scenario D — a reference that shares NO PREFIX with the unit it names.

   Found on proto_alpha, not by review. Scenarios A–C all assume the reference
   spells a prefix of the defining unit's dune name, so enumerating "__"-joins
   of prefixes covers them. A re-export facade breaks that assumption outright:

     reference:      Facade.Protocol.Script_int.of_zint
     defining unit:  Rawlib__Script_int              (rawlib/script_int.ml)

   [facade] re-exports the whole of [rawlib] through a nested module [Protocol],
   exactly as [tezos_protocol_alpha] re-exports [tezos_raw_protocol_alpha]. The
   two names have no common prefix, so no prefix reading can ever bridge them
   and the reference falls through to "proven external leaf" — a NULL-free MUST
   into a library that IS in the index. Measured cost of not bridging it, before
   the second resolution tier existed: 2385 lost resolutions on proto_alpha,
   including src/proto_alpha/lib_protocol/script_interpreter.ml.

   This is the shape that makes the facade tier necessary, so it is pinned here
   rather than left to the next corpus run to rediscover. Note what it must NOT
   become: the old bare-segment lookup keyed one basename to ONE path
   last-writer-wins, which is scenario A's defect. Here a bare segment maps to
   every unit that could define it and the function table still arbitrates — so
   scenario A stays green, and a genuine two-answer case still degrades to ⊤
   (scenario C). *)
let facade_raw_dune =
  ("rawlib/dune", "(library\n (name rawlib)\n (modules script_int)\n (flags (:standard -w -a)))\n")

let facade_raw_impl = ("rawlib/script_int.ml", "let of_zint (n : int) : int = n\n")

(* The facade's main module re-exports the whole library under a nested name.
   It defines no function of its own, so no reading rooted at [Facade] has a
   row to resolve against. *)
let facade_dune =
  ( "facadelib/dune",
    "(library\n (name facade)\n (libraries rawlib)\n (modules facade)\n (flags (:standard -w \
     -a)))\n" )

let facade_impl = ("facadelib/facade.ml", "module Protocol = Rawlib\n")

let facade_caller_dune =
  ( "facadecaller/dune",
    "(library\n (name facadecaller)\n (libraries facade)\n (modules f)\n (flags (:standard -w \
     -a)))\n" )

let facade_caller_f =
  ("facadecaller/f.ml", "let go () : int = Facade.Protocol.Script_int.of_zint 1\n")

let scenario_d_files =
  [
    dune_project; facade_raw_dune; facade_raw_impl; facade_dune; facade_impl;
    facade_caller_dune; facade_caller_f;
  ]

let register_reexport_facade () =
  Test.register ~__FILE__
    ~title:"cmt: a reference through a cross-library re-export facade resolves to the real unit"
    ~tags:["cmt"; "qualified_name"; "library_scoping"; "facade"]
  @@ fun () ->
  Batch.run (fun b ->
      with_fixture ~name:"qual-scope-d" ~files:scenario_d_files @@ fun fixture ->
      let db = index fixture in
      Db.with_db db (fun conn ->
          let impl = fn_id conn ~mod_like:"%rawlib/script_int.ml" ~name:"of_zint" b ~label:"D" in
          match impl with
          | None -> Batch.note b "D: rawlib/script_int.ml of_zint is not indexed at all"
          | Some impl ->
              let callee, kind = single_call conn ~caller_fn:"go" ~label:"D" in
              (* The resolution half. Leaving this unresolved is not caution:
                 the callee is IN the index, so an unresolved MUST here is a
                 proof-shaped edge into a body the graph does have. *)
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "D: go -> Facade.Protocol.Script_int.of_zint resolved to %s (kind=%s), \
                      expected rawlib/script_int.ml of_zint (%s). The reference shares no prefix \
                      with the unit Rawlib__Script_int, so prefix readings alone cannot reach \
                      it — and the callee IS indexed, so failing to reach it emits a NULL MUST \
                      into a library the graph contains"
                     (show callee) kind impl)
                (callee = Some impl) ;
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "D: go -> Facade.Protocol.Script_int.of_zint is kind=%s, expected MUST. \
                      Exactly one indexed unit ends in Script_int and exactly one function in it \
                      answers to of_zint, so there is nothing to be uncertain about here; ⊤ \
                      belongs to the two-answer case (scenario C), not to this one"
                     kind)
                (kind = "MUST"))) ;
  Lwt.return_unit
