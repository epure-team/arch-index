(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Architecture fitness functions.

    Every test here is really the same test: does the engine still know the
    difference between a proof and a blind spot? A tool that collapses "I proved
    it cannot" into "I found nothing" is exactly the tool this one exists to
    replace, so the five verdicts have to stay distinct.

    - [VIOLATION] — a MUST path exists.
    - [POSSIBLE] — reachable only over MAY_ENUMERATED.
    - [UNKNOWN] — nothing found, but the cone escapes through a ⊤ edge.
    - [UNKNOWN_NO_CONTRACT] — nothing found, on an index that never marked ⊤.
    - [PASS] — nothing found, cone closed, index ⊤-marked: a real proof.

    The exit-code policy is part of the same subject. A rule that reads "n/a" on
    every run is indistinguishable from one that passes, so NOT_COMPUTED fails
    the gate by default; and a misspelled policy flag must abort rather than be
    read as "do not fail", because the safest-looking flag in the tool was once
    the one that removed the check. *)

open Arch_tezt

let rules args = run_command (arch_rules ()) args

let rules_json b ~what args =
  let code, output = rules args in
  ignore code ;
  match Json.strict_object ~what output with
  | Ok j -> Some j
  | Error e ->
      Batch.note b "%s" e ;
      None

let rule_file name contents =
  let path = Temp.file (name ^ ".rules") in
  write_file path contents ;
  path

(* ui.handle  --MUST-->      db.write            a definite layering violation
   api.serve  --MAY_ENUM-->  db.write            possible: dispatch could land there
   job.run    --MUST--> util.helper --MAY_TOP--> ⊤   nothing can be ruled out
   pure.calc  --MUST-->      pure.inner          a closed cone: a real proof *)
let layered_stream =
  {|{"type":"function","name":"ui.handle","file_path":"src/ui/handler.ts","exported":true}
{"type":"function","name":"api.serve","file_path":"src/api/serve.ts","exported":true}
{"type":"function","name":"job.run","file_path":"src/job/run.ts"}
{"type":"function","name":"util.helper","file_path":"src/util/helper.ts"}
{"type":"function","name":"pure.calc","file_path":"src/pure/calc.ts"}
{"type":"function","name":"pure.inner","file_path":"src/pure/inner.ts"}
{"type":"function","name":"db.write","file_path":"lib/db/write.ts"}
{"type":"function","name":"db.my_write","file_path":"lib/db/my_write.ts"}
{"type":"call","caller_name":"ui.handle","caller_file":"src/ui/handler.ts","callee_name":"db.write","callee_file":"lib/db/write.ts","call_site":"src/ui/handler.ts:5","kind":"MUST"}
{"type":"call","caller_name":"api.serve","caller_file":"src/api/serve.ts","callee_name":"db.write","callee_file":"lib/db/write.ts","call_site":"src/api/serve.ts:9","kind":"MAY_ENUMERATED"}
{"type":"call","caller_name":"job.run","caller_file":"src/job/run.ts","callee_name":"util.helper","callee_file":"src/util/helper.ts","call_site":"src/job/run.ts:3","kind":"MUST"}
{"type":"call","caller_name":"util.helper","caller_file":"src/util/helper.ts","callee_name":"*TOP*","callee_file":null,"call_site":"src/util/helper.ts:7","kind":"MAY_TOP"}
{"type":"call","caller_name":"pure.calc","caller_file":"src/pure/calc.ts","callee_name":"pure.inner","callee_file":"src/pure/inner.ts","call_site":"src/pure/calc.ts:2","kind":"MUST"}
|}

let four_rules =
  {|rule "ui must not reach persistence"
  forbid reach from file:src/ui/** to file:lib/db/**
rule "api must not reach persistence"
  forbid reach from file:src/api/** to file:lib/db/**
rule "jobs must not reach persistence"
  forbid reach from file:src/job/** to file:lib/db/**
rule "pure code must not reach persistence"
  forbid reach from file:src/pure/** to file:lib/db/**
|}

(* Verdict of the first rule whose name starts with [prefix]. *)
let verdict_of j ~prefix =
  match Json.member "results" j with
  | Some (`List rs) ->
      List.find_map
        (function
          | `Assoc f -> (
              match (List.assoc_opt "rule" f, List.assoc_opt "verdict" f) with
              | Some (`String r), Some (`String v) when has_prefix ~prefix r -> Some v
              | _ -> None)
          | _ -> None)
        rs
  | _ -> None

let int_field b j ~what key expected =
  match Json.int ~what key j with
  | Ok n -> Batch.eq_int b ~msg:(what ^ "." ^ key) n expected
  | Error e -> Batch.note b "%s" e

let bool_field b j ~what key expected =
  match Json.bool ~what key j with
  | Ok v ->
      Batch.check b
        ~msg:(Printf.sprintf "%s.%s must be %b" what key expected)
        (v = expected)
  | Error e -> Batch.note b "%s" e

let register_verdicts () =
  Test.register ~__FILE__ ~title:"rules: the five verdicts stay distinct"
    ~tags:["rules"]
  @@ fun () ->
  let db = Fixture.flat ~name:"rules" layered_stream in
  let rf = rule_file "four" four_rules in
  Batch.run (fun b ->
      match rules_json b ~what:"rules" [db; rf; "--format"; "json"] with
      | None -> ()
      | Some j ->
          List.iter
            (fun (prefix, expected) ->
              Batch.eq_string_opt b
                ~msg:(Printf.sprintf "verdict for %S" prefix)
                (verdict_of j ~prefix) (Some expected))
            [
              ("ui must", "VIOLATION");
              ("api must", "POSSIBLE");
              ("jobs must", "UNKNOWN");
              ("pure code", "PASS");
            ] ;

          (* The machine-output contract. strict_object already rejected floats
             and trailing data; these are the counts a gate reads. *)
          bool_field b j ~what:"rules" "computed" true ;
          bool_field b j ~what:"rules" "contract_ok" true ;
          Batch.eq_string_opt b ~msg:"rules.verdict"
            (match Json.member "verdict" j with Some (`String s) -> Some s | _ -> None)
            (Some "fail") ;
          int_field b j ~what:"rules" "failing" 2 ;
          int_field b j ~what:"rules" "unknown" 1 ;
          int_field b j ~what:"rules" "vacuous" 0 ;
          int_field b j ~what:"rules" "not_computed" 0 ;
          (match Json.list ~what:"rules" "failed" j with
          | Ok l -> Batch.eq_int b ~msg:"rules.failed must match rules.failing" (List.length l) 2
          | Error e -> Batch.note b "%s" e) ;
          Batch.exit_code b ~msg:"a 'fail' verdict must be exit code 1" ~expected:1
            (rules [db; rf])) ;
  Lwt.return_unit

let register_selectors () =
  Test.register ~__FILE__ ~title:"rules: a glob boundary slip breaks verdicts both ways"
    ~tags:["rules"; "selectors"]
  @@ fun () ->
  let db = Fixture.flat ~name:"rules_sel" layered_stream in
  Batch.run (fun b ->
      (* `**/write.ts` must match write.ts and NOT my_write.ts. Asserted on
         target_size, because a verdict alone cannot tell a rule aimed at one
         file from one that swept up its neighbour. *)
      let bf = rule_file "boundary" "rule \"boundary\"\n  forbid reach from file:src/ui/** to file:**/write.ts\n" in
      (match rules_json b ~what:"boundary" [db; bf; "--format"; "json"] with
      | None -> ()
      | Some j -> (
          Batch.eq_string_opt b ~msg:"the boundary rule still finds the MUST path"
            (verdict_of j ~prefix:"boundary") (Some "VIOLATION") ;
          match Json.list ~what:"boundary" "results" j with
          | Ok (`Assoc f :: _) ->
              Batch.eq_string_opt b
                ~msg:"**/write.ts must match write.ts ONLY, not my_write.ts"
                (match List.assoc_opt "target_size" f with
                | Some (`Int n) -> Some (string_of_int n)
                | _ -> None)
                (Some "1")
          | _ -> Batch.note b "the boundary rule produced no result row")) ;

      let ef =
        rule_file "exported"
          "rule \"only the api layer is exported\"\n  forbid exported outside file:src/api/**\n"
      in
      match rules_json b ~what:"exported" [db; ef; "--format"; "json"] with
      | None -> ()
      | Some j -> (
          Batch.eq_string_opt b ~msg:"exported-outside must flag the offender"
            (verdict_of j ~prefix:"only the api") (Some "VIOLATION") ;
          match Json.list ~what:"exported" "results" j with
          | Ok (`Assoc f :: _) -> (
              match List.assoc_opt "detail" f with
              | Some (`List detail) ->
                  let shown =
                    String.concat ","
                      (List.filter_map (function `String s -> Some s | _ -> None) detail)
                  in
                  Batch.eq_int b ~msg:"exported-outside must flag exactly one function"
                    (List.length detail) 1 ;
                  Batch.contains b ~msg:"exported-outside must flag ui.handle" ~haystack:shown
                    "ui.handle"
              | _ -> Batch.note b "the exported rule has no detail list")
          | _ -> Batch.note b "the exported rule produced no result row")) ;
  Lwt.return_unit

