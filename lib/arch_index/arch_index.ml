(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Architecture index generator.

    Scans .cmt/.cmti files produced by dune build and populates
    [docs/architecture.db] with modules, functions, types, record fields,
    and variant constructors. *)

open Arch_index_db
open Arch_index_cmt

(* -------------------------------------------------------------------------- *)
(* Code line counting (excludes comments and blank lines)                     *)
(* -------------------------------------------------------------------------- *)

let count_code_lines = Arch_index_line_counter.run_count_code_lines

(* -------------------------------------------------------------------------- *)
(* Preserve hand-written intent fields across re-index                        *)
(* -------------------------------------------------------------------------- *)

(* -------------------------------------------------------------------------- *)
(* Source-path mapping                                                        *)
(* -------------------------------------------------------------------------- *)

(** Project root, derived from the build directory.
    E.g. if build_dir is [/foo/bar/_build/default/src], project_root is [/foo/bar]. *)
let project_root = ref ""

(* -------------------------------------------------------------------------- *)
(* Result type                                                                *)
(* -------------------------------------------------------------------------- *)

type result = {
  n_modules : int;
  n_functions : int;
  n_types : int;
  n_fields : int;
  n_constructors : int;
  n_calls : int;
  n_calls_resolved : int;
  n_deps : int;
  n_deps_resolved : int;
  n_type_usages : int;
  n_type_usages_resolved : int;
  db_path : string;
}

(* -------------------------------------------------------------------------- *)
(* Main entry point                                                           *)
(* -------------------------------------------------------------------------- *)

