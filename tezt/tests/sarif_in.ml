(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** [arch-sarif-load] — importing a foreign analyser's findings (roadmap 2.3, CHECK-1, CHECK-3,
    CHECK-3-bis).

    {1 The guarantee this file exists for}

    ADR 002: a [heuristic] fact may raise a finding and may never discharge a ⊤ anchor nor license
    a [PASS]. The design makes that structural rather than remembered — imported findings live in
    a table no reachability or effect query reads, and create no [calls] row — so the test asserts
    the {b consequence}: an import leaves the call graph byte-identical. A fact that cannot reach a
    verdict is a stronger guarantee than one merely forbidden from changing it.

    {1 The two failure states are not one}

    FR-012 keeps them apart and the spec's original CHECK-3 did not: an input that cannot be parsed
    is [failed] and writes {b no facts}; an input that parses while records are refused is
    [partial] and writes the ones that survived. Offered as alternatives, an implementation
    satisfies the check with either, and one of the two would be a lie about what happened. Both
    are asserted here, separately, with the counts. *)

open Arch_tezt

let fixture_files =
  [
    Fixture.dune_project;
    ( "dune",
      "(library\n (name si_fixture)\n (wrapped false)\n (modules si_a si_b)\n\
      \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
    ("si_a.ml", "exception Boom\nlet leaf n = if n > 0 then raise Boom else n\n");
    ("si_b.ml", "let caller n = Si_a.leaf n\n");
  ]

let write path s =
  let oc = open_out path in
  output_string oc s ; close_out oc ; path

let load db file =
  Arch_tezt.run_command (Arch_tezt.arch_sarif_load ()) [ db; file ]

let graph_shape db =
  Db.with_db db (fun c ->
      Db.int c "SELECT count(*) FROM calls",
      Db.int c "SELECT COALESCE(sum(callee_id IS NOT NULL),0) FROM calls",
      Db.int c "SELECT COALESCE(sum(kind='MAY_TOP'),0) FROM calls")

let indexed name f =
  with_fixture ~name ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db name in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  f db

let register_heuristic_cannot_reach () =
  Test.register ~__FILE__
    ~title:"sarif-in: an imported finding is heuristic and changes no edge (CHECK-1)"
    ~tags:["sarif"; "ingest"; "heuristic"; "adr002"]
  @@ fun () ->
  indexed "si_check1" @@ fun db ->
  let before = graph_shape db in
  let f =
    write (Temp.file "semgrep.sarif")
      {|{"version":"2.1.0","runs":[{"tool":{"driver":{"name":"semgrep","version":"1.2.3"}},
        "results":[{"ruleId":"ocaml.taint","level":"error","message":{"text":"tainted"},
        "locations":[{"physicalLocation":{"artifactLocation":{"uri":"si_a.ml"},
        "region":{"startLine":2}}}]}]}]}|}
  in
  let code, out = load db f in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:("the import succeeds (output:\n" ^ out ^ ")") code 0 ;
      Batch.eq_int b ~msg:"the finding landed" (Db.with_db db (fun c -> Db.int c "SELECT count(*) FROM imported_findings")) 1 ;
      (* ADR-002's class, and it is carried by the RUN rather than by a column on the finding:
         one place to be right instead of one copy per row that could drift from it. *)
      Batch.eq_string b ~msg:"it is attributed to a heuristic producer run"
        (String.concat ","
           (Db.with_db db (fun c ->
                Db.rows c
                  "SELECT r.soundness_class FROM imported_findings f \
                   JOIN producer_runs r ON f.producer_run_id = r.id")
            |> List.map (function [ x ] -> Db.to_string ~sql:"sc" x | _ -> Test.fail "shape")))
        "heuristic" ;
      (* THE GUARANTEE. Not "it did not license a PASS" — it could not have reached one. *)
      let a, b', c = graph_shape db and a0, b0, c0 = before in
      Batch.check b
        ~msg:
          (Printf.sprintf
             "the call graph is byte-identical across the import: total %d->%d, resolved %d->%d, \
              MAY_TOP %d->%d"
             a0 a b0 b' c0 c)
        (a = a0 && b' = b0 && c = c0) ;
      (* And the resolution is recorded rather than guessed: si_a.ml IS indexed, so this one
         resolves. Its unresolvable sibling is the next test's business. *)
      Batch.eq_string b ~msg:"a uri naming an indexed file resolves"
        (String.concat ","
           (Db.with_db db (fun c -> Db.rows c "SELECT resolution FROM imported_findings")
            |> List.map (function [ x ] -> Db.to_string ~sql:"res" x | _ -> Test.fail "shape")))
        "resolved") ;
  Lwt.return_unit

let register_failure_states () =
  Test.register ~__FILE__
    ~title:"sarif-in: unparseable writes no facts (CHECK-3); parseable-with-rejects is partial (CHECK-3-bis)"
    ~tags:["sarif"; "ingest"; "coverage"; "partial"]
  @@ fun () ->
  indexed "si_check3" @@ fun db ->
  let count sql = Db.with_db db (fun c -> Db.int c sql) in
  Batch.run (fun b ->
      (* CHECK-3. "Writes no facts" is transactional: a loop that stops at the bad record leaves
         everything before it written, which satisfies the words and not the intent. The whole
         input is parsed before any write is opened, so a malformed file never reaches the
         writer. *)
      let bad = write (Temp.file "bad.sarif") {|{"runs": [ this is not json|} in
      let code_bad, _ = load db bad in
      Batch.eq_int b ~msg:"a malformed SARIF exits non-zero" code_bad 2 ;
      Batch.eq_int b ~msg:"and writes NO fact rows" (count "SELECT count(*) FROM imported_findings") 0 ;
      Batch.eq_int b
        ~msg:"and creates no producer run either — nothing about the program was recorded"
        (count "SELECT count(*) FROM producer_runs WHERE soundness_class='heuristic'") 0 ;
      (* The coverage row IS written, and that is not a contradiction: it is a write about the
         FAILURE, not about the program. FR-012's own second sentence already relies on that
         distinction. *)
      Batch.eq_int b ~msg:"but a 'failed' coverage row IS written — the failure is recorded"
        (count "SELECT count(*) FROM analysis_coverage WHERE analysis='sarif_import' AND status='failed'")
        1 ;
      (* CHECK-3-bis. Parses, two records refused: an unknown `level` (SARIF's vocabulary is
         closed and the input is foreign, so a value we do not know is a fact about the producer,
         not noise to fold into a default) and a result with no ruleId. *)
      let partial =
        write (Temp.file "partial.sarif")
          {|{"version":"2.1.0","runs":[{"tool":{"driver":{"name":"clippy"}},"results":[
            {"ruleId":"good","level":"note","message":{"text":"ok"},
             "locations":[{"physicalLocation":{"artifactLocation":{"uri":"si_b.ml"},"region":{"startLine":1}}}]},
            {"ruleId":"bad.level","level":"catastrophe","message":{"text":"unknown level"}},
            {"level":"note","message":{"text":"no ruleId"}}]}]}|}
      in
      let code_p, out_p = load db partial in
      Batch.eq_int b ~msg:"a parseable SARIF with refused records still exits 0" code_p 0 ;
      Batch.eq_int b ~msg:"the accepted record is written" (count "SELECT count(*) FROM imported_findings") 1 ;
      Batch.eq_int b ~msg:"the status is 'partial', not 'failed' — a different state, not an alternative"
        (count "SELECT count(*) FROM analysis_coverage WHERE analysis='sarif_import' AND status='partial'")
        1 ;
      Batch.check b
        ~msg:("the rejected COUNT is recorded, so 'partial' is checkable (output:\n" ^ out_p ^ ")")
        (Arch_tezt.contains ~needle:"2 refused" out_p) ;
      (* THE UNRESOLVED PATH. A uri naming no indexed file is recorded as unresolved, never
         attached to the nearest match — a finding on the wrong function is worse than one on
         none, and a suffix match produces the wrong one cheerfully. *)
      let stray =
        write (Temp.file "stray.sarif")
          {|{"version":"2.1.0","runs":[{"tool":{"driver":{"name":"staticcheck"}},"results":[
            {"ruleId":"SA1000","level":"warning","message":{"text":"elsewhere"},
             "locations":[{"physicalLocation":{"artifactLocation":{"uri":"nowhere/absent.ml"},
             "region":{"startLine":9}}}]}]}]}|}
      in
      let code_s, _ = load db stray in
      Batch.eq_int b ~msg:"an unresolvable location does not fail the import" code_s 0 ;
      Batch.eq_int b ~msg:"it is recorded as unresolved with a NULL module_id, not guessed"
        (count
           "SELECT count(*) FROM imported_findings WHERE resolution='unresolved' AND module_id IS NULL \
            AND uri='nowhere/absent.ml'")
        1 ;
      (* AMBIGUITY IS THE OTHER HALF, and the fixture could not produce it: with two files whose
         basenames differ, "refuses several candidates" and "takes the first" are the same
         behaviour, and a mutant turning [| [ id ] -> Some id] into [| id :: _ -> Some id]
         SURVIVED. A second module sharing a basename is inserted so the two can differ.

         Ambiguity is absence of proof. Resolving to one of several is how a foreign finding
         lands on a function nobody meant — the same rule the qualified-name resolver follows,
         and it matters more here because the uri comes from a tool that knows nothing of this
         tree. *)
      Db.with_db_rw db (fun c ->
          ignore
            (Db.exec_result c
               "INSERT INTO modules (path, lines) VALUES ('vendor/si_a.ml', 1)")) ;
      Batch.eq_int b
        ~msg:"premise: two modules now share the basename, so the uri really is ambiguous"
        (count "SELECT count(*) FROM modules WHERE path LIKE '%si_a.ml'") 2 ;
      let ambiguous =
        write (Temp.file "ambiguous.sarif")
          {|{"version":"2.1.0","runs":[{"tool":{"driver":{"name":"gosec"}},"results":[
            {"ruleId":"G404","level":"error","message":{"text":"ambiguous"},
             "locations":[{"physicalLocation":{"artifactLocation":{"uri":"si_a.ml"},
             "region":{"startLine":2}}}]}]}]}|}
      in
      let code_a, _ = load db ambiguous in
      Batch.eq_int b ~msg:"an ambiguous location does not fail the import" code_a 0 ;
      Batch.eq_int b
        ~msg:"a uri matching TWO modules is unresolved — never resolved to the first candidate"
        (count
           "SELECT count(*) FROM imported_findings WHERE uri='si_a.ml' AND resolution='unresolved' \
            AND module_id IS NULL")
        1) ;
  Lwt.return_unit

let register () =
  register_heuristic_cannot_reach () ;
  register_failure_states ()
