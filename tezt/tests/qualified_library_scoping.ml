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

(* The [top_reason] of the single call made by [caller_fn]. Schema 1.9's entire
   observable content is one new member of this vocabulary, and nothing asserted
   it: mutating the resolver to stamp "module_param" on every ambiguous row left
   the whole suite green. A version bump whose only content is a value nobody
   checks is a bump nobody can rely on. *)
let single_call_reason conn ~caller_fn ~label =
  let rows =
    Db.rows conn
      (Printf.sprintf
         "SELECT ifnull(c.top_reason, '<null>') FROM calls c JOIN functions f ON f.id = \
          c.caller_id WHERE f.name = '%s'"
         caller_fn)
  in
  match rows with
  | [[r]] -> Db.to_string ~sql:"top_reason" r
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
                (callee = None) ;
              (* Schema 1.9's one new vocabulary member. Without this the whole
                 version bump is unobservable to the suite. *)
              let reason = single_call_reason conn ~caller_fn:"go" ~label:"C" in
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "C: go -> Api.run carries top_reason=%s, expected 'ambiguous_unit'. Two \
                      indexed units answer to this name; saying so is the entire point of the \
                      1.9 vocabulary member, and any other reason misattributes the cause"
                     reason)
                (reason = "ambiguous_unit"))) ;
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
   the second resolution tier existed: 1646 lost resolutions on
   proto_alpha/lib_protocol (26 762 resolved with the tier, 25 116 without,
   measured on this tree). An earlier version of this comment said 2385, which
   came from a wider corpus scope and a set-diff that counts a re-target as a
   loss; it reproduces nowhere.

   GREEN ON origin/main, and that matters: unlike scenarios A, C, E, G and H,
   this one is NOT a guarantee this change adds. It guards a regression the
   BRANCH introduced at 9896fdd, when removing the bare-segment lookup also
   removed the only thing bridging a re-export facade. It pins a restoration,
   not a fix.

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

(* ------------------------------------------------------------------ *)
(* S8 — the two shapes adversarial review found the facade tier opened  *)
(* ------------------------------------------------------------------ *)

(* Scenario E — the homonym whose definition arrives through [include].

   Scenario A passes only because both [api.ml] files define [run], which
   forces the prefix tier to answer. Move the definition behind an [include]
   and the prefix tier reaches ZERO function ids for [Liba.Api.run] — the unit
   is right there and indexed, only the row is elsewhere. The first version of
   the facade tier fell back on exactly that condition and handed the reference
   to the OTHER library:

     Liba.Api.run  ->  libb/api.ml:run   MUST

   which is scenario A verbatim with one word changed. Scenario A passed only
   because both api.ml files define [run], forcing the prefix tier to answer.

   SCOPE OF THIS TEST, narrowed after round-2 review. It pins the DEPTH-2 case
   only: [Ginca.Api.run], where the reference stops at the compilation unit. It
   does NOT establish the general property, and its header used to claim it did
   — a reference qualified one level deeper walked around the first gate
   entirely. That shape is {!register_nested_include_homonym} (scenario G), and
   it is what the anchor-depth gate exists for. *)
let inc_a_dune =
  ( "inca/dune",
    "(library\n (name inca)\n (modules api base_impl)\n (flags (:standard -w -a)))\n" )

let inc_a_base = ("inca/base_impl.ml", "let run () : int = 1\n")

(* The definition is reachable but not a row of [inca/api.ml] itself. *)
let inc_a_api = ("inca/api.ml", "include Base_impl\n")

let inc_b_dune =
  ("incb/dune", "(library\n (name incb)\n (modules api)\n (flags (:standard -w -a)))\n")

let inc_b_api = ("incb/api.ml", "let run () : int = 2\n")

let inc_caller_dune =
  ( "inccaller/dune",
    "(library\n (name inccaller)\n (libraries inca incb)\n (modules g)\n (flags (:standard -w \
     -a)))\n" )

let inc_caller_g =
  ("inccaller/g.ml", "let from_a () : int = Inca.Api.run ()\nlet from_b () : int = Incb.Api.run ()\n")