let run ?(db_path = db_path) ?(schema_path = schema_path) ~build_dir () =
  (* Reset global state for re-entrancy *)
  project_root := "" ;
  (* Derive project root from build_dir: strip _build/default/... suffix *)
  (let abs_build =
     if Filename.is_relative build_dir then
       Filename.concat (Sys.getcwd ()) build_dir
     else build_dir
   in
   match
     String.split_on_char '/' abs_build
     |> List.to_seq
     |> Seq.find_index (fun s -> s = "_build")
   with
   | Some idx ->
       let parts = String.split_on_char '/' abs_build in
       let root_parts = List.filteri (fun i _ -> i < idx) parts in
       project_root := String.concat "/" root_parts
   | None -> ()) ;
  if !project_root <> "" then
    Arch_io.printf "Project root: %s\n%!" !project_root ;
  Arch_io.printf
    "Scanning %s for .cmt/.cmti files...\n%!"
    build_dir ;
  let all_files = find_cmt_files build_dir in
  let cmt_files =
    List.filter (fun f -> Filename.check_suffix f ".cmt") all_files
  in
  let cmti_files =
    List.filter (fun f -> Filename.check_suffix f ".cmti") all_files
  in
  Arch_io.printf
    "Found %d .cmt and %d .cmti files\n%!"
    (List.length cmt_files)
    (List.length cmti_files) ;

  (* Collect exposed names and doc comments from .cmti files *)
  let exposed_tbl, doc_tbl, module_quint_tbl = collect_exposed cmti_files in
  Arch_io.printf
    "Found %d exposed names, %d doc comments\n%!"
    (Hashtbl.length exposed_tbl)
    (Hashtbl.length doc_tbl) ;

  (* Open or create database *)
  let db = Sqlite3.db_open db_path in
  ignore (Sqlite3.exec db "PRAGMA foreign_keys = ON") ;
  ignore (Sqlite3.exec db "PRAGMA journal_mode = WAL") ;

  (* Detect schema corruption (e.g. from a concurrent write on a self-hosted
     CI runner reusing the workspace).  If sqlite_master is unreadable, delete
     the file and reopen a fresh empty DB — intents are unrecoverable anyway. *)
  let db =
    match Sqlite3.exec db "SELECT count(*) FROM sqlite_master" with
    | Sqlite3.Rc.OK -> db
    | _ ->
        ignore (Sqlite3.db_close db) ;
        (try Sys.remove db_path with _ -> ()) ;
        Arch_io.eprintf
          "Warning: corrupt arch DB detected at %s — deleted and recreating.\n\
           %!"
          db_path ;
        Sqlite3.db_open db_path
  in

  (* Backup intents before wiping *)
  let backup = Arch_index_support.backup_intents db in
  Arch_io.printf
    "Backed up %d module intents, %d function intents, %d type intents\n%!"
    (List.length backup.module_intents)
    (List.length backup.function_intents)
    (List.length backup.type_intents) ;

  (* Drop views first (they reference the tables), then tables. *)
  List.iter
    (fun view -> exec_exn db (Printf.sprintf "DROP VIEW IF EXISTS %s" view))
    Arch_index_support.schema_views_to_drop ;
  List.iter
    (fun tbl -> exec_exn db (Printf.sprintf "DROP TABLE IF EXISTS %s" tbl))
    Arch_index_support.schema_tables_to_drop ;

  (* Re-create schema - handle missing file gracefully *)
  let sql =
    if not (Sys.file_exists schema_path) then (
      Arch_io.eprintf
        "Error: Schema file not found: %s\n\
         Set ARCH_SCHEMA_PATH or run from repository root.\n"
        schema_path ;
      exit 1)
    else
      let ic = open_in schema_path in
      Fun.protect
        ~finally:(fun () -> close_in ic)
        (fun () ->
          let n = in_channel_length ic in
          really_input_string ic n)
  in
  exec_exn db sql ;

  (* Prepare statements *)
  let stmt_mod =
    Sqlite3.prepare
      db
      "INSERT INTO modules (path, lines, last_analyzed, has_mli, \
       quint_module_raw) VALUES (?, ?, ?, ?, ?)"
  in
  let stmt_fn =
    Sqlite3.prepare
      db
      "INSERT OR REPLACE INTO functions (module_id, name, signature, \
       line_start, line_end, exposed, intent, comment_quality_score, has_pre, \
       has_post, has_violators, has_violates, violators_raw, violates_raw, \
       tests_raw, quint_raw) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, \
       ?, ?)"
  in
  let stmt_ty =
    Sqlite3.prepare
      db
      "INSERT OR REPLACE INTO types (module_id, name, kind, line_start, \
       line_end, exposed, manifest, intent) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
  in
  let stmt_fld =
    Sqlite3.prepare
      db
      "INSERT INTO type_fields (type_id, field_name, field_type, position) \
       VALUES (?, ?, ?, ?)"
  in
  let stmt_ctor =
    Sqlite3.prepare
      db
      "INSERT INTO type_constructors (type_id, constructor_name, position, \
       arg_types) VALUES (?, ?, ?, ?)"
  in
  let stmt_call =
    Sqlite3.prepare
      db
      "INSERT INTO calls (caller_id, callee_id, callee_name, call_site, kind) \
       VALUES (?, ?, ?, ?, ?)"
  in
  let stmt_dep =
    Sqlite3.prepare
      db
      "INSERT INTO module_deps (source_module, target_module, target_path, \
       dep_kind, alias_name, line_number) VALUES (?, ?, ?, ?, ?, ?)"
  in
  let stmt_type_usage =
    Sqlite3.prepare
      db
      "INSERT INTO type_usage (function_id, type_id, type_name, usage_role, \
       position) VALUES (?, ?, ?, ?, ?)"
  in

  (* Process all .cmt files inside a transaction *)
  exec_exn db "BEGIN TRANSACTION" ;
  let n_modules = ref 0 in
  let n_functions = ref 0 in
  let n_types = ref 0 in
  let all_pending_calls = ref [] in
  let all_pending_deps = ref [] in
  let all_pending_type_usages = ref [] in
  List.iter
    (fun path ->
      try
        let calls, deps, type_usages =
          process_cmt
            db
            ~project_root:!project_root
            ~source_path_of_cmt:
              (Arch_index_support.source_path_of_cmt
                 ~project_root:!project_root)
            ~count_code_lines
            ~exposed_tbl
            ~doc_tbl
            ~module_quint_tbl
            ~stmt_mod
            ~stmt_fn
            ~stmt_ty
            ~stmt_fld
            ~stmt_ctor
            path
        in
        all_pending_calls := List.rev_append calls !all_pending_calls ;
        all_pending_deps := List.rev_append deps !all_pending_deps ;
        all_pending_type_usages :=
          List.rev_append type_usages !all_pending_type_usages
      with exn ->
        Arch_io.eprintf
          "Warning: failed to process %s: %s\n"
          path
          (Printexc.to_string exn))
    cmt_files ;
  exec_exn db "COMMIT" ;

  (* Resolve and insert calls *)
  Arch_io.printf
    "Resolving %d pending calls...\n%!"
    (List.length !all_pending_calls) ;
  exec_exn db "BEGIN TRANSACTION" ;
  let n_calls = ref 0 in
  let n_resolved = ref 0 in
  let fn_lookup = Hashtbl.create 1024 in
  ignore
    (Sqlite3.exec_not_null
       db
       ~cb:(fun row _h ->
         let fn_id = int_of_string row.(0) in
         let fn_name = row.(1) in
         let mod_path = row.(2) in
         Hashtbl.replace fn_lookup (mod_path, fn_name) fn_id)
       "SELECT f.id, f.name, m.path FROM functions f JOIN modules m ON \
        f.module_id = m.id") ;
  let mod_name_to_path = Hashtbl.create 128 in
  ignore
    (Sqlite3.exec_not_null
       db
       ~cb:(fun row _h ->
         let path = row.(0) in
         let base = Filename.basename path in
         let name = Filename.remove_extension base |> String.capitalize_ascii in
         Hashtbl.replace mod_name_to_path name path)
       "SELECT path FROM modules") ;
  List.iter
    (fun (call : pending_call) ->
      match
        Hashtbl.find_opt fn_lookup (call.caller_module, call.caller_name)
      with
      | None -> ()
      | Some caller_id ->
          (* Edge-kind classification (soundy, mirroring the Go producer):
               - computed head (callee_top)  → MAY_TOP (⊤ sentinel), unresolvable
               - unqualified name resolving to a same-module top-level fn → MUST
               - unqualified name NOT resolving (a function parameter or
                 let-bound closure applied by name) → MAY_TOP: the target is
                 not statically known, so it could call anything
               - qualified name (external or in-index) → MUST: a uniquely
                 resolved static call; an unresolved external is a MUST leaf. *)
          (* Resolve an unqualified same-module callee name to its id. *)
          let resolve_local () =
            Hashtbl.find_opt fn_lookup (call.caller_module, call.callee_name)
          in
          let callee_id, callee_display_name, kind =
            match call.kind_hint with
            | Arch_index_cmt.May_top -> (None, call.callee_name, "MAY_TOP")
            | Arch_index_cmt.May_enumerated ->
                (* A named local function passed as a callback — resolve it to a
                   node so the closure can follow it, but as MAY_ENUMERATED (the
                   callee may or may not invoke it), never MUST. *)
                (match resolve_local () with
                 | Some id -> incr n_resolved ; (Some id, call.callee_name, "MAY_ENUMERATED")
                 | None -> (None, call.callee_name, "MAY_ENUMERATED"))
            | Arch_index_cmt.Resolve -> (
              match call.callee_module with
              | None -> (
                  match
                    Hashtbl.find_opt
                      fn_lookup
                      (call.caller_module, call.callee_name)
                  with
                  | Some id ->
                      incr n_resolved ;
                      (Some id, call.callee_name, "MUST")
                  | None -> (None, call.callee_name, "MAY_TOP"))
              | Some mod_name -> (
                  let display_name = mod_name ^ "." ^ call.callee_name in
                  (* For library-qualified names like Epure_db.Db_util,
                     the lookup table only has the last component "Db_util". *)
                  let lookup_name =
                    match String.rindex_opt mod_name '.' with
                    | Some i ->
                        String.sub
                          mod_name
                          (i + 1)
                          (String.length mod_name - i - 1)
                    | None -> mod_name
                  in
                  match Hashtbl.find_opt mod_name_to_path lookup_name with
                  | Some mod_path -> (
                      match
                        Hashtbl.find_opt fn_lookup (mod_path, call.callee_name)
                      with
                      | Some id ->
                          incr n_resolved ;
                          (Some id, display_name, "MUST")
                      | None -> (None, display_name, "MUST"))
                  | None -> (None, display_name, "MUST")))
          in
          insert_call
            db
            stmt_call
            ~caller_id
            ~callee_id
            ~callee_name:callee_display_name
            ~call_site:(Some call.call_site)
            ~kind ;
          incr n_calls)
    !all_pending_calls ;
  (* Every emitted edge now carries a valid kind (MUST | MAY_TOP), so this
     backend satisfies the ⊤-marking contract — but ONLY stamp the flag when a
     non-empty universe was actually indexed. Stamping on an empty/failed scan
     (0 functions) would let `unreachable` answer with false confidence for
     roots that simply were not indexed. *)
  (* fn_lookup holds one entry per indexed function; use it as the "non-empty
     universe" test — the n_functions counter is not populated until later. *)
  if Hashtbl.length fn_lookup > 0 then
    exec_exn db
      "INSERT OR REPLACE INTO comment_db_meta (key, value) VALUES \
       ('callgraph_contract', 'v1')" ;
  exec_exn db "COMMIT" ;
  Arch_io.printf
    "Inserted %d calls (%d resolved to known functions)\n%!"
    !n_calls
    !n_resolved ;

  (* Resolve and insert module dependencies *)
  Arch_io.printf
    "Resolving %d module dependencies...\n%!"
    (List.length !all_pending_deps) ;
  exec_exn db "BEGIN TRANSACTION" ;
  let n_deps = ref 0 in
  let n_deps_resolved = ref 0 in
  let mod_path_to_id = Hashtbl.create 128 in
  ignore
    (Sqlite3.exec_not_null
       db
       ~cb:(fun row _h ->
         let mod_id = int_of_string row.(0) in
         let path = row.(1) in
         Hashtbl.replace mod_path_to_id path mod_id ;
         let base = Filename.basename path in
         let name = Filename.remove_extension base |> String.capitalize_ascii in
         Hashtbl.replace mod_name_to_path name path)
       "SELECT id, path FROM modules") ;
  List.iter
    (fun (dep : pending_dep) ->
      match Hashtbl.find_opt mod_path_to_id dep.source_module with
      | None -> ()
      | Some source_id ->
          let target_id =
            match Hashtbl.find_opt mod_path_to_id dep.target_path with
            | Some id ->
                incr n_deps_resolved ;
                Some id
            | None -> (
                let parts = String.split_on_char '.' dep.target_path in
                let name = List.hd (List.rev parts) in
                match Hashtbl.find_opt mod_name_to_path name with
                | Some path -> (
                    match Hashtbl.find_opt mod_path_to_id path with
                    | Some id ->
                        incr n_deps_resolved ;
                        Some id
                    | None -> None)
                | None -> None)
          in
          insert_module_dep
            db
            stmt_dep
            ~source_module:source_id
            ~target_module:target_id
            ~target_path:dep.target_path
            ~dep_kind:dep.dep_kind
            ~alias_name:dep.alias_name
            ~line_number:dep.line_number ;
          incr n_deps)
    !all_pending_deps ;
  exec_exn db "COMMIT" ;
  Arch_io.printf
    "Inserted %d module deps (%d resolved to known modules)\n%!"
    !n_deps
    !n_deps_resolved ;

  (* Resolve and insert type usages *)
  Arch_io.printf
    "Resolving %d type usages...\n%!"
    (List.length !all_pending_type_usages) ;
  exec_exn db "BEGIN TRANSACTION" ;
  let n_type_usages = ref 0 in
  let n_type_usages_resolved = ref 0 in
  let type_lookup = Hashtbl.create 256 in
  ignore
    (Sqlite3.exec_not_null
       db
       ~cb:(fun row _h ->
         let type_id = int_of_string row.(0) in
         let type_name = row.(1) in
         let mod_path = row.(2) in
         let base = Filename.basename mod_path in
         let mod_name =
           Filename.remove_extension base |> String.capitalize_ascii
         in
         Hashtbl.replace type_lookup (mod_name, type_name) type_id)
       "SELECT t.id, t.name, m.path FROM types t JOIN modules m ON t.module_id \
        = m.id") ;
  List.iter
    (fun (usage : pending_type_usage) ->
      let mod_name, type_name =
        match String.rindex_opt usage.type_path '.' with
        | Some idx ->
            let prefix = String.sub usage.type_path 0 idx in
            let name =
              String.sub
                usage.type_path
                (idx + 1)
                (String.length usage.type_path - idx - 1)
            in
            let mod_name =
              match String.rindex_opt prefix '.' with
              | Some i ->
                  String.sub prefix (i + 1) (String.length prefix - i - 1)
              | None -> prefix
            in
            (mod_name, name)
        | None -> ("", usage.type_path)
      in
      let type_id =
        match Hashtbl.find_opt type_lookup (mod_name, type_name) with
        | Some id ->
            incr n_type_usages_resolved ;
            Some id
        | None -> None
      in
      insert_type_usage
        db
        stmt_type_usage
        ~function_id:usage.function_id
        ~type_id
        ~type_name:usage.type_path
        ~usage_role:usage.usage_role
        ~position:usage.position ;
      incr n_type_usages)
    !all_pending_type_usages ;
  exec_exn db "COMMIT" ;
  Arch_io.printf
    "Inserted %d type usages (%d resolved to known types)\n%!"
    !n_type_usages
    !n_type_usages_resolved ;

  (* Count results *)
  ignore
    (Sqlite3.exec_not_null
       db
       ~cb:(fun row _h -> n_modules := int_of_string row.(0))
       "SELECT COUNT(*) FROM modules") ;
  ignore
    (Sqlite3.exec_not_null
       db
       ~cb:(fun row _h -> n_functions := int_of_string row.(0))
       "SELECT COUNT(*) FROM functions") ;
  ignore
    (Sqlite3.exec_not_null
       db
       ~cb:(fun row _h -> n_types := int_of_string row.(0))
       "SELECT COUNT(*) FROM types") ;

  (* Restore intents *)
  Arch_index_support.restore_intents db backup ;

  (* Summary *)
  let n_fields = ref 0 in
  let n_ctors = ref 0 in
  ignore
    (Sqlite3.exec_not_null
       db
       ~cb:(fun row _h -> n_fields := int_of_string row.(0))
       "SELECT COUNT(*) FROM type_fields") ;
  ignore
    (Sqlite3.exec_not_null
       db
       ~cb:(fun row _h -> n_ctors := int_of_string row.(0))
       "SELECT COUNT(*) FROM type_constructors") ;
  Arch_io.printf
    "\n\
     Done! Indexed:\n\
    \  %d modules\n\
    \  %d functions\n\
    \  %d types (%d record fields, %d variant constructors)\n\
    \  %d calls (%d resolved)\n\
    \  %d module deps (%d resolved)\n\
    \  %d type usages (%d resolved)\n\
     Database: %s\n"
    !n_modules
    !n_functions
    !n_types
    !n_fields
    !n_ctors
    !n_calls
    !n_resolved
    !n_deps
    !n_deps_resolved
    !n_type_usages
    !n_type_usages_resolved
    db_path ;

  ignore (Sqlite3.db_close db) ;

  {
    n_modules = !n_modules;
    n_functions = !n_functions;
    n_types = !n_types;
    n_fields = !n_fields;
    n_constructors = !n_ctors;
    n_calls = !n_calls;
    n_calls_resolved = !n_resolved;
    n_deps = !n_deps;
    n_deps_resolved = !n_deps_resolved;
    n_type_usages = !n_type_usages;
    n_type_usages_resolved = !n_type_usages_resolved;
    db_path;
  }

module Arch_index_compare = Arch_index_compare
module Arch_index_git = Arch_index_git
module Comment_parser = Comment_parser
module Language_registry = Language_registry
module Lsp_client = Lsp_client
module Ocaml_enricher = Ocaml_enricher

(* -------------------------------------------------------------------------- *)
(* LSP-based run (Story #406 / #416)                                          *)
(* -------------------------------------------------------------------------- *)

let run_lsp = Runner.run