let register_exit_policy () =
  Test.register ~__FILE__ ~title:"rules: the exit-code policy, including the flags that disable it"
    ~tags:["rules"; "policy"]
  @@ fun () ->
  let db = Fixture.flat ~name:"rules_policy" layered_stream in
  let rf = rule_file "four_p" four_rules in
  Batch.run (fun b ->
      (* A rule matching no code is a gate that gates nothing. *)
      let vf =
        rule_file "vacuous"
          "rule \"aimed at nothing\"\n  forbid reach from file:src/nonexistent/** to file:lib/db/**\n"
      in
      Batch.exit_code b ~msg:"a rule matching no code must FAIL by default" ~expected:1
        (rules [db; vf]) ;
      Batch.exit_code b ~msg:"--on-vacuous warn must downgrade it" ~expected:0
        (rules [db; vf; "--on-vacuous"; "warn"]) ;

      let pf = rule_file "possible" "rule \"p\"\n  forbid reach from file:src/api/** to file:lib/db/**\n" in
      Batch.exit_code b ~msg:"POSSIBLE must fail by default" ~expected:1 (rules [db; pf]) ;
      Batch.exit_code b ~msg:"--on-possible warn must not fail" ~expected:0
        (rules [db; pf; "--on-possible"; "warn"]) ;

      let uf = rule_file "unknown" "rule \"u\"\n  forbid reach from file:src/job/** to file:lib/db/**\n" in
      Batch.exit_code b ~msg:"UNKNOWN must be fail-open by default" ~expected:0 (rules [db; uf]) ;
      Batch.exit_code b ~msg:"--on-unknown fail must fail" ~expected:1
        (rules [db; uf; "--on-unknown"; "fail"]) ;

      (* `--on-possible fial` used to compare unequal to "fail" and turn a
         failing rule green: the safest-looking flag in the tool was the one
         that removed the check. *)
      List.iter
        (fun flag ->
          Batch.exit_code b
            ~msg:
              (Printf.sprintf
                 "%s with a misspelled value must abort, not be read as 'do not fail'" flag)
            ~expected:2
            (rules [db; rf; flag; "fial"]))
        ["--on-unknown"; "--on-possible"; "--on-vacuous"; "--on-not-computed"]) ;
  Lwt.return_unit

let register_malformed_rules () =
  Test.register ~__FILE__ ~title:"rules: a rule file it cannot parse aborts the gate"
    ~tags:["rules"; "policy"]
  @@ fun () ->
  let db = Fixture.flat ~name:"rules_malformed" layered_stream in
  Batch.run (fun b ->
      (* A gate that silently skips the rule it could not parse is a gate that
         silently stops gating. *)
      List.iteri
        (fun i bad ->
          Batch.exit_code b
            ~msg:(Printf.sprintf "malformed rule file #%d must abort: %S" i bad)
            ~expected:2
            (rules [db; rule_file (Printf.sprintf "bad%d" i) (bad ^ "\n")]))
        [
          "forbid reach from file:a to file:b";
          "rule \"x\"";
          "rule \"x\"\n  forbid teleport from file:a to file:b";
          "rule \"x\"\n  forbid reach from a to file:b";
        ] ;
      Batch.exit_code b
        ~msg:"an empty rules file must abort — reporting a vacuous all-pass is worse" ~expected:2
        (rules [db; rule_file "empty" ""])) ;
  Lwt.return_unit

