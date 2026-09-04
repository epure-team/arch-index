(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Roadmap 1.3: arch-coverage-matrix, the honest-absence guarantee.

    A language/analysis pair with no invocable producer must be recorded as
    [not_analysed] with an install/build instruction, never left as silent
    zero rows — and a real gap must exit non-zero unless [--allow-partial]
    is given, per the roadmap's own worked ratchet. *)

open Arch_tezt

let ocaml_files = [Fixture.dune_project; ("dune", "(library (name covfix) (modules covfix))\n"); ("covfix.ml", "let f () = 1\n")]

let rust_files =
  [
    ("Cargo.toml", "[package]\nname = \"covfix\"\nversion = \"0.1.0\"\nedition = \"2021\"\n");
    ("src/lib.rs", "pub fn f() -> i32 { 1 }\n");
  ]

let run_matrix ?(allow_partial = false) ?lcov project db =
  let args =
    ["--project"; project; "--db-path"; db]
    @ (if allow_partial then ["--allow-partial"] else [])
    @ (match lcov with Some p -> ["--lcov"; p] | None -> [])
  in
  run_command (arch_coverage_matrix ()) args

let register_ocaml_not_built () =
  Test.register ~__FILE__
    ~title:"coverage-matrix: an un-built OCaml project reports callgraph not_analysed, exit 1"
    ~tags:["coverage_matrix"; "ocaml"]
  @@ fun () ->
  with_project ~name:"covmatrix_ocaml_unbuilt" ~files:ocaml_files @@ fun project ->
  let db = temp_db "covmatrix-ocaml-unbuilt" in
  let code, _output = run_matrix project db in
  Check.((code = 1) int ~error_msg:"a callgraph gap with no --allow-partial should exit 1, got %L") ;
  Db.with_db db (fun conn ->
      Check.(
        (Db.string_opt conn
           "SELECT status FROM analysis_coverage WHERE language = 'ocaml' AND analysis = 'callgraph'"
         = Some "not_analysed")
          (option string)
          ~error_msg:"ocaml callgraph should be not_analysed before dune build, got %L") ;
      Check.(
        (Db.string_opt conn
           "SELECT detail FROM analysis_coverage WHERE language = 'ocaml' AND analysis = 'callgraph'"
         <> None)
          (option string)
          ~error_msg:"a not_analysed row must carry a detail (the fix instruction), got %L") ;
      (* cfg/types mirror the callgraph row — not independently invoked. *)
      List.iter
        (fun analysis ->
          Check.(
            (Db.string_opt conn
               (Printf.sprintf
                  "SELECT status FROM analysis_coverage WHERE language = 'ocaml' AND analysis = '%s'"
                  analysis)
             = Some "not_analysed")
              (option string)
              ~error_msg:(Printf.sprintf "ocaml %s should mirror the callgraph row's status, got %%L" analysis)))
        ["cfg"; "types"] ;
      Lwt.return_unit)

let register_ocaml_built () =
  Test.register ~__FILE__
    ~title:"coverage-matrix: a built OCaml project reports callgraph covered"
    ~tags:["coverage_matrix"; "ocaml"]
  @@ fun () ->
  with_fixture ~name:"covmatrix_ocaml_built" ~files:ocaml_files @@ fun fixture ->
  let db = temp_db "covmatrix-ocaml-built" in
  let code, output = run_matrix fixture.root db in
  Check.(
    (code = 0) int
      ~error_msg:
        (Printf.sprintf
           "expected exit 0 — decisions/coverage's structural not_analysed never gaps the exit \
            code (only language-scoped rows do), got %%L:\n%s"
           output)) ;
  Db.with_db db (fun conn ->
      Check.(
        (Db.string_opt conn
           "SELECT status FROM analysis_coverage WHERE language = 'ocaml' AND analysis = 'callgraph'"
         = Some "covered")
          (option string)
          ~error_msg:"ocaml callgraph should be covered once dune-built, got %L") ;
      Check.(
        (Db.string_opt conn
           "SELECT status FROM analysis_coverage WHERE language = 'ocaml' AND analysis = 'effects'"
         = Some "covered")
          (option string)
          ~error_msg:"ocaml effects (a bundled dune executable) should always be covered once built, got %L") ;
      Lwt.return_unit)

let register_allow_partial () =
  Test.register ~__FILE__
    ~title:"coverage-matrix: --allow-partial accepts gaps with exit 0"
    ~tags:["coverage_matrix"]
  @@ fun () ->
  with_project ~name:"covmatrix_allow_partial" ~files:ocaml_files @@ fun project ->
  let db = temp_db "covmatrix-allow-partial" in
  let code, output = run_matrix ~allow_partial:true project db in
  Check.((code = 0) int ~error_msg:(Printf.sprintf "--allow-partial should exit 0, got %%L:\n%s" output)) ;
  Lwt.return_unit

let register_rust_no_driver () =
  Test.register ~__FILE__
    ~title:"coverage-matrix: a Cargo workspace with no callgraph-rust driver built reports not_analysed"
    ~tags:["coverage_matrix"; "rust"]
  @@ fun () ->
  with_project ~name:"covmatrix_rust" ~files:rust_files @@ fun project ->
  let db = temp_db "covmatrix-rust" in
  ignore (run_matrix project db : int * string) ;
  Db.with_db db (fun conn ->
      Check.(
        (Db.string_opt conn
           "SELECT status FROM analysis_coverage WHERE language = 'rust' AND analysis = 'callgraph'"
         = Some "not_analysed")
          (option string)
          ~error_msg:
            "rust callgraph should be not_analysed when the driver isn't built (this repo's own \
             wrapper script is always present in git — checking IT rather than the driver it \
             gates would wrongly report covered), got %L") ;
      Check.(
        (Db.string_opt conn
           "SELECT detail FROM analysis_coverage WHERE language = 'rust' AND analysis = 'callgraph'"
         = Some "arch-callgraph-rust driver not built — run: cd callgraph-rust && cargo build --release")
          (option string)
          ~error_msg:"rust callgraph's detail should name the exact fix command, got %L") ;
      Lwt.return_unit)

(* This repo's own root, resolved by calling [Coverage_matrix.find_repo_root]
   from the EXACT directory the binary under test will itself search from
   ([Filename.dirname] of its own compiled path) — not [schema ()]'s CWD-based
   search, which under `dune test`'s own sandboxed working directory can
   resolve to a DIFFERENT directory than the subprocess's own
   exe-path-based search does (both hit the same [_build/default] mirroring
   trap [find_repo_root] itself guards against, but from different starting
   points, so a stub placed via one and looked up via the other can silently
   miss). *)
let repo_root () =
  match Arch_index.Coverage_matrix.find_repo_root ~from_dir:(Filename.dirname (arch_coverage_matrix ())) with
  | Some r -> r
  | None -> Test.fail "coverage_matrix.ml's own repo_root helper could not locate the repo root"

let write_executable path contents =
  let oc = open_out path in
  output_string oc contents ;
  close_out oc ;
  Unix.chmod path 0o755

(* FIX (review, HIGH): the driver-not-built test above is indistinguishable
   from the CRITICAL repo_root bug this round also fixed — a wrapper always
   reporting [not_analysed] regardless of whether the driver exists would
   pass that test too. Plant a real stub executable at the exact path the
   driver-presence check looks for, in THIS repo's own root (not a throwaway
   fixture — the whole point is that Go/Rust availability is a property of
   the arch-index installation, never the target project), and clean it up
   unconditionally even if an assertion raises. *)