let scenario_e_files =
  [dune_project; inc_a_dune; inc_a_base; inc_a_api; inc_b_dune; inc_b_api;
   inc_caller_dune; inc_caller_g]

let register_include_homonym () =
  Test.register ~__FILE__
    ~title:"cmt: an include-defined homonym never resolves into the other library"
    ~tags:["cmt"; "qualified_name"; "library_scoping"; "facade"]
  @@ fun () ->
  Batch.run (fun b ->
      with_fixture ~name:"qual-scope-e" ~files:scenario_e_files @@ fun fixture ->
      let db = index fixture in
      Db.with_db db (fun conn ->
          let wrong = fn_id conn ~mod_like:"%incb/api.ml" ~name:"run" b ~label:"E" in
          match wrong with
          | None -> Batch.note b "E: incb/api.ml run is not indexed at all"
          | Some wrong ->
              let callee, kind = single_call conn ~caller_fn:"from_a" ~label:"E" in
              (* The whole point. Not "resolves correctly" — resolving through
                 [include] is a separate capability this change does not claim.
                 What must hold is that it never lands in the WRONG library. *)
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "E: from_a -> Inca.Api.run resolved to %s (kind=%s), which is incb/api.ml \
                      run (%s) — the other library. inca/api.ml IS indexed and [Inca__Api] is the \
                      DEEPEST reading of this reference, so the prefix tier has identified the \
                      segment and the facade tier must not re-interpret it. (This is the depth-2 \
                      guarantee only — see scenario G for deeper references, and the residuals F \
                      and J for what is still open.)"
                     (show callee) kind wrong)
                (callee <> Some wrong))) ;
  Lwt.return_unit

(* Scenario F — DISCLOSED RESIDUAL, pinned and NOT endorsed.

   A reference rooted entirely outside the index — [Stdlib.Buffer.add_string],
   [Unix.*], a vendored duplicate, or any library the caller does not link —
   still resolves to a local module of the same basename, as a MUST. No reading
   of [Stdlib.Buffer] names an indexed unit, so there is no anchor, every
   segment is fair game and the facade tier fires.

   This is ONE OF TWO shapes in the same hole. The other has an indexed root
   and is pinned separately by {!register_aliased_nested_residual} (scenario
   J); an earlier version of this comment described the residual as
   "rooted outside the index" only, which was narrower than the truth.

   This behaves identically on [origin/main]: retained, not introduced. It is
   pinned here rather than described in prose because a comment does not stop
   the next reader taking the green for a guarantee — they will read the test
   list, not the note. When someone closes this, this test fails and makes them
   decide deliberately instead of believing they fixed a bug.

   The fix needs LINKAGE evidence — the caller's own `.cmt` import list, which
   names the unit the reference actually reaches and does not name the homonym.
   Not captured today; see briefs/linkage-evidence-followup.md. The tempting
   cheap conjunct (require some prefix reading to name an indexed unit) was
   implemented and measured: it costs 1627 correct resolutions on
   proto_alpha/lib_protocol, because a facade library is routinely not indexed
   at the scope being analysed. *)
let unlinked_lib_dune =
  ("unlmylib/dune", "(library\n (name unlmylib)\n (modules buffer)\n (flags (:standard -w -a)))\n")

let unlinked_lib_buffer = ("unlmylib/buffer.ml", "let add_string (_ : int) (_ : string) = ()\n")