let register_no_contract () =
  Test.register ~__FILE__ ~title:"rules: an un-⊤-marked index can never yield PASS"
    ~tags:["rules"; "contract"]
  @@ fun () ->
  (* The same graph SHAPE as the closed-cone case, built without the contract:
     "no path" there may merely hide a dropped dynamic edge, so the proof is not
     available and must not be claimed. *)
  let legacy =
    Fixture.raw ~name:"rules_legacy"
      {|
CREATE TABLE functions(name TEXT, file_path TEXT, exported INTEGER DEFAULT 0,
                       line_start INTEGER, line_end INTEGER);
CREATE TABLE calls(caller_name TEXT, caller_file TEXT, callee_name TEXT, callee_file TEXT,
                   call_site TEXT);
INSERT INTO functions(name,file_path) VALUES ('pure.calc','src/pure/calc.ts'),
                                             ('pure.inner','src/pure/inner.ts'),
                                             ('db.write','lib/db/write.ts');
INSERT INTO calls VALUES ('pure.calc','src/pure/calc.ts','pure.inner','src/pure/inner.ts','x:1');
|}
  in
  let lf = rule_file "legacy" "rule \"l\"\n  forbid reach from file:src/pure/** to file:lib/db/**\n" in
  Batch.run (fun b ->
      (match rules_json b ~what:"legacy" [legacy; lf; "--format"; "json"] with
      | None -> ()
      | Some j ->
          Batch.eq_string_opt b ~msg:"PASS must degrade to UNKNOWN_NO_CONTRACT"
            (verdict_of j ~prefix:"l") (Some "UNKNOWN_NO_CONTRACT") ;
          bool_field b j ~what:"legacy" "contract_ok" false ;
          Batch.eq_string_opt b
            ~msg:"UNKNOWN_NO_CONTRACT is fail-open by default, so the run verdict is pass"
            (match Json.member "verdict" j with Some (`String s) -> Some s | _ -> None)
            (Some "pass")) ;
      Batch.exit_code b ~msg:"a 'pass' verdict must be exit code 0" ~expected:0
        (rules [legacy; lf]) ;

      (* The shared malformed fixture: arch-rules must agree with arch-impact,
         arch-coverage and arch-mutants, which all read Arch_db.contract_ok. *)
      let malformed = Fixture.malformed_contract ~name:"rules_malformed_contract" in
      let mf = rule_file "malformed" "rule \"m\"\n  forbid reach from fn:A to fn:sink\n" in
      match rules_json b ~what:"malformed" [malformed; mf; "--format"; "json"] with
      | None -> ()
      | Some j ->
          bool_field b j ~what:"malformed" "contract_ok" false ;
          Batch.check b
            ~msg:"a NULL-kind edge must never yield a false-sound PASS"
            (verdict_of j ~prefix:"m" <> Some "PASS")) ;
  Lwt.return_unit

let witness_of j ~prefix =
  match Json.member "results" j with
  | Some (`List rs) ->
      List.find_map
        (function
          | `Assoc f -> (
              match List.assoc_opt "rule" f with
              | Some (`String r) when has_prefix ~prefix r -> (
                  match List.assoc_opt "witness" f with
                  | Some (`List w) ->
                      Some (List.filter_map (function `String s -> Some s | _ -> None) w)
                  | _ -> None)
              | _ -> None)
          | _ -> None)
        rs
  | _ -> None

let register_witness () =
  Test.register ~__FILE__
    ~title:"rules: VIOLATION/POSSIBLE/UNKNOWN carry a concrete witness path; PASS carries none"
    ~tags:["rules"; "witness"]
  @@ fun () ->
  let db = Fixture.flat ~name:"rules_witness" layered_stream in
  let rf = rule_file "four_w" four_rules in
  Batch.run (fun b ->
      match rules_json b ~what:"witness" [db; rf; "--format"; "json"] with
      | None -> ()
      | Some j ->
          (* VIOLATION: ui.handle --MUST--> db.write. The witness is the proof itself, not
             just the offender name — checked POSITIONALLY (index 0 = source, index 1 =
             target), not merely "both names appear somewhere", so a reversed or shuffled
             path fails this test even though both names are still present. *)
          (match witness_of j ~prefix:"ui must" with
          | Some [ hop0; hop1 ] ->
              Batch.contains b ~msg:"VIOLATION witness hop 0 is the source, ui.handle" ~haystack:hop0
                "ui.handle" ;
              Batch.contains b ~msg:"VIOLATION witness hop 1 is the target, db.write" ~haystack:hop1
                "db.write"
          | Some w ->
              Batch.note b "VIOLATION witness has %d hop(s), expected exactly 2" (List.length w)
          | None -> Batch.note b "no witness field for the VIOLATION rule") ;
          (* POSSIBLE: api.serve --MAY_ENUMERATED--> db.write. *)
          (match witness_of j ~prefix:"api must" with
          | Some [ hop0; hop1 ] ->
              Batch.contains b ~msg:"POSSIBLE witness hop 0 is the source, api.serve" ~haystack:hop0
                "api.serve" ;
              Batch.contains b ~msg:"POSSIBLE witness hop 1 is the target, db.write" ~haystack:hop1
                "db.write"
          | Some w ->
              Batch.note b "POSSIBLE witness has %d hop(s), expected exactly 2" (List.length w)
          | None -> Batch.note b "no witness field for the POSSIBLE rule") ;
          (* UNKNOWN: job.run --MUST--> util.helper --MAY_TOP--> ⊤. The escape happens AT
             util.helper (it is the caller that holds the ⊤ edge), so the witness is the path
             from job.run to util.helper, not to some further, nonexistent node. *)
          (match witness_of j ~prefix:"jobs must" with
          | Some [ hop0; hop1 ] ->
              Batch.contains b ~msg:"UNKNOWN witness hop 0 is the source, job.run" ~haystack:hop0
                "job.run" ;
              Batch.contains b ~msg:"UNKNOWN witness hop 1 is the ⊤-holding caller, util.helper"
                ~haystack:hop1 "util.helper"
          | Some w ->
              Batch.note b "UNKNOWN witness has %d hop(s), expected exactly 2" (List.length w)
          | None -> Batch.note b "no witness field for the UNKNOWN rule") ;
          (* PASS: a real proof carries no reachability claim beyond the closed cone itself —
             no witness is needed or produced. *)
          (match witness_of j ~prefix:"pure code" with
          | Some w -> Batch.eq_int b ~msg:"PASS carries no witness" (List.length w) 0
          | None -> Batch.note b "no witness field for the PASS rule")) ;
  Lwt.return_unit

(* chain.a --MUST--> chain.mid --MUST--> chain.target   the ONLY all-MUST path, 2 hops
   chain.a --MAY_ENUMERATED--> chain.target              a shorter, mixed-kind shortcut, 1 hop
   A rule from chain.a to chain.target is VIOLATION (a MUST path exists) — {!layered_stream}'s
   own cases never put a shorter non-MUST edge alongside a longer all-MUST one for the SAME
   src/dst pair, so nothing in that fixture can tell "VIOLATION's witness walks must_fwd" apart
   from "VIOLATION's witness walks fwd and got lucky": both adjacency choices would return some
   2-key path when only one edge kind exists per hop. Here they diverge in LENGTH, so a witness
   walking `fwd` (which would take the shorter shortcut) is observably distinguishable from one
   walking `must_fwd` (which is forced through the long way, since the shortcut is not MUST). *)
