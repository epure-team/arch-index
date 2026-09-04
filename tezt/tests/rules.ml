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
        ~haystack:out "1 UNKNOWN" ;
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
      Batch.contains b ~msg:"four-rule summary names the UNKNOWN count" ~haystack:out4 "1 UNKNOWN") ;
  Lwt.return_unit