(* Does NOT link unlmylib. Its Buffer is Stdlib's. *)
let unlinked_user_dune =
  ("unluser/dune", "(library\n (name unluser)\n (modules u)\n (flags (:standard -w -a)))\n")

let unlinked_user_u =
  ( "unluser/u.ml",
    "let go () : string =\n\
    \  let b = Buffer.create 16 in\n\
    \  Buffer.add_string b \"x\" ;\n\
    \  Buffer.contents b\n" )

let scenario_f_files =
  [dune_project; unlinked_lib_dune; unlinked_lib_buffer; unlinked_user_dune; unlinked_user_u]

let register_unlinked_residual () =
  Test.register ~__FILE__
    ~title:
      "cmt: a reference rooted outside the index still binds a local homonym — pinned, not endorsed"
    ~tags:["cmt"; "qualified_name"; "library_scoping"; "residual"]
  @@ fun () ->
  Batch.run (fun b ->
      with_fixture ~name:"qual-scope-f" ~files:scenario_f_files @@ fun fixture ->
      let db = index fixture in
      Db.with_db db (fun conn ->
          let local = fn_id conn ~mod_like:"%unlmylib/buffer.ml" ~name:"add_string" b ~label:"F" in
          match local with
          | None -> Batch.note b "F: unlmylib/buffer.ml add_string is not indexed at all"
          | Some local ->
              let rows =
                Db.rows conn
                  "SELECT ifnull(c.callee_id, -1) FROM calls c WHERE c.callee_name = \
                   'Stdlib.Buffer.add_string'"
              in
              match rows with
              | [[id]] ->
                  let id = Db.to_string ~sql:"F callee" id in
                  (* Asserting the DEFECT. If this ever fails, the residual has
                     been closed and this test is what tells you so — delete it
                     then, deliberately, rather than discovering the change in a
                     corpus diff six months later. *)
                  Batch.check b
                    ~msg:
                      (Printf.sprintf
                         "F: Stdlib.Buffer.add_string resolved to %s, expected the local \
                          unlmylib/buffer.ml add_string (%s). This test pins a KNOWN DEFECT that \
                          also reproduces on origin/main; a change here is good news but must be \
                          deliberate — update this test and its comment together"
                         id local)
                    (id = local)
              | _ ->
                  Batch.note b "F: expected exactly one Stdlib.Buffer.add_string call row, got %d"
                    (List.length rows))) ;
  Lwt.return_unit

(* ------------------------------------------------------------------ *)
(* Round-2 review — the shapes the first gate still let through         *)
(* ------------------------------------------------------------------ *)

(* Scenario G — scenario E, one qualification level deeper.

   The first gate asked only whether the DEEPEST reading named an indexed
   unit. Insert a nested module and the deepest reading is
   [Ginca__Api__Inner], which names nothing — so the gate opened and the tier
   re-interpreted segment [Api], the very segment the prefix tier had already
   identified, against every library owning an [Api]:

     Ginca.Api.Inner.run  ->  gincb/api.ml  MUST

   Scenario E therefore did NOT establish the general property its header
   claimed; it established it for depth-2 references only. The gate now anchors
   on the deepest reading that names an indexed unit and lets the facade tier
   use only segments strictly deeper than it.

   Credit: found by adversarial review, not by this suite. *)
let g_a_dune =
  ("ginca/dune", "(library\n (name ginca)\n (modules api base_impl)\n (flags (:standard -w -a)))\n")

let g_a_base = ("ginca/base_impl.ml", "module Inner = struct let run () : int = 1 end\n")

let g_a_api = ("ginca/api.ml", "include Base_impl\n")

let g_b_dune = ("gincb/dune", "(library\n (name gincb)\n (modules api)\n (flags (:standard -w -a)))\n")

let g_b_api = ("gincb/api.ml", "module Inner = struct let run () : int = 2 end\n")

let g_caller_dune =
  ( "gcaller/dune",
    "(library\n (name gcaller)\n (libraries ginca gincb)\n (modules g)\n (flags (:standard -w \
     -a)))\n" )

let g_caller_g =
  ( "gcaller/g.ml",
    "let from_a () : int = Ginca.Api.Inner.run ()\nlet from_b () : int = Gincb.Api.Inner.run ()\n" )

let scenario_g_files =
  [dune_project; g_a_dune; g_a_base; g_a_api; g_b_dune; g_b_api; g_caller_dune; g_caller_g]

let register_nested_include_homonym () =
  Test.register ~__FILE__
    ~title:"cmt: a DEEPER include-defined homonym never resolves into the other library"
    ~tags:["cmt"; "qualified_name"; "library_scoping"; "facade"]
  @@ fun () ->
  Batch.run (fun b ->
      with_fixture ~name:"qual-scope-g" ~files:scenario_g_files @@ fun fixture ->
      let db = index fixture in
      Db.with_db db (fun conn ->
          let wrong = fn_id conn ~mod_like:"%gincb/api.ml" ~name:"Inner.run" b ~label:"G" in
          match wrong with
          | None -> Batch.note b "G: gincb/api.ml Inner.run is not indexed at all"
          | Some wrong ->
              let callee, kind = single_call conn ~caller_fn:"from_a" ~label:"G" in
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "G: from_a -> Ginca.Api.Inner.run resolved to %s (kind=%s), which is \
                      gincb/api.ml Inner.run (%s) — the other library. [Ginca__Api] IS an \
                      indexed unit, so segment [Api] is already identified and the facade tier \
                      must not re-interpret it. Gating on the deepest reading alone let this \
                      through, because [Ginca__Api__Inner] names nothing"
                     (show callee) kind wrong)
                (callee <> Some wrong))) ;
  Lwt.return_unit

