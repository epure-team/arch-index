(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** The three pcc-* binaries consumed by the proof-carrying-change workflow.

    Driven as real subprocesses against real dune projects in real git
    repositories, with no stubs, because what is under test is precisely how
    they behave when the tools underneath them report something other than
    success:

    - [pcc-index] prints one strict JSON object, and on an infra failure prints
      NOTHING at all — a partial object on stdout would be parsed by the
      workflow as a result;
    - [pcc-dossier] exits 0 while the arch-rules verdict underneath it is FAIL,
      because its job is to REPORT the verdict, not to be it — and the file it
      writes must actually contain that verdict rather than swallow it;
    - [pcc-preflight] distinguishes a passing suite from a failing one, checked
      with two fixtures that differ in exactly the assertion that fails, so a
      binary that always answers "ok" cannot pass both halves. *)

open Arch_tezt

(* Both the repository root and scripts/pcc go on PATH: the pcc-* tools resolve
   their siblings through `command -v` while running with CWD set to the target
   repo, never to this checkout. *)
let pcc_env () =
  [("PATH", Printf.sprintf "%s:%s:%s" (repo_root ()) (pcc_dir ())
              (Option.value ~default:"" (Sys.getenv_opt "PATH")))]

(* Split streams throughout: every assertion below is about what lands on
   STDOUT, and these tools legitimately write diagnostics to stderr — arch-impact
   says "the diff is empty" underneath pcc-index, which merged into stdout would
   make the JSON unparseable and the test wrong about the tool. *)
let pcc ~cwd name args =
  run_command_split ~env:(pcc_env ()) ~cwd (Filename.concat (pcc_dir ()) name) args

(* A four-function module carrying ONE pre-existing, deliberately untouched
   decision-lint finding (the duplicate conjunct in `quirky`). Without a finding
   already in the index, arch-impact --fail-on-new-findings refuses rather than
   passing, and the dossier assertions would be measuring the refusal. *)
let fixture_files =
  [
    ("dune-project", "(lang dune 3.0)\n");
    ("src/dune", "(library\n (name fixturelib)\n (modules fixturelib))\n");
    ( "src/fixturelib.ml",
      {|let add x y = x + y
let mul x y = x * y
let entry n = add (mul n 2) 1
let quirky a b = if a && b && a then 1 else 2
|} );
  ]

