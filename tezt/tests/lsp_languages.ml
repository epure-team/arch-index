(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** The LSP indexing path, per language, against the real servers.

    The CMT path has its own cover, which is exactly the problem this fills: a
    change to the shared indexer, schema or resolver could break Go or Rust
    while every OCaml test stayed green.

    Each language is checked for the same four properties — symbols are indexed,
    visibility is recorded with that language's own rule, an internal helper
    keeps its caller, and dead-code discriminates — so a backend that regresses
    fails on the property rather than on a language-specific spelling.

    What is NOT asserted here is soundness: the runner tags every edge
    MAY_ENUMERATED and stamps no contract, so no verdict from this path is
    sound, and asserting otherwise would enshrine a claim the path cannot make.
    Both halves of that — the tag on every edge, the absent contract — are
    asserted per language instead, so they hold wherever a single server
    happens to be installed. *)

open Arch_tezt

let index_project_lang ~name ~language project =
  let db = temp_db name in
  let log = Temp.file (name ^ ".log") in
  let code, output =
    run_command (arch_index_cli ())
      ["--project"; project; "--language"; language; "--output"; db; "--verbose"]
  in
  write_file log output ;
  ignore code ;
  (db, output)

(* The properties every backend owes, asserted identically for each language so
   a regression shows up as the property that broke. *)
let check_language b ~label ~db ~exported ~internal ~island =
  if not (Sys.file_exists db) then Batch.note b "%s: no database produced" label
  else begin
    Db.with_db db (fun conn ->
        Batch.ge_int b ~msg:(label ^ ": at least three functions must be indexed")
          (Db.int conn "SELECT count(*) FROM functions") 3 ;
        (* The two schemas spell visibility differently; either is fine, neither
           is not. *)
        Batch.ge_int b ~msg:(label ^ ": functions must carry a visibility column")
          (Db.int conn
             "SELECT count(*) FROM pragma_table_info('functions') WHERE name IN \
              ('exposed','exported')")
          1 ;
        List.iter
          (fun fn ->
            Batch.ge_int b
              ~msg:(Printf.sprintf "%s: '%s' must be indexed" label fn)
              (Db.int conn
                 (Printf.sprintf
                    "SELECT count(*) FROM functions WHERE name = '%s' OR name LIKE '%%.%s'" fn fn))
              1)
          [exported; internal; island] ;
        (* The kind contract of this path, asserted per language rather than
           once on the merged multi-language index: that one lived behind
           gopls AND tsserver AND npm AND the network, so on a machine with
           only gopls the production claim below had no cover at all.

           On the whole table, not a sample: the failure is silent. A NULL kind
           (or a dropped column) reads as literal 'MUST' in Arch_db.kind_sql,
           so one untagged row forges a must-reach path. *)
        Batch.eq_int b
          ~msg:
            (label
           ^ ": every LSP call edge must be MAY_ENUMERATED — an untagged edge \
              reads as MUST and forges a must-reach path")
          (Db.int conn
             "SELECT count(*) FROM calls WHERE kind IS NULL OR kind <> 'MAY_ENUMERATED'")
          0 ;
        (* And the index must NOT claim the ⊤-marking contract: callHierarchy
           never reports the call sites it failed to resolve, so the ⊤ frontier
           is unknown, not empty. `unreachable`/`escapes` have to keep
           refusing. *)
        Batch.eq_string_opt b
          ~msg:
            (label
           ^ ": the LSP path must not stamp callgraph_contract — it does not \
              enumerate unresolved targets as MAY_TOP")
          (Db.string_opt conn
             "SELECT value FROM comment_db_meta WHERE key = 'callgraph_contract'")
          None) ;
    (* Roots are given explicitly: dead-code from an exported root must still
       discriminate, which is what makes the island a finding rather than noise. *)
    let code, dc = query_raw db ["dead-code"; exported] in
    if code <> 0 then
      Batch.note b "%s: dead-code exited %d:\n%s" label code dc
    else
      Batch.contains b
        ~msg:(Printf.sprintf "%s: dead-code from '%s' must list '%s'" label exported island)
        ~haystack:dc island
  end