(* Scenario H — [include_subdirs qualified], a shape no test covered and which
   this change fixes. Two libraries each own [sub/api.ml], compiled to
   [Isa__Sub__Api] and [Isb__Sub__Api]. On main the basename key erases the
   library and [Isa.Sub.Api.run] lands in [isb/]. Credit: adversarial review. *)
let h_a_dune =
  ("isa/dune", "(include_subdirs qualified)\n(library\n (name isa)\n (flags (:standard -w -a)))\n")

let h_a_api = ("isa/sub/api.ml", "let run () : int = 1\n")

let h_b_dune =
  ("isb/dune", "(include_subdirs qualified)\n(library\n (name isb)\n (flags (:standard -w -a)))\n")

let h_b_api = ("isb/sub/api.ml", "let run () : int = 2\n")

let h_caller_dune =
  ( "icaller/dune",
    "(library\n (name icaller)\n (libraries isa isb)\n (modules i)\n (flags (:standard -w -a)))\n" )

let h_caller_i =
  ( "icaller/i.ml",
    "let from_a () : int = Isa.Sub.Api.run ()\nlet from_b () : int = Isb.Sub.Api.run ()\n" )

let scenario_h_files =
  [
    ("dune-project", "(lang dune 3.7)\n"); h_a_dune; h_a_api; h_b_dune; h_b_api; h_caller_dune;
    h_caller_i;
  ]

let register_include_subdirs () =
  Test.register ~__FILE__
    ~title:"cmt: include_subdirs qualified — a nested module resolves within its own library"
    ~tags:["cmt"; "qualified_name"; "library_scoping"]
  @@ fun () ->
  Batch.run (fun b ->
      with_fixture ~name:"qual-scope-h" ~files:scenario_h_files @@ fun fixture ->
      let db = index fixture in
      Db.with_db db (fun conn ->
          let in_a = fn_id conn ~mod_like:"%isa/sub/api.ml" ~name:"run" b ~label:"H" in
          let in_b = fn_id conn ~mod_like:"%isb/sub/api.ml" ~name:"run" b ~label:"H" in
          match (in_a, in_b) with
          | None, _ | _, None -> Batch.note b "H: one of the two sub/api.ml run functions is absent"
          | Some a_fn, Some _ ->
              let callee, kind = single_call conn ~caller_fn:"from_a" ~label:"H" in
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "H: from_a -> Isa.Sub.Api.run resolved to %s (kind=%s), expected \
                      isa/sub/api.ml run (%s). Both libraries use (include_subdirs qualified) and \
                      own a sub/api.ml, so the compiled units are Isa__Sub__Api and Isb__Sub__Api \
                      — distinct, and the reference names one of them"
                     (show callee) kind a_fn)
                (callee = Some a_fn))) ;
  Lwt.return_unit

