(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** [arch-rules --format sarif] — roadmap 2.1.

    {1 The validator decision}

    The SARIF 2.1.0 schema
    (https://raw.githubusercontent.com/oasis-tcs/sarif-spec/main/sarif-2.1/schema/sarif-schema-2.1.0.json,
    vendored at [vendor/sarif/sarif-schema-2.1.0.json]) declares itself
    ["$schema": "http://json-schema.org/draft-04/schema#"] — JSON Schema draft-04, the
    least-supported draft in modern validators. This is CHECK-4's whole difficulty.

    The opam package [jsonschema] (0.1.0) claims draft-4 support and was tried first — but an
    experiment (not this file; done once, by hand, while designing this test, and recorded here
    so the decision is not re-litigated by a future reader) found it silently accepts a SARIF
    document MISSING its required top-level ["version"] field and a [driver] missing its
    required ["name"]: it reported the whole document VALID. A validator that cannot reject an
    invalid document is not a validator — CHECK-4 needs a tool that can go RED, and this one
    could not be shown to. python3's [jsonschema] library (4.26.0, locally confirmed available)
    correctly rejects both defects via its [Draft4Validator]. That is the tool this file shells
    out to.

    Declared, not assumed present (per this repo's own PR #69 lesson — a tool assumed present and
    declared nowhere): [.github/workflows/ci.yml] installs it with an explicit
    [pip install 'jsonschema==4.26.0'] step, named so its absence reads as "the install step
    rotted", not "the machine is bare". [validate_sarif] below never skips: an absent python3 or
    an absent [jsonschema] module both {!Tezt.Test.fail}, loudly, naming what is missing — the
    "validation must never silently skip" rule from this item's brief. *)

open Arch_tezt

let rules args = run_command (arch_rules ()) args

let rule_file name contents =
  let path = Temp.file (name ^ ".rules") in
  write_file path contents ;
  path

(* Same shape as rules.ml's `layered_stream`, kept local and self-contained rather than shared:
   this file's fixture needs one more thing rules.ml's does not carry by default — a `top_reason`
   on the MAY_TOP edge, which is what lets the UNKNOWN case assert
   `properties.top_reason` end to end.

   ui.handle  --MUST-->      db.write            a definite layering violation      -> VIOLATION
   api.serve  --MAY_ENUM-->  db.write            possible: dispatch could land there -> POSSIBLE
   job.run    --MUST--> util.helper --MAY_TOP--> ⊤ (top_reason=reflection)           -> UNKNOWN
   pure.calc  --MUST-->      pure.inner          a closed cone: a real proof         -> PASS *)
let layered_stream =
  {|{"type":"function","name":"ui.handle","file_path":"src/ui/handler.ts","exported":true}
{"type":"function","name":"api.serve","file_path":"src/api/serve.ts","exported":true}
{"type":"function","name":"job.run","file_path":"src/job/run.ts"}
{"type":"function","name":"util.helper","file_path":"src/util/helper.ts"}
{"type":"function","name":"pure.calc","file_path":"src/pure/calc.ts"}
{"type":"function","name":"pure.inner","file_path":"src/pure/inner.ts"}
{"type":"function","name":"db.write","file_path":"lib/db/write.ts"}
{"type":"call","caller_name":"ui.handle","caller_file":"src/ui/handler.ts","callee_name":"db.write","callee_file":"lib/db/write.ts","call_site":"src/ui/handler.ts:5","kind":"MUST"}
{"type":"call","caller_name":"api.serve","caller_file":"src/api/serve.ts","callee_name":"db.write","callee_file":"lib/db/write.ts","call_site":"src/api/serve.ts:9","kind":"MAY_ENUMERATED"}
{"type":"call","caller_name":"job.run","caller_file":"src/job/run.ts","callee_name":"util.helper","callee_file":"src/util/helper.ts","call_site":"src/job/run.ts:3","kind":"MUST"}
{"type":"call","caller_name":"util.helper","caller_file":"src/util/helper.ts","callee_name":"*TOP*","callee_file":null,"call_site":"src/util/helper.ts:7","kind":"MAY_TOP","top_reason":"reflection"}
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

let fixture_db () = Fixture.flat ~name:"sarif_out" layered_stream

let sarif_schema_path () =
  let p = Filename.concat (repo_root ()) "vendor/sarif/sarif-schema-2.1.0.json" in
  if not (Sys.file_exists p) then Test.fail "vendored SARIF schema not found at %s" p ;
  p

(* Shells out to python3's jsonschema (Draft4Validator) — see the module header for why. Returns
   [(valid, message)]. Never returns [(true, _)] on a missing interpreter or module: both cases
   {!Test.fail} directly, which is what "must never silently skip" means operationally. *)
let validate_sarif ~what json_text =
  let py =
    let code, out = run_command "sh" ["-c"; "command -v python3"] in
    let path = String.trim out in
    if code <> 0 || path = "" then
      Test.fail
        "%s: python3 is required to validate SARIF output against the draft-04 schema (CHECK-4) \
         and was not found on PATH"
        what ;
    path
  in
  let script =
    {|
import sys, json
try:
    from jsonschema import Draft4Validator
except ImportError as e:
    print("JSONSCHEMA_MODULE_MISSING: " + str(e))
    sys.exit(3)
schema = json.load(open(sys.argv[1]))
doc = json.load(open(sys.argv[2]))
errors = list(Draft4Validator(schema).iter_errors(doc))
if errors:
    print("INVALID")
    for e in errors[:20]:
        print(" - " + e.message)
    sys.exit(1)
print("VALID")
|}
  in
  let script_path = Temp.file "validate_sarif.py" in
  write_file script_path script ;
  let doc_path = Temp.file (what ^ ".sarif.json") in
  write_file doc_path json_text ;
  let code, output = run_command py [script_path; sarif_schema_path (); doc_path] in
  if code = 3 then
    Test.fail
      "%s: python3's `jsonschema` module is not installed — install it with `pip install \
       jsonschema` (see .github/workflows/ci.yml for the declared CI step). Output:\n\
       %s"
      what output ;
  (code = 0, output)

let sarif_json b ~what output =
  match Json.strict_object ~what output with
  | Ok j -> Some j
  | Error e ->
      Batch.note b "%s" e ;
      None

(* Every rule's [ruleId] -> its `results[]` entries, in document order. *)
let results_by_rule j =
  match Json.member "runs" j with
  | Some (`List [ run ]) -> (
      match Json.member "results" run with
      | Some (`List rs) ->
          List.filter_map
            (function
              | `Assoc _ as r -> ( match Json.member "ruleId" r with Some (`String id) -> Some (id, r) | _ -> None)
              | _ -> None)
            rs
      | _ -> [])
  | _ -> []

let find_result j ~rule_id = List.assoc_opt rule_id (results_by_rule j)

(* -------------------------------------------------------------------- *)

let register_schema_valid () =
  Test.register ~__FILE__ ~title:"sarif: --format sarif validates against the SARIF 2.1.0 schema"
    ~tags:["sarif"; "rules"]
  @@ fun () ->
  let db = fixture_db () in
  let rf = rule_file "sarif_valid" four_rules in
  let code, output = rules [db; rf; "--format"; "sarif"] in
  ignore code ;
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some _j ->
          let valid, msg = validate_sarif ~what:"sarif output" output in
          Batch.check b ~msg:(Printf.sprintf "SARIF output must validate against the 2.1.0 schema:\n%s" msg) valid) ;
  Lwt.return_unit