let test_files ~expected =
  [
    ("test/dune", "(test\n (name test_fixturelib)\n (libraries fixturelib alcotest))\n");
    ( "test/test_fixturelib.ml",
      Printf.sprintf
        {|let () =
  Alcotest.run "fixturelib"
    [ ("add", [ Alcotest.test_case "2+3=%d" `Quick (fun () ->
          Alcotest.(check int) "add" %d (Fixturelib.add 2 3)) ]) ]
|}
        expected expected );
  ]

let register_index () =
  Test.register ~__FILE__ ~title:"pcc: pcc-index answers in one strict JSON object, or not at all"
    ~tags:["pcc"]
  @@ fun () ->
  Fixture.git_project ~name:"pcc_index" ~files:fixture_files @@ fun root ->
  Batch.run (fun b ->
      let code, out, err = pcc ~cwd:root "pcc-index" ["--db"; ".pcc/index.db"] in
      Batch.exit_code b ~msg:"pcc-index must succeed on a clean, buildable fixture" ~expected:0
        (code, err) ;
      (match Json.strict_object ~what:"pcc-index" out with
      | Error e -> Batch.note b "%s" e
      | Ok j ->
          (match Json.bool ~what:"pcc-index" "computed" j with
          | Ok v -> Batch.check b ~msg:"pcc-index must report computed:true" v
          | Error e -> Batch.note b "%s" e) ;
          (match Json.int ~what:"pcc-index" "functions" j with
          | Ok n -> Batch.ge_int b ~msg:"pcc-index must report an int function count" n 1
          | Error e -> Batch.note b "%s" e) ;
          (* The OCaml CMT producer is sound by construction, so this fixture
             must reach a marked index — if it did not, every downstream verdict
             in this workflow would be a candidate rather than a proof. *)
          match Json.bool ~what:"pcc-index" "contract_ok" j with
          | Ok v -> Batch.check b ~msg:"the OCaml CMT path must reach contract_ok:true" v
          | Error e -> Batch.note b "%s" e)) ;
  Lwt.return_unit

let register_index_infra_failure () =
  Test.register ~__FILE__ ~title:"pcc: a broken build produces no stdout to misread"
    ~tags:["pcc"]
  @@ fun () ->
  Fixture.git_project ~name:"pcc_broken" ~files:fixture_files @@ fun root ->
  (* Appended AFTER the initial commit, then committed, so the failure is a real
     compile error in tracked source rather than a dirty tree. *)
  let src = Filename.concat root "src/fixturelib.ml" in
  write_file src (read_file src ^ "let x = this is not valid ocaml (((\n") ;
  let code, out = run_command ~cwd:root "sh" ["-c"; "git commit -qam 'break the build'"] in
  if code <> 0 then Test.fail "could not commit the broken fixture:\n%s" out ;
  let code, out, _err = pcc ~cwd:root "pcc-index" ["--db"; ".pcc/index.db"] in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"pcc-index must exit 2 on a broken dune build" code 2 ;
      (* The important half: the workflow parses STDOUT. Anything there — even a
         half-written object — would be read as a result rather than as the infra
         failure it is. Diagnostics belong on stderr, which is why the streams
         are kept apart here. *)
      Batch.eq_string b ~msg:"pcc-index must print nothing on stdout on an infra failure"
        (String.trim out) "") ;
  Lwt.return_unit

let register_dossier () =
  Test.register ~__FILE__ ~title:"pcc: pcc-dossier reports a FAIL verdict without becoming one"
    ~tags:["pcc"]
  @@ fun () ->
  Fixture.git_project ~name:"pcc_dossier"
    ~files:
      [
        ("dune-project", "(lang dune 3.0)\n");
        ("src/dune", "(library\n (name dosfix)\n (modules ui db))\n");
        ("src/db.ml", "let write (x : int) : int = x\n");
        ("src/ui.ml", "let handle (x : int) : int = x + 1\n");
        ( "arch-rules.txt",
          "rule \"ui must not reach db\"\n  forbid reach from file:src/ui.ml to file:src/db.ml\n"
        );
      ]
  @@ fun root ->
  (* A REAL, uncommitted architecture violation: the exact shape arch-rules must
     report as FAIL. *)
  write_file (Filename.concat root "src/ui.ml") "let handle (x : int) : int = Db.write (x + 1)\n" ;
  let code, _out, err = pcc ~cwd:root "pcc-index" ["--db"; ".pcc/index.db"] in
  if code <> 0 then Test.fail "the dossier fixture failed to index (exit %d):\n%s" code err ;
  let dossier = Filename.concat root ".pcc/dossier.md" in
  Batch.run (fun b ->
      Batch.exit_code b
        ~msg:"pcc-dossier must exit 0 even though arch-rules reports a violation underneath"
        ~expected:0
        (let c, _, e =
           pcc ~cwd:root "pcc-dossier"
             ["--db"; ".pcc/index.db"; "--repo"; "."; "--diff"; "HEAD"; "--rules";
              "arch-rules.txt"; "--out"; ".pcc/dossier.md"]
         in
         (c, e)) ;
      if not (Sys.file_exists dossier) then
        Batch.note b "pcc-dossier wrote no file to --out"
      else begin
        let contents = read_file dossier in
        Batch.check b ~msg:"pcc-dossier must write a non-empty file"
          (String.length (String.trim contents) > 0) ;
        Batch.contains b
          ~msg:"the dossier must surface the real arch-rules FAIL verdict, not swallow it"
          ~haystack:contents "FAIL"
      end ;

      (* A missing required argument must fail loudly, before writing anything —
         a dossier silently produced without its rules is a dossier that proves
         less than it appears to. *)
      let code, _out, err =
        pcc ~cwd:root "pcc-dossier"
          ["--db"; ".pcc/index.db"; "--repo"; "."; "--diff"; "HEAD"; "--out"; ".pcc/bad.md"]
      in
      Batch.check b
        ~msg:"pcc-dossier with a missing --rules must not silently succeed" (code <> 0) ;
      Batch.check b
        ~msg:"pcc-dossier with a missing required argument must say so"
        (String.length (String.trim err) > 0)) ;
  Lwt.return_unit

(* Two fixtures differing in exactly the assertion that fails. A binary that
   always answers "ok" — or always "not ok" — cannot satisfy both halves. *)
let register_preflight () =
  Test.register ~__FILE__ ~title:"pcc: pcc-preflight tells a passing suite from a failing one"
    ~tags:["pcc"]
  @@ fun () ->
  Fixture.git_project ~name:"pcc_pass" ~files:(fixture_files @ test_files ~expected:5)
  @@ fun pass_root ->
  Fixture.git_project ~name:"pcc_fail" ~files:(fixture_files @ test_files ~expected:6)
  @@ fun fail_root ->
  Batch.run (fun b ->
      let code, out, err = pcc ~cwd:pass_root "pcc-preflight" [] in
      Batch.exit_code b ~msg:"pcc-preflight must exit 0 on a passing suite" ~expected:0
        (code, err) ;
      (match Json.strict_object ~what:"pcc-preflight (pass)" out with
      | Error e -> Batch.note b "%s" e
      | Ok j ->
          (match Json.bool ~what:"pcc-preflight" "ok" j with
          | Ok v -> Batch.check b ~msg:"a passing suite must report ok:true" v
          | Error e -> Batch.note b "%s" e) ;
          (match Json.int ~what:"pcc-preflight" "tests" j with
          | Ok n -> Batch.ge_int b ~msg:"a passing suite must report at least one test" n 1
          | Error e -> Batch.note b "%s" e)) ;

      let code, out, _err = pcc ~cwd:fail_root "pcc-preflight" [] in
      Batch.check b ~msg:"pcc-preflight must exit nonzero on a failing suite" (code <> 0) ;
      match Json.strict_object ~what:"pcc-preflight (fail)" out with
      | Error e -> Batch.note b "%s" e
      | Ok j -> (
          match Json.bool ~what:"pcc-preflight" "ok" j with
          | Ok v -> Batch.check b ~msg:"a failing suite must report ok:false" (not v)
          | Error e -> Batch.note b "%s" e)) ;
  Lwt.return_unit