(* Scenario I — DISCLOSED RESIDUAL, the precision cost of the 1/2+/0 rule.

   A library main module that DEFINES [Bar] rather than aliasing it shadows the
   sibling [bar.ml] for every external reference, so [Hfoo.Bar.baz] is
   determinate in OCaml. The resolver sees two readings reaching two ids — unit
   [Hfoo] with a row [Bar.baz], unit [Hfoo__Bar] with a row [baz] — and calls
   that ambiguous. Main resolved it, correctly.

   Sound direction (⊤, not a wrong MUST) and vanishingly rare: exactly ONE
   [ambiguous_unit] row across proto_alpha's 73 588 calls, zero on
   octez-manager. Pinned rather than described so that closing it — by
   preferring the longest [__]-join that hits, say — is a deliberate edit.
   Note scenario B passes only because ITS main module is a pure alias defining
   no row; the moment it defines one, the tie-break inverts. Credit:
   adversarial review. *)
let i_lib_dune =
  ("hfoo/dune", "(library\n (name hfoo)\n (modules hfoo bar)\n (flags (:standard -w -a)))\n")

let i_lib_bar = ("hfoo/bar.ml", "let baz () : int = 2\n")

let i_lib_main = ("hfoo/hfoo.ml", "module Bar = struct let baz () : int = 1 end\n")

let i_caller_dune =
  ( "hcaller/dune",
    "(library\n (name hcaller)\n (libraries hfoo)\n (modules h)\n (flags (:standard -w -a)))\n" )

let i_caller_h = ("hcaller/h.ml", "let go () : int = Hfoo.Bar.baz ()\n")

let scenario_i_files =
  [dune_project; i_lib_dune; i_lib_bar; i_lib_main; i_caller_dune; i_caller_h]

let register_shadowing_residual () =
  Test.register ~__FILE__
    ~title:"cmt: a main module SHADOWING a sibling degrades to ⊤ — pinned, not endorsed"
    ~tags:["cmt"; "qualified_name"; "library_scoping"; "residual"]
  @@ fun () ->
  Batch.run (fun b ->
      with_fixture ~name:"qual-scope-i" ~files:scenario_i_files @@ fun fixture ->
      let db = index fixture in
      Db.with_db db (fun conn ->
          let callee, kind = single_call conn ~caller_fn:"go" ~label:"I" in
          (* Asserting a PRECISION LOSS against origin/main, which resolved this
             to hfoo/hfoo.ml Bar.baz. The direction is safe and the corpus cost
             is one row, but it is a real regression and must not be discovered
             later as a surprise. *)
          Batch.check b
            ~msg:
              (Printf.sprintf
                 "I: go -> Hfoo.Bar.baz is kind=%s callee=%s. This pins a KNOWN PRECISION LOSS: \
                  OCaml scoping makes the reference determinate (hfoo.ml's own Bar shadows \
                  bar.ml) and origin/main resolved it, but two readings reach two ids and the \
                  resolver calls that ambiguous. If this now resolves, the residual is closed — \
                  good news, but update this test and its comment deliberately"
                 kind (show callee))
            (kind = "MAY_TOP" && callee = None) ;
          let reason = single_call_reason conn ~caller_fn:"go" ~label:"I" in
          Batch.check b
            ~msg:
              (Printf.sprintf
                 "I: go -> Hfoo.Bar.baz carries top_reason=%s, expected 'ambiguous_unit'"
                 reason)
            (reason = "ambiguous_unit"))) ;
  Lwt.return_unit

(* Scenario J — DISCLOSED RESIDUAL, the half scenario F's description missed.

   F pins a reference rooted OUTSIDE the index. This one is rooted INSIDE it
   and leaks anyway:

     owner/owner.ml  = "module Submod = Base"   (an alias, defining no row)
     owner/base.ml   = the real definition
     other/submod.ml = a homonym, in a library the caller does NOT link
     caller          = Owner.Submod.f ()

   The root [Owner] is an indexed unit, the correct target [owner/base.ml] is
   indexed, and the reference still binds [other/submod.ml] as a NULL-free
   MUST. The anchor is [Owner] at depth 0, segment [Submod] is deeper, and
   below the anchor nothing constrains which library a bare segment may reach.

   Identical on [origin/main] — retained, not introduced — and materially more
   common in dune projects than F's [Stdlib] shape, since it is just an alias
   in a library's main module.

   Why it is not simply fixed: this is structurally IDENTICAL to scenario D,
   the legitimate cross-library facade — indexed root, deeper segment naming a
   unit in another library. D must resolve; J must not. The index alone cannot
   separate them, which is why the fix is the caller's [.cmt] import list
   (briefs/linkage-evidence-followup.md) and not a cleverer predicate over the
   data already here. Closing it will flip this test; that is the point.

   Credit: found by adversarial review, from a probe I had not written. *)