let adjacency_stream =
  {|{"type":"function","name":"chain.a","file_path":"src/chain/a.ts"}
{"type":"function","name":"chain.mid","file_path":"src/chain/mid.ts"}
{"type":"function","name":"chain.target","file_path":"src/chain/target.ts"}
{"type":"call","caller_name":"chain.a","caller_file":"src/chain/a.ts","callee_name":"chain.mid","callee_file":"src/chain/mid.ts","call_site":"src/chain/a.ts:2","kind":"MUST"}
{"type":"call","caller_name":"chain.mid","caller_file":"src/chain/mid.ts","callee_name":"chain.target","callee_file":"src/chain/target.ts","call_site":"src/chain/mid.ts:2","kind":"MUST"}
{"type":"call","caller_name":"chain.a","caller_file":"src/chain/a.ts","callee_name":"chain.target","callee_file":"src/chain/target.ts","call_site":"src/chain/a.ts:5","kind":"MAY_ENUMERATED"}
|}

let register_witness_adjacency () =
  Test.register ~__FILE__
    ~title:"rules: VIOLATION's witness walks must_fwd even when a shorter fwd path exists"
    ~tags:["rules"; "witness"]
  @@ fun () ->
  let db = Fixture.flat ~name:"rules_witness_adjacency" adjacency_stream in
  let rf =
    rule_file "chain" "rule \"chain\"\n  forbid reach from fn:chain.a to fn:chain.target\n"
  in
  Batch.run (fun b ->
      match rules_json b ~what:"chain" [db; rf; "--format"; "json"] with
      | None -> ()
      | Some j ->
          Batch.eq_string_opt b ~msg:"a MUST path exists, so the verdict is VIOLATION"
            (verdict_of j ~prefix:"chain") (Some "VIOLATION") ;
          (match witness_of j ~prefix:"chain" with
          | Some [ hop0; hop1; hop2 ] ->
              Batch.contains b ~msg:"witness hop 0 is the source, chain.a" ~haystack:hop0 "chain.a" ;
              Batch.contains b ~msg:"witness hop 1 is the MUST-only intermediate, chain.mid"
                ~haystack:hop1 "chain.mid" ;
              Batch.contains b ~msg:"witness hop 2 is the target, chain.target" ~haystack:hop2
                "chain.target"
          | Some w ->
              Batch.note b
                "witness has %d hop(s) — expected the 3-hop all-MUST path, not the 1-hop \
                 MAY_ENUMERATED shortcut (which would produce 2)"
                (List.length w)
          | None -> Batch.note b "no witness field for the chain rule")) ;
  Lwt.return_unit

