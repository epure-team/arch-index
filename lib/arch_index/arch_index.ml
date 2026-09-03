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

(* -------------------------------------------------------------------------- *)
(* Error-channels config discovery/precedence (specs/error-channels.md,      *)
(* slice 0). No analysis change yet: builtin/profile/user declarations are   *)
(* parsed, merged and validated against the paths the walk actually saw, but *)
(* the producer still only ever emits the [exception] channel — [run] below  *)
(* hardcodes [error_contract = "v1:exception"] regardless of what the        *)
(* effective config declares.                                                *)
(* -------------------------------------------------------------------------- *)

(** [--errors-config <path>] > [arch-errors.toml] at the project root > none. *)
let discover_user_config ~project_root ~errors_config =
  match errors_config with
  | Some path -> Some path
  | None ->
      let candidate =
        if project_root = "" then "arch-errors.toml"
        else Filename.concat project_root "arch-errors.toml"
      in
      if Sys.file_exists candidate then Some candidate else None

(** [ARCH_ERRORS_PROFILES_DIR], then [<project root>/profiles], then
    [<exe dir>/../../../profiles] (dune's install layout) — first hit wins;
    the resolved path is printed (spec: "its path is printed"). *)
let discover_profile ~project_root ~name =
  let file = name ^ "-errors.toml" in
  let candidates =
    (match Sys.getenv_opt "ARCH_ERRORS_PROFILES_DIR" with
    | Some d -> [Filename.concat d file]
    | None -> [])
    @ (if project_root = "" then []
       else [Filename.concat (Filename.concat project_root "profiles") file])
    @ [
        Filename.concat
          (Filename.concat
             (Filename.dirname (Filename.dirname (Filename.dirname Sys.executable_name)))
             "profiles")
          file;
      ]
  in
  List.find_opt Sys.file_exists candidates

let read_file path =
  let ic = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () ->
      let n = in_channel_length ic in
      really_input_string ic n)

(** Load and merge the effective error-channels config: built-in < profile <
    user file, per Clarifications. Any parse failure (bad TOML, unknown key,
    unresolved [--errors-profile]) is fatal — printed and [exit 1] — since a
    silently-ignored bad config is exactly the "declaration matching
    nothing" bug class this feature exists to catch. Returns the effective
    config and the human-readable source description for
    [comment_db_meta.error_config_source]. *)
let load_errors_config ~project_root ~errors_config ~errors_profile =
  let acc = ref Arch_errors_config.builtin in
  let sources = ref ["builtin"] in
  (match errors_profile with
  | None -> ()
  | Some name -> (
      match discover_profile ~project_root ~name with
      | None ->
          Arch_io.eprintf
            "arch-errors: --errors-profile %s: no profiles/%s-errors.toml found (checked \
             ARCH_ERRORS_PROFILES_DIR, <project root>/profiles, <exe dir>/../../../profiles)\n"
            name
            name ;
          exit 1
      | Some path -> (
          Arch_io.printf "arch-errors: using profile %s\n%!" path ;
          match Arch_errors_config.of_toml (read_file path) with
          | Error msg ->
              Arch_io.eprintf "arch-errors: %s: %s\n" path msg ;
              exit 1
          | Ok cfg ->
              acc := Arch_errors_config.merge !acc cfg ;
              sources := path :: !sources))) ;
  (match discover_user_config ~project_root ~errors_config with
  | None -> ()
  | Some path -> (
      match Arch_errors_config.of_toml (read_file path) with
      | Error msg ->
          Arch_io.eprintf "arch-errors: %s: %s\n" path msg ;
          exit 1
      | Ok cfg ->
          acc := Arch_errors_config.merge !acc cfg ;
          sources := path :: !sources)) ;
  (!acc, String.concat "," (List.rev !sources))

