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
type t = {entries : (string * lsp_server_config) list}

(** [command_on_path cmd] checks whether [cmd] is available on PATH by
    walking PATH directories.  No subprocess is spawned. *)
let command_on_path cmd =
  match Sys.getenv_opt "PATH" with
  | None -> false
  | Some path_var ->
      let dirs = String.split_on_char ':' path_var in
      List.exists
        (fun dir ->
          let full = Filename.concat dir cmd in
          Sys.file_exists full)
        dirs

(** [default ()] creates the default registry with built-in backends. *)
let default () =
  {
    entries =
      [
        ("ocaml", {command = "ocamllsp"; args = []; init_options = None});
        ( "typescript",
          {
            command = "typescript-language-server";
            args = ["--stdio"];
            init_options = None;
          } );
        ("rust", {command = "rust-analyzer"; args = []; init_options = None});
        ("go", {command = "gopls"; args = []; init_options = None});
        ("python", {command = "pylsp"; args = []; init_options = None});
      ];
  }

(** [tsserver_init_options ~project_dir] returns
    [Some \{"tsserver":\{"path":"..."\}\}] when a project-local TypeScript
    installation exists under
    [project_dir/node_modules/typescript/lib/tsserver.js], otherwise [None].
    Passed as [initializationOptions] in the LSP initialize request.  This is
    the correct mechanism for monorepos that install TypeScript locally rather
    than globally — the CLI [--tsserver-path] flag is not supported by all
    server versions. *)
let tsserver_init_options ~project_dir =
  let local =
    Filename.concat
      project_dir
      (Filename.concat
         "node_modules"
         (Filename.concat "typescript" (Filename.concat "lib" "tsserver.js")))
  in
  if Sys.file_exists local then
    Some (`Assoc [("tsserver", `Assoc [("path", `String local)])])
  else None

(** [lookup t ~language ~project_dir] returns the LSP server config for
    [language].  Returns [Error msg] if not registered or binary not found on
    PATH.  [project_dir] is used to locate project-local tooling (e.g.
    [node_modules/typescript] for TypeScript projects). *)
let lookup t ~language ~project_dir =
  match List.assoc_opt language t.entries with
  | None ->
      Error
        (Printf.sprintf
           "language_registry: no LSP server registered for language %S"
           language)
  | Some cfg ->
      (* For TypeScript, inject local tsserver path via initializationOptions. *)
      let ts_init_opts =
        if language = "typescript" then tsserver_init_options ~project_dir
        else None
      in
      (* Special case: for TypeScript, fallback to npx if direct binary absent *)
      if language = "typescript" && not (command_on_path cfg.command) then begin
        if command_on_path "npx" then
          Ok
            {
              command = "npx";
              args = ["typescript-language-server"; "--stdio"];
              init_options = ts_init_opts;
            }
        else
          Error
            (Printf.sprintf
               "language_registry: %s not found on PATH and npx not available"
               cfg.command)
      end
      else if command_on_path cfg.command then
        Ok {cfg with init_options = ts_init_opts}
      else
        Error
          (Printf.sprintf
             "language_registry: LSP binary %S not found on PATH"
             cfg.command)

(** [detect_language ~project_dir] auto-detects the language from manifest
    files. Returns [None] if no manifest found. *)
let detect_language ~project_dir =
  let exists f = Sys.file_exists (Filename.concat project_dir f) in
  let glob_exists ext =
    try
      let files = Sys.readdir project_dir in
      Array.exists (fun f -> Filename.extension f = ext) files
    with _ -> false
  in
  if exists "tsconfig.json" then Some "typescript"
  else if exists "dune-project" || glob_exists ".opam" then Some "ocaml"
  else if exists "Cargo.toml" then Some "rust"
  else if exists "go.mod" then Some "go"
  else if exists "setup.py" || exists "pyproject.toml" then Some "python"
  else None

(* Directories skipped during recursive manifest scanning. *)
let skip_dir = function
  | ".git" | "_build" | ".epure" | "node_modules" | ".hg" | ".svn" | ".claude"
  | ".codex" | ".gemini" | ".opencode" | ".aider" | ".cursor" | ".windsurf"
  | ".crucible" ->
      true
  | _ -> false

(** [detect_all_languages ~project_dir] scans the repository tree rooted at
    [project_dir] (up to 4 levels deep, skipping VCS, build, dependency, and
    agent-owned directories) and returns every language whose manifest is found.
    De-duplicates: each language appears at most once regardless of how many
    manifests exist.  Checks every manifest independently so multi-language
    repositories are fully covered. *)
let detect_all_languages ~project_dir =
  let detected = Hashtbl.create 8 in
  let add lang = Hashtbl.replace detected lang () in
  let check_dir dir =
    let exists f = Sys.file_exists (Filename.concat dir f) in
    let glob_exists ext =
      try
        let files = Sys.readdir dir in
        Array.exists (fun f -> Filename.extension f = ext) files
      with _ -> false
    in
    if exists "tsconfig.json" then add "typescript" ;
    if exists "dune-project" || glob_exists ".opam" then add "ocaml" ;
    if exists "Cargo.toml" then add "rust" ;
    if exists "go.mod" then add "go" ;
    if exists "setup.py" || exists "pyproject.toml" then add "python" ;
    if exists "CMakeLists.txt" || glob_exists ".c" || glob_exists ".h" then
      add "c" ;
    if exists "pom.xml" || exists "build.gradle" || exists "build.gradle.kts"
    then add "java"
  in
  let rec walk depth dir =
    check_dir dir ;
    if depth < 4 then
      match Sys.readdir dir with
      | entries ->
          Array.iter
            (fun entry ->
              if not (skip_dir entry) then
                let child = Filename.concat dir entry in
                match Sys.is_directory child with
                | true -> walk (depth + 1) child
                | false -> ()
                | exception _ -> ())
            entries
      | exception _ -> ()
  in
  walk 0 project_dir ;
  (* Return in a stable order: priority order of common languages *)
  List.filter
    (Hashtbl.mem detected)
    ["ocaml"; "typescript"; "rust"; "go"; "python"; "c"; "java"]

(** [lsp_install_instruction ~language] returns the recommended install command
    for the LSP binary used by [language], or [None] if unknown. *)
let lsp_install_instruction ~language =
  match language with
  | "ocaml" -> Some "opam install ocaml-lsp-server"
  | "typescript" -> Some "npm install -g typescript-language-server typescript"
  | "rust" -> Some "rustup component add rust-analyzer"
  | "go" -> Some "go install golang.org/x/tools/gopls@latest"
  | "python" -> Some "pip install python-lsp-server"
  | "c" ->
      Some "install clangd via your package manager (apt: clangd, brew: llvm)"
  | "java" ->
      Some
        "install eclipse.jdt.ls or use 'brew install jdtls' / see \
         https://github.com/eclipse-jdtls/eclipse.jdt.ls"
  | _ -> None
