(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** [arch-report] — one query pass, three renderings (roadmap 2.2,
    specs/reporting-and-integration.md).

    {1 CHECK-5 is a construction constraint, and this file is what keeps it one}

    The spec asks that every finding in [report.json] appear in [report.sarif] and in the rendered
    HTML with identical provenance. The cheap way to satisfy that is to build three renderings and
    then assert three times over them — a test that cannot fail for the right reason, because
    three independently-built collections can be wrong the same way and the assertion compares two
    implementations of one mistake.

    {!Arch_tools.Arch_report} therefore runs the queries once and the three renderers are total
    functions of that one value. This file asserts the round-trip anyway: a guarantee nothing
    checks is a guarantee that expires the first time someone adds a fourth renderer.

    {1 What the fixture must be able to do}

    Every assertion here is written against a database with findings in it, because a round-trip
    over zero findings holds vacuously — and the empty case gets its own test rather than being
    the accidental shape of this one. *)

open Arch_tezt

let fixture_files =
  [
    Fixture.dune_project;
    ( "dune",
      "(library\n\
      \ (name rep_fixture)\n\
      \ (wrapped false)\n\
      \ (modules rep_a)\n\
      \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
    ( "rep_a.ml",
      {|exception Boom
let leaf n = if n > 0 then raise Boom else n
let caller n = leaf n
|} );
  ]

(* Two dead-code rows inserted directly, so the round-trip has content this test CONTROLS: the
   ids it asserts on are derived from these, not from whatever the walker happened to find. A
   fixture whose findings depend on the producer would make this test drift with the producer. *)
let seed_findings db =
  Db.with_db_rw db (fun c ->
      List.iter
        (fun sql -> ignore (Db.exec_result c sql))
        [
          "INSERT INTO dead_code_sites (function_id, call_site, callee_name) SELECT id, \
           'rep_a.ml:2', 'Stdlib.raise' FROM functions WHERE name='leaf' LIMIT 1";
          "INSERT INTO dead_code_sites (function_id, call_site, callee_name) SELECT id, \
           'rep_a.ml:3', 'leaf' FROM functions WHERE name='caller' LIMIT 1";
        ])

let run_report db =
  let dir = Temp.dir "arch_report_out" in
  let code, out = Arch_tezt.run_command (Arch_tezt.arch_report ()) [ db; "--out"; dir ] in
  if code <> 0 then Test.fail "arch-report failed (exit %d):\n%s" code out ;
  let read name =
    let ic = open_in (Filename.concat dir name) in
    let n = in_channel_length ic in
    let s = really_input_string ic n in
    close_in ic ; s
  in
  (read "report.json", read "report.sarif", read "report.html")

let str k j = match Json.member k j with Some (`String s) -> Some s | _ -> None

(* Read through the same accessor the other suites use, so a shape change in the report shows up
   here as a missing field rather than as a silently-empty list. *)
let json_findings raw =
  match Json.strict_object ~what:"report.json" raw with
  | Error e -> Test.fail "%s" e
  | Ok j ->
      (match Json.member "sections" j with Some (`List l) -> l | _ -> [])
      |> List.concat_map (fun s ->
             match Json.member "findings" s with Some (`List l) -> l | _ -> [])
      |> List.map (fun f ->
             ( Option.value ~default:"<no id>" (str "id" f),
               str "location" f,
               Option.value ~default:"<none>" (str "soundness_class" f) ))

let register_round_trip () =
  Test.register ~__FILE__
    ~title:"arch-report: every finding in report.json appears in the SARIF and the HTML (CHECK-5)"
    ~tags:["report"; "sarif"; "html"; "roundtrip"]
  @@ fun () ->
  with_fixture ~name:"rep_rt" ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "rep_rt" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  seed_findings db ;
  let json, sarif, html = run_report db in
  Batch.run (fun b ->
      let fs = json_findings json in
      (* PREMISE. A round-trip over zero findings holds for every implementation, correct or not.
         The empty case is a DIFFERENT test, below. *)
      Batch.eq_int b ~msg:"premise: the report carries the two seeded findings" (List.length fs) 2 ;
      List.iter
        (fun (id, loc, sc) ->
          (* The SARIF channel. Matching on the LOCATION and the soundness class rather than on
             the id: the id is this report's own handle, while location and provenance are what a
             consumer of the SARIF actually reads, so asserting on them is what makes "identical
             provenance" mean something to a reader of that file. *)
          Batch.check b
            ~msg:(Printf.sprintf "finding %s: its location reaches report.sarif" id)
            (match loc with
             | Some l -> Arch_tezt.contains ~needle:l sarif
             | None -> true) ;
          Batch.check b
            ~msg:(Printf.sprintf "finding %s: its soundness_class reaches report.sarif" id)
            (Arch_tezt.contains ~needle:sc sarif) ;
          (* The HTML channel. Same two facts, and the id as well, since the HTML is the one a
             human reads and the handle is what they would quote back. *)
          Batch.check b
            ~msg:(Printf.sprintf "finding %s: its id reaches report.html" id)
            (Arch_tezt.contains ~needle:id html) ;
          Batch.check b
            ~msg:(Printf.sprintf "finding %s: its location reaches report.html" id)
            (match loc with Some l -> Arch_tezt.contains ~needle:l html | None -> true))
        fs) ;
  Lwt.return_unit

(* FR-024 / CHECK-2. An analysis that produced nothing must appear as a labelled, empty section —
   never as an absent one, and never as a clean result. *)
let register_not_analysed () =
  Test.register ~__FILE__
    ~title:"arch-report: an analysis that did not run renders explicitly, never as absent (FR-024)"
    ~tags:["report"; "coverage"; "not_analysed"]
  @@ fun () ->
  with_fixture ~name:"rep_na" ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "rep_na" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  Batch.run (fun b ->
      (* THREE STATES, and the point of the test is that they are three. An empty table and an
         absent one are the same picture to a reader who only sees "no findings", and telling
         them apart is what FR-003 asks for. *)
      let status () =
        let json, _, html = run_report db in
        (* Scoped to the section under test rather than concatenating every status. The first
           version joined them all, so adding a SECOND analysis broke three assertions that had
           nothing to do with it — an assertion coupled to the section LIST rather than to the
           section it is about. *)
        let s =
          match Json.strict_object ~what:"report.json" json with
          | Error e -> Test.fail "%s" e
          | Ok j ->
              (match Json.member "sections" j with Some (`List l) -> l | _ -> [])
              |> List.find_opt (fun sec -> str "analysis" sec = Some "dead_code")
              |> (function Some sec -> Option.value ~default:"<no status>" (str "status" sec)
                         | None -> "<no dead_code section>")
        in
        (s, html)
      in
      let s_empty, html_empty = status () in
      Batch.eq_string b
        ~msg:"an EMPTY findings table is 'unknown' — it may have run and found nothing, or never \
              run, and the database cannot say which"
        s_empty "unknown" ;
      Batch.check b
        ~msg:"and the HTML says so rather than showing a bare empty list"
        (Arch_tezt.contains ~needle:"NOT a clean result" html_empty) ;
      Batch.check b ~msg:"the section is present and labelled even with no findings"
        (Arch_tezt.contains ~needle:"dead_code" html_empty) ;
      (* Now with rows: the same section must become 'covered'. Without this the assertion above
         would also be satisfied by an implementation that says 'unknown' unconditionally. *)
      seed_findings db ;
      let s_rows, _ = status () in
      Batch.eq_string b ~msg:"with rows, the same analysis reports covered" s_rows "covered" ;
      (* And absent: a different word again. *)
      Db.with_db_rw db (fun c -> ignore (Db.exec_result c "DROP TABLE dead_code_sites")) ;
      let s_absent, html_absent = status () in
      Batch.eq_string b ~msg:"an ABSENT table is not_analysed, not 'unknown' and not 'covered'"
        s_absent "not_analysed" ;
      Batch.check b ~msg:"and the section still appears, labelled — FR-024's whole point"
        (Arch_tezt.contains ~needle:"dead_code" html_absent)) ;
  Lwt.return_unit