let run ?(db_path = db_path) ?(schema_path = schema_path) ?errors_config ?errors_profile
    ?(errors_strict = false) ~build_dir () =
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
  (* Error-channels config (specs/error-channels.md slice 0): load/merge now,
     hand the walker a [seen] collector so every value/type path it visits
     can flip a declared-path found-flag, validate once the whole corpus has
     been walked. *)
  let errors_effective, error_config_source =
    load_errors_config ~project_root:!project_root ~errors_config ~errors_profile
  in
  let errors_seen = Arch_errors_config.create errors_effective in
  Arch_index_cmt.set_seen_collector (Some errors_seen) ;
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

  (* FIX (found while testing roadmap 1.2's producer_runs table, but
     pre-existing and independent of it — reproduces on plain `calls`/
     `functions` alone): with `PRAGMA foreign_keys = ON` (set above), SQLite
     refuses a `DROP TABLE` on a table some OTHER table's FK still declares a
     reference to, even via `IF EXISTS` — and once the referencing table
     itself has already been dropped earlier in this same loop, the error is
     the cryptic "no such table: main.<already-dropped-table>" rather than
     anything mentioning the table this statement is actually trying to
     drop. This made every re-index of an EXISTING (non-empty) database fail
     — the very case [backup_intents] above exists to support — and nothing
     caught it because no test had exercised a real double invocation
     against the same on-disk file before. Turn enforcement off for the
     drop-then-recreate cycle; architecture-schema.sql's own `PRAGMA
     foreign_keys = ON` turns it back on immediately after, so every insert
     below still enforces the FK. *)
  exec_exn db "PRAGMA foreign_keys = OFF" ;
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

  (* Roadmap 1.2 (ADR 002): one producer_runs row for this whole invocation.
     'sound_with_top' is a deliberate, explicit claim, not the module's
     conservative default — the CMT walker is the one producer in this
     codebase that marks unresolvable targets ⊤ rather than dropping them
     (see [lsp_edge_kind] in runner.ml for the contrasting case that keeps
     the conservative default). *)
  let producer_run_id =
    Arch_index_db.insert_producer_run
      db
      ~producer:"arch_index_cmt"
      ~invocation_digest:
        (Some
           (Arch_index_db.invocation_digest
              ~producer:"arch_index_cmt"
              ~producer_version:None
              (* [run]'s own parameters, not [Sys.argv]: this function is
                 published library surface (FIX above, review-round finding)
                 — a host process's argv does not vary between two [run]
                 calls with different [~build_dir], so hashing it would make
                 every invocation from the same process indistinguishable,
                 defeating the digest's one stated purpose. *)
              ~argv:[| build_dir; db_path; schema_path |]))
      ~soundness_class:"sound_with_top"
      ()
  in
  (* A rejected insert here is silent otherwise — every function/call row
     this run writes would carry NULL provenance with no local signal why,
     and [n_statement_failures] only surfaces post-hoc, per-table, with no
     mention of [producer_runs] specifically. This is a single, once-per-run
     insert, so failing loudly is cheap. *)
  if producer_run_id = None then
    Arch_io.eprintf
      "arch_index: warning: producer_runs insert failed — every row this run \
       writes will have NULL provenance\n" ;

  (* Prepare statements *)
  let stmt_mod =
    Sqlite3.prepare
      db
      "INSERT INTO modules (path, lines, last_analyzed, has_mli, \
       quint_module_raw, language) VALUES (?, ?, ?, ?, ?, ?)"
  in
  let stmt_fn =
    Sqlite3.prepare
      db
      "INSERT OR REPLACE INTO functions (module_id, name, signature, \
       line_start, line_end, exposed, intent, comment_quality_score, has_pre, \
       has_post, has_violators, has_violates, violators_raw, violates_raw, \
       tests_raw, quint_raw, mutation_sites, deref_sites, language, \
       producer_run_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, \
       ?, ?, ?, ?, ?)"
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
      "INSERT INTO calls (caller_id, callee_id, callee_name, call_site, kind, \
       producer_run_id, top_reason, top_anchor) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
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
       catch_all, channel) VALUES (?, ?, ?, ?, ?, ?, ?)"
  in
  let stmt_catch =
    Sqlite3.prepare db "INSERT INTO exn_scope_catches (scope_id, exn_path) VALUES (?, ?)"
  in
  let stmt_origin =
    Sqlite3.prepare
      db
      "INSERT INTO exn_origins (function_id, scope_id, form, exn_path, escapes, \
       line, col, channel) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
  in
  let stmt_rebind =
    Sqlite3.prepare
      db
      "INSERT OR IGNORE INTO exn_rebinds (alias_path, target_path) VALUES (?, ?)"
  in
  let stmt_call_scope =
    Sqlite3.prepare db "INSERT INTO call_exn_scopes (call_id, scope_id) VALUES (?, ?)"
  in
  let stmt_carrier =
    Sqlite3.prepare
      db
      "INSERT OR IGNORE INTO channel_carriers (function_id, channel) VALUES (?, ?)"
  in
  let stmt_edge =
    Sqlite3.prepare
      db
      "INSERT OR IGNORE INTO exn_edges (call_id, channel, role) VALUES (?, ?, ?)"
  in
  (* Value channels the producer actually analyses (specs/error-channels.md
     "Carrier check"): every declared channel with a non-empty carrier
     [type_paths] — [exception] (a marker with none) is excluded, it stays
     the untouched [lexn]/[calls]-based path above. *)
  let value_channels =
    List.filter
      (fun (c : Arch_errors_config.channel) -> c.type_paths <> [])
      errors_effective.Arch_errors_config.channels
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
            ~value_channels
            ~stmt_carrier
            ~producer_run_id
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

  (* The walk is over: stop feeding [errors_seen] (a run-scoped collector;
     nothing else must mutate it after this point) and check every declared
     path against what was actually seen. FR-023: a per-path miss is a
     warning (recorded below); a channel whose whole carrier type matched
     nothing, or any miss under [--errors-strict], is fatal — exit 1 naming
     it, since a silently-inert declaration is precisely the bug class this
     feature exists to catch.

     DECISION (slice 0, no spec scenario covers it): the loud "carrier type
     matched nothing" abort is for a declaration the user (or a shipped
     profile) wrote and got wrong — not for the pure built-in defaults
     applying to a corpus too small to use [result]/[option] at all (every
     tezt OCaml fixture; some of épure's own tiny units). Skip validation
     entirely when no [arch-errors.toml]/profile was ever loaded
     ([error_config_source = "builtin"]): AC-15 scenario 1 only requires
     [error_contract]/[error_config_source] for that case, and "the
     built-ins didn't fire on a corpus with no result/option" is not the bug
     class FR-023 exists to catch. Any real config file re-enables full
     validation, builtins included, since [merge] can fold user overrides
     into them. *)
  Arch_index_cmt.set_seen_collector None ;
  let builtin_names =
    List.map (fun (c : Arch_errors_config.channel) -> c.name) Arch_errors_config.builtin.channels
  in
  (if error_config_source <> "builtin" then
     match
       Arch_errors_config.validate errors_effective errors_seen ~strict:errors_strict
         ~builtin_names ()
     with
     | Error msg ->
         Arch_io.eprintf "%s\n" msg ;
         exit 1
     | Ok () -> ()) ;
  let error_config_unmatched = String.concat "," (Arch_errors_config.unmatched errors_seen) in
  let error_config_digest = Arch_errors_config.digest errors_effective in
  (* [error_summaries] (specs/error-channels.md FR-031, slice 5): the
     [[summaries]] table, serialised so [Arch_tools.Arch_exn] — which does
     NOT depend on [otoml]/[Arch_errors_config] — can decode it at query
     time without re-reading the config file. One line per callee: TAB
     separates the callee path from its per-channel lists; each channel
     entry is [name:path1,path2] joined by [|]. OCaml paths never contain
     tab/newline/comma/pipe/colon-as-separator (dots and backticks only), so
     no escaping is needed. *)
  let error_summaries =
    String.concat "\n"
      (List.map
         (fun (callee, chans) ->
           callee ^ "\t"
           ^ String.concat "|"
               (List.map (fun (c, paths) -> c ^ ":" ^ String.concat "," paths) chans))
         errors_effective.Arch_errors_config.summaries)
  in
  (* [error_contract]: [exception] (frozen, always emitted, FR-029's
     byte-identical requirement) plus every value channel that matched at
     least one carrier type in the corpus — the Clarifications table's
     "built-in channels that match nothing" rule: an unmatched BUILT-IN
     channel is simply not emitted (never fatal); a channel from a FILE
     that matches nothing is already fatal above, so by this point every
     surviving file-sourced channel matched something too. A channel with
     no [type_paths] at all (only [exception]) trivially "matches". *)
  let channel_emitted (c : Arch_errors_config.channel) =
    c.Arch_errors_config.type_paths = []
    || List.exists (fun p -> not (List.mem p (Arch_errors_config.unmatched errors_seen))) c.type_paths
  in
  let error_contract =
    "v1:"
    ^ String.concat
        ","
        ("exception"
        :: List.filter_map
             (fun (c : Arch_errors_config.channel) ->
               if channel_emitted c then Some c.Arch_errors_config.name else None)
             value_channels)
  in
  (* Bound, not sprintf'd, into the SQL text: [error_config_source] and
     [error_config_unmatched] embed filesystem paths, which may contain a
     single quote. *)
  let stmt_meta =
    Sqlite3.prepare db "INSERT OR REPLACE INTO comment_db_meta (key, value) VALUES (?, ?)"
  in
  List.iter
    (fun (key, value) ->
      Arch_index_db.bind_text stmt_meta 1 key ;
      Arch_index_db.bind_text stmt_meta 2 value ;
      Arch_index_db.exec_stmt db ~what:"comment_db_meta" stmt_meta)
    [
      ("error_contract", error_contract);
      ("error_config_digest", error_config_digest);
      ("error_config_source", error_config_source);
      ("error_config_unmatched", error_config_unmatched);
      ("error_summaries", error_summaries);
    ] ;

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
          (* Roadmap 1.4 (⊤-anchor taxonomy): [top_reason] is [None] whenever
             [kind] is not "MAY_TOP" (the column is meaningless for a
             resolved or bounded-candidate edge), [Some <reason>] otherwise.
             [Dropped_node] always wins over the head's own carried reason —
             it is the MORE SPECIFIC explanation ("this callee's row/unit was
             rejected this run") wherever it applies, not a fallback. *)
          let callee_id, callee_display_name, kind, top_reason =
            match call.head with
            | Arch_index_cmt.Head_unknown (n, reason) ->
                (None, n, "MAY_TOP", Some (Arch_index_cmt.top_reason_to_string reason))
            | Arch_index_cmt.Head_enumerated n -> (
                (* A named local function passed as a callback — resolve it to a
                   node so the closure can follow it, but as MAY_ENUMERATED (the
                   callee may or may not invoke it), never MUST — conditional or
                   not, the candidate set is the same. *)
                match resolve_local n with
                | Some id -> incr n_resolved ; (Some id, n, "MAY_ENUMERATED", None)
                | None ->
                    (* A dropped candidate is not an enumerated one: its body is
                       unknown, so the honest kind is ⊤. *)
                    if dropped_local n then (None, n, "MAY_TOP", Some "dropped_node")
                    else (None, n, "MAY_ENUMERATED", None))
            | Arch_index_cmt.Head_local n -> (
                match resolve_local n with
                | Some id ->
                    incr n_resolved ;
                    (Some id, n, (if demoted then "MAY_ENUMERATED" else "MUST"), None)
                | None ->
                    (* FIX (review, HIGH): this branch (a same-module name
                       that failed to resolve) is exactly where a genuinely
                       DROPPED function lands, same as every other unresolved
                       branch in this match — it must check [dropped_local]
                       too, not default straight to [callback_param]. [kind]
                       is "MAY_TOP" either way, so this changes only
                       [top_reason], with zero soundness risk. *)
                    if dropped_local n then (None, n, "MAY_TOP", Some "dropped_node")
                    else (None, n, "MAY_TOP", Some "callback_param"))
            | Arch_index_cmt.Head_qualified (mod_opt, n) -> (
                let display_name =
                  match mod_opt with Some m -> m ^ "." ^ n | None -> n
                in
                let kind = if demoted then "MAY_ENUMERATED" else "MUST" in
                match mod_opt with
                | None -> (
                    match resolve_local n with
                    | Some id -> incr n_resolved ; (Some id, n, kind, None)
                    | None ->
                        if dropped_local n then (None, n, "MAY_TOP", Some "dropped_node")
                        else
                          ( None,
                            n,
                            (if demoted then "MAY_ENUMERATED" else "MAY_TOP"),
                            (if demoted then None else Some "callback_param") ))
                | Some mod_name -> (
                    match resolve_qualified mod_name n with
                    | Some id -> incr n_resolved ; (Some id, display_name, kind, None)
                    | None ->
                        (* Unresolved. A genuine external is a leaf either way —
                           MUST leaf when unconditional, enumerated leaf when
                           demoted. A callee this run DROPPED only looks like
                           one: it is the ⊤ frontier, not a leaf, and claiming
                           MUST there would let a reachability query terminate
                           on a body nobody analysed. *)
                        if dropped_qualified mod_name n then
                          (None, display_name, "MAY_TOP", Some "dropped_node")
                        else (None, display_name, kind, None)))
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
               ~top_reason
               (* FIX (review, LOW): key on [kind] directly, not [top_reason]
                  — states the actual invariant (top_anchor is meaningful
                  exactly when kind is MAY_TOP) rather than relying on
                  top_reason always agreeing with it, which a future branch
                  could get wrong independently. *)
               ~top_anchor:(if kind = "MAY_TOP" then Some call.call_site else None)
               ~producer_run_id
               ()
           with
          | Some call_id -> (
              (* The handler scope enclosing THIS call site, linked to this
                 call's own rowid — the pair is written back to back so no
                 other insert can slip in between. *)
              (match call.exn_scope with
              | Some scope_id ->
                  Arch_index_db.insert_call_exn_scope db stmt_call_scope ~call_id ~scope_id
              | None -> ()) ;
              (* Propagating value-channel edge (specs/error-channels.md
                 "Propagating edges"): only once the callee's resolution is
                 known, so a call to a DROPPED node — genuinely a c-carrier,
                 its body just was not stored — still counts (the edge row
                 exists independent of [callee_id]; the query's own ⊤
                 handling for a MAY_TOP/unresolved callee already covers it,
                 same as the exception channel). *)
              match call.errch_propagates with
              | Some channel ->
                  Arch_index_db.insert_exn_edge db stmt_edge ~call_id ~channel ~role:"propagates"
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
module Coverage_matrix = Coverage_matrix
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
