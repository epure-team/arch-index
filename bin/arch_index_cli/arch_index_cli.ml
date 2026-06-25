(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Thin CLI wrapper for the epure_arch_index library.

    All analysis logic is in [src/arch_index/].  This file contains only
    argument parsing and the call to [Arch_index.run_lsp]. *)

open Cmdliner

let run project language output no_enrich verbose =
  Eio_posix.run (fun env ->
      Eio.Switch.run (fun sw ->
          match
            Arch_index.run_lsp
              ~sw
              ~env
              ~project_dir:project
              ~language
              ~output
              ~no_enrich
              ~verbose
              ()
          with
          | Ok () -> ()
          | Error msg ->
              Arch_io.eprintf "arch_index: error: %s\n%!" msg ;
              exit 1))

let project_arg =
  let doc = "Path to the project root to analyse." in
  Arg.(required & opt (some dir) None & info ["project"; "p"] ~docv:"DIR" ~doc)

let language_arg =
  let doc =
    "Language to index: auto (default), ocaml, typescript, rust, go, python."
  in
  Arg.(value & opt string "auto" & info ["language"; "l"] ~docv:"LANG" ~doc)

let output_arg =
  let doc = "Path to write the output SQLite comment_db file." in
  Arg.(
    required & opt (some string) None & info ["output"; "o"] ~docv:"FILE" ~doc)

let no_enrich_arg =
  let doc =
    "Skip language enrichment (CMT for OCaml, ts-morph for TypeScript)."
  in
  Arg.(value & flag & info ["no-enrich"] ~doc)

let verbose_arg =
  let doc = "Log progress to stderr." in
  Arg.(value & flag & info ["verbose"; "v"] ~doc)

let cmd =
  let doc = "Index a project's functions and doc-comment quality via LSP." in
  let info = Cmd.info "arch_index" ~doc in
  Cmd.v
    info
    Term.(
      const run $ project_arg $ language_arg $ output_arg $ no_enrich_arg
      $ verbose_arg)

let () = exit (Cmd.eval cmd)