(* THE INTERACTION, and it was found by running one slice's binary against the other's database
   rather than by reviewing either. Roadmap 2.3 imports foreign findings; this report renders
   findings. Neither is wrong alone, and together they produced a FALSE CLEAN: the header listed
   `semgrep` and `gosec` as heuristic producers while every section showed nothing, so a reader
   saw two third-party tools having run and a clean report.

   An analysis present in the provenance and absent from the results is not a missing feature. It
   is the exact reading FR-024 exists to prevent, reached through composition. *)
let register_imported_section () =
  Test.register ~__FILE__
    ~title:"arch-report: imported heuristic findings are rendered, with their own provenance"
    ~tags:["report"; "imported"; "heuristic"; "adr002"]
  @@ fun () ->
  with_fixture ~name:"rep_imp" ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "rep_imp" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  Batch.run (fun b ->
      (* An index without the table is the shape `main` has today, and the honest answer is
         `not_analysed` — the analysis is not available here, which is a different statement from
         "it found nothing". *)
      let sections () =
        let json, _, html = run_report db in
        let st =
          match Json.strict_object ~what:"report.json" json with
          | Error e -> Test.fail "%s" e
          | Ok j ->
              (match Json.member "sections" j with Some (`List l) -> l | _ -> [])
              |> List.filter_map (fun s ->
                     match (str "analysis" s, str "status" s) with
                     | Some a, Some st -> Some (a ^ "=" ^ st)
                     | _ -> None)
              |> String.concat ","
        in
        (st, html)
      in
      let before, _ = sections () in
      Batch.check b
        ~msg:("without the table, the section is present and not_analysed (got " ^ before ^ ")")
        (Arch_tezt.contains ~needle:"imported=not_analysed" before) ;
      (* Now the 2.3 shape: the table, a heuristic producer run, and a finding attributed to it.
         Created here rather than by invoking the adapter, so this test does not depend on a
         binary from another branch — it depends on the SHAPE that branch writes. *)
      Db.with_db_rw db (fun c ->
          List.iter
            (fun sql -> ignore (Db.exec_result c sql))
            [
              "CREATE TABLE IF NOT EXISTS imported_findings (id INTEGER PRIMARY KEY \
               AUTOINCREMENT, producer_run_id INTEGER NOT NULL, rule_id TEXT NOT NULL, level \
               TEXT NOT NULL, message TEXT NOT NULL, uri TEXT, start_line INTEGER, module_id \
               INTEGER, resolution TEXT NOT NULL, created_at TEXT DEFAULT CURRENT_TIMESTAMP)";
              "INSERT INTO producer_runs (producer, producer_version, soundness_class) VALUES \
               ('semgrep', '1.2.3', 'heuristic')";
              "INSERT INTO imported_findings (producer_run_id, rule_id, level, message, uri, \
               start_line, resolution) SELECT id, 'ocaml.taint', 'error', 'tainted input', \
               'rep_a.ml', 2, 'resolved' FROM producer_runs WHERE producer='semgrep'";
            ]) ;
      let after, html = sections () in
      Batch.check b
        ~msg:("with the table and a row, the section is covered (got " ^ after ^ ")")
        (Arch_tezt.contains ~needle:"imported=covered" after) ;
      (* THE PROVENANCE, and it is the point rather than a detail. A heuristic finding rendered
         with the SOUND producer's class would be an ADR-002 mislabel — the class must come from
         the finding's OWN run, since several producers coexist in one database. *)
      (* ASSERTED ON THE FINDING'S OWN FIELDS, not on the presence of a word in the page. The
         first version used [contains "heuristic"] and [contains "sound_with_top"], and BOTH
         strings are already in the producers table whatever the finding carries — so a mutant
         taking the class from the FIRST producer (the sound indexer) instead of from the
         finding's own run SURVIVED. The needle was in the haystack before the search began. *)
      let imported_findings =
        let json, _, _ = run_report db in
        match Json.strict_object ~what:"report.json" json with
        | Error e -> Test.fail "%s" e
        | Ok j ->
            (match Json.member "sections" j with Some (`List l) -> l | _ -> [])
            |> List.filter (fun sec -> str "analysis" sec = Some "imported")
            |> List.concat_map (fun sec ->
                   match Json.member "findings" sec with Some (`List l) -> l | _ -> [])
      in
      Batch.eq_int b ~msg:"premise: exactly one imported finding to reason about"
        (List.length imported_findings) 1 ;
      List.iter
        (fun f ->
          Batch.eq_string b ~msg:"the finding names its OWN producer, not the indexer"
            (Option.value ~default:"<none>" (str "producer" f))
            "semgrep" ;
          (* THE ADR-002 LABEL. A heuristic finding carrying the sound producer's class is the
             mislabel the whole soundness_class design exists to prevent, and it is invisible to
             any assertion that only checks the word appears on the page. *)
          Batch.eq_string b ~msg:"and its OWN soundness class — 'heuristic', never the indexer's"
            (Option.value ~default:"<none>" (str "soundness_class" f))
            "heuristic")
        imported_findings ;
      (* And the indexer keeps its own class in the header, so the two are not merged in the
         other direction either. *)
      Batch.check b
        ~msg:"the sound producer is still shown as sound in the header"
        (Arch_tezt.contains ~needle:"sound_with_top" html)) ;
  Lwt.return_unit

let register () =
  register_round_trip () ;
  register_not_analysed () ;
  register_imported_section ()
