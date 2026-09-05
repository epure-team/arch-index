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
    and then tested rather than assumed. Re-derived 2026-09-05, on a table
    carrying no [UNIQUE] constraint over these columns — so the probe could have
    returned zero and did not:

    - proto_alpha: 30 526 origins, 5 305 distinct identities, {b 26 901 rows
      (88 %) in colliding groups}, worst group 139.
    - octez-manager: 18 758 / 6 367 / {b 15 569 (83 %)}, worst 118.
    - whole [src]: 265 217 / 116 684 / {b 169 525 (64 %)}, worst 139.

    Adding the column does {b not} rescue it — 26 901 → 26 786 on proto_alpha —
    so 139 origins can share a function, file, line, form and exception. Without
    a count an entry is a SET exemption whose membership can grow after review: a
    140th origin on an exempted line inherits the decision taken about the first
    139.

    Filtered to the population this gate polices, the picture inverts: the 37
    crash-surface sites reachable from proto_alpha's [main.ml] are {b all ×1}. A
    format that is a key on the population you demo and not on the table it reads
    is exactly the shape that survives review — which is why [register_count]
    exists, and why its fixture deliberately puts two origins on one line.

    (An earlier revision of this docstring cited "25 479 origins, 1 150
    collisions"; those could not be reproduced on any available corpus, and 139
    was the worst GROUP SIZE rather than a residual count. The correction runs
    safe — the real rate is an order of magnitude worse — but a number nobody
    re-derived is how a briefing becomes a fact.) *)

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