let register_pass_excluded () =
  Test.register ~__FILE__ ~title:"sarif: a PASS verdict never becomes a result — only non-PASS verdicts do"
    ~tags:["sarif"; "rules"]
  @@ fun () ->
  let db = fixture_db () in
  let rf = rule_file "sarif_pass" four_rules in
  let _, output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j ->
          let ids = List.map fst (results_by_rule j) in
          Batch.check b
            ~msg:(Printf.sprintf "a PASS rule ('pure code must not reach persistence') must not appear \
                                   in results, got: [%s]" (String.concat "; " ids))
            (not (List.mem "pure code must not reach persistence" ids)) ;
          (* The other three ARE non-PASS and must all be present — a mutant that dropped every
             result (not just PASS) would still make the assertion above pass vacuously, so this
             is the assertion that catches THAT mutant. *)
          List.iter
            (fun name ->
              Batch.check b ~msg:(Printf.sprintf "%S must appear in results" name) (List.mem name ids))
            ["ui must not reach persistence"; "api must not reach persistence";
             "jobs must not reach persistence"]) ;
  Lwt.return_unit

let register_level_mapping () =
  Test.register ~__FILE__ ~title:"sarif: VIOLATION/POSSIBLE/UNKNOWN map to error/warning/note"
    ~tags:["sarif"; "rules"]
  @@ fun () ->
  let db = fixture_db () in
  let rf = rule_file "sarif_levels" four_rules in
  let _, output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j ->
          let level_of rule_id =
            match find_result j ~rule_id with
            | Some r -> ( match Json.member "level" r with Some (`String s) -> Some s | _ -> None)
            | None -> None
          in
          Batch.eq_string_opt b ~msg:"VIOLATION -> level=error"
            (level_of "ui must not reach persistence") (Some "error") ;
          Batch.eq_string_opt b ~msg:"POSSIBLE -> level=warning"
            (level_of "api must not reach persistence") (Some "warning") ;
          Batch.eq_string_opt b ~msg:"UNKNOWN -> level=note"
            (level_of "jobs must not reach persistence") (Some "note")) ;
  Lwt.return_unit

let register_unknown_carries_soundness_and_top_reason () =
  Test.register ~__FILE__
    ~title:"sarif: an UNKNOWN result carries properties.soundness=unknown_top and its top_reason"
    ~tags:["sarif"; "rules"; "top_reason"]
  @@ fun () ->
  let db = fixture_db () in
  let rf = rule_file "sarif_unknown" four_rules in
  let _, output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j -> (
          match find_result j ~rule_id:"jobs must not reach persistence" with
          | None -> Batch.note b "the UNKNOWN rule has no SARIF result at all"
          | Some r -> (
              match Json.member "properties" r with
              | None -> Batch.note b "UNKNOWN result has no properties bag at all"
              | Some props ->
                  Batch.eq_string_opt b ~msg:"properties.soundness"
                    (match Json.member "soundness" props with Some (`String s) -> Some s | _ -> None)
                    (Some "unknown_top") ;
                  (* H3: the verdict must survive verbatim, not only as prose in message.text —
                     a machine reading `level=note` alone cannot tell UNKNOWN from NOT_COMPUTED
                     from NO_SOURCE, all four of which map to the same SARIF severity. *)
                  Batch.eq_string_opt b ~msg:"properties.verdict"
                    (match Json.member "verdict" props with Some (`String s) -> Some s | _ -> None)
                    (Some "UNKNOWN") ;
                  (match Json.member "top_reason" props with
                  | Some (`List [ `String r ]) ->
                      Batch.eq_string b ~msg:"properties.top_reason[0]" r "reflection"
                  | other -> Batch.note b "properties.top_reason is not a singleton list: %s" (Json.show other))))) ;
  Lwt.return_unit

(* H3: UNKNOWN and UNKNOWN_NO_CONTRACT are DIFFERENT soundness gaps with different fixes (the
   engine's own `census` comment in arch_rules.ml draws exactly this line: one means "this cone's
   witness escaped through a real ⊤ edge", the other means "the whole index was never ⊤-marked, so
   nothing was proved for ANY rule") — a mutant collapsing both onto `soundness=unknown_top` (the
   PR #70 defect class this brief names) would still pass the test above, since that fixture only
   ever produces a plain UNKNOWN. This fixture is un-⊤-marked (no `callgraph_contract` meta key),
   so its one rule must come back UNKNOWN_NO_CONTRACT with `soundness=no_contract`, never
   `unknown_top`. *)
let register_unknown_no_contract_distinct_soundness () =
  Test.register ~__FILE__
    ~title:"sarif: UNKNOWN_NO_CONTRACT carries properties.soundness=no_contract, not unknown_top"
    ~tags:["sarif"; "rules"; "soundness"]
  @@ fun () ->
  (* `arch-load` REFUSES to write a call edge with no/invalid `kind` — it is the enforcement
     point that guarantees a ⊤-marked DB is never a lie — so an un-⊤-marked index cannot be built
     through it at all; every flat fixture built via {!Fixture.flat} is contract_ok=true. The way
     every other UNKNOWN_NO_CONTRACT test in this suite (see rules.ml's `register_no_contract`)
     gets there is the same one used here: a legacy pre-contract schema built with
     {!Fixture.raw}, which has no `kind` column and no `callgraph_contract` meta key at all.
     `pure.calc` reaches `pure.inner`, never `db.write`, so nothing is reachable and nothing
     escapes through a ⊤ edge either — only the missing contract forces UNKNOWN_NO_CONTRACT. *)
  let db =
    Fixture.raw ~name:"sarif_no_contract"
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
  let rf =
    rule_file "sarif_no_contract" "rule \"l\"\n  forbid reach from file:src/pure/** to file:lib/db/**\n"
  in
  let _, output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j -> (
          match find_result j ~rule_id:"l" with
          | None -> Batch.note b "the UNKNOWN_NO_CONTRACT rule has no SARIF result at all"
          | Some r -> (
              match Json.member "properties" r with
              | None -> Batch.note b "UNKNOWN_NO_CONTRACT result has no properties bag at all"
              | Some props ->
                  Batch.eq_string_opt b ~msg:"properties.verdict"
                    (match Json.member "verdict" props with Some (`String s) -> Some s | _ -> None)
                    (Some "UNKNOWN_NO_CONTRACT") ;
                  Batch.eq_string_opt b ~msg:"properties.soundness must be no_contract, not unknown_top"
                    (match Json.member "soundness" props with Some (`String s) -> Some s | _ -> None)
                    (Some "no_contract")))) ;
  Lwt.return_unit

(* H4: `results[].top_reasons` in `--format json` had ZERO coverage anywhere in the suite —
   replacing its emission with `List [] passed the whole 175-test suite. Documented at
   docs/fitness-functions.md:188, user-visible, and this file already has the one fixture that
   carries a `top_reason` (reflection, on util.helper's MAY_TOP edge) — reused here rather than
   asserting only through the SARIF channel, which is a different code path entirely
   (arch_rules.ml's `--format json` branch, not `--format sarif`'s). *)
let register_json_top_reasons () =
  Test.register ~__FILE__
    ~title:"json: an UNKNOWN result's top_reasons carries the ⊤-anchor taxonomy value"
    ~tags:["rules"; "json"; "top_reason"]
  @@ fun () ->
  let db = fixture_db () in
  let rf = rule_file "json_top_reasons" four_rules in
  let _, output = rules [db; rf; "--format"; "json"] in
  Batch.run (fun b ->
      match Json.strict_object ~what:"json output" output with
      | Error e -> Batch.note b "%s" e
      | Ok j -> (
          match Json.member "results" j with
          | Some (`List rs) -> (
              let jobs_result =
                List.find_opt
                  (function
                    | `Assoc f -> List.assoc_opt "rule" f = Some (`String "jobs must not reach persistence")
                    | _ -> false)
                  rs
              in
              match jobs_result with
              | None -> Batch.note b "the UNKNOWN rule has no json result at all"
              | Some (`Assoc f) -> (
                  match List.assoc_opt "top_reasons" f with
                  | Some (`List [ `String r ]) ->
                      Batch.eq_string b ~msg:"results[].top_reasons[0]" r "reflection"
                  | other ->
                      Batch.note b "results[].top_reasons is not the singleton [\"reflection\"]: %s"
                        (Json.show other))
              | Some _ -> Batch.note b "the UNKNOWN result is not a JSON object")
          | other -> Batch.note b "json output has no results list: %s" (Json.show other))) ;
  Lwt.return_unit

(* chain.a --MUST--> chain.mid --MUST--> chain.target   the ONLY all-MUST path, 2 hops (3 nodes)
   chain.a --MAY_ENUMERATED--> chain.target              a shorter, mixed-kind shortcut, 1 hop
   Reused verbatim from rules.ml's `adjacency_stream` (same fixture, same comment there) — this
   file needs the SAME property that fixture was built for (a real ≥3-node witness whose three
   names are all distinct, so a reversed order is observably different from the correct one), not
   a different one. A 2-hop fixture (the old `ui.handle -> db.write` case, 2 locations) cannot
   catch a reversed witness: with only two symmetric endpoints, `List.rev` and the identity
   produce sets that "contains" checks alone cannot tell apart order-wise without also checking
   POSITION, which is what this test now does. *)
let adjacency_stream =
  {|{"type":"function","name":"chain.a","file_path":"src/chain/a.ts"}
{"type":"function","name":"chain.mid","file_path":"src/chain/mid.ts"}
{"type":"function","name":"chain.target","file_path":"src/chain/target.ts"}
{"type":"call","caller_name":"chain.a","caller_file":"src/chain/a.ts","callee_name":"chain.mid","callee_file":"src/chain/mid.ts","call_site":"src/chain/a.ts:2","kind":"MUST"}
{"type":"call","caller_name":"chain.mid","caller_file":"src/chain/mid.ts","callee_name":"chain.target","callee_file":"src/chain/target.ts","call_site":"src/chain/mid.ts:2","kind":"MUST"}
{"type":"call","caller_name":"chain.a","caller_file":"src/chain/a.ts","callee_name":"chain.target","callee_file":"src/chain/target.ts","call_site":"src/chain/a.ts:5","kind":"MAY_ENUMERATED"}
|}

let register_witness_becomes_code_flow () =
  Test.register ~__FILE__
    ~title:"sarif: a rule's witness path becomes a codeFlow with one location per step, IN ORDER"
    ~tags:["sarif"; "rules"; "witness"]
  @@ fun () ->
  let db = Fixture.flat ~name:"sarif_codeflow" adjacency_stream in
  let rf =
    rule_file "sarif_codeflow" "rule \"chain\"\n  forbid reach from fn:chain.a to fn:chain.target\n"
  in
  let _, output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j -> (
          match find_result j ~rule_id:"chain" with
          | None -> Batch.note b "the VIOLATION rule has no SARIF result at all"
          | Some r -> (
              match Json.member "codeFlows" r with
              | Some (`List [ flow ]) -> (
                  match Json.member "threadFlows" flow with
                  | Some (`List [ tf ]) -> (
                      match Json.member "locations" tf with
                      | Some (`List locs) ->
                          (* chain.a -> chain.mid -> chain.target: exactly three steps. A mutant
                             that emitted the witness as a single collapsed string (rather than
                             per-step locations) would make this 1, not 3. *)
                          Batch.eq_int b ~msg:"codeFlow location count" (List.length locs) 3 ;
                          let fqn_of loc =
                            match Json.member "location" loc with
                            | Some l -> (
                                match Json.member "logicalLocations" l with
                                | Some (`List [ ll ]) -> (
                                    match Json.member "fullyQualifiedName" ll with
                                    | Some (`String s) -> Some s
                                    | _ -> None)
                                | _ -> None)
                            | None -> None
                          in
                          (* Source-to-target order (roadmap 1.5's own contract, restated on the
                             SARIF finding's doc comment): the FIRST codeFlow location must be the
                             source, chain.a, and the LAST must be the target, chain.target. A
                             `List.rev` mutant would swap these two — this fixture's three names
                             are pairwise distinct, so a reversal is observable at both ends,
                             unlike the old 2-hop symmetric fixture. *)
                          (match locs with
                          | first :: rest when rest <> [] ->
                              let last = List.nth rest (List.length rest - 1) in
                              Batch.eq_string_opt b ~msg:"codeFlow first location is the source, chain.a"
                                (fqn_of first) (Some "chain.a") ;
                              Batch.eq_string_opt b ~msg:"codeFlow last location is the target, chain.target"
                                (fqn_of last) (Some "chain.target")
                          | _ -> Batch.note b "codeFlow has fewer than 2 locations, cannot check order")
                      | other -> Batch.note b "threadFlow has no locations list: %s" (Json.show other))
                  | other -> Batch.note b "codeFlow has no singleton threadFlows: %s" (Json.show other))
              | other -> Batch.note b "VIOLATION result has no singleton codeFlows: %s" (Json.show other)))) ;
  Lwt.return_unit

let register_run_shape_and_category () =
  Test.register ~__FILE__
    ~title:"sarif: driver name/category/automationDetails are set, and the ⊤ frontier is a count, not results"
    ~tags:["sarif"; "rules"; "category"]
  @@ fun () ->
  let db = fixture_db () in
  let rf = rule_file "sarif_shape" four_rules in
  let _, output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j -> (
          match Json.member "runs" j with
          | Some (`List [ run ]) ->
              let driver =
                match Json.member "tool" run with Some t -> Json.member "driver" t | None -> None
              in
              (match driver with
              | Some d ->
                  Batch.eq_string_opt b ~msg:"tool.driver.name"
                    (match Json.member "name" d with Some (`String s) -> Some s | _ -> None)
                    (Some "arch-index")
              | None -> Batch.note b "run has no tool.driver at all") ;
              let props = Json.member "properties" run in
              (match props with
              | Some p ->
                  Batch.eq_string_opt b ~msg:"run.properties.category"
                    (match Json.member "category" p with Some (`String s) -> Some s | _ -> None)
                    (Some "arch-index/rules") ;
                  (* The ⊤ frontier (roadmap 1.4/1.5's escaping edge on util.helper) must be a
                     COUNT in run.properties, never a member of `results` — GitHub caps a run at
                     25 000 results and a real corpus's frontier is orders of magnitude past
                     that. A mutant that turned this into a results-list entry would still pass
                     every OTHER assertion in this file, which is why it gets its own check. *)
                  (match Json.member "top_frontier" p with
                  | Some (`Int n) -> Batch.check b ~msg:"top_frontier must be >= 1" (n >= 1)
                  | other -> Batch.note b "run.properties.top_frontier missing or not an int: %s" (Json.show other)) ;
                  (* H3: `contract_ok`/`computed`/`proved` have no SARIF counterpart at all in the
                     original PR, so an all-PASS run and a run that evaluated nothing produce
                     identical documents. Mirrored from the same `--format json` channel's own
                     top-level fields. *)
                  (match Json.member "contract_ok" p with
                  | Some (`Bool true) -> ()
                  | other -> Batch.note b "run.properties.contract_ok is not `true`: %s" (Json.show other)) ;
                  (match Json.member "computed" p with
                  | Some (`Bool true) -> ()
                  | other -> Batch.note b "run.properties.computed is not `true`: %s" (Json.show other)) ;
                  (* four_rules: exactly one of the four ("pure code must not reach persistence")
                     is a PASS. *)
                  (match Json.member "proved" p with
                  | Some (`Int n) -> Batch.eq_int b ~msg:"run.properties.proved" n 1
                  | other -> Batch.note b "run.properties.proved missing or not an int: %s" (Json.show other))
              | None -> Batch.note b "run has no properties bag at all") ;
              (match Json.member "automationDetails" run with
              | Some ad ->
                  Batch.eq_string_opt b ~msg:"automationDetails.id"
                    (match Json.member "id" ad with Some (`String s) -> Some s | _ -> None)
                    (Some "arch-index/rules")
              | None -> Batch.note b "run has no automationDetails at all")
          | other -> Batch.note b "sarif output does not have exactly one run: %s" (Json.show other))) ;
  Lwt.return_unit

(* CHECK-5's round-trip, in spirit: every non-PASS verdict `--format json` reports must be
   traceable in `--format sarif` too, with a level consistent with that same verdict. An
   asymmetry here is exactly PR #70's defect class (the JSON channel honest, another channel
   not) reproduced for the JSON/SARIF pair instead of JSON/text. *)
let register_json_sarif_round_trip () =
  Test.register ~__FILE__ ~title:"sarif: every non-PASS verdict in --format json appears in --format sarif"
    ~tags:["sarif"; "rules"; "round_trip"]
  @@ fun () ->
  let db = fixture_db () in
  let rf = rule_file "sarif_roundtrip" four_rules in
  let _, json_output = rules [db; rf; "--format"; "json"] in
  let _, sarif_output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match (Json.strict_object ~what:"json output" json_output, sarif_json b ~what:"sarif output" sarif_output) with
      | Error e, _ ->
          Batch.note b "%s" e
      | _, None -> ()
      | Ok jj, Some sj -> (
          match Json.list ~what:"json" "results" jj with
          | Error e -> Batch.note b "%s" e
          | Ok rs ->
              let sarif_rule_ids = List.map fst (results_by_rule sj) in
              (* H3: level alone is not enough — UNKNOWN/UNKNOWN_NO_CONTRACT/NOT_COMPUTED/
                 NO_SOURCE/NO_TARGET all map to the same `note`, so the expected level here is
                 keyed on the SARIF severity vocabulary, and `properties.verdict` is checked
                 separately against the exact json verdict string, which is the part `level`
                 cannot express. *)
              let expected_level = function
                | "VIOLATION" -> "error"
                | "POSSIBLE" -> "warning"
                | _ -> "note"
              in
              List.iter
                (fun r ->
                  match (Json.member "rule" r, Json.member "verdict" r) with
                  | Some (`String rule), Some (`String verdict) when verdict <> "PASS" ->
                      Batch.check b
                        ~msg:(Printf.sprintf "non-PASS rule %S (verdict %s) must appear in sarif results, got [%s]"
                                rule verdict (String.concat "; " sarif_rule_ids))
                        (List.mem rule sarif_rule_ids) ;
                      (match find_result sj ~rule_id:rule with
                      | None -> ()
                      | Some sr ->
                          Batch.eq_string_opt b
                            ~msg:(Printf.sprintf "rule %S: sarif level must match verdict %s" rule verdict)
                            (match Json.member "level" sr with Some (`String s) -> Some s | _ -> None)
                            (Some (expected_level verdict)) ;
                          (* The verdict itself must round-trip verbatim into properties.verdict —
                             `level` alone cannot distinguish the five verdicts that all map to
                             `note`. *)
                          (match Json.member "properties" sr with
                          | Some props ->
                              Batch.eq_string_opt b
                                ~msg:(Printf.sprintf "rule %S: properties.verdict must equal the json verdict" rule)
                                (match Json.member "verdict" props with Some (`String s) -> Some s | _ -> None)
                                (Some verdict)
                          | None ->
                              Batch.note b "rule %S: sarif result has no properties bag to carry properties.verdict"
                                rule))
                  | Some (`String rule), Some (`String "PASS") ->
                      Batch.check b ~msg:(Printf.sprintf "PASS rule %S must NOT appear in sarif results" rule)
                        (not (List.mem rule sarif_rule_ids))
                  | _ -> Batch.note b "a json result is missing rule/verdict")
                rs)) ;
  Lwt.return_unit

let register_not_analysed_becomes_notification () =
  Test.register ~__FILE__
    ~title:"sarif: an analysis_coverage row with status=not_analysed becomes a toolExecutionNotification, never silence"
    ~tags:["sarif"; "rules"; "coverage"]
  @@ fun () ->
  let db = fixture_db () in
  (* analysis_coverage (roadmap 1.3) is not part of arch-load's flat schema — added here the way
     a coverage-writing producer (arch-coverage-matrix) would, so the SARIF writer's read path is
     exercised the same way it would be on a real polyglot index. *)
  (* A COVERED row alongside the not_analysed one — required to catch the "not_analysed
     inversion" mutant: replacing `if c.status = "not_analysed"` with `if true` would turn this
     covered row into a spurious notification too, and a fixture carrying only the not_analysed
     row could never observe that, since there would be nothing else to wrongly include. *)
  Db.with_db_rw db (fun conn ->
      Db.exec conn
        "CREATE TABLE analysis_coverage(id INTEGER PRIMARY KEY, language TEXT, analysis TEXT NOT \
         NULL, status TEXT NOT NULL, detail TEXT);
         INSERT INTO analysis_coverage(language, analysis, status, detail) VALUES \
         ('rust', 'callgraph', 'not_analysed', 'no rust producer configured'), \
         ('typescript', 'callgraph', 'covered', 'fully analysed');") ;
  let rf = rule_file "sarif_notanalysed" four_rules in
  let _, output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j -> (
          match Json.member "runs" j with
          | Some (`List [ run ]) ->
              (* MEDIUM: run.properties.coverage (roadmap 1.3) — dropping it silently regresses a
                 promise `docs/fitness-functions.md:227` makes. Both rows must appear here,
                 covered included: this is the full matrix, not just the not_analysed subset. *)
              (match Json.member "properties" run with
              | Some p -> (
                  match Json.member "coverage" p with
                  | Some (`List rows) ->
                      let statuses =
                        List.filter_map
                          (fun r -> match Json.member "status" r with Some (`String s) -> Some s | _ -> None)
                          rows
                      in
                      Batch.eq_int b ~msg:"run.properties.coverage must carry both rows"
                        (List.length statuses) 2 ;
                      Batch.check b ~msg:"run.properties.coverage must include the covered row"
                        (List.mem "covered" statuses)
                  | other -> Batch.note b "run.properties.coverage missing or not a list: %s" (Json.show other))
              | None -> Batch.note b "run has no properties bag at all") ;
              (match Json.member "invocations" run with
              | Some (`List [ inv ]) -> (
                  match Json.member "toolExecutionNotifications" inv with
                  | Some (`List notifs) ->
                      let texts =
                        List.filter_map
                          (fun n ->
                            match Json.member "message" n with
                            | Some m -> ( match Json.member "text" m with Some (`String s) -> Some s | _ -> None)
                            | None -> None)
                          notifs
                      in
                      Batch.check b
                        ~msg:(Printf.sprintf "a not_analysed notification mentioning 'rust' must be present, got: [%s]"
                                (String.concat "; " texts))
                        (List.exists (fun t -> contains ~needle:"rust" t) texts) ;
                      (* The inversion mutant, caught directly: a covered row's OWN analysis name
                         must never surface as a notification. `rust`'s analysis name is also
                         "callgraph", so this checks the language-qualified `typescript` mention
                         specifically, not just absence of the string "callgraph" (which the rust
                         notification legitimately contains). *)
                      Batch.check b
                        ~msg:(Printf.sprintf
                                "a covered row (typescript/callgraph) must NOT produce a \
                                 notification, got: [%s]"
                                (String.concat "; " texts))
                        (not (List.exists (fun t -> contains ~needle:"typescript" t) texts)) ;
                      Batch.eq_int b ~msg:"exactly one notification (the not_analysed row only)"
                        (List.length notifs) 1 ;
                      (* LOW (round-3 review): descriptor.id had zero coverage — this is SARIF's
                         own vocabulary for "not analysed", distinct from message.text, and a
                         consumer filtering on it (rather than string-matching the message) would
                         see nothing wrong if this regressed silently. *)
                      (match notifs with
                      | [ n ] -> (
                          match Json.member "descriptor" n with
                          | Some d -> (
                              match Json.member "id" d with
                              | Some (`String id) ->
                                  Batch.eq_string b ~msg:"notification descriptor.id" id
                                    "not_analysed/callgraph"
                              | other -> Batch.note b "descriptor.id missing or not a string: %s" (Json.show other))
                          | None -> Batch.note b "notification has no descriptor at all")
                      | other -> Batch.note b "expected exactly one notification, got %d" (List.length other))
                  | other -> Batch.note b "invocation has no toolExecutionNotifications: %s" (Json.show other))
              | other -> Batch.note b "run has no singleton invocations: %s" (Json.show other))
          | other -> Batch.note b "sarif output does not have exactly one run: %s" (Json.show other))) ;
  Lwt.return_unit

(* MEDIUM: provenance read path. The old fixture wrote no `producer` key at all, so the assertion
   there only ever observed the fallback constant "arch-index" — the SAME value whether or not the
   MAIN-schema `producer_runs`/FLAT-schema `comment_db_meta` read paths work at all.
   `driver.version` was never emitted in ANY tested scenario. This exercises the MAIN-schema path
   the reviewer verified by hand: a real `producer_runs` row with a distinct producer/version,
   read back through {!Arch_rules.producer_info}. *)
let provenance_seed =
  "INSERT INTO producer_runs(producer, producer_version, invocation_digest, soundness_class) \
   VALUES ('acme-analyzer', '9.9.9', 'deadbeef', 'sound_with_top'); \
   INSERT INTO modules(path, lines) VALUES ('src/prov/a.ml', 10), ('src/prov/b.ml', 10); \
   INSERT INTO functions(module_id, name, producer_run_id) VALUES \
     (1, 'prov.a', (SELECT id FROM producer_runs WHERE producer = 'acme-analyzer')), \
     (2, 'prov.b', (SELECT id FROM producer_runs WHERE producer = 'acme-analyzer')); \
   INSERT INTO calls(caller_id, callee_id, callee_name, kind, producer_run_id) VALUES \
     (1, 2, 'prov.b', 'MUST', (SELECT id FROM producer_runs WHERE producer = 'acme-analyzer')); \
   INSERT OR REPLACE INTO comment_db_meta(key, value) VALUES ('callgraph_contract', 'v1');"

let register_provenance_read_path () =
  Test.register ~__FILE__
    ~title:"sarif: tool.driver.name/version are read from a real producer_runs row, not just the fallback"
    ~tags:["sarif"; "rules"; "provenance"]
  @@ fun () ->
  let db = Fixture.main ~name:"sarif_provenance" ~seed:provenance_seed () in
  let rf =
    rule_file "sarif_provenance" "rule \"prov\"\n  forbid reach from file:src/prov/a.ml to file:src/prov/b.ml\n"
  in
  let _, output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j -> (
          match Json.member "runs" j with
          | Some (`List [ run ]) -> (
              match Json.member "tool" run with
              | Some t -> (
                  match Json.member "driver" t with
                  | Some d ->
                      Batch.eq_string_opt b ~msg:"tool.driver.name must come from producer_runs, not the fallback"
                        (match Json.member "name" d with Some (`String s) -> Some s | _ -> None)
                        (Some "acme-analyzer") ;
                      Batch.eq_string_opt b ~msg:"tool.driver.version must come from producer_runs"
                        (match Json.member "version" d with Some (`String s) -> Some s | _ -> None)
                        (Some "9.9.9")
                  | None -> Batch.note b "run has no tool.driver at all")
              | None -> Batch.note b "run has no tool at all") ;
              (* LOW: the index-level soundness_class (read the same way, from producer_runs) must
                 also round-trip into the finding's own properties.soundness_class — arch_rules.ml
                 used to hardcode `None` here despite the docs advertising this field for FR-022
                 filtering. *)
              (match Json.member "results" run with
              | Some (`List (r :: _)) -> (
                  match Json.member "properties" r with
                  | Some props ->
                      Batch.eq_string_opt b ~msg:"results[0].properties.soundness_class"
                        (match Json.member "soundness_class" props with Some (`String s) -> Some s | _ -> None)
                        (Some "sound_with_top")
                  | None -> Batch.note b "result has no properties bag at all")
              | other -> Batch.note b "run has no results to check soundness_class on: %s" (Json.show other))
          | other -> Batch.note b "sarif output does not have exactly one run: %s" (Json.show other))) ;
  Lwt.return_unit

(* Roadmap 2.1's amendment: two analyses from ONE producer must carry distinct
   `properties.category`/`automationDetails.id`, or a second GitHub upload overwrites the first
   rather than merging (GitHub stopped combining same-category runs in July 2025). Exercised
   directly against {!Arch_tools.Arch_sarif}, the shared writer, since a single `arch-rules`
   invocation only ever emits one run — this is 2.2 (`arch-report`, several runs per log)'s
   contract, checked here so it cannot regress before that item exists to exercise it end to end. *)
let register_two_runs_distinct_categories () =
  Test.register ~__FILE__
    ~title:"sarif: two runs from one producer must carry distinct category/automationDetails.id"
    ~tags:["sarif"; "category"]
  @@ fun () ->
  let open Arch_tools in
  let finding rule_id : Arch_sarif.finding =
    { rule_id; level = Arch_sarif.Error; message = "x"; verdict = None; soundness_class = None;
      soundness = None; top_reasons = []; locations = []; detail_total = 0; code_flow = [] }
  in
  let run1 : Arch_sarif.run =
    { producer = "arch-index"; producer_version = Some "1.0"; category = "arch-index/callgraph";
      findings = [ finding "r1" ]; coverage = []; top_frontier = None; notifications = [];
      contract_ok = None; computed = None; proved = None }
  in
  let run2 : Arch_sarif.run =
    { producer = "arch-index"; producer_version = Some "1.0"; category = "arch-index/effects";
      findings = [ finding "r2" ]; coverage = []; top_frontier = None; notifications = [];
      contract_ok = None; computed = None; proved = None }
  in
  let log_text = Arch_sarif.to_string [ run1; run2 ] in
  Batch.run (fun b ->
      match Json.strict_object ~what:"combined sarif log" log_text with
      | Error e -> Batch.note b "%s" e
      | Ok j -> (
          match Json.member "runs" j with
          | Some (`List [ a; b_run ]) ->
              let category r =
                match Json.member "properties" r with
                | Some p -> ( match Json.member "category" p with Some (`String s) -> Some s | _ -> None)
                | None -> None
              in
              let automation_id r =
                match Json.member "automationDetails" r with
                | Some ad -> ( match Json.member "id" ad with Some (`String s) -> Some s | _ -> None)
                | None -> None
              in
              let show_opt = function None -> "<none>" | Some s -> Printf.sprintf "%S" s in
              Batch.check b
                ~msg:(Printf.sprintf "the two runs' categories must differ, got %s and %s"
                        (show_opt (category a)) (show_opt (category b_run)))
                (category a <> category b_run && category a <> None) ;
              Batch.check b
                ~msg:(Printf.sprintf "the two runs' automationDetails.id must differ, got %s and %s"
                        (show_opt (automation_id a)) (show_opt (automation_id b_run)))
                (automation_id a <> automation_id b_run && automation_id a <> None) ;
              let valid, msg = validate_sarif ~what:"combined two-run sarif log" log_text in
              Batch.check b ~msg:(Printf.sprintf "the two-run log must still validate:\n%s" msg) valid
          | other -> Batch.note b "expected exactly two runs, got: %s" (Json.show other))) ;
  Lwt.return_unit

(* MEDIUM: `results[].locations` — dropping the whole array SURVIVES unless something asserts
   its presence and content directly (as opposed to `codeFlows`, which is a distinct SARIF
   section covering the witness path, not the primary finding location). *)
let register_locations_present () =
  Test.register ~__FILE__ ~title:"sarif: a VIOLATION result carries results[].locations with the source's fullyQualifiedName"
    ~tags:["sarif"; "rules"; "locations"]
  @@ fun () ->
  let db = fixture_db () in
  let rf = rule_file "sarif_locations" four_rules in
  let _, output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j -> (
          match find_result j ~rule_id:"ui must not reach persistence" with
          | None -> Batch.note b "the VIOLATION rule has no SARIF result at all"
          | Some r -> (
              match Json.member "locations" r with
              | Some (`List (_ :: _ as locs)) ->
                  let fqns =
                    List.filter_map
                      (fun loc ->
                        match Json.member "logicalLocations" loc with
                        | Some (`List [ ll ]) -> (
                            match Json.member "fullyQualifiedName" ll with Some (`String s) -> Some s | _ -> None)
                        | _ -> None)
                      locs
                  in
                  Batch.check b
                    ~msg:(Printf.sprintf "results[].locations must name the offending detail entry, got [%s]"
                            (String.concat "; " fqns))
                    (List.exists (fun s -> contains ~needle:"db.write" s) fqns)
              | other -> Batch.note b "results[].locations missing or empty: %s" (Json.show other)))) ;
  Lwt.return_unit

(* MEDIUM: `split_label` fabricating a path from a filename containing a parenthesis — the
   concrete case the reviewer measured: a file `wri#te (x).ts` used to make `String.rindex_opt`
   pick the WRONG `(` (the one inside the file name), splitting the label into a bogus
   `fullyQualifiedName` and a `uri` naming a file that does not exist. The fix searches for the
   exact "  (" separator {!Arch_graph.label} inserts, leftmost occurrence, so this exercises that
   separator search directly against {!Arch_tools.Arch_sarif}'s writer rather than through the
   whole pipeline (arch-rules has no selector that lets a test control the exact display label
   the way a raw finding's `locations` field can). *)
let register_split_label_paren_in_filename () =
  Test.register ~__FILE__
    ~title:"sarif: a file name containing a parenthesis does not fabricate a bogus location"
    ~tags:["sarif"; "locations"; "regression"]
  @@ fun () ->
  let open Arch_tools in
  let label = "db.write  (/home/me/proj/lib/db/wri#te (x).ts)" in
  let finding : Arch_sarif.finding =
    { rule_id = "r"; level = Arch_sarif.Error; message = "x"; verdict = None; soundness_class = None;
      soundness = None; top_reasons = []; locations = [ label ]; detail_total = 1; code_flow = [] }
  in
  let run : Arch_sarif.run =
    { producer = "arch-index"; producer_version = None; category = "arch-index/regression";
      findings = [ finding ]; coverage = []; top_frontier = None; notifications = [];
      contract_ok = None; computed = None; proved = None }
  in
  let text = Arch_sarif.to_string [ run ] in
  Batch.run (fun b ->
      match Json.strict_object ~what:"split_label regression log" text with
      | Error e -> Batch.note b "%s" e
      | Ok j -> (
          match find_result j ~rule_id:"r" with
          | None -> Batch.note b "the finding has no SARIF result at all"
          | Some r -> (
              match Json.member "locations" r with
              | Some (`List [ loc ]) ->
                  let fqn =
                    match Json.member "logicalLocations" loc with
                    | Some (`List [ ll ]) -> ( match Json.member "fullyQualifiedName" ll with Some (`String s) -> Some s | _ -> None)
                    | _ -> None
                  in
                  Batch.eq_string_opt b ~msg:"logicalLocations.fullyQualifiedName must be the whole name, not a truncated fragment"
                    fqn (Some "db.write") ;
                  let uri =
                    match Json.member "physicalLocation" loc with
                    | Some pl -> (
                        match Json.member "artifactLocation" pl with
                        | Some al -> ( match Json.member "uri" al with Some (`String s) -> Some s | _ -> None)
                        | None -> None)
                    | None -> None
                  in
                  (* The full, correctly-percent-encoded file path — not a fragment ending at the
                     wrong '(', and '#' must not survive raw (it is a URI fragment delimiter that
                     GitHub's SARIF viewer would otherwise split the path on). *)
                  Batch.eq_string_opt b ~msg:"artifactLocation.uri must be the full path, percent-encoded, not a truncated fragment"
                    uri (Some "/home/me/proj/lib/db/wri%23te%20%28x%29.ts")
              | other -> Batch.note b "expected exactly one location: %s" (Json.show other)))) ;
  Lwt.return_unit

(* MEDIUM: category collision. `Arch_sarif.log` must reject two runs sharing (producer, category)
   NOW, before 2.2 (`arch-report`) exists to emit several runs and trip over this in production —
   GitHub overwrites a run sharing tool+category with a later one rather than merging. *)
let register_duplicate_category_rejected () =
  Test.register ~__FILE__ ~title:"sarif: two runs sharing (producer, category) are rejected, not silently emitted"
    ~tags:["sarif"; "category"; "regression"]
  @@ fun () ->
  let open Arch_tools in
  let finding rule_id : Arch_sarif.finding =
    { rule_id; level = Arch_sarif.Error; message = "x"; verdict = None; soundness_class = None;
      soundness = None; top_reasons = []; locations = []; detail_total = 0; code_flow = [] }
  in
  let run cat rid : Arch_sarif.run =
    { producer = "arch-index"; producer_version = None; category = cat; findings = [ finding rid ];
      coverage = []; top_frontier = None; notifications = []; contract_ok = None; computed = None;
      proved = None }
  in
  Batch.run (fun b ->
      let raised =
        try
          ignore (Arch_sarif.to_string [ run "arch-index/rules" "r1"; run "arch-index/rules" "r2" ]) ;
          false
        with Invalid_argument _ -> true
      in
      Batch.check b ~msg:"Arch_sarif.log must reject two runs sharing (producer, category)" raised) ;
  Lwt.return_unit

(* A future SARIF-in adapter (roadmap 2.3) constructs {!Arch_tools.Arch_sarif.finding} values
   with [soundness_class = Some "heuristic"] directly — this is the writer-level guarantee that
   the field round-trips into `properties.soundness_class` (spec FR-022: "a heuristic fact
   carries that in its properties bag so a consumer can filter"), checked once here rather than
   only implicitly through arch-rules, which never sets this field itself. *)
let register_heuristic_soundness_class () =
  Test.register ~__FILE__ ~title:"sarif: a finding's soundness_class=heuristic round-trips into properties"
    ~tags:["sarif"; "heuristic"]
  @@ fun () ->
  let open Arch_tools in
  let finding : Arch_sarif.finding =
    { rule_id = "semgrep.some-rule"; level = Arch_sarif.Warning; message = "heuristic finding";
      verdict = None; soundness_class = Some "heuristic"; soundness = None; top_reasons = [];
      locations = []; detail_total = 0; code_flow = [] }
  in
  let run : Arch_sarif.run =
    { producer = "semgrep"; producer_version = Some "1.2.3"; category = "semgrep/oss";
      findings = [ finding ]; coverage = []; top_frontier = None; notifications = [];
      contract_ok = None; computed = None; proved = None }
  in
  let text = Arch_sarif.to_string [ run ] in
  Batch.run (fun b ->
      match Json.strict_object ~what:"heuristic sarif log" text with
      | Error e -> Batch.note b "%s" e
      | Ok j -> (
          match find_result j ~rule_id:"semgrep.some-rule" with
          | None -> Batch.note b "the finding has no SARIF result at all"
          | Some r -> (
              match Json.member "properties" r with
              | Some props ->
                  Batch.eq_string_opt b ~msg:"properties.soundness_class"
                    (match Json.member "soundness_class" props with Some (`String s) -> Some s | _ -> None)
                    (Some "heuristic")
              | None -> Batch.note b "result has no properties bag at all"))) ;
  Lwt.return_unit

(* H1 (round-3 review): `dep`'s `detail` rows are "A --kind--> B  (line N)" PROSE, not
   `Arch_graph.label` display labels — and that prose contains the EXACT "  (" separator
   `split_label` searches for, with a line NUMBER after it. Before this fix, `finding_of` passed
   `r.detail` straight through as `locations` for every rule kind, so `split_label` parsed
   "line 42" as a file name and fabricated a `physicalLocation` naming a nonexistent file (the
   round-3 reviewer's H1 finding, reproduced by hand against this exact fixture shape). A wrong
   fix that reverts to `locations = r.detail` unconditionally would make `results[].locations`
   reappear with a `logicalLocations[0].fullyQualifiedName` containing "--open-->" and a
   `physicalLocation.artifactLocation.uri` of "line%2001" — this test fails loudly on that shape
   by asserting `locations` is either absent or empty AND that no location's `uri` ends in a
   percent-encoded "line...". *)
let dep_violation_seed =
  "INSERT INTO modules(id, path) VALUES (1, 'src/ui/handler.ml'), (2, 'lib/db/writer.ml');\n\
   INSERT INTO functions(id, module_id, name) VALUES (1, 1, 'noop'), (2, 2, 'noop2');\n\
   INSERT INTO module_deps(source_module, target_module, target_path, dep_kind, line_number) \
   VALUES (1, 2, 'lib/db/writer.ml', 'open', 1);\n\
   INSERT INTO comment_db_meta(key, value) VALUES ('callgraph_contract', 'v1');"

let register_dep_violation_no_fabricated_location () =
  Test.register ~__FILE__
    ~title:"sarif: a `dep` VIOLATION does not fabricate results[].locations from its prose detail"
    ~tags:["sarif"; "rules"; "locations"; "regression"]
  @@ fun () ->
  let db = Fixture.main ~name:"sarif_dep_violation" ~seed:dep_violation_seed () in
  let rf =
    rule_file "sarif_dep_violation"
      "rule \"ui must not declare a dep on db\"\n\
      \  forbid dep from module:src/ui/** to module:lib/db/**\n"
  in
  let _, output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j -> (
          match find_result j ~rule_id:"ui must not declare a dep on db" with
          | None -> Batch.note b "the dep VIOLATION rule has no SARIF result at all"
          | Some r -> (
              (* The evidence must not be LOST, only kept out of `locations` — it must still be
                 readable somewhere, and `message.text` is where `message_of` already puts it. *)
              (match Json.member "message" r with
              | Some (`Assoc _ as m) -> (
                  match Json.member "text" m with
                  | Some (`String text) ->
                      Batch.contains b ~msg:"message.text must still carry the dep evidence"
                        ~haystack:text "writer.ml"
                  | _ -> Batch.note b "result has no message.text")
              | _ -> Batch.note b "result has no message object") ;
              match Json.member "locations" r with
              | None -> ()
              | Some (`List []) -> ()
              | Some (`List locs) ->
                  List.iter
                    (fun loc ->
                      match Json.member "physicalLocation" loc with
                      | None -> ()
                      | Some pl -> (
                          match Json.member "artifactLocation" pl with
                          | None -> ()
                          | Some al -> (
                              match Json.member "uri" al with
                              | Some (`String uri) ->
                                  Batch.check b
                                    ~msg:
                                      (Printf.sprintf
                                         "a dep VIOLATION must not fabricate a uri from its \
                                          'line N' suffix, got %S"
                                         uri)
                                    (not (contains ~needle:"line" uri))
                              | _ -> ())))
                    locs
              | other -> Batch.note b "results[].locations is present but not a list: %s" (Json.show other)))) ;
  Lwt.return_unit

(* M2: `message.text` is the ONLY channel carrying `r.note` for a "nothing proved" verdict — a
   mutant replacing the whole message with the constant "finding" passes every OTHER assertion in
   this suite, because nothing checks `message.text`'s actual content on such a verdict. Reuses
   the UNKNOWN_NO_CONTRACT fixture above (rule name "l"), which has a fixed, distinctive note. *)
let register_message_text_carries_evidence () =
  Test.register ~__FILE__
    ~title:"sarif: a nothing-proved result's message.text names the rule, the verdict, and its note"
    ~tags:["sarif"; "rules"; "message"]
  @@ fun () ->
  let db =
    Fixture.raw ~name:"sarif_message_text"
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
  let rf =
    rule_file "sarif_message_text" "rule \"l\"\n  forbid reach from file:src/pure/** to file:lib/db/**\n"
  in
  let _, output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j -> (
          match find_result j ~rule_id:"l" with
          | None -> Batch.note b "the UNKNOWN_NO_CONTRACT rule has no SARIF result at all"
          | Some r -> (
              match Json.member "message" r with
              | Some (`Assoc _ as m) -> (
                  match Json.member "text" m with
                  | Some (`String text) ->
                      Batch.contains b ~msg:"message.text must name the rule (\"l\")" ~haystack:text "l" ;
                      Batch.contains b ~msg:"message.text must name the verdict"
                        ~haystack:text "UNKNOWN_NO_CONTRACT" ;
                      Batch.contains b
                        ~msg:"message.text must carry a fragment of the note explaining WHY"
                        ~haystack:text "dropped dynamic edge"
                  | _ -> Batch.note b "result has no message.text — a mutant replacing it with a \
                                       constant would pass every other assertion in this suite")
              | _ -> Batch.note b "result has no message object"))) ;
  Lwt.return_unit

(* M4: the MAIN-schema half of `top_reasons_for` (arch_rules.ml) — the [caller_id] '#'-prefixed
   key parsing and the `caller_id IN (...)` query — had ZERO coverage: `| Arch_db.Main -> []`
   passes every existing test, because the only `top_reason` fixture in this suite (and in
   rules.ml) is FLAT. MAIN is the schema the OCaml `.cmt` backend actually produces. *)
let main_top_reason_seed =
  "INSERT INTO modules(id, path) VALUES (1, 'src/m/a.ml'), (2, 'src/m/b.ml'), \
   (3, 'src/m/target.ml');\n\
   INSERT INTO functions(id, module_id, name) VALUES (1, 1, 'a_fn'), (2, 2, 'b_fn'), \
   (3, 3, 'target_fn');\n\
   INSERT INTO calls(caller_id, callee_id, callee_name, kind) VALUES \
   (1, 2, 'b_fn', 'MUST');\n\
   INSERT INTO calls(caller_id, callee_id, callee_name, kind, top_reason) VALUES \
   (2, NULL, '*TOP*', 'MAY_TOP', 'reflection');\n\
   INSERT INTO comment_db_meta(key, value) VALUES ('callgraph_contract', 'v1');"

let register_main_schema_top_reasons () =
  Test.register ~__FILE__
    ~title:"sarif: a MAIN-schema UNKNOWN result's top_reasons is read via caller_id, not left empty"
    ~tags:["sarif"; "rules"; "top_reason"; "main_schema"]
  @@ fun () ->
  let db = Fixture.main ~name:"sarif_main_top_reason" ~seed:main_top_reason_seed () in
  let rf =
    rule_file "sarif_main_top_reason"
      "rule \"m\"\n  forbid reach from file:src/m/a.ml to file:src/m/target.ml\n"
  in
  let _, output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j -> (
          match find_result j ~rule_id:"m" with
          | None ->
              Batch.note b
                "the MAIN-schema rule has no SARIF result at all — expected UNKNOWN (b_fn's own \
                 MAY_TOP escape); a PASS here would mean this fixture stopped exercising the \
                 UNKNOWN branch at all"
          | Some r -> (
              (match Json.member "properties" r with
              | Some props ->
                  Batch.eq_string_opt b ~msg:"properties.verdict must be UNKNOWN on this fixture"
                    (match Json.member "verdict" props with Some (`String s) -> Some s | _ -> None)
                    (Some "UNKNOWN")
              | None -> Batch.note b "result has no properties bag at all") ;
              match Json.member "properties" r with
              | Some props -> (
                  match Json.member "top_reason" props with
                  | Some (`List [ `String s ]) ->
                      Batch.eq_string b ~msg:"properties.top_reason[0]" s "reflection"
                  | other ->
                      Batch.note b
                        "properties.top_reason missing or not a singleton list — the MAIN branch \
                         of top_reasons_for returned [] (its `| Arch_db.Main -> []` stub \
                         survives): %s"
                        (Json.show other))
              | None -> Batch.note b "result has no properties bag at all"))) ;
  Lwt.return_unit

(* M5: FLAT-schema provenance — `comment_db_meta.producer` and `comment_db_meta.soundness_class`
   both had zero direct coverage: the only provenance test in this suite exercises MAIN's
   `producer_runs` path. Every `arch-load` DB writes `soundness_class` unconditionally (defaulting
   to "heuristic" with no `--soundness-class` flag) — the exact FLAT/heuristic case FR-022's
   `properties.soundness_class` filter exists for — and `producer` when `--producer` is passed. *)
let register_flat_provenance_round_trip () =
  Test.register ~__FILE__
    ~title:"sarif: a FLAT index's producer/soundness_class round-trip from comment_db_meta"
    ~tags:["sarif"; "rules"; "provenance"; "flat_schema"]
  @@ fun () ->
  let db_name = "sarif_flat_provenance" in
  let db_path =
    let p = Temp.file (db_name ^ ".db") in
    if Sys.file_exists p then Sys.remove p ;
    p
  in
  let code, load_output =
    run_command ~stdin:layered_stream (arch_load ()) ["--producer=acme-flat"; db_path]
  in
  if code <> 0 then Test.fail "building FLAT provenance fixture failed (exit %d):\n%s" code load_output ;
  let rf = rule_file "sarif_flat_provenance" four_rules in
  let _, output = rules [db_path; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j -> (
          (match Json.member "runs" j with
          | Some (`List [ run ]) -> (
              match Json.member "tool" run with
              | Some t -> (
                  match Json.member "driver" t with
                  | Some d ->
                      Batch.eq_string_opt b ~msg:"tool.driver.name must come from comment_db_meta('producer')"
                        (match Json.member "name" d with Some (`String s) -> Some s | _ -> None)
                        (Some "acme-flat")
                  | None -> Batch.note b "run has no tool.driver at all")
              | None -> Batch.note b "run has no tool at all")
          | other -> Batch.note b "sarif output does not have exactly one run: %s" (Json.show other)) ;
          match find_result j ~rule_id:"ui must not reach persistence" with
          | None -> Batch.note b "the VIOLATION rule has no SARIF result at all"
          | Some r -> (
              match Json.member "properties" r with
              | Some props ->
                  Batch.eq_string_opt b
                    ~msg:"results[0].properties.soundness_class must be 'heuristic' \
                          (comment_db_meta's default, unread by a stubbed-out FLAT path)"
                    (match Json.member "soundness_class" props with Some (`String s) -> Some s | _ -> None)
                    (Some "heuristic")
              | None -> Batch.note b "result has no properties bag at all"))) ;
  Lwt.return_unit

(* M6: `results[].locations` is silently truncated at 20 (arch_rules.ml's `take 20`) with no
   signal a consumer can use to tell "20 shown" from "20 of N total" — the exact channel
   asymmetry docs/fitness-functions.md's `detail_total` fitness function exists to close, now
   reintroduced in the SARIF channel specifically. 25 exported functions, none matched by the
   rule's selector, so EVERY one is an offender: `locations` truncates to 20 but
   `properties.detail_total` must still say 25. *)
let many_offenders_stream =
  let buf = Buffer.create 1024 in
  for i = 1 to 25 do
    Buffer.add_string buf
      (Printf.sprintf {|{"type":"function","name":"pub.fn%d","file_path":"src/pub/fn%d.ts","exported":true}
|} i i)
  done ;
  (* `arch-load` refuses a call-free stream outright ("0 call edges loaded ... would report
     EVERYTHING as UNREACHABLE") — one harmless internal call keeps this a normal, non-empty
     index without adding a 26th exported offender. *)
  Buffer.add_string buf
    {|{"type":"function","name":"internal.helper","file_path":"src/internal/helper.ts"}
{"type":"call","caller_name":"pub.fn1","callee_name":"internal.helper","call_site":"src/pub/fn1.ts:1","kind":"MUST"}
|} ;
  Buffer.contents buf

let register_detail_total_property () =
  Test.register ~__FILE__
    ~title:"sarif: a truncated results[].locations still carries properties.detail_total"
    ~tags:["sarif"; "rules"; "locations"; "truncation"]
  @@ fun () ->
  let db = Fixture.flat ~name:"sarif_detail_total" many_offenders_stream in
  let rf =
    rule_file "sarif_detail_total" "rule \"none exported\"\n  forbid exported outside file:zzzz/nope/**\n"
  in
  let _, output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j -> (
          match find_result j ~rule_id:"none exported" with
          | None -> Batch.note b "the VIOLATION rule has no SARIF result at all"
          | Some r -> (
              (match Json.member "locations" r with
              | Some (`List locs) ->
                  Batch.eq_int b ~msg:"results[].locations is truncated to 20" (List.length locs) 20
              | other -> Batch.note b "results[].locations missing or not a list: %s" (Json.show other)) ;
              match Json.member "properties" r with
              | Some props -> (
                  match Json.member "detail_total" props with
                  | Some (`Int n) ->
                      Batch.eq_int b
                        ~msg:"properties.detail_total must be the UNTRUNCATED count (25), not \
                              List.length locations (20)"
                        n 25
                  | other ->
                      Batch.note b "properties.detail_total missing or not an int: %s" (Json.show other))
              | None -> Batch.note b "result has no properties bag at all"))) ;
  Lwt.return_unit

let register () =
  register_schema_valid () ;
  register_pass_excluded () ;
  register_level_mapping () ;
  register_unknown_carries_soundness_and_top_reason () ;
  register_unknown_no_contract_distinct_soundness () ;
  register_json_top_reasons () ;
  register_witness_becomes_code_flow () ;
  register_run_shape_and_category () ;
  register_json_sarif_round_trip () ;
  register_not_analysed_becomes_notification () ;
  register_provenance_read_path () ;
  register_two_runs_distinct_categories () ;
  register_locations_present () ;
  register_split_label_paren_in_filename () ;
  register_duplicate_category_rejected () ;
  register_heuristic_soundness_class () ;
  register_dep_violation_no_fabricated_location () ;
  register_message_text_carries_evidence () ;
  register_main_schema_top_reasons () ;
  register_flat_provenance_round_trip () ;
  register_detail_total_property ()