let go_files =
  [
    ("go.mod", "module archfix\n\ngo 1.21\n");
    ( "main.go",
      {|package main

// helper is unexported: internal to the package.
func helper(x int) int { return x + 1 }

// Entry is exported and calls helper.
func Entry(x int) int { return helper(x) * 2 }

// islandFn is exported but nothing in this package calls it.
func islandFn() int { return 99 }

func main() { _ = Entry(1) }
|} );
  ]

let register_go () =
  Test.register ~__FILE__ ~title:"lsp: Go is indexed with Go's own visibility rule"
    ~tags:["lsp"; "go"]
  @@ fun () ->
  if not (runnable "gopls" ["version"] && runnable "go" ["version"]) then
    not_exercised "Go: gopls is not runnable (absent, or a shim without its component)"
  else
    with_project ~name:"lsp_go" ~files:go_files (fun project ->
        let db, _ = index_project_lang ~name:"lsp_go" ~language:"go" project in
        Batch.run (fun b ->
            check_language b ~label:"Go" ~db ~exported:"Entry" ~internal:"helper"
              ~island:"islandFn" ;
            (* Go decides visibility lexically: exported exactly when the
               identifier starts with an upper-case letter. *)
            Db.with_db db (fun conn ->
                List.iter
                  (fun (fn, expected) ->
                    Batch.eq_string_opt b
                      ~msg:(Printf.sprintf "Go: '%s' visibility" fn)
                      (Db.string_opt conn
                         (Printf.sprintf
                            "SELECT COALESCE(exported, -1) FROM functions WHERE name = '%s'" fn))
                      (Some expected))
                  [("Entry", "1"); ("helper", "0"); ("islandFn", "0"); ("main", "0")] ;
                (* main is unexported, so this also guards against tying call
                   extraction back to visibility — a private function's outgoing
                   calls are exactly what reachability needs. *)
                List.iter
                  (fun (caller, callee) ->
                    Batch.ge_int b
                      ~msg:(Printf.sprintf "Go: missing call edge '%s -> %s'" caller callee)
                      (Db.int conn
                         (Printf.sprintf
                            "SELECT count(*) FROM calls WHERE caller_name = '%s' AND callee_name \
                             = '%s'"
                            caller callee))
                      1)
                  [("Entry", "helper"); ("main", "Entry")]))) ;
  Lwt.return_unit

let rust_files =
  [
    ("Cargo.toml", "[package]\nname = \"archfix\"\nversion = \"0.1.0\"\nedition = \"2021\"\n");
    ( "src/lib.rs",
      {|// helper is private to the crate.
fn helper(x: i32) -> i32 { x + 1 }

/// entry is public and calls helper.
pub fn entry(x: i32) -> i32 { helper(x) * 2 }

/// island is public but nothing in this crate calls it.
pub fn island() -> i32 { 99 }

pub mod inner {
    pub fn nested(x: i32) -> i32 { super::entry(x) }
}
|} );
  ]

