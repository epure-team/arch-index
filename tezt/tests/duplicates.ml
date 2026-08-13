(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** arch-body-compare: the CLI over the body-hash duplicate proof.

    The verdicts have to stay distinguishable, because they carry different
    weight. DUPLICATE is a proof — the bodies were read and hashed equal.
    UNVERIFIABLE is the absence of one: the sources could not be read, so two
    empty bodies hashed equal and that says nothing. Collapsing the second into
    the first would report every deleted file as a proven duplicate of every
    other deleted file. *)

open Arch_tezt

let repo_files =
  [
    (* Identical modulo whitespace, under one shared name in two modules. *)
    ("lib/a/dup.ml", "  let run () =\n      1 + 1\n");
    ("lib/b/dup.ml", "let run () =\n1 + 1\n");
    (* Genuinely different, used to flip the verdict to DIFFERS. *)
    ("lib/c/dup.ml", "let run () =\n2 + 2\n");
    ("lib/a/solo.ml", "let solo () = 42\n");
  ]

let bc db args = run_command (arch_body_compare ()) (db :: args)

let bc_out db args =
  let code, output = bc db args in
  if code <> 0 then
    Test.fail "arch-body-compare %s failed (exit %d):\n%s" (String.concat " " args) code output ;
  output

let seed_db name sql = Fixture.main ~name ~seed:sql ()

let register () =
  Test.register ~__FILE__ ~title:"duplicates: a proof, a single, and a difference"
    ~tags:["duplicates"; "body_compare"]
  @@ fun () ->
  with_project ~name:"duprepo" ~files:repo_files @@ fun repo ->
  let db =
    seed_db "duplicates"
      {|
INSERT INTO modules(path, lines) VALUES ('lib/a/dup.ml', 2), ('lib/b/dup.ml', 2), ('lib/a/solo.ml', 1);
INSERT INTO functions(module_id, name, line_start, line_end) VALUES
  ((SELECT id FROM modules WHERE path='lib/a/dup.ml'), 'dup', 1, 2),
  ((SELECT id FROM modules WHERE path='lib/b/dup.ml'), 'dup', 1, 2),
  ((SELECT id FROM modules WHERE path='lib/a/solo.ml'), 'solo', 1, 1);
|}
  in
  Batch.run (fun b ->
      Batch.contains b ~msg:"an unknown name must report NOT FOUND"
        ~haystack:(bc_out db ["nope"; "--repo"; repo]) "NOT FOUND" ;
      Batch.contains b ~msg:"a name defined once must report SINGLE, not a duplicate"
        ~haystack:(bc_out db ["solo"; "--repo"; repo]) "SINGLE" ;
      Batch.contains b
        ~msg:"two whitespace-only-different occurrences must be a proven DUPLICATE"
        ~haystack:(bc_out db ["dup"; "--repo"; repo]) "DUPLICATE: 2 occurrence" ;

      (* A genuinely different third occurrence must flip the verdict. *)
      Db.with_db_rw db (fun conn ->
          Db.exec conn
            "INSERT INTO modules(path, lines) VALUES ('lib/c/dup.ml', 2);\n\
             INSERT INTO functions(module_id, name, line_start, line_end) VALUES \
             ((SELECT id FROM modules WHERE path='lib/c/dup.ml'), 'dup', 1, 2);") ;
      Batch.contains b
        ~msg:"a genuinely different body must flip dup to DIFFERS across 3 occurrences"
        ~haystack:(bc_out db ["dup"; "--repo"; repo]) "DIFFERS: 3 occurrence" ;
      Db.with_db_rw db (fun conn ->
          Db.exec conn
            "DELETE FROM functions WHERE name='dup' AND module_id=(SELECT id FROM modules WHERE \
             path='lib/c/dup.ml');\n\
             DELETE FROM modules WHERE path='lib/c/dup.ml';") ;

      (* ---- the sweep ---- *)
      let out = bc_out db ["duplicates"; "--repo"; repo] in
      Batch.contains b ~msg:"the sweep must report exactly 1 proven duplicate" ~haystack:out
        "1 proven duplicate" ;
      Batch.contains b ~msg:"the sweep must name dup as the proven duplicate" ~haystack:out
        "DUPLICATE dup" ;
      Batch.not_contains b ~msg:"the sweep must not mention solo (defined once, not a candidate)"
        ~haystack:out "solo" ;

      (* The JSON shape, parsed rather than grepped: a machine consumer reads
         these fields, so a renamed key is a breaking change even when the
         human-readable line still says the right thing. *)
      let json = bc_out db ["duplicates"; "--repo"; repo; "--format"; "json"] in
      match Batch.expect b (Json.strict_object ~what:"duplicates --format json" json) with
      | None -> ()
      | Some parsed ->
          Option.iter
            (fun n -> Batch.eq_int b ~msg:"json: candidates_with_multiple_definitions" n 1)
            (Batch.expect b
               (Json.int ~what:"duplicates" "candidates_with_multiple_definitions" parsed)) ;
          Option.iter
            (fun items ->
              Batch.eq_string b ~msg:"json: proven_duplicates names"
                (String.concat "," (Json.field_of_objects ~field:"name" items))
                "dup")
            (Batch.expect b (Json.list ~what:"duplicates" "proven_duplicates" parsed)) ;
          Option.iter
            (fun items ->
              Batch.eq_int b
                ~msg:"json: unverifiable_empty_body should be empty here"
                (List.length items) 0)
            (Batch.expect b (Json.list ~what:"duplicates" "unverifiable_empty_body" parsed))) ;
  Lwt.return_unit