let j_owner_dune =
  ("jowner/dune", "(library\n (name jowner)\n (modules jowner base)\n (flags (:standard -w -a)))\n")

let j_owner_base = ("jowner/base.ml", "let f () : int = 1\n")

let j_owner_main = ("jowner/jowner.ml", "module Submod = Base\n")

let j_other_dune =
  ("jother/dune", "(library\n (name jother)\n (modules submod)\n (flags (:standard -w -a)))\n")

let j_other_submod = ("jother/submod.ml", "let f () : int = 2\n")

(* Links jowner ONLY. jother is in the index but not on this library's path. *)
let j_caller_dune =
  ( "jcaller/dune",
    "(library\n (name jcaller)\n (libraries jowner)\n (modules j)\n (flags (:standard -w -a)))\n" )

let j_caller_j = ("jcaller/j.ml", "let go () : int = Jowner.Submod.f ()\n")

let scenario_j_files =
  [dune_project; j_owner_dune; j_owner_base; j_owner_main; j_other_dune; j_other_submod;
   j_caller_dune; j_caller_j]

let register_aliased_nested_residual () =
  Test.register ~__FILE__
    ~title:
      "cmt: an aliased nested module can still bind an unlinked homonym — pinned, not endorsed"
    ~tags:["cmt"; "qualified_name"; "library_scoping"; "residual"]
  @@ fun () ->
  Batch.run (fun b ->
      with_fixture ~name:"qual-scope-j" ~files:scenario_j_files @@ fun fixture ->
      let db = index fixture in
      Db.with_db db (fun conn ->
          let unlinked = fn_id conn ~mod_like:"%jother/submod.ml" ~name:"f" b ~label:"J" in
          let correct = fn_id conn ~mod_like:"%jowner/base.ml" ~name:"f" b ~label:"J" in
          match (unlinked, correct) with
          | None, _ | _, None -> Batch.note b "J: one of the two f functions is not indexed"
          | Some unlinked, Some correct ->
              let callee, kind = single_call conn ~caller_fn:"go" ~label:"J" in
              (* Asserting the DEFECT, like F. If this fails, the residual has
                 been closed — verify the answer is now jowner/base.ml (%s) and
                 delete this scenario deliberately, together with F and the
                 paragraph in the resolver that disclaims both. *)
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "J: go -> Jowner.Submod.f resolved to %s (kind=%s), expected the UNLINKED \
                      jother/submod.ml f (%s). This pins a KNOWN DEFECT that also reproduces on \
                      origin/main: the correct answer is jowner/base.ml f (%s), reachable through \
                      the alias, but nothing below the anchor constrains which library a bare \
                      segment may reach. A change here is good news and must be deliberate"
                     (show callee) kind unlinked correct)
                (callee = Some unlinked))) ;
  Lwt.return_unit

