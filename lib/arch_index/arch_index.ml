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
       tests_raw, quint_raw, mutation_sites, deref_sites) VALUES (?, ?, ?, ?, \
       ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
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
  let stmt_dead =
    Sqlite3.prepare
      db
      "INSERT INTO dead_code_sites (function_id, call_site, callee_name) \
       VALUES (?, ?, ?)"
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
  (* One (rel_path, module_identity) entry per successfully processed file —
     the project-wide source of truth for "which dune library owns this
     module", built without any ambiguous, order-dependent SQL query.  See
     [Arch_index_cmt.module_identity]. *)
  let all_module_identities = ref [] in
  List.iter
    (fun path ->
      try
        let calls, deps, type_usages, module_identity =
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
          List.rev_append type_usages !all_pending_type_usages ;
        (match module_identity with
        | Some entry -> all_module_identities := entry :: !all_module_identities
        | None -> ())
      with exn ->
        Arch_io.eprintf
          "Warning: failed to process %s: %s\n"
          path
          (Printexc.to_string exn))
    cmt_files ;
  exec_exn db "COMMIT" ;

  (* Library-scoped resolution maps, shared by all three resolution phases
     below (calls, module deps, type usages).  Built once, from the
     project-wide module identities collected above — never from a
     [SELECT ... FROM modules] with no [ORDER BY], and never keyed by bare
     file basename, which is what let a qualified reference into one dune
     library silently resolve into an unrelated library's same-named file
     (see specs/sound-qualified-name-resolution.md).

     [wrapped_library_members]: library wrapper name -> (capitalised module
     basename -> module path), scoped to exactly that library's own modules.
     dune enforces a unique module namespace within one library, so this
     table cannot itself collide.

     [standalone_modname_to_paths]: a module's own persistent name -> every
     module path that answers to it.  Most of the time this is exactly one
     module (an unwrapped library, or a library's "main module").  When two
     unrelated unwrapped modules across different libraries happen to share
     a name, the list has more than one entry and resolution deliberately
     refuses to pick one — that is the honest-degradation path (P2), not a
     single-candidate guess (F2). *)
  let wrapped_library_members : (string, (string, string) Hashtbl.t) Hashtbl.t
      =
    Hashtbl.create 32
  in
  let standalone_modname_to_paths : (string, string list) Hashtbl.t =
    Hashtbl.create 32
  in
  List.iter
    (fun (rel_path, identity) ->
      match identity with
      | Arch_index_cmt.Wrapped (lib, local) ->
          let tbl =
            match Hashtbl.find_opt wrapped_library_members lib with
            | Some tbl -> tbl
            | None ->
                let tbl = Hashtbl.create 16 in
                Hashtbl.add wrapped_library_members lib tbl ;
                tbl
          in
          Hashtbl.replace tbl (String.capitalize_ascii local) rel_path
      | Arch_index_cmt.Standalone modname ->
          let existing =
            Option.value
              ~default:[]
              (Hashtbl.find_opt standalone_modname_to_paths modname)
          in
          Hashtbl.replace
            standalone_modname_to_paths
            modname
            (rel_path :: existing))
    !all_module_identities ;
  (* dune's wrapping scheme names the library wrapper after the library
     itself (e.g. [Liba]) UNLESS one of the library's own modules already
     has that exact name (a library's "main module", e.g. library [efxtest]
     with a module [efxtest.ml]) — a real compiled unit already owns the
     plain name, so the wrapper is disambiguated to [Lib__] (observed on
     dune 3.x: the wrapper module for library [efxtest] there is literally
     [Efxtest__], not [Efxtest]).  [wrapped_library_members] is keyed from
     splitting the SUBMODULES' own mangled names (e.g. "Efxtest__Efxdeep"),
     which yields the plain library name regardless of this case — so any
     library name that collides with a standalone module name it also owns
     is re-keyed here to the "__"-suffixed spelling external references
     actually use, and the plain spelling is left exclusively for
     [standalone_modname_to_paths] to resolve the main module itself. *)
  Hashtbl.iter
    (fun lib _ ->
      if Hashtbl.mem standalone_modname_to_paths lib then (
        match Hashtbl.find_opt wrapped_library_members lib with
        | Some tbl ->
            Hashtbl.remove wrapped_library_members lib ;
            Hashtbl.replace wrapped_library_members (lib ^ "__") tbl
        | None -> ()))
    (Hashtbl.copy wrapped_library_members) ;
  (* Resolve a dotted, persistently-rooted qualified name (as produced by
     [Path.name] — e.g. ["Liba.Api"] or ["Qual.G1.B"]) to the exact module
     file it names, scoped to the library the root positively identifies.
     Returns [Some (mod_path, deeper)] where [deeper] is whatever remains
     after the file itself — nested-module qualification within that one
     file, or [] when the reference names the file directly.  Returns [None]
     when the root names no known project library (a genuine external
     dependency — Stdlib, a vendored path, an unindexed unit) or when it
     names more than one candidate (the honest-degradation case above): in
     neither case does this function fall back to guessing by basename. *)
  let resolve_module_root segments =
    match segments with
    | [] -> None
    | root :: rest -> (
        match Hashtbl.find_opt wrapped_library_members root with
        | Some basename_tbl -> (
            match rest with
            | [] -> None (* the wrapper itself defines no functions/types *)
            | file_seg :: deeper -> (
                match
                  Hashtbl.find_opt
                    basename_tbl
                    (String.capitalize_ascii file_seg)
                with
                | Some mod_path -> Some (mod_path, deeper)
                | None -> None))
        | None -> (
            match rest with
            | [] -> (
                match Hashtbl.find_opt standalone_modname_to_paths root with
                | Some [mod_path] -> Some (mod_path, [])
                | Some _ | None -> None)
            | _ :: _ -> None))
  in

  (* Resolve and insert calls *)
  Arch_io.printf
    "Resolving %d pending calls...\n%!"
    (List.length !all_pending_calls) ;
  exec_exn db "BEGIN TRANSACTION" ;
  let n_calls = ref 0 in
  let n_resolved = ref 0 in
  let n_dead_sites = ref 0 in
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
  List.iter
    (fun (call : pending_call) ->
      match
        Hashtbl.find_opt fn_lookup (call.caller_module, call.caller_name)
      with
      | None -> ()
      | Some caller_id ->
          (* Edge-kind classification from the (head × cond × partial) facts —
             execution-sound dominance with ENUMERATED demotion:
               - Head_unknown → MAY_TOP (⊤): could call anything. This is the
                 ONLY source of ⊤ — computed heads, parameter/local-value
                 calls, dynamic roots, over-application residuals.
               - Head_enumerated → MAY_ENUMERATED (bounded candidate), whether
                 or not the escape site is conditional.
               - Head_local / Head_qualified, unconditional + saturated → MUST
                 (resolved id or external leaf).
               - Head_local / Head_qualified, conditional or partial →
                 MAY_ENUMERATED (candidate set of one): the call either invokes
                 that exact callee or does not execute — it can never reach
                 anything outside the callee's subtree, so demoting to ⊤ would
                 only inject false UNKNOWNs. Resolution identity is preserved
                 (callee_id when in-index; external leaf otherwise). *)
          let resolve_local name =
            Hashtbl.find_opt fn_lookup (call.caller_module, name)
          in
          (* [Liba.Api.run]'s root is the PERSISTENT identity dune's wrapping
             gives an external qualified reference — the owning library's
             wrapper name (or the module's own name when unwrapped) — never a
             bare basename.  [resolve_module_root] resolves that root within
             the project-wide library-scoped maps built above; whatever
             remains after the file itself is a nested-module qualification
             looked up directly against that ONE file's functions, never
             against every file in the project sharing a basename.  A root
             that names no known library, or a standalone name shared by more
             than one unrelated module, resolves to [None] here — the call
             site below then falls back to its existing "unresolved external
             leaf" treatment, exactly as it already does for e.g. Stdlib
             calls.  There is deliberately no candidate-narrowing step that
             could turn "no positively identified owner" into a guess (F2). *)
          let resolve_qualified mod_name name =
            let segments = String.split_on_char '.' mod_name in
            match resolve_module_root segments with
            | None -> None
            | Some (mod_path, deeper) ->
                let qualified_name = String.concat "." (deeper @ [name]) in
                Hashtbl.find_opt fn_lookup (mod_path, qualified_name)
          in
          let demoted = call.cond || call.partial in
          let callee_id, callee_display_name, kind =
            match call.head with
            | Arch_index_cmt.Head_unknown n -> (None, n, "MAY_TOP")
            | Arch_index_cmt.Head_enumerated n -> (
                (* A named local function passed as a callback — resolve it to a
                   node so the closure can follow it, but as MAY_ENUMERATED (the
                   callee may or may not invoke it), never MUST — conditional or
                   not, the candidate set is the same. *)
                match resolve_local n with
                | Some id -> incr n_resolved ; (Some id, n, "MAY_ENUMERATED")
                | None -> (None, n, "MAY_ENUMERATED"))
            | Arch_index_cmt.Head_local n -> (
                match resolve_local n with
                | Some id ->
                    incr n_resolved ;
                    (Some id, n, (if demoted then "MAY_ENUMERATED" else "MUST"))
                | None ->
                    (* Not in the function table (shadow/anomaly): unknowable. *)
                    (None, n, "MAY_TOP"))
            | Arch_index_cmt.Head_qualified (mod_opt, n) -> (
                let display_name =
                  match mod_opt with Some m -> m ^ "." ^ n | None -> n
                in
                let kind = if demoted then "MAY_ENUMERATED" else "MUST" in
                match mod_opt with
                | None -> (
                    match resolve_local n with
                    | Some id -> incr n_resolved ; (Some id, n, kind)
                    | None -> (None, n, (if demoted then "MAY_ENUMERATED" else "MAY_TOP")))
                | Some mod_name -> (
                    match resolve_qualified mod_name n with
                    | Some id -> incr n_resolved ; (Some id, display_name, kind)
                    | None ->
                        (* Unresolved external: a leaf either way — MUST leaf
                           when unconditional, enumerated leaf when demoted. *)
                        (None, display_name, kind)))
          in
          insert_call
            db
            stmt_call
            ~caller_id
            ~callee_id
            ~callee_name:callee_display_name
            ~call_site:(Some call.call_site)
            ~kind ;
          (* R2: the call sits in a block unreachable from its function's CFG
             entry, so it can never execute. Recorded with its location — that
             is what makes the finding actionable. *)
          if call.dead then begin
            Arch_index_db.bind_int stmt_dead 1 caller_id ;
            Arch_index_db.bind_text stmt_dead 2 call.call_site ;
            Arch_index_db.bind_text stmt_dead 3 callee_display_name ;
            Arch_index_db.exec_stmt db stmt_dead ;
            incr n_dead_sites
          end ;
          incr n_calls)
    !all_pending_calls ;
  (* Every emitted edge now carries a valid kind (MUST | MAY_ENUMERATED | MAY_TOP), so this
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
         Hashtbl.replace mod_path_to_id path mod_id)
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
                (* [dep.target_path] is a [Path.name]-shaped dotted string
                   (e.g. "Liba.Api" or "Stdlib.List") — the same
                   persistently-rooted shape a call's qualified name has, so
                   the same library-scoped resolution applies: a homonymous
                   [open]/[include]/module-alias target must never be
                   attributed to the wrong library's same-named file. *)
                let segments = String.split_on_char '.' dep.target_path in
                match resolve_module_root segments with
                | Some (mod_path, _deeper) -> (
                    match Hashtbl.find_opt mod_path_to_id mod_path with
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
  (* Keyed by (module path, type name AS STORED — dotted nested-module
     qualification within that one file, e.g. "Nested.story"), mirroring
     [fn_lookup] above.  This key is exact and file-scoped, so — unlike the
     capitalised-basename table it replaces — it cannot collide across two
     libraries that each happen to have a same-named file. *)
  let type_lookup = Hashtbl.create 256 in
  ignore
    (Sqlite3.exec_not_null
       db
       ~cb:(fun row _h ->
         let type_id = int_of_string row.(0) in
         let type_name = row.(1) in
         let mod_path = row.(2) in
         Hashtbl.replace type_lookup (mod_path, type_name) type_id)
       "SELECT t.id, t.name, m.path FROM types t JOIN modules m ON t.module_id \
        = m.id") ;
  List.iter
    (fun (usage : pending_type_usage) ->
      (* [usage.type_path] is a [Path.name]-shaped dotted string, exactly like
         a call's [module . name] pair — split off the trailing type name and
         resolve the remaining module path the same library-scoped way,
         rather than keeping only the last two components (which is the same
         "last component wins" collision this whole fix removes, just for
         types instead of calls). *)
      let type_id =
        match List.rev (String.split_on_char '.' usage.type_path) with
        | [] -> None (* unreachable: split_on_char always yields >= 1 part *)
        | type_name :: rev_mod_segments -> (
            match resolve_module_root (List.rev rev_mod_segments) with
            | None -> None
            | Some (mod_path, deeper) -> (
                let qualified_type_name =
                  String.concat "." (deeper @ [type_name])
                in
                match
                  Hashtbl.find_opt type_lookup (mod_path, qualified_type_name)
                with
                | Some id ->
                    incr n_type_usages_resolved ;
                    Some id
                | None -> None))
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
module Arch_index_cfg = Arch_index_cfg
module Comment_parser = Comment_parser
module Language_registry = Language_registry
module Lsp_client = Lsp_client
module Ocaml_enricher = Ocaml_enricher

(* -------------------------------------------------------------------------- *)
(* LSP-based run (Story #406 / #416)                                          *)
(* -------------------------------------------------------------------------- *)

let run_lsp = Runner.run
let run_lsp_multi = Runner.run_multi