(* Two occurrences whose sources cannot be read hash the same (empty) body. That
   is an absence of evidence, and reporting it as DUPLICATE would turn every
   pair of deleted files into a proven duplicate. *)
let register_unverifiable () =
  Test.register ~__FILE__ ~title:"duplicates: unreadable bodies are unverifiable, not proven"
    ~tags:["duplicates"; "body_compare"]
  @@ fun () ->
  with_project ~name:"dupghost" ~files:repo_files @@ fun repo ->
  let db =
    seed_db "duplicates_ghost"
      {|
INSERT INTO modules(path, lines) VALUES ('lib/gone/x.ml', 5), ('lib/gone/y.ml', 5);
INSERT INTO functions(module_id, name, line_start, line_end) VALUES
  ((SELECT id FROM modules WHERE path='lib/gone/x.ml'), 'ghost', 1, 5),
  ((SELECT id FROM modules WHERE path='lib/gone/y.ml'), 'ghost', 1, 5);
|}
  in
  Batch.run (fun b ->
      let single = bc_out db ["ghost"; "--repo"; repo] in
      Batch.contains b ~msg:"two occurrences with no readable source must report UNVERIFIABLE"
        ~haystack:single "UNVERIFIABLE" ;
      Batch.not_contains b ~msg:"an unreadable-body match must never be a proven DUPLICATE"
        ~haystack:single "DUPLICATE" ;
      let sweep = bc_out db ["duplicates"; "--repo"; repo] in
      Batch.contains b ~msg:"the sweep must exclude an unverifiable match from the proven count"
        ~haystack:sweep "0 proven duplicate" ;
      Batch.contains b ~msg:"the sweep must still surface ghost, under UNVERIFIABLE"
        ~haystack:sweep "ghost") ;
  Lwt.return_unit

let register_refusals () =
  Test.register ~__FILE__ ~title:"duplicates: refuses an index with no source mapping"
    ~tags:["duplicates"; "body_compare"; "contract"]
  @@ fun () ->
  let flat = Fixture.minimal_flat ~name:"duplicates_flat" in
  (* A database that is not an arch-index at all is broken input, not a
     soundness verdict: exit 2, never 3. *)
  let not_a_db = temp_db "duplicates_notadb" in
  Db.with_db_rw not_a_db (fun conn -> Db.exec conn "CREATE TABLE unrelated(x INTEGER);") ;
  Batch.run (fun b ->
      let exits ~msg ~expected db args = Batch.exit_code b ~msg ~expected (bc db args) in
      exits ~msg:"a flat index has no modules table, so body compare must REFUSE" ~expected:3 flat
        ["f"] ;
      exits ~msg:"the duplicates sweep must REFUSE on a flat index too" ~expected:3 flat
        ["duplicates"] ;
      exits ~msg:"a database with no functions table is broken input, not a refusal" ~expected:2
        not_a_db ["anything"]) ;
  Lwt.return_unit
