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

let register () =
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
