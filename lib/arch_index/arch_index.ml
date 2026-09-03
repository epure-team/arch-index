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
  n_statement_failures : int;
  (* Rejected rows per destination table. The scalar above says a run lost
     rows; this says which table lost them, which is what decides whether the
     loss invalidates a metric or a graph edge. *)
  rejections_by_table : (string * int) list;
      (** Prepared-statement steps that did not return [DONE] during this run.

          [exec_stmt] prints such a failure and continues, so a run can reject
          rows and still exit 0. When this is non-zero the other counts in this
          record are ATTEMPTS, not stored rows, and a caller that owns an exit
          status must fail. Measured before this field existed: indexing
          épure's src/ rejected 238 type_usage inserts on a stale
          [function_id] and reported them as written. *)
  db_path : string;
}

(* -------------------------------------------------------------------------- *)
(* Main entry point                                                           *)
(* -------------------------------------------------------------------------- *)

let run ?(db_path = db_path) ?(schema_path = schema_path) ~build_dir () =
  (* Reset global state for re-entrancy *)
  project_root := "" ;
  (* The rejection tally and the dropped-node registry live at module level in
     [Arch_index_db] and [Arch_index_cmt], so they are process-cumulative, not
     per-run. Now that this function is part of the published library surface, a
     consumer calling [run] twice would otherwise read run 1's rejections folded
     into run 2's report -- and [n_statement_failures] / [rejections_by_table]
     on the result record are documented as THIS run's. Reset here so the record
     means what it says, and so run 2 does not resolve a callee to MAY_TOP on
     the strength of a unit run 1 dropped. *)
  Arch_index_db.reset_all () ;
  Arch_index_cmt.reset_dropped () ;
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
  (* FIX (review): this is the ONLY path that writes architecture-schema.sql
     (the schema current_schema_version's history actually describes — the
     migrations that bumped it to 1.1/1.2 apply to THIS schema, not
     runner.ml's separate flat 3-table one). It never stamped schema_version
     at all before this fix — meaning the versioning mechanism #51 asked for
     was, until now, never actually exercised for the schema it was built to
     describe. Unconditional (unlike callgraph_contract below, which is
     gated on a non-empty universe): the database's STRUCTURE is
     architecture-schema.sql regardless of how much got indexed into it. *)
  exec_exn
    db
    (Printf.sprintf
       "INSERT OR REPLACE INTO comment_db_meta (key, value) VALUES \
        ('schema_version', '%s')"
       Arch_index_db.current_schema_version) ;

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
  (* Exception-identity rows (specs/exn-raise-sets.md). *)
  let stmt_scope =
    Sqlite3.prepare
      db
      "INSERT INTO exn_scopes (function_id, parent_id, form, line, col, \
       catch_all) VALUES (?, ?, ?, ?, ?, ?)"
  in
  let stmt_catch =
    Sqlite3.prepare db "INSERT INTO exn_scope_catches (scope_id, exn_path) VALUES (?, ?)"
  in
  let stmt_origin =
    Sqlite3.prepare
      db
      "INSERT INTO exn_origins (function_id, scope_id, form, exn_path, escapes, \
       line, col) VALUES (?, ?, ?, ?, ?, ?, ?)"
  in
  let stmt_rebind =
    Sqlite3.prepare
      db
      "INSERT OR IGNORE INTO exn_rebinds (alias_path, target_path) VALUES (?, ?)"
  in
  let stmt_call_scope =
    Sqlite3.prepare db "INSERT INTO call_exn_scopes (call_id, scope_id) VALUES (?, ?)"
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
            ~stmt_scope
            ~stmt_catch
            ~stmt_origin
            ~stmt_rebind
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
  let module_name_of_path path =
    Filename.basename path |> Filename.remove_extension
    |> String.capitalize_ascii
  in
  let mod_name_to_path = Hashtbl.create 128 in
  ignore
    (Sqlite3.exec_not_null
       db
       ~cb:(fun row _h ->
         let path = row.(0) in
         Hashtbl.replace mod_name_to_path (module_name_of_path path) path)
       "SELECT path FROM modules") ;
  (* Compilation units whose [modules] row was rejected have no path in
     [mod_name_to_path] — the table is built from STORED rows — so they must be
     recognised by name. Derived through the same function as the stored names
     so the two agree by construction. *)
  let dropped_unit_names = Hashtbl.create 8 in
  List.iter
    (fun path ->
      Hashtbl.replace dropped_unit_names (module_name_of_path path) ())
    (Arch_index_cmt.dropped_unit_paths ()) ;
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
          (* [Fx3.G1.B.f] can be read several ways: compilation unit [Fx3]
             holding [G1.B.f], unit [G1] holding [B.f], or unit [B] holding
             [f].  Keeping only the last component -- the previous behaviour --
             picks the last reading, which binds to an unrelated [b.ml] that
             happens to define an [f] whenever one exists: a confident MUST edge
             to the wrong function.

             Nested definitions are indexed under their path, so the readings
             are tried from the most qualified function name to the least, and
             the first that resolves wins.  A name that resolves under no
             reading stays unresolved rather than being forced onto a homonym. *)
          let resolve_qualified mod_name name =
            let parts = String.split_on_char '.' mod_name in
            let rec try_from prefix rest =
              match rest with
              | [] -> None
              | unit_name :: deeper -> (
                  let qualified_name =
                    String.concat "." (deeper @ [name])
                  in
                  match Hashtbl.find_opt mod_name_to_path unit_name with
                  | Some mod_path -> (
                      match Hashtbl.find_opt fn_lookup (mod_path, qualified_name) with
                      | Some _ as found -> found
                      | None -> try_from (prefix @ [unit_name]) deeper)
                  | None -> try_from (prefix @ [unit_name]) deeper)
            in
            try_from [] parts
          in
          (* "Not in [fn_lookup]" has two very different causes, and the
             resolver above cannot tell them apart: the callee is genuinely
             outside the index (Stdlib, a C stub — a real leaf, and a MUST edge
             to it is honest), or it is an in-project body this run analysed and
             then failed to store. The second is not a leaf. Its body exists,
             nothing it calls is in the graph, and stopping reachability there
             is precisely the unsound answer — an UNREACHABLE verdict backed by
             a node whose code was never read.

             [Arch_index_cmt] records every such drop, so the two cases are
             distinguishable, and a known-dropped callee is recorded MAY_TOP:
             the ⊤ frontier marker, which turns that verdict into UNKNOWN. *)
          let dropped_local name =
            Arch_index_cmt.is_dropped_node
              ~module_path:call.caller_module
              ~name
          in
          (* The same readings [resolve_qualified] tries, asked of the dropped
             set instead of the stored one. A whole dropped unit is matched by
             name because it has no stored path to match by. *)
          let dropped_qualified mod_name name =
            let parts = String.split_on_char '.' mod_name in
            let rec try_from rest =
              match rest with
              | [] -> false
              | unit_name :: deeper ->
                  let qualified_name = String.concat "." (deeper @ [name]) in
                  Hashtbl.mem dropped_unit_names unit_name
                  || (match Hashtbl.find_opt mod_name_to_path unit_name with
                     | Some mod_path ->
                         Arch_index_cmt.is_dropped_node
                           ~module_path:mod_path
                           ~name:qualified_name
                     | None -> false)
                  || try_from deeper
            in
            try_from parts
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
                | None ->
                    (* A dropped candidate is not an enumerated one: its body is
                       unknown, so the honest kind is ⊤. *)
                    if dropped_local n then (None, n, "MAY_TOP")
                    else (None, n, "MAY_ENUMERATED"))
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
                    | None ->
                        if dropped_local n then (None, n, "MAY_TOP")
                        else
                          ( None,
                            n,
                            (if demoted then "MAY_ENUMERATED" else "MAY_TOP") ))
                | Some mod_name -> (
                    match resolve_qualified mod_name n with
                    | Some id -> incr n_resolved ; (Some id, display_name, kind)
                    | None ->
                        (* Unresolved. A genuine external is a leaf either way —
                           MUST leaf when unconditional, enumerated leaf when
                           demoted. A callee this run DROPPED only looks like
                           one: it is the ⊤ frontier, not a leaf, and claiming
                           MUST there would let a reachability query terminate
                           on a body nobody analysed. *)
                        if dropped_qualified mod_name n then
                          (None, display_name, "MAY_TOP")
                        else (None, display_name, kind)))
          in
          (match
             insert_call_rowid
               db
               stmt_call
               ~caller_id
               ~callee_id
               ~callee_name:callee_display_name
               ~call_site:(Some call.call_site)
               ~kind
           with
          | Some call_id -> (
              (* The handler scope enclosing THIS call site, linked to this
                 call's own rowid — the pair is written back to back so no
                 other insert can slip in between. *)
              match call.exn_scope with
              | Some scope_id ->
                  Arch_index_db.insert_call_exn_scope db stmt_call_scope ~call_id ~scope_id
              | None -> ())
          | None -> ()) ;
          (* R2: the call sits in a block unreachable from its function's CFG
             entry, so it can never execute. Recorded with its location — that
             is what makes the finding actionable. *)
          if call.dead then begin
            Arch_index_db.bind_int stmt_dead 1 caller_id ;
            Arch_index_db.bind_text stmt_dead 2 call.call_site ;
            Arch_index_db.bind_text stmt_dead 3 callee_display_name ;
            Arch_index_db.exec_stmt db ~what:"dead_code_sites" stmt_dead ;
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
  if Hashtbl.length fn_lookup > 0 then begin
    exec_exn db
      "INSERT OR REPLACE INTO comment_db_meta (key, value) VALUES \
       ('callgraph_contract', 'v1')" ;
    (* Exception sites were emitted for every indexed node by this same
       producer; the flag is what lets a query tell "nothing raises" from
       "nobody looked" (specs/exn-raise-sets.md). *)
    exec_exn db
      "INSERT OR REPLACE INTO comment_db_meta (key, value) VALUES \
       ('exn_contract', 'v1')"
  end ;
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
    n_statement_failures = Arch_index_db.statement_failures ();
    rejections_by_table = Arch_index_db.rejections_by_table ();
    db_path;
  }

module Arch_index_compare = Arch_index_compare
module Arch_index_git = Arch_index_git
module Arch_index_cfg = Arch_index_cfg
module Comment_parser = Comment_parser
module Language_registry = Language_registry
module Lsp_client = Lsp_client
module Lsp_types = Lsp_types
module Ocaml_enricher = Ocaml_enricher
module Db = Arch_index_db

(* -------------------------------------------------------------------------- *)
(* LSP-based run (Story #406 / #416)                                          *)
(* -------------------------------------------------------------------------- *)

let run_lsp = Runner.run
let run_lsp_multi = Runner.run_multi

(* -------------------------------------------------------------------------- *)
(* Schema version and shipped schema text (#51 part 1)                        *)
(* -------------------------------------------------------------------------- *)

let schema_version = Arch_index_db.current_schema_version
let schema_version_at_least = Arch_index_db.schema_version_at_least
let schema_sql = Arch_index_db.schema_sql