(* An OPERATOR whose name contains '|'. Not exotic: [|+|] already exists in this
   repository's own scenario_dsl.ml. Its origin's identity therefore contains the
   allow-file's own field separator. *)
let ( |/| ) a b = a / b

let piped_div a b = a |/| b

(* An origin that does NOT escape: the division is inside a handler that catches
   what it raises. Without this the escapes = 1 filter is unobservable — a
   fixture where everything escapes cannot tell a filter that works from one
   that was deleted. *)
let caught_div a b = try a / b with Division_by_zero -> 0

(* TWENTY-FIVE distinct division sites, so the offender list crosses the 20 that
   every other verdict caps at while staying under this verb's 200. Without them
   the documented divergence is unpinnable: the reviewer measured that dropping
   the cap from 200 to 20 SURVIVES, and it had to — a fixture yielding five
   offenders cannot tell the two caps apart, so no assertion written against it
   could ever have failed. The cap is not decoration: this list is the artefact a
   reviewer transcribes into the allow-file, and there is deliberately no
   --regenerate to produce it another way. *)
let d01 a b = a / b
let d02 a b = a / b
let d03 a b = a / b
let d04 a b = a / b
let d05 a b = a / b
let d06 a b = a / b
let d07 a b = a / b
let d08 a b = a / b
let d09 a b = a / b
let d10 a b = a / b
let d11 a b = a / b
let d12 a b = a / b
let d13 a b = a / b
let d14 a b = a / b
let d15 a b = a / b
let d16 a b = a / b
let d17 a b = a / b
let d18 a b = a / b
let d19 a b = a / b
let d20 a b = a / b
let d21 a b = a / b
let d22 a b = a / b
let d23 a b = a / b
let d24 a b = a / b
let d25 a b = a / b

(* An OPTION-channel origin: on that channel, "raising" means returning None.
   Present so that "the default channel is exception" is a claim that CAN FAIL.
   Without an origin on another channel, a default that silently widened to
   every channel would produce identical output and no assertion could see it —
   which would be worse than the bug it replaced. *)
let maybe_div a b = if b = 0 then None else Some (a / b)
|} );
    ( "ro_main.ml",
      {|let entry a b c =
  let x = Ro_leaf.two_on_one_line a b c in
  let y = Ro_leaf.piped_div x a in
  let z = Ro_leaf.caught_div y b in
  let _ = Ro_leaf.maybe_div x b in
  let _ = Ro_leaf.d01 x b + Ro_leaf.d02 x b + Ro_leaf.d03 x b + Ro_leaf.d04 x b
          + Ro_leaf.d05 x b + Ro_leaf.d06 x b + Ro_leaf.d07 x b + Ro_leaf.d08 x b
          + Ro_leaf.d09 x b + Ro_leaf.d10 x b + Ro_leaf.d11 x b + Ro_leaf.d12 x b
          + Ro_leaf.d13 x b + Ro_leaf.d14 x b + Ro_leaf.d15 x b + Ro_leaf.d16 x b
          + Ro_leaf.d17 x b + Ro_leaf.d18 x b + Ro_leaf.d19 x b + Ro_leaf.d20 x b
          + Ro_leaf.d21 x b + Ro_leaf.d22 x b + Ro_leaf.d23 x b + Ro_leaf.d24 x b
          + Ro_leaf.d25 x b in
  Ro_leaf.one_assert (x + y + z)
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
      (* AN UNKNOWN CHANNEL. Same argument as the unknown form three lines above,
         and it took a reviewer to point out that I had made it for one token and
         not the other. Measured before the fix: `channel:banana` and
         `channel:result` produced BYTE-IDENTICAL `[UNKNOWN] 0 origin(s)`
         verdicts at exit 0 — a misspelling indistinguishable from a genuinely
         clean channel, and on a cone with no ⊤ escape an outright PASS.

         The refusal has to name the channels PRESENT, because unlike `form:`
         this vocabulary is not a schema CHECK: it comes from the errors profile
         the index was built with, so only the database can answer. *)
      let code_ch, out_ch =
        run "ror_chan"
          (Printf.sprintf
             "forbid origin from file:**/ro_main.ml form:division channel:banana allow-file:%s"
             ok_allow)
      in
      Batch.eq_int b ~msg:"an unknown channel aborts instead of policing an empty population"
        code_ch 2 ;
      Batch.check b
        ~msg:("the refusal lists the channels this index DOES contain (output:\n" ^ out_ch ^ ")")
        (Arch_tezt.contains ~needle:"exception" out_ch) ;
      (* THE ASSERTION THAT MAKES THE OTHER TWO MEAN ANYTHING, and without which
         this check was itself vacuous.

         `banana` and a needle of "exception" are satisfied by ANY hardcoded
         list containing that word. Proved by mutation: replacing
         [channels_in_index] with the literal
         ["exception";"option";"result";"tzresult";"error_monad"] left the suite
         at 170/0 — reinstalling the round-2 defect in full, since `channel:result`
         against an index with no `result` channel then reports [ pass ] at
         exit 0.

         The discriminating probe is a channel that is PLAUSIBLE ELSEWHERE and
         ABSENT HERE. This fixture's index carries exactly two channels,
         `exception` and `option`; `result` and `tzresult` are real members of
         the Tezos errors profile — both are named in this PR's own CHANGELOG —
         and neither is in this database. A hardcoded list accepts them; reading
         the index refuses them. That is the whole thesis of the fix, and it is
         the only assertion that can see it. *)
      List.iter
        (fun ch ->
          let code_p, out_p =
            run ("ror_plausible_" ^ ch)
              (Printf.sprintf
                 "forbid origin from file:**/ro_main.ml form:division channel:%s allow-file:%s"
                 ch ok_allow)
          in
          Batch.eq_int b
            ~msg:
              (Printf.sprintf
                 "channel %S is a real channel elsewhere but ABSENT from this index, so it is \
                  refused — a hardcoded vocabulary would accept it (output:\n%s)"
                 ch out_p)
            code_p 2)
        [ "result"; "tzresult" ] ;
      (* The premise the two lines above rest on, stated rather than assumed:
         this index really has only the two channels. If a future fixture gained
         a `result` origin, the probe above would start measuring nothing and
         this assertion is what says so. *)
      Batch.eq_string b
        ~msg:"premise: the fixture index carries exactly the two channels the probe assumes"
        (String.concat ","
           (Db.with_db db (fun c ->
                Db.rows c "SELECT DISTINCT channel FROM exn_origins ORDER BY 1")
            |> List.map (function
                 | [x] -> Db.to_string ~sql:"chan" x
                 | _ -> Test.fail "chan: unexpected row shape")))
        "exception,option" ;
      (* And the negation, which is what stops the check from being a blanket
         refusal: a channel that IS present is accepted even when it yields no
         origin in this cone. A typo and a genuinely clean channel must be
         distinguishable in BOTH directions. *)
      let code_ok_ch, out_ok_ch =
        run "ror_chan_ok"
          (Printf.sprintf
             "forbid origin from file:**/ro_main.ml form:division channel:option allow-file:%s"
             ok_allow)
      in
      (* The negation, and it asserts the OUTPUT rather than the absence of an
         abort: [code <> 2] is satisfied by an implementation with no channel
         check whatsoever, so it could not distinguish "accepted correctly" from
         "never looked". *)
      Batch.check b
        ~msg:("a channel present in the index is accepted, empty or not, and is the one \
               policed (output:\n" ^ out_ok_ch ^ ")")
        (code_ok_ch <> 2 && Arch_tezt.contains ~needle:"on channel 'option'" out_ok_ch) ;
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

(* THE FLOW DEFECTS. Each of these is a way the gate misbehaves for a person
   USING it rather than a way it computes a wrong answer, and each was found by a
   reviewer rather than by this file. *)
let register_flow () =
  Test.register ~__FILE__
    ~title:"rules origin: the allow-file survives a '|' in a name, and refuses a duplicate"
    ~tags:["rules"; "origin"; "allow"; "flow"]
  @@ fun () ->
  with_indexed "ro_flow" @@ fun db ->
  Batch.run (fun b ->
      (* A '|' IN A FUNCTION NAME. OCaml operator names legitimately contain one.
         A left split requiring exactly five fields made such a site permanently
         un-exemptable — and because a malformed allow-file ABORTS, one such line
         copied verbatim from the tool's own output took EVERY OTHER RULE in the
         file down with it. *)
      let _, out =
        rules [db; rule_file "rof_e" (origin_rule ~forms:"division" ~allow:(allow_file "rof_e" ""))]
      in
      let piped =
        String.split_on_char '\n' out
        |> List.find_opt (fun l -> Arch_tezt.contains ~needle:"|/|" l)
      in
      match piped with
      | None ->
          Batch.check b
            ~msg:("premise: the operator's own division site is listed (output:\n" ^ out ^ ")")
            false
      | Some l ->
          let l = String.trim l in
          let entry =
            match String.index_opt l ']' with
            | Some i -> String.trim (String.sub l (i + 1) (String.length l - i - 1))
            | None -> l
          in
          Batch.check b ~msg:"premise: the listed identity really contains a '|'"
            (Arch_tezt.contains ~needle:"|/|" entry) ;
          (* Copied VERBATIM, the way a reviewer would. *)
          let af = allow_file "rof_pipe" (entry ^ "\n") in
          let code, out2 =
            rules [db; rule_file "rof_pipe" (origin_rule ~forms:"division" ~allow:af)]
          in
          Batch.check b
            ~msg:("an entry whose name contains '|' is accepted, not an abort (output:\n" ^ out2 ^ ")")
            (code <> 2) ;
          Batch.check b ~msg:"and it actually exempts its own site"
            (not (Arch_tezt.contains ~needle:"[new]" out2 && Arch_tezt.contains ~needle:"|/|" out2)) ;
          (* A DUPLICATE identity. Previously accepted in silence with FIRST-wins,
             so the ORDER OF LINES decided the verdict — and in an append-only
             workflow, which is the one this design imposes, a corrected
             allowance appended at the end was silently ignored. *)
          let dup = allow_file "rof_dup" (entry ^ "\n" ^ entry ^ "\n") in
          let code_d, out_d =
            rules [db; rule_file "rof_dup" (origin_rule ~forms:"division" ~allow:dup)]
          in
          Batch.eq_int b ~msg:"a duplicate allow-list entry aborts instead of silently first-winning"
            code_d 2 ;
          Batch.check b ~msg:"and the refusal names both counts"
            (Arch_tezt.contains ~needle:"duplicate" out_d)) ;
  Lwt.return_unit

(* THE COVERAGE DELTA — the condition this design named for its own survival, and
   which had no test at all: deleting it left the suite green. A widened-coverage
   failure that reads as a regression is how a gate gets disabled. *)
let register_coverage_and_scope () =
  Test.register ~__FILE__
    ~title:"rules origin: the coverage figure, the channel scope, and the escapes filter"
    ~tags:["rules"; "origin"; "coverage"; "channel"]
  @@ fun () ->
  with_indexed "ro_cov" @@ fun db ->
  Batch.run (fun b ->
      let empty = allow_file "roc_cov" "" in
      let _, out = rules [db; rule_file "roc_cov" (origin_rule ~forms:"division" ~allow:empty)] in
      Batch.check b
        ~msg:("the verdict reports a coverage figure, not only the sites (output:\n" ^ out ^ ")")
        (Arch_tezt.contains ~needle:"coverage:" out) ;
      Batch.check b ~msg:"it states the cone size, so a widened cone is visible as such"
        (Arch_tezt.contains ~needle:"node(s) in cone" out) ;
      (* THE CAP, pinned. [detail] caps at 200 here and at 20 everywhere else,
         and the divergence is deliberate: elsewhere the list is a SAMPLE a human
         reads, here it IS the payload a human transcribes. Counting the listed
         offenders is the only assertion that can tell the two caps apart, and it
         needs a fixture with more than 20 — which is what the d01..d25 sites are
         for. *)
      let listed =
        String.split_on_char '\n' out
        |> List.filter (fun l -> Arch_tezt.contains ~needle:"[new]" l)
        |> List.length
      in
      Batch.check b
        ~msg:
          (Printf.sprintf
             "the offender list is not truncated at the sibling verbs' 20 (listed %d)" listed)
        (listed > 20) ;
      Batch.check b ~msg:"and how many allow-entries matched nothing"
        (Arch_tezt.contains ~needle:"matching nothing" out) ;
      (* THE CHANNEL SCOPE. exn_origins holds every error channel, not just
         exceptions. Measured on proto_alpha's lib_protocol (500 .cmt), indexed from
         origin/main 0982a42 with --errors-profile=tezos: `form:raise` from
         file:**/main.ml finds 1 origin on `exception`, 128 on `option` (where
         "raising" means RETURNING None) and 247 on `tzresult` — so the unscoped
         gate quantified over 376. A reviewer measured 1/75/161 on their own
         build of the same tree; both are internally consistent and the gap is
         corpus COVERAGE, which is why the figure names its build state and not
         just its tree. Default is `exception`. *)
      Batch.check b ~msg:"the coverage line names the channel it polices"
        (Arch_tezt.contains ~needle:"on channel 'exception'" out) ;
      let _, out_o =
        rules
          [ db;
            rule_file "roc_opt"
              (Printf.sprintf
                 "rule \"opt\"\n  forbid origin from file:**/ro_main.ml form:raise \
                  channel:option allow-file:%s\n"
                 empty) ]
      in
      Batch.check b ~msg:"an explicit channel is honoured"
        (Arch_tezt.contains ~needle:"on channel 'option'" out_o) ;
      (* THE DEFAULT MUST RESTRICT, not merely be named. A default that silently
         widened to every channel would print the same word and report MORE
         sites — worse than the unscoped bug it replaces, because it would look
         scoped. So the claim is made against a fixture that HAS an origin on
         another channel, and it is a count. *)
      let sites out =
        String.split_on_char '\n' out
        |> List.filter_map (fun l ->
               match String.index_opt l ',' with
               | _ when not (Arch_tezt.contains ~needle:"site(s)" l) -> None
               | _ ->
                   let rec scan i acc =
                     if i >= String.length l then acc
                     else if l.[i] >= '0' && l.[i] <= '9' then
                       let j = ref i in
                       while !j < String.length l && l.[!j] >= '0' && l.[!j] <= '9' do incr j done ;
                       let n = int_of_string (String.sub l i (!j - i)) in
                       if !j + 5 <= String.length l && String.sub l !j 5 = " site" then Some n
                       else scan !j acc
                     else scan (i + 1) acc
                   in
                   scan 0 None)
        |> function [ n ] -> n | _ -> -1
      in
      Batch.eq_int b
        ~msg:"premise: the fixture carries an option-channel origin, so the default CAN be wrong"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM exn_origins WHERE channel='option'") > 0
         |> fun x -> if x then 1 else 0)
        1 ;
      let _, out_raise =
        rules [db; rule_file "roc_raise" (origin_rule ~forms:"raise" ~allow:empty)]
      in
      let _, out_raise_opt =
        rules
          [ db;
            rule_file "roc_raise_opt"
              (Printf.sprintf
                 "rule \"ro\"\n  forbid origin from file:**/ro_main.ml form:raise \
                  channel:option allow-file:%s\n"
                 empty) ]
      in
      Batch.check b
        ~msg:
          (Printf.sprintf
             "the DEFAULT channel restricts: form:raise sees %d site(s) by default and %d on \
              channel:option — a default that widened would make these equal"
             (sites out_raise) (sites out_raise_opt))
        (sites out_raise <> sites out_raise_opt) ;
      (* THE escapes = 1 FILTER. [caught_div] divides inside a handler that
         catches Division_by_zero, so its origin does not escape and must not be
         policed. A fixture with no handler cannot tell a working filter from a
         deleted one. *)
      Batch.eq_int b
        ~msg:"premise: the fixture really contains a non-escaping division origin"
        (Db.with_db db (fun c ->
             Db.int c
               "SELECT count(*) FROM exn_origins o JOIN functions f ON o.function_id=f.id \
                WHERE f.name='caught_div' AND o.form='division' AND o.escapes=0"))
        1 ;
      Batch.check b
        ~msg:("a caught origin is not reported as a site (output:\n" ^ out ^ ")")
        (not (Arch_tezt.contains ~needle:"caught_div" out))) ;
  Lwt.return_unit

let register () =
  register_count () ;
  register_refusals () ;
  register_not_computed () ;
  register_flow () ;
  register_coverage_and_scope ()
