(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** LSP server configuration for a language. *)
type lsp_server_config = {
  command : string;
  args : string list;
  init_options : Yojson.Safe.t option;
}

(** Language registry: maps language identifiers to LSP server configs.
    Pure immutable value — safe to use from concurrent Eio fibers. *)
type t

(** [default ()] creates the default registry with built-in backends for
    OCaml, TypeScript, Rust, Go, and Python. *)
val default : unit -> t

(** [lookup t ~language ~project_dir] returns the LSP server config for
    [language], or [Error msg] if not registered or binary not found on PATH.
    [project_dir] is used to locate project-local tooling (e.g.
    [node_modules/typescript] for TypeScript projects). *)
val lookup :
  t ->
  language:string ->
  project_dir:string ->
  (lsp_server_config, string) result

(** [detect_language ~project_dir] auto-detects the language from manifest
    files:
    - tsconfig.json → "typescript"
    - dune-project / *.opam → "ocaml"
    - Cargo.toml → "rust"
    - go.mod → "go"
    - setup.py / pyproject.toml → "python"
    Returns [None] if no manifest found. *)
val detect_language : project_dir:string -> string option

(** [detect_all_languages ~project_dir] scans the repository tree rooted at
    [project_dir] (up to 4 levels deep, skipping VCS, build, dependency, and
    agent-owned directories) and returns every language whose manifest is found.
    Unlike [detect_language], which stops at the first match in [project_dir]
    alone, this function collects all languages across the full tree:
    - tsconfig.json → "typescript"
    - dune-project / *.opam → "ocaml"
    - Cargo.toml → "rust"
    - go.mod → "go"
    - setup.py / pyproject.toml → "python"
    - CMakeLists.txt / *.c / *.h → "c"
    - pom.xml / build.gradle / build.gradle.kts → "java"
    Returns [[]] if no manifest found.  Each language appears at most once. *)
val detect_all_languages : project_dir:string -> string list

(** [lsp_install_instruction ~language] returns the recommended shell command
    to install the LSP binary for [language], or [None] if no instruction is
    known for that language.

    Known instructions:
    - "ocaml"      → ["opam install ocaml-lsp-server"]
    - "typescript" → ["npm install -g typescript-language-server typescript"]
    - "rust"       → ["rustup component add rust-analyzer"]
    - "go"         → ["go install golang.org/x/tools/gopls\@latest"]
    - "python"     → ["pip install python-lsp-server"]
    - "c"          → install clangd via package manager
    - "java"       → install eclipse.jdt.ls *)
val lsp_install_instruction : language:string -> string option
