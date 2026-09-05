(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Thin CLI wrapper for [Arch_index.Coverage_matrix] (roadmap 1.3).

    All detection logic is in [lib/arch_index/coverage_matrix.ml]. This file
    is argument parsing and the exit-code policy. The [analysis_coverage]
    table's DDL is not duplicated here: it re-executes
    [Arch_index.schema_sql] (the full architecture-schema.sql text, already
    embedded at compile time via ppx_blob — [lib/arch_index/arch_index_db.ml])
    against the output database. Every statement in that file is
    [CREATE ... IF NOT EXISTS], so running the whole schema is a safe no-op
    against an existing populated main-schema database and a complete
    bootstrap against an empty one — one source of truth for the DDL either
    way, not a second hand-copied literal that could silently drift from it. *)

open Cmdliner

let run project db_path lcov allow_partial verbose =
  let repo_root =
    match Arch_index.Coverage_matrix.find_repo_root ~from_dir:(Filename.dirname Sys.executable_name) with
    | Some root -> root
    (* An INSTALLED copy of this binary reaches here unconditionally, and
       that is deliberate. [find_repo_root] searches upward from
       [Sys.executable_name] only, and stops at the enclosing [dune-project]:
       an install prefix ([~/.opam/<switch>/bin], [/usr/local/bin], ...) holds
       no [architecture-schema.sql]+[_build] pair anywhere above it, so the
       search correctly reports "none". The [Sys.getcwd ()] fallback removed
       in the same change used to make `cd <a-checkout> && arch_coverage_matrix`
       work by accident — and that is exactly the escape the boundary exists
       to close, since a CWD-rooted search is unbounded and could just as
       easily have landed in a SIBLING checkout's root and probed the wrong
       installation's Go/Rust drivers. Measured, not reasoned: `dune install
       --prefix <tmp>` then running <tmp>/bin/arch_coverage_matrix with the
       CWD inside a built checkout exits 2 here, where the pre-change binary
       at the same path exited 0. Consequence: Go/Rust callgraph detection is
       a repo-checkout-only capability today. Loudly, on stderr, with a
       distinct exit code — never a silent [Not_analysed]. *)
    | None ->
        Printf.eprintf
          "arch-coverage-matrix: could not locate this arch-index checkout's own root \
           (searched upward for architecture-schema.sql) — Go/Rust callgraph detection needs it\n%!" ;
        exit 2
  in
  let rows = Arch_index.Coverage_matrix.compute ~project_dir:project ~repo_root ?lcov ~db_path () in
  let db = Sqlite3.db_open db_path in
  (match Sqlite3.exec db Arch_index.schema_sql with
  | Sqlite3.Rc.OK -> ()
  | rc ->
      Printf.eprintf "arch-coverage-matrix: failed to create analysis_coverage table: %s\n%!"
        (Sqlite3.Rc.to_string rc) ;
      exit 2) ;
  Arch_index.Coverage_matrix.write_coverage db rows ;
  ignore (Sqlite3.db_close db) ;
  List.iter
    (fun (row : Arch_index.Coverage_matrix.row) ->
      let language = Option.value row.language ~default:"*" in
      if verbose || row.status <> Covered then
        Printf.printf
          "%s %s: %s%s\n"
          language
          row.analysis
          (Arch_index.Coverage_matrix.status_to_string row.status)
          (match row.detail with Some d -> Printf.sprintf " (%s)" d | None -> ""))
    rows ;
  let gap = Arch_index.Coverage_matrix.has_gap rows in
  if gap && not allow_partial then (
    Printf.eprintf
      "arch-coverage-matrix: coverage gaps exist (not_analysed/failed rows) — pass --allow-partial to accept them\n%!" ;
    exit 1)

let project_arg =
  let doc = "Path to the project root to compute coverage for." in
  Arg.(required & opt (some dir) None & info ["project"; "p"] ~docv:"DIR" ~doc)

let output_arg =
  let doc = "Path to the SQLite database to write analysis_coverage into (created if absent)." in
  Arg.(required & opt (some string) None & info ["db-path"; "o"] ~docv:"FILE" ~doc)

let lcov_arg =
  let doc = "Path to an LCOV tracefile, if one is available, for the test-line coverage row." in
  Arg.(value & opt (some string) None & info ["lcov"] ~docv:"FILE" ~doc)

let allow_partial_arg =
  let doc = "Accept not_analysed/failed rows with exit 0 instead of exit 1." in
  Arg.(value & flag & info ["allow-partial"] ~doc)

let verbose_arg =
  let doc = "Print every row, not just non-covered ones." in
  Arg.(value & flag & info ["verbose"; "v"] ~doc)

let cmd =
  let doc = "Compute the (language, analysis) coverage matrix for a project (roadmap 1.3)." in
  let info = Cmd.info "arch_coverage_matrix" ~doc in
  Cmd.v
    info
    Term.(const run $ project_arg $ output_arg $ lcov_arg $ allow_partial_arg $ verbose_arg)

let () = exit (Cmd.eval cmd)