let register_go_driver_built () =
  Test.register ~__FILE__
    ~title:"coverage-matrix: a built arch-callgraph-go driver reports callgraph covered"
    ~tags:["coverage_matrix"; "go"]
  @@ fun () ->
  let stub = Filename.concat (repo_root ()) "bin/arch-callgraph-go" in
  let stub_existed = Sys.file_exists stub in
  Fun.protect
    ~finally:(fun () -> if not stub_existed then try Sys.remove stub with Sys_error _ -> ())
    (fun () ->
      if not stub_existed then (
        (try Unix.mkdir (Filename.concat (repo_root ()) "bin") 0o755 with Unix.Unix_error _ -> ()) ;
        write_executable stub "#!/bin/sh\nexit 0\n") ;
      with_project ~name:"covmatrix_go_stub" ~files:[("go.mod", "module covmatrixgostub\n\ngo 1.21\n")]
      @@ fun project ->
      let db = temp_db "covmatrix-go-stub" in
      ignore (run_matrix project db : int * string) ;
      Db.with_db db (fun conn ->
          Check.(
            (Db.string_opt conn
               "SELECT status FROM analysis_coverage WHERE language = 'go' AND analysis = 'callgraph'"
             = Some "covered")
              (option string)
              ~error_msg:
                "go callgraph should be covered once the driver at repo_root/bin/arch-callgraph-go \
                 exists and is executable, got %L") ;
          Lwt.return_unit))