let register_rust () =
  Test.register ~__FILE__ ~title:"lsp: Rust keeps its module nesting and its call edges"
    ~tags:["lsp"; "rust"]
  @@ fun () ->
  if not (runnable "rust-analyzer" ["--version"] && runnable "cargo" ["--version"]) then
    not_exercised
      "Rust: rust-analyzer is not runnable (absent, or a rustup shim whose component is missing)"
  else
    with_project ~name:"lsp_rust" ~files:rust_files (fun project ->
        (* Warm the crate: a never-compiled crate makes the server's initial load
           slow enough to matter, and the readiness wait has a budget. *)
        ignore (run_command ~cwd:project "cargo" ["check"; "-q"]) ;
        let db, log = index_project_lang ~name:"lsp_rust" ~language:"rust" project in
        Batch.run (fun b ->
            check_language b ~label:"Rust" ~db ~exported:"entry" ~internal:"helper"
              ~island:"island" ;
            Db.with_db db (fun conn ->
                Batch.ge_int b ~msg:"Rust: 'inner::nested' must be indexed, not flattened away"
                  (Db.int conn "SELECT count(*) FROM functions WHERE name LIKE '%nested%'") 1 ;
                let edges = Db.int conn "SELECT count(*) FROM calls" in
                (* This assertion USED to be gated on readiness having been
                   reported, with a bare [Log.warn] on the other branch — the
                   exact defect shape this suite exists to remove, and one a
                   review proved live here: with the extractor returning no
                   edges and the readiness line reworded, a test titled "…and
                   its call edges" passed with zero call edges under
                   ARCH_TEZT_REQUIRE_SERVERS=1, because [Log.warn] is not
                   escalated by that flag.

                   Gating an assertion on a signal that the regression would
                   itself destroy means the assertion cannot fail. So edges are
                   now required unconditionally, and the readiness line is only
                   used to explain WHICH failure this is. *)
                let readiness_reported =
                  contains ~needle:"readiness: reported complete" log
                in
                Batch.ge_int b
                  ~msg:
                    (Printf.sprintf
                       "Rust: call edges must be extracted (readiness was %s — if it was not \
                        reported, the wait or the budget is the suspect, not the extractor)"
                       (if readiness_reported then "reported" else "NOT reported"))
                  edges 1))) ;
  Lwt.return_unit

let ts_files =
  [
    ( "tsconfig.json",
      "{\"compilerOptions\":{\"target\":\"ES2020\",\"module\":\"commonjs\",\"strict\":true},\"include\":[\"src\"]}\n"
    );
    ( "src/index.ts",
      {|export function helper(x: number): number { return x + 1; }
export function entry(x: number): number { return helper(x) * 2; }
function island(): number { return 99; }
|} );
  ]

let register_typescript () =
  Test.register ~__FILE__ ~title:"lsp: TypeScript enrichment actually reaches the rows"
    ~tags:["lsp"; "typescript"]
  @@ fun () ->
  (* typescript-language-server refuses to start without a TypeScript install in
     the workspace, and looks for node_modules/typescript/lib/tsserver.js — a
     layout TypeScript 7 no longer has, hence the 5.x pin. *)
  if not (runnable "typescript-language-server" ["--version"] && runnable "npm" ["--version"]) then
    not_exercised "TypeScript: typescript-language-server is not runnable, or npm is absent"
  else
    with_project ~name:"lsp_ts" ~files:ts_files (fun project ->
        let code, out =
          run_command ~cwd:project "npm"
            ["i"; "--silent"; "--no-audit"; "--no-fund"; "typescript@5"; "ts-morph"]
        in
        if code <> 0 then
          (* Reaching the npm registry is a property of the network, never of
             this code, so it stays a skip even under the strict flag. *)
          external_failure "TypeScript: npm install failed (exit %d):\n%s" code out
        else begin
          let db, _ = index_project_lang ~name:"lsp_ts" ~language:"typescript" project in
          Batch.run (fun b ->
              check_language b ~label:"TypeScript" ~db ~exported:"entry" ~internal:"helper"
                ~island:"island" ;
              Db.with_db db (fun conn ->
                  (* ts-morph enrichment fills these in. An UPDATE keyed on a
                     path the LSP rows do not use matched nothing and left both
                     columns as the LSP had them — silently, because an UPDATE
                     matching no row still returns DONE. *)
                  List.iter
                    (fun (fn, expected) ->
                      Batch.eq_string_opt b
                        ~msg:(Printf.sprintf "TypeScript: '%s' visibility" fn)
                        (Db.string_opt conn
                           (Printf.sprintf
                              "SELECT COALESCE(exported, -1) FROM functions WHERE name = '%s'" fn))
                        (Some expected))
                    [("entry", "1"); ("helper", "1"); ("island", "0")] ;
                  Batch.check b
                    ~msg:"TypeScript: 'entry' must have a signature — ts-morph enrichment applied"
                    (match
                       Db.string_opt conn
                         "SELECT COALESCE(signature, '') FROM functions WHERE name = 'entry'"
                     with
                    | Some s -> String.trim s <> ""
                    | None -> false)))
        end) ;
  Lwt.return_unit
