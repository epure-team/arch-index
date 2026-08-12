(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** One polyglot repository, one index.

    [Lsp_languages] indexes each language in its own project and its own
    database.  Real repositories are not shaped like that: a Go service and a
    TypeScript front end sit side by side, and [arch_index --project <repo>]
    with no [--language] must cover both.  That path had never been exercised —
    the runner picked a single language through [detect_language], so
    everything else in the repository was silently absent from the index.

    What this pins:
    - auto-detection finds every language in the tree, not the first one;
    - each language is indexed from the directory holding its project file,
      since typescript-language-server refuses a root with no [tsconfig.json];
    - rows from all of them land in one database;
    - file paths and call sites are relative to the REPOSITORY, not to each
      language's sub-root, or two sub-projects with a [main.go] each would be
      indistinguishable;
    - the [language] meta key records every contributor. *)

open Arch_tezt

let files =
  [
    ("gosvc/go.mod", "module polysvc\n\ngo 1.21\n");
    ( "gosvc/main.go",
      {go|package main

func goHelper(x int) int { return x + 1 }

func GoEntry(x int) int { return goHelper(x) }

func main() { _ = GoEntry(1) }
|go} );
    ( "tsapp/tsconfig.json",
      {json|{"compilerOptions":{"target":"ES2020","module":"commonjs","strict":true},"include":["src"]}
|json} );
    ( "tsapp/src/index.ts",
      {ts|export function tsHelper(x: number): number { return x + 1; }
export function tsEntry(x: number): number { return tsHelper(x); }
function tsIsland(): number { return 9; }
|ts} );
  ]

(* This test needs two language servers at once; a runner that has neither
   should report "not exercised", not "failed". *)
let servers_available () =
  let missing =
    List.filter
      (fun (_, prog, args) -> not (runnable prog args))
      [
        ("gopls", "gopls", ["version"]);
        ( "typescript-language-server",
          "typescript-language-server",
          ["--version"] );
        ("go", "go", ["version"]);
        ("npm", "npm", ["--version"]);
      ]
  in
  match missing with
  | [] -> true
  | _ ->
      not_exercised "%s not runnable"
        (String.concat ", " (List.map (fun (n, _, _) -> n) missing)) ;
      false

let exported db name =
  Db.int_opt db
    (Printf.sprintf "SELECT exported FROM functions WHERE name = '%s'" name)

let register () =
  Test.register ~__FILE__ ~title:"index: one polyglot repository, one database"
    ~tags:["lsp"; "multilang"; "go"; "typescript"]
  @@ fun () ->
  if not (servers_available ()) then Lwt.return_unit
  else begin
    with_project ~name:"arch_tezt_polyrepo" ~files @@ fun repo ->
    let code, output =
      run_command ~cwd:(Filename.concat repo "tsapp") "npm"
        ["i"; "--silent"; "--no-audit"; "--no-fund"; "typescript@5"; "ts-morph"]
    in
    (* Reaching the npm registry is a property of the machine, never of
       arch-index, so a failure here is "not exercised" and not a red test.
       Without it [dune test] would need the network to pass. *)
    if code <> 0 then begin
      not_exercised "npm install failed (exit %d):\n%s" code output ;
      Lwt.return_unit
    end
    else begin
      (* No --language: the point is that auto-detection covers the whole
         repository. *)
      let db_path = index_project ~name:"polyrepo" repo in
      Db.with_db db_path (fun db ->
        (* both languages contributed *)
        let langs =
          Option.value ~default:""
            (Db.string_opt db
               "SELECT value FROM comment_db_meta WHERE key = 'language'")
        in
        List.iter
          (fun lang ->
            Check.(
              (langs =~ rex lang)
                ~error_msg:
                  (Printf.sprintf
                     "the language meta key (%%L) does not mention %s" lang)))
          ["go"; "typescript"] ;

        (* rows from both, in one database *)
        List.iter
          (fun name ->
            Check.(
              (Db.int db
                 (Printf.sprintf
                    "SELECT count(*) FROM functions WHERE name = '%s'" name)
               >= 1)
                int
                ~error_msg:
                  (Printf.sprintf "'%s' missing from the combined index (%%L rows)"
                     name)))
          ["GoEntry"; "goHelper"; "tsEntry"; "tsHelper"; "tsIsland"] ;

        (* paths are relative to the repository, not to each sub-root *)
        List.iter
          (fun (name, expected) ->
            Check.(
              (Db.string_opt db
                 (Printf.sprintf
                    "SELECT file_path FROM functions WHERE name = '%s' LIMIT 1"
                    name)
               = Some expected)
                (option string)
                ~error_msg:
                  (Printf.sprintf
                     "%s should be rooted at the repository: got %%L, expected \
                      %%R"
                     name)))
          [("GoEntry", "gosvc/main.go"); ("tsEntry", "tsapp/src/index.ts")] ;

        (* call sites carry the same rooting *)
        let site =
          Option.value ~default:"(none)"
            (Db.string_opt db
               "SELECT call_site FROM calls WHERE caller_name = 'GoEntry' LIMIT 1")
        in
        Check.(
          (site =~ rex "^gosvc/main\\.go:")
            ~error_msg:"call sites should be repository-rooted, got %L") ;

        (* edges from both languages *)
        List.iter
          (fun (caller, callee) ->
            Check.(
              (Db.int db
                 (Printf.sprintf
                    "SELECT count(*) FROM calls WHERE caller_name = '%s' AND \
                     callee_name = '%s'"
                    caller callee)
               >= 1)
                int
                ~error_msg:
                  (Printf.sprintf "missing call edge '%s -> %s' (%%L)" caller
                     callee)))
          [("GoEntry", "goHelper"); ("tsEntry", "tsHelper")] ;

        (* each language's own visibility rule survives the merge *)
        List.iter
          (fun (name, expected) ->
            Check.(
              (exported db name = Some expected) (option int)
                ~error_msg:
                  (Printf.sprintf
                     "'%s' should have exported = %%R in the merged index, got \
                      %%L"
                     name)))
          [("GoEntry", 1); ("goHelper", 0); ("tsEntry", 1); ("tsIsland", 0)] ;

        (* Every edge is MAY_ENUMERATED, and the merge did not lose it.

           This asserts on the whole table rather than a sample, because the
           failure being guarded against is silent: a NULL kind (or a dropped
           column) reads as MUST in Arch_db.kind_sql, so a single untagged row
           re-introduces a must-reach claim the LSP path cannot support. *)
        Check.(
          (Db.int db
             "SELECT count(*) FROM calls WHERE kind IS NULL OR kind <> \
              'MAY_ENUMERATED'"
           = 0)
            int
            ~error_msg:
              "%L call edge(s) are not MAY_ENUMERATED — an untagged LSP edge \
               reads as MUST and forges a must-reach path") ;

        (* And the index must NOT claim the ⊤-marking contract: callHierarchy
           never reports the call sites it failed to resolve, so the ⊤ frontier
           is unknown, not empty. `unreachable`/`escapes` have to keep
           refusing. *)
        Check.(
          (Db.string_opt db
             "SELECT value FROM comment_db_meta WHERE key = \
              'callgraph_contract'"
           = None)
            (option string)
            ~error_msg:
              "the LSP path must not stamp callgraph_contract (got %L): it \
               does not enumerate unresolved targets as MAY_TOP")) ;
      Lwt.return_unit
    end
  end