let register_rust_driver_and_merge_built () =
  Test.register ~__FILE__
    ~title:"coverage-matrix: a built callgraph-rust driver AND merge pass reports callgraph covered"
    ~tags:["coverage_matrix"; "rust"]
  @@ fun () ->
  let driver_dir = Filename.concat (repo_root ()) "callgraph-rust/target/release" in
  let driver = Filename.concat driver_dir "arch-callgraph-rust" in
  let merge_dir = Filename.concat (repo_root ()) "_build/default/bin/arch_callgraph_rust_merge" in
  let merge = Filename.concat merge_dir "arch_callgraph_rust_merge.exe" in
  let driver_existed = Sys.file_exists driver in
  let merge_existed = Sys.file_exists merge in
  Fun.protect
    ~finally:(fun () ->
      if not driver_existed then try Sys.remove driver with Sys_error _ -> () ;
      if not merge_existed then try Sys.remove merge with Sys_error _ -> ())
    (fun () ->
      let rec mkdir_p d =
        if not (Sys.file_exists d) then (
          mkdir_p (Filename.dirname d) ;
          try Unix.mkdir d 0o755 with Unix.Unix_error _ -> ())
      in
      if not driver_existed then (
        mkdir_p driver_dir ;
        write_executable driver "#!/bin/sh\nexit 0\n") ;
      if not merge_existed then (
        mkdir_p merge_dir ;
        write_executable merge "#!/bin/sh\nexit 0\n") ;
      with_project ~name:"covmatrix_rust_stub" ~files:rust_files @@ fun project ->
      let db = temp_db "covmatrix-rust-stub" in
      ignore (run_matrix project db : int * string) ;
      Db.with_db db (fun conn ->
          Check.(
            (Db.string_opt conn
               "SELECT status FROM analysis_coverage WHERE language = 'rust' AND analysis = 'callgraph'"
             = Some "covered")
              (option string)
              ~error_msg:
                "rust callgraph should be covered once both the driver and the merge pass exist, \
                 got %L") ;
          Lwt.return_unit))

let register_cross_language_rows () =
  Test.register ~__FILE__
    ~title:"coverage-matrix: coverage and decisions are always not_analysed without --lcov, language NULL"
    ~tags:["coverage_matrix"]
  @@ fun () ->
  with_project ~name:"covmatrix_cross_lang" ~files:ocaml_files @@ fun project ->
  let db = temp_db "covmatrix-cross-lang" in
  ignore (run_matrix project db : int * string) ;
  Db.with_db db (fun conn ->
      List.iter
        (fun analysis ->
          Check.(
            (Db.int conn
               (Printf.sprintf
                  "SELECT count(*) FROM analysis_coverage WHERE analysis = '%s' AND language IS NULL \
                   AND status = 'not_analysed'"
                  analysis)
             = 1)
              int
              ~error_msg:(Printf.sprintf "%s should have exactly one language-NULL not_analysed row, got %%L" analysis)))
        ["coverage"; "decisions"] ;
      Lwt.return_unit)

let register_snapshot_semantics () =
  Test.register ~__FILE__
    ~title:"coverage-matrix: re-running replaces rather than accumulates rows"
    ~tags:["coverage_matrix"]
  @@ fun () ->
  with_project ~name:"covmatrix_snapshot" ~files:ocaml_files @@ fun project ->
  let db = temp_db "covmatrix-snapshot" in
  ignore (run_matrix project db : int * string) ;
  let count_rows () =
    let count = ref 0 in
    ignore
      (Db.with_db db (fun conn ->
           count := Db.int conn "SELECT count(*) FROM analysis_coverage" ;
           Lwt.return_unit)
        : unit Lwt.t) ;
    !count
  in
  let first_count = count_rows () in
  ignore (run_matrix project db : int * string) ;
  let second_count = count_rows () in
  Check.(
    (second_count = first_count) int
      ~error_msg:
        (Printf.sprintf
           "row count should stay constant across re-runs (snapshot semantics), got %%L (first run: %d)"
           first_count)) ;
  Lwt.return_unit

