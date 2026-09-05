(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Phantom `option` origins — an OMITTED OPTIONAL ARGUMENT is not a returned [None]
    (roadmap 3.14).

    {1 What the rows were}

    [Typecore.option_none] synthesises a [None] constructor for every optional argument a call
    leaves out. Those nodes have no source position, and the walker recorded each of them as an
    origin of the [option] error channel — so a call writing [f x] where [f] takes [?title] and
    [?description] produced TWO origins claiming the function can return [None].

    They are not position-less rows to be given a position. They are rows about something that
    never happened, and the fix is to stop writing them.

    {1 Why nothing caught it}

    On proto_alpha the class was 27 182 of 30 526 origins — 89 % — and removing it moved no test:
    the suite was 197/0 before and after. A table can lose most of its rows with every assertion
    still green when nothing asserts on that table's SHAPE, only on the answers derived from it.
    Which is why this file asserts the shape.

    {1 Sound throughout, and that is the awkward part}

    The class only ever ADDED [None] origins, so nothing downstream was ever unsound — an
    over-approximation of an error channel is safe by construction. It was a precision loss that
    drowned the real signal twenty to one, and a safe defect is exactly the kind that survives:
    nothing goes wrong, so nothing prompts a look. *)

open Arch_tezt

let fixture_files =
  [
    Fixture.dune_project;
    ( "dune",
      "(library\n (name ph_fixture)\n (wrapped false)\n (modules ph_a)\n\
      \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
    ( "ph_a.ml",
      {|(* A None a programmer WROTE. It has a position and is a real origin. *)
let real_none x = if x > 0 then Some x else None

let with_opts ?title ?description n = ignore title ; ignore description ; n

(* Calls that OMIT the optional arguments. The compiler synthesises a None for
   each omission, with no source position. Two here, then one. *)
let omits_both n = with_opts n
let omits_one n = with_opts ~title:"t" n

(* An exception origin, as the control: this fix must not touch any other
   channel, and a test that only counts `option` rows could not tell a targeted
   fix from one that emptied the table. *)
exception Boom

let raises n = if n > 0 then raise Boom else n
|} );
  ]

let origins db ~channel =
  Db.with_db db (fun c ->
      Db.rows c
        (Printf.sprintf
           "SELECT f.name || '@' || CAST(o.line AS TEXT) FROM exn_origins o \
            JOIN functions f ON o.function_id = f.id WHERE o.channel = '%s' ORDER BY 1"
           channel))
  |> List.map (function [ x ] -> Db.to_string ~sql:"origins" x | _ -> Test.fail "shape")

(* A SECOND FIXTURE, for the placement of [note_seen_value_path] alone.

   No [None] is WRITTEN anywhere in it, and the only [None] nodes the compiler puts in the tree
   are the two it synthesises for the omitted optional arguments. The carrier type is present, so
   the [option] channel is live and its declared origin ["None"] is the only thing whose
   observation is in question. *)
let seen_only_files =
  [
    Fixture.dune_project;
    ( "dune",
      "(library\n\
      \ (name ph_seen)\n\
      \ (wrapped false)\n\
      \ (modules ph_s)\n\
      \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
    (* [channel.option] EXTENDS the built-in field by field rather than replacing it, which is
       the only spelling the config accepts: a differently-named channel over the same carrier is
       refused outright, because selection is first-match-wins and the built-in is merged first.
       The profile exists at all because validation does not run without one — the first draft of
       this test asserted on the strict output of a run that never validated anything, and passed
       against the mutant for that reason. *)
    ("profiles/ph-errors.toml", "[channel.option]\ntype = \"option\"\norigins = [{path = \"None\", arg = 0}]\n");
    ( "ph_s.ml",
      {|(* The carrier: something of type _ option exists, so the channel is not vacuous. *)
let carrier (x : int option) : int option = x

let with_opts ?title ?description n = ignore title ; ignore description ; n

(* The ONLY None nodes in this unit are the two the compiler synthesises here. *)
let omits_both n = with_opts n
|} );
  ]

(* THE DECISION THIS TEST EXISTS FOR, and it had none.

   [note_seen_value_path] is called OUTSIDE the [has_source] guard. A review pointed out that
   moving it INSIDE survives the whole suite — nine lines of comment and a CHANGELOG paragraph
   defended a placement that nothing could distinguish from its opposite. That is this PR's own
   thesis turned on the PR: a table lost 89 % of its rows with every assertion green, because
   nothing asserted on the thing that changed.

   The two placements answer different questions, and this fixture separates them:

     outside (correct)  "is the declared path ['None'] plausible for this corpus?" — a question
                        about the CONFIG. A synthetic [None] is still a [None] node the compiler
                        put in the tree, so the declaration IS observed.
     inside  (wrong)    conflates that with "did the program produce an error here?", so on a
                        corpus whose only [None]s are synthetic, [--errors-strict] reports a
                        correctly-declared channel as never observed — a false alarm about the
                        config, raised by a fact about the code.

   Red-verified by hand before this test was written, same binary, same fixture:
     correct  exit 0, no [channel option: 'None'] line
     mutant   exit 1, [arch-errors: channel option: 'None' matched nothing] *)
let register_seen_outside_the_guard () =
  Test.register ~__FILE__
    ~title:"phantom origins: a synthetic None still OBSERVES the declared path (3.14)"
    ~tags:["cmt"; "errch"; "option"; "origins"; "strict"]
  @@ fun () ->
  with_fixture ~name:"phantom_seen" ~files:seen_only_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "phantom_seen" in
  let code, output =
    Arch_tezt.index_raw_into ~db
      ~env:[("ARCH_ERRORS_PROFILES_DIR", Filename.concat fixture.Arch_tezt.root "profiles")]
      ~extra_args:["--errors-profile"; "ph"; "--errors-strict"]
      fixture
  in
  Batch.run (fun b ->
      (* PREMISE 0: the profile was actually loaded. Without it no validation runs at all and
         every assertion below is vacuous — which is exactly how the first version of this test
         passed against the mutant it was written to kill. *)
      Batch.check b
        ~msg:(Printf.sprintf "premise: the error profile was loaded:\n%s" output)
        (Batch.has_substring ~needle:"arch-errors: using profile " output) ;
      (* PREMISE 1: the omissions are really there. Without them the unit has no [None] node at
         all, and "the declaration was observed" would be false for an uninteresting reason. *)
      Batch.check b ~msg:"premise: the function that omits optional arguments was indexed"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM functions WHERE name = 'omits_both'")
        = 1) ;
      (* PREMISE 2: and NO origin row survives — this fixture writes no real [None], so the guard
         drops everything it produced. This is what makes the assertion discriminate: the path is
         reported as observed while contributing zero rows. *)
      Batch.eq_int b ~msg:"premise: this fixture contributes no option origin at all"
        (List.length (origins db ~channel:"option"))
        0 ;
      (* PREMISE 3: the mechanism can say "matched nothing" on THIS run. Other declarations of the
         same channel do go unobserved here, so a silent 'None' is a decision, not an empty
         validator. *)
      Batch.check b
        ~msg:(Printf.sprintf "premise: the validator does report misses on this run:\n%s" output)
        (Batch.has_substring ~needle:"arch-errors: channel option: 'Stdlib.Option.get'" output) ;
      (* THE ASSERTION, on the exact line and not on a substring shared with every other
         channel's misses. *)
      Batch.check b
        ~msg:
          (Printf.sprintf
             "the declared origin 'None' is observed, so it is NOT reported unmatched:\n%s"
             output)
        (not
           (Batch.has_substring ~needle:"arch-errors: channel option: 'None' matched nothing"
              output)) ;
      Batch.eq_int b ~msg:(Printf.sprintf "--errors-strict exits 0:\n%s" output) code 0) ;
  Lwt.return_unit

let register_exact_set () =
  Test.register ~__FILE__
    ~title:"phantom origins: an omitted optional argument is not a returned None (3.14)"
    ~tags:["cmt"; "errch"; "option"; "origins"]
  @@ fun () ->
  with_fixture ~name:"phantom" ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "phantom" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  Batch.run (fun b ->
      (* PREMISE. The fixture must actually contain the omissions, or "no phantom rows" is also
         what a fixture with nothing to omit produces. Three omissions are written: two in
         [omits_both], one in [omits_one]. *)
      Batch.check b
        ~msg:"premise: the fixture indexed the functions that omit optional arguments"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM functions WHERE name IN ('omits_both','omits_one')")
        = 2) ;
      (* THE ASSERTION. The EXACT set, not a count: a count would also be satisfied by keeping a
         phantom and dropping the real one. [real_none] is at line 2 of the fixture. *)
      Batch.eq_string b
        ~msg:"only the written None is an origin, and it keeps its real line"
        (String.concat ", " (origins db ~channel:"option"))
        "real_none@2" ;
      (* NO row at line 0 survives anywhere, on any channel. A zero line is the compiler saying
         the node has no source, and nothing positioned should be recorded from one. *)
      Batch.eq_int b ~msg:"no origin anywhere carries line 0"
        (Db.with_db db (fun c -> Db.int c "SELECT count(*) FROM exn_origins WHERE line = 0"))
        0 ;
      (* THE CONTROL, and it is what stops this from passing for a fix that emptied the table.
         The exception channel must be untouched — on proto_alpha it is byte-identical across the
         change, 1219 origins before and after. *)
      Batch.eq_string b
        ~msg:"the exception channel is untouched — this fix is targeted, not a purge"
        (String.concat ", " (origins db ~channel:"exception"))
        (* Line 16 and once, counted off the fixture text above rather than copied from the
           tool's output: [exception Boom] is at 14 and [let raises] at 16, with a single
           [raise]. An expected value read back from the thing under test asserts only that it
           is self-consistent. *)
        "raises@16") ;
  Lwt.return_unit

let register () =
  register_exact_set () ;
  register_seen_outside_the_guard ()