(* Scenario K — DISCLOSED RESIDUAL: the two sites this change does NOT fix.

   specs/sound-qualified-name-resolution.md S4 names THREE resolution sites.
   This change fixes one — calls. Module dependencies and type usages still key
   on the capitalised file BASENAME in a last-writer-wins table
   ([arch_index.ml] module-dependency and type-usage sites), so the owning
   library is erased there exactly as it was for calls before this change.

   Reproduced with the branch's own binary, on a caller linking [liba] ONLY:

     module Alias = Liba.Api        -> module_deps target = libb/api.ml
     let use (x : Liba.Api.t) = x   -> type_usage  type_id = libb/api.ml : t

   This is NOT cosmetic. arch-rules builds its [forbid dep] verdict directly
   from module_deps.target_module, so on this fixture it reports:

     [ FAIL ] callerlib must not depend on libb   <- callerlib does NOT
     [ pass ] callerlib must not depend on liba   <- callerlib DOES

   A real architecture violation reports pass and a nonexistent one reports
   FAIL — the precise failure mode scenario A exists to eliminate, in the
   sibling channels the spec names.

   Identical on [origin/main]: retained, not introduced. It is pinned here
   because an earlier revision of this branch shipped nine green scoping tests
   against a spec claiming three sites, with no test and no prose saying two of
   them were untouched — which reads as "all three are fixed". Found by
   adversarial review; disclosing it was the review's recommendation and the
   right call, since re-keying [type_lookup] on (path, name) and routing both
   sites through [unit_readings] is its own slice with its own corpus
   validation.

   When that slice lands, this test fails. That is the point. *)
let k_a_dune =
  ("kliba/dune", "(library\n (name kliba)\n (modules api)\n (flags (:standard -w -a)))\n")

let k_a_api = ("kliba/api.ml", "type t = int\nlet run () : int = 1\n")

let k_b_dune =
  ("klibb/dune", "(library\n (name klibb)\n (modules api)\n (flags (:standard -w -a)))\n")

let k_b_api = ("klibb/api.ml", "type t = string\nlet run () : string = \"b\"\n")

(* Links kliba ONLY. Every reference below names kliba explicitly. *)
let k_caller_dune =
  ( "kcaller/dune",
    "(library\n (name kcaller)\n (libraries kliba)\n (modules k)\n (flags (:standard -w -a)))\n" )

let k_caller_k =
  ("kcaller/k.ml", "module Alias = Kliba.Api\nlet use (x : Kliba.Api.t) : int = x\n")

let scenario_k_files =
  [dune_project; k_a_dune; k_a_api; k_b_dune; k_b_api; k_caller_dune; k_caller_k]

let register_sibling_sites_residual () =
  Test.register ~__FILE__
    ~title:"cmt: module_deps and type_usage still erase the owning library — pinned, not endorsed"
    ~tags:["cmt"; "qualified_name"; "library_scoping"; "residual"]
  @@ fun () ->
  Batch.run (fun b ->
      with_fixture ~name:"qual-scope-k" ~files:scenario_k_files @@ fun fixture ->
      let db = index fixture in
      Db.with_db db (fun conn ->
          let dep_targets =
            Db.rows conn
              "SELECT m.path FROM module_deps d JOIN modules m ON m.id = d.target_module \
               WHERE d.target_path = 'Kliba.Api'"
          in
          (match dep_targets with
          | [[p]] ->
              let p = Db.to_string ~sql:"dep target" p in
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "K: module_deps for `Kliba.Api` targets %s, expected the WRONG library \
                      klibb/api.ml. This pins a KNOWN DEFECT (spec S4, sites 2 and 3) that also \
                      reproduces on origin/main. If it now targets kliba/api.ml the residual is \
                      closed — good news, delete this half deliberately and update the spec"
                     p)
                (String.length p >= 11
                && String.sub p (String.length p - 11) 11 = "klibb/api.ml"
                   || Filename.dirname p = "klibb")
          | _ -> Batch.note b "K: expected exactly one module_deps row for Kliba.Api, got %d"
                   (List.length dep_targets)) ;
          let usage_targets =
            Db.rows conn
              "SELECT m.path FROM type_usage u JOIN types t ON t.id = u.type_id JOIN modules m \
               ON m.id = t.module_id WHERE t.name = 't'"
          in
          match usage_targets with
          | [[p]] ->
              let p = Db.to_string ~sql:"usage target" p in
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "K: type_usage for `Kliba.Api.t` resolves to %s, expected the WRONG library \
                      klibb/api.ml. Same residual, the type channel"
                     p)
                (Filename.dirname p = "klibb")
          | _ ->
              Batch.note b "K: expected exactly one resolved type_usage row for t, got %d"
                (List.length usage_targets))) ;
  Lwt.return_unit