let register_existing_main_schema () =
  Test.register ~__FILE__
    ~title:"coverage-matrix: writing into an existing, populated main-schema database is safe"
    ~tags:["coverage_matrix"]
  @@ fun () ->
  with_project ~name:"covmatrix_existing_schema" ~files:ocaml_files @@ fun project ->
  let db =
    Fixture.main ~name:"covmatrix-existing-schema"
      ~seed:"INSERT INTO modules(path, lines, has_mli) VALUES ('lib/x.ml', 10, 0);"
      ()
  in
  let code, output = run_matrix project db in
  let normal_exit = code = 0 || code = 1 in
  Check.(
    (normal_exit = true) bool
      ~error_msg:(Printf.sprintf "expected a normal exit (0 or 1), not a crash (code=%d):\n%s" code output)) ;
  Db.with_db db (fun conn ->
      Check.(
        (Db.int conn "SELECT count(*) FROM modules WHERE path = 'lib/x.ml'" = 1)
          int
          ~error_msg:"the pre-existing modules row must survive re-running the (idempotent) schema DDL, got %L") ;
      Check.(
        (Db.string_opt conn
           "SELECT status FROM analysis_coverage WHERE language = 'ocaml' AND analysis = 'callgraph'"
         <> None)
          (option string)
          ~error_msg:"analysis_coverage should be populated even in a pre-existing database, got %L") ;
      Lwt.return_unit)

let register_error_channels_from_contract () =
  Test.register ~__FILE__
    ~title:"coverage-matrix: the error_channels row reads the producer's contract"
    ~tags:["coverage_matrix"; "error_channels"]
  @@ fun () ->
  with_project ~name:"covmatrix_error_channels" ~files:ocaml_files @@ fun project ->
  (* A database that already records what a producer emitted. The matrix must
     report what the contract SAYS, not what the environment could do. *)
  let db =
    Fixture.main ~name:"covmatrix-error-channels"
      ~seed:
        "INSERT INTO comment_db_meta(key, value) VALUES ('error_contract', 'v1:exception');"
      ()
  in
  let code, output = run_matrix ~allow_partial:true project db in
  Check.(
    (code = 0) int
      ~error_msg:(Printf.sprintf "--allow-partial should exit 0, got %%L:\n%s" output)) ;
  Db.with_db db (fun conn ->
      (* PARTIAL, not covered: a database carrying only the exception channel
         is not one carrying all three, and flattening that would overstate
         what was analysed. *)
      Check.(
        (Db.string_opt conn
           "SELECT status FROM analysis_coverage WHERE language = 'ocaml' AND analysis = 'error_channels'"
         = Some "partial")
          (option string)
          ~error_msg:"a contract listing only 'exception' must be partial, got %L") ;
      Check.(
        (Db.string_opt conn
           "SELECT detail FROM analysis_coverage WHERE language = 'ocaml' AND analysis = 'error_channels'"
         = Some "analysed exception; NOT analysed result,option")
          (option string)
          ~error_msg:"the detail must name which channels were and were not analysed, got %L") ;
      (* The row exists for every detected language — silence is the failure
         this table exists to prevent — but a contract written by the OCaml
         producer never speaks for another one. *)
      Check.(
        (Db.int conn "SELECT count(*) FROM analysis_coverage WHERE analysis = 'error_channels'" >= 1)
          int
          ~error_msg:"every detected language needs an error_channels row, got %L") ;
      Lwt.return_unit)

let register () =
  register_ocaml_not_built () ;
  register_ocaml_built () ;
  register_allow_partial () ;
  register_rust_no_driver () ;
  register_go_driver_built () ;
  register_rust_driver_and_merge_built () ;
  register_cross_language_rows () ;
  register_snapshot_semantics () ;
  register_existing_main_schema () ;
  register_error_channels_from_contract ()
