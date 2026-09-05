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
   miss).

   This lookup ROUTES A WRITE: the stub-planting tests below create files
   under whatever directory it returns, so "could this ever name a SIBLING
   checkout's root?" is the question issue #77 raised about this exact call.
   It cannot, and the reasoning is short enough to keep next to the code
   rather than only in the commit that established it (issue #77 / PR #83):
   a BUILT worktree satisfies [find_repo_root_from]'s
   [architecture-schema.sql]+[_build] markers in its own root, which the walk
   reaches before any ancestor; an UNBUILT one never gets this far, because
   [arch_coverage_matrix ()] — the binary path this search starts from —
   fails loudly first via [arch_tezt.ml]'s own (PR #78) bounded locate. The
   [dune-project] boundary [find_repo_root] gained in PR #83 is a second,
   independent stop for the same escape. *)
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

(* Issue #77 (production half): [find_sibling_tool]/[find_repo_root] must
   stop climbing at the enclosing [dune-project] rather than escape into an
   outer checkout and answer a presence question with a stale sibling's
   truth. The fixture below plants a real, executable "ancestor tool" TWO
   levels above a nested directory that itself carries its own
   [dune-project] — mirroring an agent worktree ([.claude/worktrees/agent-*])
   living inside a parent checkout, each with its own [dune-project] — and
   the search must come back empty from inside the nested tree.

   The precondition that the ancestor tool genuinely sits where an unbounded
   walk WOULD find it is checked with plain [Sys.file_exists], never with
   [find_sibling_tool] itself: a check built from the function under test
   would report the fixture as correct even if that function were the
   thing miscounting directories — see the sibling assertion further down,
   which instead runs the very same search from a directory with NO
   intervening [dune-project] and confirms it non-vacuously finds the
   ancestor tool, proving the fixture is a real escape route and not merely
   an unreachable one. *)
