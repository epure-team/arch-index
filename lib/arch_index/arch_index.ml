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
  (* Module name -> EVERY path carrying that basename.

     This used to be [Hashtbl.replace name path] — one path per capitalised
     basename, last writer wins, silently. Two modules named `api.ml` in two
     libraries collapse to one entry, and every qualified reference to `Api`
     from anywhere resolves to whichever the scan happened to reach last. That
     is not a missing edge: it is a MUST edge, confidently pointing at the wrong
     function. Reachability gets forged toward the survivor and lost from the
     losers, and the verdict says `sound`.

     Keeping the whole list lets the resolvers below bind a reference to the
     whole CANDIDATE SET when the name does not designate a single module —
     one MAY_ENUMERATED edge per candidate, never one arbitrary member and
     never MUST. The set is guaranteed to contain the true target, which is
     what makes it sound: `reaches` walks MUST edges only and so cannot forge a
     path through it, while `unreachable`/`escapes`/`arch-rules` traverse all of
     them and stay correct.

     Resolving BY UNIT IDENTITY would collapse most sets to one member: dune
     mangles these to `Rootlib__Api` and `Sublib__Api` and the .cmt files carry
     it. That is the follow-up. Ambiguity that survives it — two
     `(wrapped false)` libraries, two vendored copies of one library — is
     permanent, so the candidate set is not scaffolding. *)
  let mod_name_to_paths : (string, string list) Hashtbl.t = Hashtbl.create 128 in
  ignore
    (Sqlite3.exec_not_null
       db
       ~cb:(fun row _h ->
         let path = row.(0) in
         let base = Filename.basename path in
         let name = Filename.remove_extension base |> String.capitalize_ascii in
         let prev =
           match Hashtbl.find_opt mod_name_to_paths name with
           | Some l -> l
           | None -> []
         in
         Hashtbl.replace mod_name_to_paths name (path :: prev))
       "SELECT path FROM modules") ;
  let n_ambiguous = ref 0 in
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
          (* Returns EVERY function this reference could designate, under the
             most qualified reading that matches anything.

             The candidates are the modules sharing the referenced basename that
             actually DEFINE the function — the module map is ambiguous, the
             function set usually is not: two libraries with an `api.ml` where
             only one defines `run` leave exactly one candidate, and refusing
             there would throw away a resolution nothing was ambiguous about. *)
          let resolve_qualified mod_name name =
            let parts = String.split_on_char '.' mod_name in
            let rec try_from rest =
              match rest with
              | [] -> []
              | unit_name :: deeper -> (
                  let qualified_name = String.concat "." (deeper @ [name]) in
                  let paths =
                    match Hashtbl.find_opt mod_name_to_paths unit_name with
                    | Some l -> l
                    | None -> []
                  in
                  let defining =
                    List.filter
                      (fun p -> Hashtbl.mem fn_lookup (p, qualified_name))
                      paths
                  in
                  (* NO directory heuristic here, and that is a decision.

                     An earlier version narrowed these candidates by matching
                     the already-consumed components against the module's
                     directory segments — `Sublib` picking `sublib/api.ml` — on
                     the grounds that dune lays a library out under a directory
                     of its name. It is a convention, not a guarantee, and when
                     it is wrong it is wrong in the worst possible way: library
                     `q` living in `alt/` and library `qq` living in `q/` makes
                     the filter elect `q/api.ml` for `Q.Api.beta` and stamp it
                     MUST — a forged proof pointing at another library, which is
                     the exact defect this whole commit removes, re-created by
                     its own fix. The comment there claimed the narrowing "can
                     gain precision, never invent it"; it invents.

                     So the candidate set stands as it is. It is guaranteed to
                     CONTAIN the true target, which is what makes it sound. *)
                  let ids ps =
                    List.filter_map
                      (fun p -> Hashtbl.find_opt fn_lookup (p, qualified_name))
                      ps
                  in
                  match defining with
                  | [] -> try_from deeper
                  | found -> ids found)
            in
            try_from parts
          in
          let demoted = call.cond || call.partial in
          (* A list, because an ambiguous reference emits ONE ROW PER CANDIDATE
             rather than a single row that lies.

             The first attempt at this refused instead — callee_id NULL — and
             that was bit-for-bit the encoding of an EXTERNAL LEAF (`Stdlib.+`),
             so `arch-rules` answered `pass` ("proved unreachable in a closed
             universe") and `unreachable` answered "sound" on a fixture whose
             caller literally calls the other library. A confident-wrong absence
             replacing a confident-wrong edge.

             MAY_ENUMERATED is the contract's own word for "bounded to a known
             candidate set", which is exactly what this is. It is the sound
             direction: `reaches` walks MUST edges only, so an enumerated set
             can never forge a must-path, while `unreachable`/`escapes`/rules —
             the over-approximating side — traverse all of them and stay
             correct. The schema already carries several rows per call site
             (argument escapes emit them routinely), so this needs no migration. *)
          let outcomes =
            match call.head with
            | Arch_index_cmt.Head_unknown n -> [(None, n, "MAY_TOP")]
            | Arch_index_cmt.Head_enumerated n -> (
                (* A named local function passed as a callback — resolve it to a
                   node so the closure can follow it, but as MAY_ENUMERATED (the
                   callee may or may not invoke it), never MUST — conditional or
                   not, the candidate set is the same. *)
                match resolve_local n with
                | Some id -> incr n_resolved ; [(Some id, n, "MAY_ENUMERATED")]
                | None -> [(None, n, "MAY_ENUMERATED")])
            | Arch_index_cmt.Head_local n -> (
                match resolve_local n with
                | Some id ->
                    incr n_resolved ;
                    [(Some id, n, (if demoted then "MAY_ENUMERATED" else "MUST"))]
                | None ->
                    (* Not in the function table (shadow/anomaly): unknowable. *)
                    [(None, n, "MAY_TOP")])
            | Arch_index_cmt.Head_qualified (mod_opt, n) -> (
                let display_name =
                  match mod_opt with Some m -> m ^ "." ^ n | None -> n
                in
                let kind = if demoted then "MAY_ENUMERATED" else "MUST" in
                match mod_opt with
                | None -> (
                    match resolve_local n with
                    | Some id -> incr n_resolved ; [(Some id, n, kind)]
                    | None -> [(None, n, (if demoted then "MAY_ENUMERATED" else "MAY_TOP"))])
                | Some mod_name -> (
                    match resolve_qualified mod_name n with
                    | [id] -> incr n_resolved ; [(Some id, display_name, kind)]
                    | [] ->
                        (* Unresolved external: a leaf either way — MUST leaf
                           when unconditional, enumerated leaf when demoted. *)
                        [(None, display_name, kind)]
                    | ids ->
                        (* Several modules share the basename AND define the
                           name: the reference designates one of them and we
                           cannot tell which, so record the whole candidate set.
                           Never MUST — no single one of these is guaranteed. *)
                        (* Counted per ROW, because [n_calls] — the denominator
                           it is printed against, "N calls (M resolved to known
                           functions)" — is incremented per row below. Counting
                           sites here instead would make the fraction compare a
                           site count to a row count; the number of SITES that
                           are ambiguous is what [n_ambiguous] reports on its
                           own line. *)
                        incr n_ambiguous ;
                        n_resolved := !n_resolved + List.length ids ;
                        List.map
                          (fun id -> (Some id, display_name, "MAY_ENUMERATED"))
                          ids))
          in
          List.iter
            (fun (callee_id, callee_display_name, kind) ->
              insert_call
                db
                stmt_call
                ~caller_id
                ~callee_id
                ~callee_name:callee_display_name
                ~call_site:(Some call.call_site)
                ~kind ;
              incr n_calls)
            outcomes ;
          (* R2: the call sits in a block unreachable from its function's CFG
             entry, so it can never execute. Recorded with its location — that
             is what makes the finding actionable. Once per SITE, not per
             candidate: the finding is about the site. *)
          if call.dead then begin
            let _, display, _ = List.hd outcomes in
            Arch_index_db.bind_int stmt_dead 1 caller_id ;
            Arch_index_db.bind_text stmt_dead 2 call.call_site ;
            Arch_index_db.bind_text stmt_dead 3 display ;
            Arch_index_db.exec_stmt db stmt_dead ;
            incr n_dead_sites
          end)
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
  if !n_ambiguous > 0 then
    (* Named out loud: an enumerated candidate set is a weaker answer than a
       resolved edge, and silence would let it pass for one. *)
    Arch_io.printf
      "  %d call site(s) bound to a CANDIDATE SET rather than one function: the \
       qualified name designates two or more modules sharing a basename\n%!"
      !n_ambiguous ;

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
  (* [mod_name_to_paths] is already built above from the same table and the
     modules set has not changed since; this block used to rebuild it with the
     same last-writer-wins collapse. *)
  let n_deps_ambiguous = ref 0 in
  List.iter
    (fun (dep : pending_dep) ->
      match Hashtbl.find_opt mod_path_to_id dep.source_module with
      | None -> ()
      | Some source_id ->
          (* Every module the written path could designate, not one guess and
             not a refusal. The refusal shipped in the first draft of this
             commit and a review caught it here after it had been fixed for
             calls: an unresolved dep degrades to its dotted string, so a
             path-shaped `forbid dep` selector stops matching and the rule goes
             green — on a fixture whose source literally contains
             `open Sublib.Api`. One row per candidate keeps the true target in
             the table, which is what the rule needs to see. *)
          let targets =
            let name =
              List.hd (List.rev (String.split_on_char '.' dep.target_path))
            in
            match Hashtbl.find_opt mod_path_to_id dep.target_path with
            | Some id -> [Some id]
            | None -> (
                let paths =
                  match Hashtbl.find_opt mod_name_to_paths name with
                  | Some l -> l
                  | None -> []
                in
                match List.filter_map (Hashtbl.find_opt mod_path_to_id) paths with
                | [] -> [None]
                | [one] -> [Some one]
                | several ->
                    incr n_deps_ambiguous ;
                    List.map (fun id -> Some id) several)
          in
          n_deps_resolved :=
            !n_deps_resolved + List.length (List.filter (fun t -> t <> None) targets) ;
          List.iter
            (fun target_module ->
              insert_module_dep
                db
                stmt_dep
                ~source_module:source_id
                ~target_module
                ~target_path:dep.target_path
                ~dep_kind:dep.dep_kind
                ~alias_name:dep.alias_name
                ~line_number:dep.line_number ;
              incr n_deps)
            targets)
    !all_pending_deps ;
  exec_exn db "COMMIT" ;
  Arch_io.printf
    "Inserted %d module deps (%d resolved to known modules)\n%!"
    !n_deps
    !n_deps_resolved ;
  if !n_deps_ambiguous > 0 then
    Arch_io.printf
      "  %d module dep(s) bound to a CANDIDATE SET for the same reason: one row \
       per candidate module\n%!"
      !n_deps_ambiguous ;

  (* Resolve and insert type usages *)
  Arch_io.printf
    "Resolving %d type usages...\n%!"
    (List.length !all_pending_type_usages) ;
  exec_exn db "BEGIN TRANSACTION" ;
  let n_type_usages = ref 0 in
  let n_type_usages_resolved = ref 0 in
  let n_types_ambiguous = ref 0 in
  let type_lookup = Hashtbl.create 256 in
  ignore
    (Sqlite3.exec_not_null
       db
       ~cb:(fun row _h ->
         let type_id = int_of_string row.(0) in
         let type_name = row.(1) in
         let mod_path = row.(2) in
         (* Keyed by module PATH, not by capitalised basename. The basename key
            was a third instance of the same last-writer-wins collapse fixed for
            calls and module deps in this commit — and the worst of the three,
            because the lookup below then kept only the LAST component of the
            written prefix, discarding the very library name that tells the two
            apart. `use (x : Api.t)` in rootlib recorded sublib's `t`. *)
         Hashtbl.replace type_lookup (mod_path, type_name) type_id)
       "SELECT t.id, t.name, m.path FROM types t JOIN modules m ON t.module_id \
        = m.id") ;
  List.iter
    (fun (usage : pending_type_usage) ->
      let mod_parts, type_name =
        match String.rindex_opt usage.type_path '.' with
        | Some idx ->
            let prefix = String.sub usage.type_path 0 idx in
            let name =
              String.sub
                usage.type_path
                (idx + 1)
                (String.length usage.type_path - idx - 1)
            in
            (String.split_on_char '.' prefix, name)
        | None -> ([], usage.type_path)
      in
      let type_id =
        (* Same candidate rule as for calls: the modules whose basename matches
           the last written component AND define the type. *)
        match List.rev mod_parts with
        | [] -> None
        | last :: _ -> (
            let paths =
              match Hashtbl.find_opt mod_name_to_paths last with
              | Some l -> l
              | None -> []
            in
            let defining =
              List.filter (fun p -> Hashtbl.mem type_lookup (p, type_name)) paths
            in
            (* No directory heuristic, for the reason given on the call path.
               A type usage has one FK and no candidate-set kind to fall back
               on, so an ambiguous one stays unresolved — under-approximate,
               and type_usage feeds no soundness closure. *)
            match defining with
            | [one] ->
                incr n_type_usages_resolved ;
                Hashtbl.find_opt type_lookup (one, type_name)
            | [] -> None
            | _ ->
                incr n_types_ambiguous ;
                None)
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
  if !n_types_ambiguous > 0 then
    Arch_io.printf
      "  %d type usage(s) left unresolved: the written path designates two or \
       more modules sharing a basename\n%!"
      !n_types_ambiguous ;

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