let register_not_computed () =
  Test.register ~__FILE__ ~title:"rules: a rule that was never evaluated is not a passing rule"
    ~tags:["rules"; "policy"]
  @@ fun () ->
  let db = Fixture.flat ~name:"rules_notcomputed" layered_stream in
  let nf =
    rule_file "notcomputed"
      {|rule "no global mutation from ui"
  forbid effect from file:src/ui/** kind:GlobalVar
rule "ui must not declare a dep on db"
  forbid dep from module:src/ui/** to module:lib/db/**
|}
  in
  Batch.run (fun b ->
      (match rules_json b ~what:"not_computed" [db; nf; "--format"; "json"] with
      | None -> ()
      | Some j ->
          (match Json.list ~what:"not_computed" "results" j with
          | Ok rs ->
              let verdicts =
                String.concat "," (Json.field_of_objects ~field:"verdict" rs)
              in
              Batch.eq_string b
                ~msg:"effect/dep rules on an index lacking that data must say NOT_COMPUTED"
                verdicts "NOT_COMPUTED,NOT_COMPUTED"
          | Error e -> Batch.note b "%s" e) ;
          (* Saying NOT_COMPUTED is only half the job. Unlike UNKNOWN — an
             analysis RESULT — NOT_COMPUTED means the rule was never evaluated,
             and a rule that reads "n/a" on every run is indistinguishable from
             one that passes. *)
          int_field b j ~what:"not_computed" "not_computed" 2 ;
          int_field b j ~what:"not_computed" "failing" 2 ;
          int_field b j ~what:"not_computed" "unknown" 0 ;
          int_field b j ~what:"not_computed" "vacuous" 0 ;
          (match Json.list ~what:"not_computed" "failed" j with
          | Ok l ->
              Batch.eq_int b ~msg:"NOT_COMPUTED rules must be listed under failed"
                (List.length l) 2
          | Error e -> Batch.note b "%s" e)) ;
      Batch.exit_code b ~msg:"NOT_COMPUTED must fail the gate by default" ~expected:1
        (rules [db; nf]) ;
      Batch.exit_code b ~msg:"--on-not-computed warn must downgrade it" ~expected:0
        (rules [db; nf; "--on-not-computed"; "warn"])) ;
  Lwt.return_unit

let register_summary_line () =
  Test.register ~__FILE__
    ~title:"rules: the text summary must not report a three-state verdict as one number"
    ~tags:["rules"; "summary"]
  @@ fun () ->
  let db = Fixture.flat ~name:"rules_summary" layered_stream in
  Batch.run (fun b ->
      (* The channel a human reads was the dishonest one. Every other test in
         this file asserts against --format json, which has always carried
         `unknown`; the default text summary omitted it, so "N rule(s), 0
         failing" over a run that proved nothing read as a pass. That is
         specs/qualified-unit-resolution.md §10.5 — a three-state verdict
         reported as one number — and it was misread in practice, twice. *)
      let uf =
        rule_file "summary_unknown"
          "rule \"u\"\n  forbid reach from file:src/job/** to file:lib/db/**\n"
      in
      let code, out = rules [db; uf] in
      (* UNKNOWN is fail-open, so this run genuinely exits 0. The exit code is
         not the defect; the summary claiming it as a result is. *)
      Batch.eq_int b ~msg:"an UNKNOWN-only run still exits 0 (fail-open)" code 0 ;
      Batch.contains b ~msg:"the summary must state how many rules were UNKNOWN"
        ~haystack:out "1 unknown" ;
      Batch.contains b
        ~msg:"the summary must state how many rules were actually PROVED, not only how many failed"
        ~haystack:out "0 proved" ;
      (* The line must not be readable as a pass. Before this test the whole
         summary for this input was "1 rule(s), 0 failing". *)
      Batch.check b
        ~msg:"a run that proved nothing must not summarise as only a failing count"
        (String.trim out <> "1 rule(s), 0 failing") ;

      (* All four verdicts at once: VIOLATION + POSSIBLE fail, UNKNOWN is
         fail-open, PASS is the only proof. Each count must appear separately,
         so no two states can be collapsed into one another. *)
      let rf = rule_file "summary_four" four_rules in
      let _, out4 = rules [db; rf] in
      Batch.contains b ~msg:"four-rule summary names the proved count" ~haystack:out4 "1 proved" ;
      Batch.contains b ~msg:"four-rule summary names the failing count" ~haystack:out4 "2 failing" ;
      Batch.contains b ~msg:"four-rule summary names the UNKNOWN count" ~haystack:out4 "1 unknown" ;
      (* POSSIBLE was the state the first version of this summary forgot. It is
         fail-OPEN under --on-possible warn, so on that run it appeared in no
         count at all: "4 rule(s), 1 proved, 1 failing, 1 UNKNOWN" accounted for
         three of four rules and the missing one was the state that means a
         dynamic dispatch could land on the forbidden target. *)
      Batch.contains b ~msg:"four-rule summary names the POSSIBLE count" ~haystack:out4
        "1 possible" ;
      Batch.contains b ~msg:"four-rule summary names the VIOLATION count" ~haystack:out4
        "1 violation" ;
      let _, out_pw = rules [db; rf; "--on-possible"; "warn"] in
      Batch.contains b
        ~msg:"POSSIBLE must be named even when the policy lets it through the gate"
        ~haystack:out_pw "1 possible") ;
  Lwt.return_unit

(* The census line must PARTITION the rules: every rule has exactly one verdict,
   so the counts on it sum to the rule count. The previous line could not be read
   that way — it printed `failing`, a policy aggregate that overlaps six of the
   seven verdict states, in among the verdict counts, so "4 rule(s), 1 proved,
   3 failing, 1 UNKNOWN" summed to 5 over 4 rules.

   Mutations this kills: printing `failing` inside the census again (the sum
   exceeds the total); dropping any state from the census (the sum falls short);
   merging UNKNOWN with UNKNOWN_NO_CONTRACT (the two-index case below); making
   the per-state lines conditional such that "0 proved" can vanish. *)
let has_sub ~haystack sub =
  let n = String.length sub and m = String.length haystack in
  let rec go i = i + n <= m && (String.sub haystack i n = sub || go (i + 1)) in
  go 0

let census_of line =
  (* "N rule(s): a x, b y, ..." -> [(x, a); ...] *)
  match String.index_opt line ':' with
  | None -> []
  | Some i ->
      String.sub line (i + 1) (String.length line - i - 1)
      |> String.split_on_char ','
      |> List.filter_map (fun part ->
             match String.split_on_char ' ' (String.trim part) with
             | [n; name] -> ( match int_of_string_opt n with Some n -> Some (name, n) | None -> None)
             | _ -> None)

let summary_lines out =
  String.split_on_char '\n' out
  |> List.filter (fun l -> has_sub ~haystack:l "rule(s):" || has_sub ~haystack:l "gate:")

let register_summary_partitions () =
  Test.register ~__FILE__
    ~title:"rules: the summary census partitions the rules, and the gate is a separate line"
    ~tags:["rules"; "summary"]
  @@ fun () ->
  let db = Fixture.flat ~name:"rules_partition" layered_stream in
  let rf = rule_file "partition_four" four_rules in
  Batch.run (fun b ->
      List.iter
        (fun (flags, expected_gate) ->
          let _, out = rules ([db; rf] @ flags) in
          match summary_lines out with
          | [census; gate] ->
              let cs = census_of census in
              Batch.eq_int b
                ~msg:
                  (Printf.sprintf "the census must cover all 4 rules under %s"
                     (String.concat " " flags))
                (List.fold_left (fun a (_, n) -> a + n) 0 cs)
                4 ;
              (* Every state gets a number, present or not. A state that only
                 appears when non-zero cannot be told from a state the tool does
                 not have, and "0 proved" is the single most important thing
                 this line ever says. *)
              List.iter
                (fun k ->
                  Batch.check b
                    ~msg:(Printf.sprintf "the census must always name %S" k)
                    (List.mem_assoc k cs))
                ["proved"; "violation"; "possible"; "unknown"; "unknown-no-contract"; "vacuous";
                 "not-computed"] ;
              (* The gate is policy-dependent and overlaps the census, so it
                 lives on its own line and is never added to those counts. *)
              Batch.contains b
                ~msg:
                  (Printf.sprintf "the gate line must report %d failing under %s" expected_gate
                     (String.concat " " flags))
                ~haystack:gate
                (Printf.sprintf "%d failing" expected_gate) ;
              (* The parenthetical used to read "fail-open by default" even to an
                 operator who had passed --on-unknown fail: a newly-written
                 sentence false for the run it annotated. It must read the LIVE
                 policy. *)
              List.iter
                (fun (flag, value) ->
                  if List.mem flag flags then
                    Batch.contains b
                      ~msg:(Printf.sprintf "the gate line must state the LIVE %s policy" flag)
                      ~haystack:gate value)
                [("--on-unknown", "unknown=fail"); ("--on-possible", "possible=warn")]
          | ls ->
              Batch.note b "expected exactly one census line and one gate line, got %d"
                (List.length ls))
        [([], 2); (["--on-unknown"; "fail"], 3); (["--on-possible"; "warn"], 1)] ;

      (* --format md is not decoration: scripts/pcc/pcc-dossier embeds this output
         verbatim into a Markdown dossier a human reads. In Markdown two
         consecutive plain lines are ONE paragraph — a renderer reflows them onto
         a single line and puts the census and the gate back together, which is
         exactly the conflation this split exists to undo. The two lines are
         therefore bullets, and that is load-bearing.

         Mutation this kills (the reviewer's N10): `let bullet = ""` unconditionally
         in arch_rules.ml. It survived the whole suite, tezt/tests/pcc.ml included,
         before this assertion existed. *)
      let _, out_md = rules [db; rf; "--format"; "md"] in
      let md_summary = summary_lines out_md in
      Batch.eq_int b ~msg:"--format md prints exactly one census line and one gate line"
        (List.length md_summary) 2 ;
      List.iter
        (fun l ->
          Batch.check b
            ~msg:
              (Printf.sprintf
                 "in --format md the summary line %S must be a bullet, or Markdown reflows the \
                  census and the gate into one paragraph"
                 l)
            (String.length l >= 2 && String.sub l 0 2 = "- "))
        md_summary ;

      (* An all-PASS run must not mention states it does not have, beyond the
         zeros in the census itself: no cause line for a state with no members.
         Kills the mutant that makes the explanatory lines unconditional, which
         printed "the cone escapes through a ⊤ edge" over a run where nothing
         escaped. *)
      let pf =
        rule_file "partition_pass"
          "rule \"p\"\n  forbid reach from file:src/pure/** to file:lib/db/**\n"
      in
      let code, outp = rules [db; pf] in
      Batch.eq_int b ~msg:"an all-PASS run exits 0" code 0 ;
      Batch.contains b ~msg:"an all-PASS run reports 1 proved" ~haystack:outp "1 proved" ;
      Batch.check b
        ~msg:"an all-PASS run must not print the ⊤-edge explanation for a state it does not have"
        (not (has_sub ~haystack:outp "cone reaches a ⊤ edge"))) ;
  Lwt.return_unit

(* UNKNOWN and UNKNOWN_NO_CONTRACT were counted together and explained with ONE
   sentence — "the cone escapes through a ⊤ edge" — which is false for the
   second: no cone escaped, the index was never ⊤-marked, so nothing could have
   been proved for any rule on it. Different cause, different fix.

   Mutation this kills (the reviewer's M6): dropping UNKNOWN_NO_CONTRACT from the
   count. Before the split it survived all 9 tests in this file. *)
let register_two_unknowns_are_two_states () =
  Test.register ~__FILE__
    ~title:"rules: an escaping cone and an un-⊤-marked index are not the same UNKNOWN"
    ~tags:["rules"; "summary"]
  @@ fun () ->
  (* The same graph twice: once ⊤-marked, once not. The rule is identical, so the
     ONLY thing that can move the verdict is the contract. *)
  let marked = Fixture.flat ~name:"rules_two_unk_marked" layered_stream in
  let unmarked = Fixture.flat ~name:"rules_two_unk_unmarked" layered_stream in
  Db.with_db_rw unmarked (fun conn ->
      Db.exec conn "DELETE FROM comment_db_meta WHERE key = 'callgraph_contract'") ;
  let uf =
    rule_file "two_unknowns_escaping"
      "rule \"u\"\n  forbid reach from file:src/job/** to file:lib/db/**\n"
  in
  let pf =
    rule_file "two_unknowns_closed"
      "rule \"p\"\n  forbid reach from file:src/pure/** to file:lib/db/**\n"
  in
  Batch.run (fun b ->
      let _, out_esc = rules [marked; uf] in
      Batch.contains b ~msg:"an escaping cone is counted as `unknown`" ~haystack:out_esc
        "1 unknown, 0 unknown-no-contract" ;
      let _, out_nc = rules [unmarked; pf] in
      Batch.contains b
        ~msg:"an un-⊤-marked index is counted as `unknown-no-contract`, NOT as `unknown`"
        ~haystack:out_nc "0 unknown, 1 unknown-no-contract" ;
      Batch.check b
        ~msg:"UNKNOWN_NO_CONTRACT must not be explained as an escaping cone — nothing escaped"
        (not (has_sub ~haystack:out_nc "cone reaches a ⊤ edge")) ;
      Batch.contains b
        ~msg:"UNKNOWN_NO_CONTRACT must be explained by the missing contract"
        ~haystack:out_nc "not ⊤-marked" ;
      (* JSON keeps `unknown` as the union — gates read it — and gains the split
         pair, so text and JSON can be checked against each other. *)
      match rules_json b ~what:"no_contract" [unmarked; pf; "--format"; "json"] with
      | None -> ()
      | Some j ->
          int_field b j ~what:"no_contract" "unknown" 1 ;
          int_field b j ~what:"no_contract" "unknown_escaping" 0 ;
          int_field b j ~what:"no_contract" "unknown_no_contract" 1 ;
          int_field b j ~what:"no_contract" "proved" 0) ;
  Lwt.return_unit

(* `pass` was emitted with NO vacuity check at all for `dep`, `exported` and
   `effect`: only `reach` had NO_SOURCE/NO_TARGET. So --on-vacuous fail — the
   flag that exists precisely to catch a rule that has stopped matching —
   covered one rule form in four, and the other three printed the word "proved"
   for a rule that could not fail.

   The `exported` case contradicted itself on screen: the note said the selector
   matched nothing, and two lines below the summary said proved. *)
let register_vacuity_covers_every_rule_form () =
  Test.register ~__FILE__
    ~title:"rules: --on-vacuous covers every rule form, not only `reach`"
    ~tags:["rules"; "policy"; "vacuous"]
  @@ fun () ->
  (* No function here is exported, and no effects table is populated. *)
  let bare =
    Fixture.flat ~name:"rules_vacuous_forms"
      {|{"type":"function","name":"a.one","file_path":"src/a/one.ts"}
{"type":"function","name":"a.two","file_path":"src/a/two.ts"}
{"type":"call","caller_name":"a.one","caller_file":"src/a/one.ts","callee_name":"a.two","callee_file":"src/a/two.ts","call_site":"src/a/one.ts:1","kind":"MUST"}
|}
  in
  Batch.run (fun b ->
      let ef =
        rule_file "vac_exported"
          "rule \"nothing is named like this\"\n  forbid exported outside file:zzzz/nope/**\n"
      in
      Batch.exit_code b
        ~msg:"an `exported` rule over an index with no exported function must FAIL --on-vacuous fail"
        ~expected:1
        (rules [bare; ef; "--on-vacuous"; "fail"]) ;
      let _, out_e = rules [bare; ef; "--on-vacuous"; "fail"] in
      Batch.check b ~msg:"a vacuous `exported` rule must not be summarised as proved"
        (has_sub ~haystack:out_e "0 proved" && has_sub ~haystack:out_e "1 vacuous") ;
      Batch.exit_code b ~msg:"--on-vacuous warn still downgrades it" ~expected:0
        (rules [bare; ef; "--on-vacuous"; "warn"]) ;

      (* A selector that matches no function makes the effect cone empty, so "no
         effect found" is a statement about the empty set. Asserted on a main
         index WITH an effects table, so the verdict cannot be NOT_COMPUTED. *)
      let eff_db =
        Fixture.main ~name:"rules_vacuous_effect"
          ~seed:
            "INSERT INTO modules (id, path) VALUES (1, 'src/a/one.ml');\n\
             INSERT INTO functions (id, module_id, name) VALUES (1, 1, 'one');\n\
             INSERT INTO comment_db_meta (key, value) VALUES ('callgraph_contract', 'v1');" ()
      in
      Db.with_db_rw eff_db (fun conn ->
          Db.exec conn
            (read_file (locate ~env_var:"ARCH_EFFECTS_MIGRATION" "effects-schema-migration.sql")) ;
          (* Non-empty, because arch-rules reports NOT_COMPUTED on an EMPTY
             function_effects table — which would satisfy the vacuity assertion
             below for the wrong reason and make it a check that checks nothing. *)
          Db.exec conn
            "INSERT INTO function_effects (function_name, file_path, value_kind, target, \
             is_direct, soundness) VALUES ('one', 'src/a/one.ml', 'GlobalVar', 'g', 1, 'sound')") ;
      let ff =
        rule_file "vac_effect"
          "rule \"aimed at nothing\"\n  forbid effect from file:zzzz/nope/** kind:GlobalVar\n"
      in
      let _, out_f = rules [eff_db; ff; "--on-vacuous"; "fail"] in
      Batch.contains b ~msg:"a vacuous `effect` rule is VACUOUS, not proved" ~haystack:out_f
        "1 vacuous" ;
      Batch.exit_code b ~msg:"a vacuous `effect` rule must FAIL --on-vacuous fail" ~expected:1
        (rules [eff_db; ff; "--on-vacuous"; "fail"]) ;

      (* `dep` reads module paths from a table, so its vacuity is a source
         selector matching no module. The TARGET side gets no such check on
         purpose: a `dep` target ranges over modules already depended on, so
         "nothing matches Web.**" is the preventive rule SUCCEEDING, and calling
         it vacuous would fail the gate exactly when the codebase is clean. *)
      let dep_db =
        Fixture.main ~name:"rules_vacuous_dep"
          ~seed:
            "INSERT INTO modules (id, path) VALUES (1, 'lib/core/engine.ml'), (2, \
             'lib/util/str.ml');\n\
             INSERT INTO functions (id, module_id, name) VALUES (1, 1, 'run'), (2, 2, 'trim');\n\
             INSERT INTO module_deps (source_module, target_module, target_path, dep_kind, \
             line_number) VALUES (1, 2, 'lib/util/str.ml', 'open', 1);\n\
             INSERT INTO comment_db_meta (key, value) VALUES ('callgraph_contract', 'v1');" ()
      in
      let df =
        rule_file "vac_dep"
          "rule \"no such module anywhere\"\n\
          \  forbid dep from module:zzzz/nope/** to module:Qqqq.**\n"
      in
      Batch.exit_code b ~msg:"a `dep` rule whose source matches no module must FAIL --on-vacuous fail"
        ~expected:1
        (rules [dep_db; df; "--on-vacuous"; "fail"]) ;
      let _, out_d = rules [dep_db; df; "--on-vacuous"; "fail"] in
      Batch.contains b ~msg:"a vacuous `dep` rule reports 0 proved" ~haystack:out_d "0 proved" ;
      Batch.contains b ~msg:"a vacuous `dep` rule reports 1 vacuous" ~haystack:out_d "1 vacuous" ;

      (* The control that stops the check above from being satisfied by absence:
         a real source with an unmatched TARGET must still be a PASS, not
         VACUOUS. Without this, "everything is vacuous" would pass the test. *)
      let pf =
        rule_file "dep_preventive"
          "rule \"core must not depend on the web framework\"\n\
          \  forbid dep from module:lib/core/** to module:Web.**\n"
      in
      Batch.exit_code b
        ~msg:"a preventive `dep` rule whose target matches nothing must PASS, not be VACUOUS"
        ~expected:0
        (rules [dep_db; pf; "--on-vacuous"; "fail"]) ;
      let _, out_p = rules [dep_db; pf; "--on-vacuous"; "fail"] in
      Batch.contains b ~msg:"the preventive `dep` rule is proved, not vacuous" ~haystack:out_p
        "1 proved" ;
      Batch.contains b ~msg:"the preventive `dep` rule is not counted vacuous" ~haystack:out_p
        "0 vacuous" ;

      (* Same control on the `exported` side: with exported functions present, an
         empty selector is a VIOLATION (every export is an offender), never
         downgraded to VACUOUS. A verdict you FOUND is never demoted. *)
      let exp_db = Fixture.flat ~name:"rules_vacuous_exp_control" layered_stream in
      Batch.exit_code b
        ~msg:"an empty `exported` selector over a real export set stays a VIOLATION"
        ~expected:1
        (rules [exp_db; ef]) ;
      let _, out_c = rules [exp_db; ef] in
      Batch.contains b ~msg:"that control is a violation, not a vacuity" ~haystack:out_c
        "1 violation" ;
      Batch.contains b ~msg:"that control is not counted vacuous" ~haystack:out_c "0 vacuous") ;
  Lwt.return_unit

(** Roadmap 2.4 — the [ext:] selector.

    An external leaf is a call whose callee has no indexed body: the edge is asserted to happen,
    towards something the index does not hold. On Octez that is 58.3% of all MUST edges, and it is
    where the raw-arithmetic gate has to aim — [Stdlib.+] is not a node, so no other selector kind
    can name it.

    Four things are asserted, and only the first is about the happy path:

    - it selects, and the population is exactly the external leaves, not every callee;
    - it is REFUSED in the five positions where it could only be inert, and refused loudly
      (exit 2) — an inert selector yields a green verdict the rule never earned;
    - it is NOT_COMPUTED on a flat index. [arch-load] synthesises a [functions] row for every
      callee it sees, so that schema {b cannot represent an external leaf at all}: a stream
      declaring two functions and calling [Stdlib.+] writes three. "Matched nothing" there would
      read as a typo in the pattern rather than as a property of the index;
    - and a cone reaching no external still PASSes, which is the control proving the VIOLATION
      came from the edge rather than from a selector matching everything. *)

(* Main schema, because it is the only one that can hold an external leaf: `calls.callee_id IS
   NULL` is the representation, and it has no flat equivalent.

   calc.add   --MUST--> (NULL) Stdlib.+          an asserted call we cannot follow
   calc.add   --MUST--> (NULL) Stdlib.List.iter  a second, so a glob can over-match
   calc.pure  --MUST--> calc.inner               a closed cone: no external reachable *)
let ext_seed =
  "INSERT INTO modules(path,lines) VALUES ('src/calc/add.ml',10),('src/calc/pure.ml',10),\
   ('src/calc/inner.ml',10); \
   INSERT INTO functions(id,module_id,name) VALUES (1,1,'calc.add'),(2,2,'calc.pure'),\
   (3,3,'calc.inner'); \
   INSERT INTO calls(caller_id,callee_id,callee_name,kind) VALUES \
   (1,NULL,'Stdlib.+','MUST'),(1,NULL,'Stdlib.List.iter','MUST'),(2,3,'calc.inner','MUST'); \
   INSERT OR REPLACE INTO comment_db_meta(key,value) VALUES ('callgraph_contract','v1');"

let register_ext_selector () =
  Test.register ~__FILE__ ~title:"rules: ext: names external leaves, and is refused where it would be inert"
    ~tags:["rules"; "selectors"; "ext"]
  @@ fun () ->
  let db = Fixture.main ~name:"rules_ext" ~seed:ext_seed () in
  Batch.run (fun b ->
      (* The gate the roadmap names: forbid reaching raw arithmetic. *)
      let rf =
        rule_file "ext_arith"
          "rule \"no raw arithmetic\"\n  forbid reach from file:src/calc/** to ext:Stdlib.+\n"
      in
      (match rules_json b ~what:"ext_arith" [db; rf; "--format"; "json"] with
      | None -> ()
      | Some j -> (
          Batch.eq_string_opt b ~msg:"ext: must find the MUST edge into the external leaf"
            (verdict_of j ~prefix:"no raw arithmetic") (Some "VIOLATION") ;
          match Json.list ~what:"ext_arith" "results" j with
          | Ok (`Assoc f :: _) ->
              (* target_size = 1, not 2: `Stdlib.+` and not `Stdlib.List.iter`. A selector that
                 swept up every external would produce the same VIOLATION, so the verdict alone
                 does not discriminate — the size is what does. *)
              Batch.eq_string_opt b
                ~msg:"ext:Stdlib.+ must match that one leaf, not every external"
                (match List.assoc_opt "target_size" f with
                | Some (`Int n) -> Some (string_of_int n)
                | _ -> None)
                (Some "1")
          | _ -> Batch.note b "the ext: rule produced no result row")) ;

      (* A glob over externals, pinning that the population is the external leaves and NOT every
         callee: `calc.inner` is a call target too, and it HAS a body, so it must not appear. *)
      let gf =
        rule_file "ext_glob"
          "rule \"no stdlib at all\"\n  forbid reach from file:src/calc/** to ext:Stdlib.**\n"
      in
      (match rules_json b ~what:"ext_glob" [db; gf; "--format"; "json"] with
      | None -> ()
      | Some j -> (
          match Json.list ~what:"ext_glob" "results" j with
          | Ok (`Assoc f :: _) ->
              Batch.eq_string_opt b
                ~msg:"ext:Stdlib.** must match both externals and nothing with a body"
                (match List.assoc_opt "target_size" f with
                | Some (`Int n) -> Some (string_of_int n)
                | _ -> None)
                (Some "2")
          | _ -> Batch.note b "the ext: glob rule produced no result row")) ;

      (* The population itself, asserted where the GLOB cannot do the work.

         `ext:Stdlib.**` above does not discriminate how ext_keys is defined: a definition that
         wrongly included indexed nodes would still be filtered by that pattern, since a Main
         node's key is `#<id>` and never begins with "Stdlib.". Verified by mutation — widening
         ext_keys to every bwd key left every other assertion here green.

         `ext:**` is the pattern that cannot be filtered. There are exactly two external leaves;
         `calc.inner` is also a call target but HAS a body, so a third match means the definition
         has stopped meaning "no indexed body". *)
      let af =
        rule_file "ext_any"
          "rule \"nothing unresolved at all\"\n  forbid reach from file:src/calc/** to ext:**\n"
      in
      (match rules_json b ~what:"ext_any" [db; af; "--format"; "json"] with
      | None -> ()
      | Some j -> (
          match Json.list ~what:"ext_any" "results" j with
          | Ok (`Assoc f :: _) ->
              Batch.eq_string_opt b
                ~msg:"ext:** must match the external leaves ONLY — not indexed callees"
                (match List.assoc_opt "target_size" f with
                | Some (`Int n) -> Some (string_of_int n)
                | _ -> None)
                (Some "2")
          | _ -> Batch.note b "the ext:** rule produced no result row")) ;

      (* The control. `calc.pure` reaches only `calc.inner`, which has a body, so no external is
         reachable and PASS is earned. Without this, a selector matching every key would produce
         the VIOLATION above and look correct. *)
      let pf =
        rule_file "ext_pass"
          "rule \"pure code touches no external\"\n  forbid reach from file:src/calc/pure.ml to ext:Stdlib.**\n"
      in
      (match rules_json b ~what:"ext_pass" [db; pf; "--format"; "json"] with
      | None -> ()
      | Some j ->
          Batch.eq_string_opt b ~msg:"a cone that reaches no external must PASS, not VIOLATION"
            (verdict_of j ~prefix:"pure code") (Some "PASS")) ;

      (* A flat index cannot represent an external leaf, so the question is unanswerable rather
         than answered "none" — NOT_COMPUTED, which fails the gate by default. This is the case a
         prefix-based implementation got wrong by returning the empty set. *)
      let flat_db = Fixture.flat ~name:"rules_ext_flat" layered_stream in
      (match rules_json b ~what:"ext_flat" [flat_db; rf; "--format"; "json"] with
      | None -> ()
      | Some j ->
          Batch.eq_string_opt b
            ~msg:"ext: on a flat index is NOT_COMPUTED — the schema cannot hold an external leaf"
            (verdict_of j ~prefix:"no raw arithmetic") (Some "NOT_COMPUTED")) ;
      Batch.exit_code b
        ~msg:"and that unanswerable rule fails the gate rather than passing quietly"
        ~expected:1 (rules [flat_db; rf]) ;

      (* The five refusals. Each position consults a population an external leaf can never join,
         so the selector would match nothing and the rule would report a green verdict it never
         earned. Exit 2 = the parse aborted, which is how this tool refuses. *)
      List.iter
        (fun (what, body) ->
          let f = rule_file ("ext_bad_" ^ what) (Printf.sprintf "rule \"r\"\n  %s\n" body) in
          Batch.exit_code b
            ~msg:(Printf.sprintf "ext: as %s must abort, not silently match nothing" what)
            ~expected:2 (rules [db; f]) ;
          let _, out = rules [db; f] in
          Batch.contains b
            ~msg:(Printf.sprintf "the %s refusal must name the kind, not read as a typo" what)
            ~haystack:out "not valid in this position")
        [
          ("reach-source", "forbid reach from ext:Stdlib.+ to file:src/**");
          ("dep-source", "forbid dep from ext:Stdlib.+ to module:Web.**");
          ("dep-target", "forbid dep from module:src/** to ext:Stdlib.+");
          ("exported", "forbid exported outside ext:Stdlib.+");
          ("effect", "forbid effect from ext:Stdlib.+ kind:GlobalVar");
        ]) ;
  Lwt.return_unit