let register_find_sibling_tool_stops_at_dune_project () =
  Test.register ~__FILE__
    ~title:"coverage-matrix: find_sibling_tool never climbs past the enclosing dune-project"
    ~tags:["coverage_matrix"; "worktree_boundary"]
  @@ fun () ->
  let outer = Temp.dir "covmatrix_boundary_outer" in
  let rel = "bin/arch_effects_ocaml/arch_effects_ocaml.exe" in
  let rec mkdir_p d =
    if not (Sys.file_exists d) then (
      mkdir_p (Filename.dirname d) ;
      try Unix.mkdir d 0o755 with Unix.Unix_error _ -> ())
  in
  (* The ancestor tool: what a parent checkout's own build would have
     produced, sitting directly under [outer]. *)
  let ancestor_tool = Filename.concat outer rel in
  mkdir_p (Filename.dirname ancestor_tool) ;
  write_executable ancestor_tool "#!/bin/sh\nexit 0\n" ;
  (* The nested worktree: its own dune-project, its own (empty) tool
     directory tree, no copy of the tool itself. *)
  let nested = Filename.concat outer "nested_worktree" in
  mkdir_p nested ;
  write_file (Filename.concat nested "dune-project") "(lang dune 3.0)\n" ;
  let from_dir = Filename.concat nested "bin/some_other_tool" in
  mkdir_p from_dir ;
  (* Precondition, established WITHOUT the function under test. *)
  Check.(
    (Sys.file_exists ancestor_tool = true) bool
      ~error_msg:"fixture bug: the ancestor tool this test plants must exist, got %L") ;
  Check.(
    (Sys.file_exists (Filename.concat nested "dune-project") = true) bool
      ~error_msg:"fixture bug: the nested worktree's own dune-project must exist, got %L") ;
  (* Non-vacuous escape route: searching from a directory under [outer]
     with NO dune-project in between DOES find the ancestor tool — so the
     nested-worktree search below is bounded by the dune-project, not by
     the tool being unreachable in the first place. *)
  let unbounded_sibling = Filename.concat outer "no_boundary_here/bin/some_other_tool" in
  mkdir_p unbounded_sibling ;
  Check.(
    (Arch_index.Coverage_matrix.find_sibling_tool ~from_dir:unbounded_sibling rel = Some ancestor_tool)
      (option string)
      ~error_msg:
        "fixture bug: an unbounded search (no dune-project in between) must find the ancestor \
         tool, got %L -- the boundary test below would be vacuous otherwise") ;
  (* The actual assertion: bounded by [nested]'s own dune-project, the
     search must never see [outer]'s tool. *)
  Check.(
    (Arch_index.Coverage_matrix.find_sibling_tool ~from_dir rel = None)
      (option string)
      ~error_msg:
        "find_sibling_tool must stop at the nested worktree's own dune-project and report None, \
         never escape to an enclosing checkout's tool, got %L") ;
  Lwt.return_unit

(* The test above plants the ancestor tool at [outer/rel] — [find_upwards]'s
   FIRST candidate. The escape actually observed in issue #77 came through the
   SECOND one, [<ancestor>/_build/default/rel]: a worktree whose own
   [_build/default] lacked the compiled tool climbed into the parent
   checkout's [_build/default] and found it there. The sentinel is checked
   before recursion, so both arms are pinned by the same line of code — but
   "pinned by the same line" is an argument about the implementation, and a
   fixture that only ever exercises the first candidate cannot notice if the
   two candidates are ever computed differently (a per-candidate search, a
   reordering, a [_build]-only fallback added later). Same shape as above,
   one path changed. *)
let register_find_sibling_tool_stops_at_dune_project_build_candidate () =
  Test.register ~__FILE__
    ~title:
      "coverage-matrix: find_sibling_tool never climbs past the enclosing dune-project \
       (_build/default candidate)"
    ~tags:["coverage_matrix"; "worktree_boundary"]
  @@ fun () ->
  let outer = Temp.dir "covmatrix_boundary_build_outer" in
  let rel = "bin/arch_effects_ocaml/arch_effects_ocaml.exe" in
  let rec mkdir_p d =
    if not (Sys.file_exists d) then (
      mkdir_p (Filename.dirname d) ;
      try Unix.mkdir d 0o755 with Unix.Unix_error _ -> ())
  in
  (* The ancestor tool, reachable ONLY through the second candidate: it sits
     in [outer]'s build output, and there is deliberately no [outer/rel]. *)
  let ancestor_tool = Filename.concat outer (Filename.concat "_build/default" rel) in
  mkdir_p (Filename.dirname ancestor_tool) ;
  write_executable ancestor_tool "#!/bin/sh\nexit 0\n" ;
  let nested = Filename.concat outer "nested_worktree" in
  mkdir_p nested ;
  write_file (Filename.concat nested "dune-project") "(lang dune 3.0)\n" ;
  let from_dir = Filename.concat nested "bin/some_other_tool" in
  mkdir_p from_dir ;
  (* Preconditions, established WITHOUT the function under test: the tool is
     reachable through the [_build/default] candidate and through that one
     only. *)
  Check.(
    (Sys.file_exists ancestor_tool = true) bool
      ~error_msg:"fixture bug: the ancestor tool under _build/default must exist, got %L") ;
  Check.(
    (Sys.file_exists (Filename.concat outer rel) = false) bool
      ~error_msg:
        "fixture bug: no plain [outer/rel] may exist, or this test would exercise the FIRST \
         candidate again, got %L") ;
  Check.(
    (Sys.file_exists (Filename.concat nested "dune-project") = true) bool
      ~error_msg:"fixture bug: the nested worktree's own dune-project must exist, got %L") ;
  (* Non-vacuous escape route through the second candidate specifically. *)
  let unbounded_sibling = Filename.concat outer "no_boundary_here/bin/some_other_tool" in
  mkdir_p unbounded_sibling ;
  Check.(
    (Arch_index.Coverage_matrix.find_sibling_tool ~from_dir:unbounded_sibling rel
    = Some ancestor_tool)
      (option string)
      ~error_msg:
        "fixture bug: an unbounded search (no dune-project in between) must find the ancestor \
         tool through its _build/default candidate, got %L -- the boundary assertion below would \
         be vacuous otherwise") ;
  (* The actual assertion. *)
  Check.(
    (Arch_index.Coverage_matrix.find_sibling_tool ~from_dir rel = None)
      (option string)
      ~error_msg:
        "find_sibling_tool must stop at the nested worktree's own dune-project and report None, \
         never escape to an enclosing checkout's _build/default tool, got %L") ;
  Lwt.return_unit

let register_find_repo_root_stops_at_dune_project () =
  Test.register ~__FILE__
    ~title:"coverage-matrix: find_repo_root never climbs past the enclosing dune-project"
    ~tags:["coverage_matrix"; "worktree_boundary"]
  @@ fun () ->
  let outer = Temp.dir "covmatrix_boundary_outer_root" in
  let rec mkdir_p d =
    if not (Sys.file_exists d) then (
      mkdir_p (Filename.dirname d) ;
      try Unix.mkdir d 0o755 with Unix.Unix_error _ -> ())
  in
  (* The outer checkout: a real repo root, built ([architecture-schema.sql]
     + [_build] together). *)
  write_file (Filename.concat outer "architecture-schema.sql") "-- stub schema\n" ;
  mkdir_p (Filename.concat outer "_build") ;
  (* The nested worktree: its own dune-project, no schema/_build pair of its
     own (never built). *)
  let nested = Filename.concat outer "nested_worktree" in
  mkdir_p nested ;
  write_file (Filename.concat nested "dune-project") "(lang dune 3.0)\n" ;
  let from_dir = Filename.concat nested "_build/default/bin/some_tool" in
  mkdir_p from_dir ;
  (* Precondition, established WITHOUT the function under test. *)
  Check.(
    (Sys.file_exists (Filename.concat outer "architecture-schema.sql") = true) bool
      ~error_msg:"fixture bug: the outer checkout's schema marker must exist, got %L") ;
  Check.(
    (Sys.is_directory (Filename.concat outer "_build") = true) bool
      ~error_msg:"fixture bug: the outer checkout's _build directory must exist, got %L") ;
  (* Non-vacuous escape route: searching from a directory under [outer] with
     no dune-project in between DOES find [outer] as the repo root. *)
  let unbounded_sibling = Filename.concat outer "no_boundary_here/deep/dir" in
  mkdir_p unbounded_sibling ;
  Check.(
    (Arch_index.Coverage_matrix.find_repo_root ~from_dir:unbounded_sibling = Some outer)
      (option string)
      ~error_msg:
        "fixture bug: an unbounded search (no dune-project in between) must find the outer \
         checkout's root, got %L -- the boundary test below would be vacuous otherwise") ;
  (* The actual assertion: bounded by [nested]'s own dune-project, the
     search must never see [outer]'s root. *)
  Check.(
    (Arch_index.Coverage_matrix.find_repo_root ~from_dir = None)
      (option string)
      ~error_msg:
        "find_repo_root must stop at the nested worktree's own dune-project and report None, \
         never escape to an enclosing checkout's root, got %L") ;
  Lwt.return_unit

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
      (* COVERED, not partial: a corpus using neither result nor option
         legitimately produces a shorter contract, and calling that a gap made
         the ratchet fire on a correctly analysed project. Which channels ran
         stays visible in the detail. *)
      Check.(
        (Db.string_opt conn
           "SELECT status FROM analysis_coverage WHERE language = 'ocaml' AND analysis = 'error_channels'"
         = Some "covered")
          (option string)
          ~error_msg:"a shorter contract is covered, not a gap, got %L") ;
      Check.(
        (Db.string_opt conn
           "SELECT detail FROM analysis_coverage WHERE language = 'ocaml' AND analysis = 'error_channels'"
         = Some "exception (no result/option carrier in this corpus)")
          (option string)
          ~error_msg:"the detail must still say which channels ran and why the others did not, got %L") ;
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
  register_find_sibling_tool_stops_at_dune_project () ;
  register_find_sibling_tool_stops_at_dune_project_build_candidate () ;
  register_find_repo_root_stops_at_dune_project () ;
  register_cross_language_rows () ;
  register_snapshot_semantics () ;
  register_existing_main_schema () ;
  register_error_channels_from_contract ()
