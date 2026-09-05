(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** [forbid origin] — the crash-surface regression gate (roadmap 3.12).

    The verb states an invariant absolutely and names the already-accepted sites
    in an allow-file. It is deliberately NOT a baseline, and there is deliberately
    no [--regenerate] flag: a site list can grow for three different reasons — a
    real regression, WIDENED COVERAGE, or a proof that strengthened MAY→MUST — and
    a line-diff conflates all three. Only a person can tell them apart, so the
    gate's job is to force the person, not to automate an excuse.

    What is asserted here is the part of that design a reader cannot check by
    reading the code, plus the two parser properties that bite a file path.

    {b The count is the load-bearing field, and it is here because a measurement
    said so.} The identity [fn | file:line | form | exn] was specified as a key
    and then tested rather than assumed: on the full Octez population of 25 479
    origins it collides {b 1 150 times}, and adding the column still leaves 139 —
    [Make_Module.mul] at poseidon_utils.ml:114 form [index] appears eight times,
    and a nested [a.(i).(j)] puts two [index] origins at one column. So no
    positional identity is unique. Without a count, an allow-list entry is a SET
    exemption whose membership can grow after review: a ninth array access on an
    already-exempted line inherits the decision taken about the first eight.

    It would have looked correct on proto_alpha, where the 37 sites collide
    {b zero} times. A format that is a key on the demo corpus and not on the real
    one is exactly the shape that survives review, which is why [register_count]
    exists and why its fixture puts two origins on one line. *)

open Arch_tezt

let rules args = run_command (arch_rules ()) args

let rule_file name contents =
  let path = Temp.file (name ^ ".rules") in
  write_file path contents ;
  path

let allow_file name contents =
  let path = Temp.file (name ^ ".allow") in
  write_file path contents ;
  path

let fixture_files =
  [
    Fixture.dune_project;
    ( "dune",
      "(library\n\
      \ (name ro_fixture)\n\
      \ (wrapped false)\n\
      \ (modules ro_main ro_leaf)\n\
      \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
    (* TWO divisions on ONE line, which is the whole point: they share a
       function, a file, a line, a form and an exception, so the four declared
       fields cannot tell them apart. Only the count can. *)
    ( "ro_leaf.ml",
      {|let two_on_one_line a b c = (a / b) + (a / c)

let one_assert n =
  assert (n > 0) ;
  n
|} );
    ( "ro_main.ml",
      {|let entry a b c =
  let x = Ro_leaf.two_on_one_line a b c in
  Ro_leaf.one_assert x
|} );
  ]

let with_indexed name f =
  with_fixture ~name ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db name in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  f db

let origin_rule ~forms ~allow =
  Printf.sprintf "rule \"no new fatal origin\"\n  forbid origin from file:**/ro_main.ml form:%s allow-file:%s\n"
    forms allow

(* THE ASSERTION THE DESIGN CORRECTION EXISTS FOR. *)
let register_count () =
  Test.register ~__FILE__
    ~title:"rules origin: an exemption is bounded by its count, not by its four fields"
    ~tags:["rules"; "origin"; "allow"; "count"]
  @@ fun () ->
  with_indexed "ro_count" @@ fun db ->
  (* Derived by hand from the fixture BEFORE running, which is the only way this
     assertion means anything: [two_on_one_line] performs [a / b] and [a / c] on
     line 1, so ONE identity carries TWO origins. *)
  let ident = ref "" in
  Batch.run (fun b ->
      (* PREMISE. If the producer recorded one division instead of two — or
         none — every assertion below would pass for the wrong reason: an
         under-count cannot exceed an allowance. *)
      let n =
        Db.with_db db (fun c ->
            Db.int c
              "SELECT count(*) FROM exn_origins o JOIN functions f ON o.function_id=f.id \
               WHERE f.name='two_on_one_line' AND o.form='division'")
      in
      Batch.eq_int b ~msg:"premise: the fixture really puts TWO division origins on one line" n 2 ;
      (* Read the identity out of the tool rather than reconstructing its
         formatting here: a test that spells the identity itself would keep
         passing if the tool's spelling changed underneath it. *)
      let _, out = rules [db; rule_file "roc_empty" (origin_rule ~forms:"division" ~allow:(allow_file "roc_empty" ""))] in
      let line =
        String.split_on_char '\n' out
        |> List.find_opt (fun l -> Arch_tezt.contains ~needle:"two_on_one_line" l)
      in
      match line with
      | None -> Batch.check b ~msg:("the tool listed the two-origin site (output:\n" ^ out ^ ")") false
      | Some l ->
          (* Strip the leading [new] marker and the trailing count to recover the
             four fields, the way a reviewer transcribing the line would. *)
          let l = String.trim l in
          let l =
            match String.index_opt l ']' with
            | Some i -> String.trim (String.sub l (i + 1) (String.length l - i - 1))
            | None -> l
          in
          (match String.rindex_opt l '|' with
          | Some i -> ident := String.trim (String.sub l 0 i)
          | None -> ident := l) ;
          Batch.check b
            ~msg:("the listed site reports a count of two (line: " ^ l ^ ")")
            (Arch_tezt.contains ~needle:"\xc3\x972" l) ;
          (* THE ASSERTION. Exempting the identity with a count of ONE must NOT
             exempt the second origin. This is the silent-widening path the
             design was written to eliminate, and it is invisible on any corpus
             where every site is ×1. *)
          let under = allow_file "roc_under" (!ident ^ " | \xc3\x971\n") in
          let code_u, out_u = rules [db; rule_file "roc_under" (origin_rule ~forms:"division" ~allow:under)] in
          Batch.eq_int b
            ~msg:("an allowance of \xc3\x971 does not cover TWO origins (output:\n" ^ out_u ^ ")")
            code_u 1 ;
          Batch.check b
            ~msg:"the failure says what was allowed, so the reviewer sees the delta not just the site"
            (Arch_tezt.contains ~needle:"[was \xc3\x971]" out_u) ;
          (* And the control: the SAME entry with the right count passes. Without
             this, the assertion above would also be satisfied by a gate that
             rejects every entry. *)
          let exact = allow_file "roc_exact" (!ident ^ " | \xc3\x972\n") in
          let _, out_e = rules [db; rule_file "roc_exact" (origin_rule ~forms:"division" ~allow:exact)] in
          Batch.check b
            ~msg:("the same entry with \xc3\x972 covers the site (output:\n" ^ out_e ^ ")")
            (not (Arch_tezt.contains ~needle:"two_on_one_line" out_e))) ;
  Lwt.return_unit

(* The two parser properties that bite a FILE PATH specifically, and the selector
   kinds this verb declares. All three are refusals, and a refusal that does not
   fire is indistinguishable from a feature that was never reached — so each is
   paired with the accepted form it is the negation of. *)
let register_refusals () =
  Test.register ~__FILE__
    ~title:"rules origin: the parser refuses what it cannot serve, and says which character"
    ~tags:["rules"; "origin"; "parse"; "policy"]
  @@ fun () ->
  with_indexed "ro_refuse" @@ fun db ->
  let ok_allow = allow_file "ror_ok" "" in
  let run name body = rules [db; rule_file name ("rule \"r\"\n  " ^ body ^ "\n")] in
  Batch.run (fun b ->
      (* THE CONTROL. Every refusal below must be a refusal of something
         SPECIFIC, not of the verb; if this line did not parse, the four
         assertions after it would pass with the feature absent. *)
      let code_ok, _ =
        run "ror_ok" (Printf.sprintf "forbid origin from file:**/ro_main.ml form:assert allow-file:%s" ok_allow)
      in
      Batch.check b ~msg:"control: the accepted form parses and evaluates (exit 0 or 1, not 2)"
        (code_ok <> 2) ;
      (* '#' TRUNCATION. Comment stripping cuts from the FIRST '#' anywhere in
         the line, so a path containing one is silently shortened — the line
         still parses, just against a different file. Failure BY DELETION. *)
      let code_h, out_h =
        run "ror_hash" (Printf.sprintf "forbid origin from file:**/ro_main.ml form:assert allow-file:%s#1" ok_allow)
      in
      Batch.eq_int b ~msg:"a '#' glued to a token aborts rather than truncating silently" code_h 2 ;
      Batch.check b
        ~msg:("the refusal names the character, so the author is not left hunting (output:\n" ^ out_h ^ ")")
        (Arch_tezt.contains ~needle:"'#'" out_h) ;
      (* And the negation of that refusal: a '#' with a space before it is an
         ordinary trailing comment and must STAY legal. A guard that refuses
         both would have been caught by nothing here without this line. *)
      let code_c, _ =
        run "ror_comment"
          (Printf.sprintf "forbid origin from file:**/ro_main.ml form:assert allow-file:%s # a note" ok_allow)
      in
      Batch.check b ~msg:"a spaced '#' is still an ordinary comment" (code_c <> 2) ;
      (* SELECTOR KINDS, declared rather than inherited. `Dep` discards the kind
         and globs the pattern, so `forbid dep from fn:foo` is accepted and
         silently reinterpreted; a verb that does not name its kinds inherits
         that by omission. *)
      let code_m, out_m =
        run "ror_module" (Printf.sprintf "forbid origin from module:Foo form:assert allow-file:%s" ok_allow)
      in
      Batch.eq_int b ~msg:"module: is refused — an origin belongs to a function in a file" code_m 2 ;
      Batch.check b ~msg:"the refusal names the kinds that ARE accepted"
        (Arch_tezt.contains ~needle:"file" out_m && Arch_tezt.contains ~needle:"fn" out_m) ;
      let code_e, _ =
        run "ror_ext" (Printf.sprintf "forbid origin from ext:Foo form:assert allow-file:%s" ok_allow)
      in
      Batch.eq_int b ~msg:"ext: is refused — an external leaf has no body to hold an origin" code_e 2 ;
      (* AN UNKNOWN FORM. It would select nothing, so the rule would report a
         PASS while policing an empty population — the vacuous green this whole
         tool exists to refuse. Caught where the author is looking. *)
      let code_f, out_f =
        run "ror_form" (Printf.sprintf "forbid origin from file:**/ro_main.ml form:asserts allow-file:%s" ok_allow)
      in
      Batch.eq_int b ~msg:"an unknown origin form aborts instead of policing nothing" code_f 2 ;
      Batch.check b ~msg:"the refusal lists the known forms"
        (Arch_tezt.contains ~needle:"division" out_f) ;
      (* A MISSING allow-file must abort at PARSE time. A gate that starts
         evaluating and then finds it cannot read its own exemptions has already
         printed half a verdict. *)
      let code_missing, _ =
        run "ror_missing" "forbid origin from file:**/ro_main.ml form:assert allow-file:/nonexistent/nope.txt"
      in
      Batch.eq_int b ~msg:"an unreadable allow-file aborts the run" code_missing 2 ;
      (* A MALFORMED allow-file, same reason. Four fields instead of five is the
         likely mistake: someone omits the count, which is the field that bounds
         the exemption. *)
      let four = allow_file "ror_four" "f | a.ml:1 | division | Division_by_zero\n" in
      let code_four, out_four =
        run "ror_four" (Printf.sprintf "forbid origin from file:**/ro_main.ml form:assert allow-file:%s" four)
      in
      Batch.eq_int b ~msg:"an allow-file entry missing its count aborts" code_four 2 ;
      Batch.check b ~msg:"and says how many fields it expected"
        (Arch_tezt.contains ~needle:"five" out_four)) ;
  Lwt.return_unit

(* NOT_COMPUTED must not read as PASS, and the two ways of having no origins must
   not read as each other. *)
let register_not_computed () =
  Test.register ~__FILE__
    ~title:"rules origin: an index with no origin data reports NOT_COMPUTED, never PASS"
    ~tags:["rules"; "origin"; "not_computed"]
  @@ fun () ->
  with_indexed "ro_nc" @@ fun db ->
  Batch.run (fun b ->
      let allow = allow_file "ronc" "" in
      (* Emptying the table is the point: the table EXISTS, so this is the
         "producer killed before the exception pass" shape, which is precisely
         what must not be reported the same way as "this code has no origins". *)
      Db.with_db_rw db (fun c -> ignore (Db.exec_result c "DELETE FROM exn_origins")) |> ignore ;
      let code, out = rules [db; rule_file "ronc" (origin_rule ~forms:"assert,division" ~allow)] in
      Batch.eq_int b ~msg:"NOT_COMPUTED fails the gate by default" code 1 ;
      Batch.check b ~msg:("the verdict is NOT_COMPUTED (output:\n" ^ out ^ ")")
        (Arch_tezt.contains ~needle:"not-computed" out || Arch_tezt.contains ~needle:"NOT_COMPUTED" out) ;
      Batch.check b ~msg:"and it says the pass produced nothing, not that the code is clean"
        (Arch_tezt.contains ~needle:"never evaluated" out)) ;
  Lwt.return_unit

let register () =
  register_count () ;
  register_refusals () ;
  register_not_computed ()
