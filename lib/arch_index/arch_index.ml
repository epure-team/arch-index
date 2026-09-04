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

(** [ARCH_ERRORS_PROFILES_DIR], then [<project root>/profiles], then a
    [profiles/] directory in any ancestor of the executable — first hit wins;
    the resolved path is printed (spec: "its path is printed").

    FIX: [project_root] is the root of the project being ANALYSED, not of
    arch-index, so for the shipped Tezos profile the second candidate is
    [<tezos>/profiles] — which does not exist. That left the exe-relative
    fallback as the only one that can ever find a shipped profile, and it was
    off by one: [dirname^3] of [_build/default/bin/<tool>/<tool>.exe] is
    [_build/], not the repository root. `--errors-profile tezos` therefore
    failed on every external corpus — precisely the case a shipped profile
    exists for. Walking ancestors instead of hardcoding a depth also covers an
    installed layout, where the distance from the binary to its data
    directory differs from dune's. *)
let discover_profile ~project_root ~name =
  let file = name ^ "-errors.toml" in
  (* Ancestors of the executable's directory, nearest first, bounded so a
     binary run from / cannot walk the whole filesystem. *)
  let exe_ancestors =
    let rec up acc dir n =
      if n <= 0 then List.rev acc
      else
        let parent = Filename.dirname dir in
        if parent = dir then List.rev acc else up (parent :: acc) parent (n - 1)
    in
    let exe_dir = Filename.dirname Sys.executable_name in
    exe_dir :: up [] exe_dir 6
  in
  let candidates =
    (match Sys.getenv_opt "ARCH_ERRORS_PROFILES_DIR" with
    | Some d -> [Filename.concat d file]
    | None -> [])
    @ (if project_root = "" then []
       else [Filename.concat (Filename.concat project_root "profiles") file])
    @ List.map (fun d -> Filename.concat (Filename.concat d "profiles") file) exe_ancestors
  in
  List.find_opt Sys.file_exists candidates

(* The DELETE, built from [Arch_index_support.completion_marker_keys] rather
   than respelled. Two call sites use it (before the schema is demolished and
   after it is recreated), and a marker added to that list is covered by both
   without touching either. *)
let delete_completion_markers_sql () =
  Printf.sprintf
    "DELETE FROM comment_db_meta WHERE key IN (%s)"
    (String.concat ", "
       (List.map
          (fun k -> "'" ^ k ^ "'")
          Arch_index_support.completion_marker_keys))

let read_file path =
  let ic = open_in path in
  Fun.protect
    ~finally:(fun () -> close_in ic)
    (fun () ->
      let n = in_channel_length ic in
      really_input_string ic n)

(* [--errors-config <path>] is a USER-typed path, unlike [--errors-profile]
   (resolved via [discover_profile], which already checks [Sys.file_exists]
   before ever calling [read_file]) — a typo here must be the same clean
   "arch-errors: ... exit 1" FR-021 promises for every other config
   failure, not an uncaught [Sys_error] backtrace at exit code 125. *)
let read_file_or_die path =
  try read_file path
  with Sys_error msg ->
    Arch_io.eprintf "arch-errors: --errors-config %s: %s\n" path msg ;
    exit 1

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
  (* Paths the operator's own FILES spell, accumulated as each is parsed —
     the merged config cannot tell them from the built-ins' inherited
     vocabulary, and [--errors-strict] must only ever fail on the former. *)
  let operator_paths = ref [] in
  (match errors_profile with
  | None -> ()
  | Some name -> (
      match discover_profile ~project_root ~name with
      | None ->
          Arch_io.eprintf
            "arch-errors: --errors-profile %s: no profiles/%s-errors.toml found (checked \
             ARCH_ERRORS_PROFILES_DIR, <analysed project root>/profiles, and profiles/ in \
             each ancestor of the executable)\n"
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
              operator_paths := Arch_errors_config.declared_paths cfg @ !operator_paths ;
              sources := path :: !sources))) ;
  (match discover_user_config ~project_root ~errors_config with
  | None -> ()
  | Some path -> (
      match Arch_errors_config.of_toml (read_file_or_die path) with
      | Error msg ->
          Arch_io.eprintf "arch-errors: %s: %s\n" path msg ;
          exit 1
      | Ok cfg ->
          acc := Arch_errors_config.merge !acc cfg ;
          operator_paths := Arch_errors_config.declared_paths cfg @ !operator_paths ;
          sources := path :: !sources)) ;
  (!acc, String.concat "," (List.rev !sources), !operator_paths)

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
  let errors_effective, error_config_source, errors_operator_paths =
    load_errors_config ~project_root:!project_root ~errors_config ~errors_profile
  in
  (* Reachability is a property of the CONFIG alone, so it is decided before
     a single .cmt is read — unlike the found-flag validation below, which
     needs the whole corpus walked first. A channel shadowed by an earlier
     one would otherwise be published in [error_contract] and answer
     NOT_A_CARRIER for every function in the corpus: a claim about the code,
     from a channel that was never applicable (review round 1, HIGH). *)
  (match Arch_errors_config.check_reachable errors_effective with
  | Error msg ->
      Arch_io.eprintf "%s\n" msg ;
      exit 1
  | Ok () -> ()) ;
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
  (* FIX (review round 3, H1): clear the completion markers BEFORE the schema
     is demolished, not only after it is rebuilt.

     Deleting them after the recreate (below) leaves a ~10ms window in which
     the evidence tables are already gone and the markers are still present —
     the same lie as the original bug, in a narrower slice. Reproduced on the
     FIXED binary: 12 hits in 60 SIGKILL attempts uniformly in [0.018, 0.032]s
     left no [functions] table and all three markers, and on that captured
     state `arch-coverage-matrix` — the consumer this exists to protect —
     answered `ocaml callgraph: covered`.

     [comment_db_meta] may not exist yet on a fresh database, and this runs
     before the schema is created, so the delete cannot use [exec_exn]: it is
     gated on the table actually being there. The post-recreate delete is kept
     as well — belt and braces, and it is the one that runs when this branch is
     skipped. *)
  (* [Sqlite3.exec], not [exec_exn]: on a fresh database [comment_db_meta] does
     not exist yet and the statement legitimately fails. There is nothing to
     clear in that case, which is exactly the state we want. The post-recreate
     call below DOES use [exec_exn], so a genuine failure against a table that
     exists is still fatal — this call is the early half of a belt-and-braces
     pair, not the only one. *)
  ignore (Sqlite3.exec db (delete_completion_markers_sql ())) ;

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

  (* FIX (review round 2, CRITICAL): clear every COMPLETION MARKER before the
     run does any work.

     Moving [error_contract] after its transaction (below) made its presence
     honest only on a FRESH database. On a RE-INDEX — the case that actually
     occurs, since nobody re-indexes into an empty file — the PREVIOUS run's
     marker is still on disk, and nothing here removed it: [comment_db_meta]
     is deliberately outside [schema_tables_to_drop] (the [self_managed]
     allowlist in tezt/tests/schema_drop_list.ml), justified there by "INSERT
     OR REPLACE, so a re-index overwrites it". That justification holds only
     for a run that REACHES the write. A producer killed mid-analysis never
     reaches it, so the stale marker survives and answers for a run that
     produced nothing — reproduced with SIGKILL at five different instants,
     each leaving the contract present against zero rows.

     [INSERT OR REPLACE] can keep a key CURRENT at the end of a successful
     run; it cannot make that key's PRESENCE meaningful. Only deleting it up
     front can, which is what this does.

     All three markers are one class and share the failure — fixing only
     [error_contract] would leave two siblings lying on exactly the same kill.
     They are cleared here, in the same autocommitted step as the schema
     drop/recreate above and before the first BEGIN TRANSACTION, so the window
     in which a marker can outlive its evidence does not exist. *)
  exec_exn db (delete_completion_markers_sql ()) ;

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
         ~builtin_names ~operator_paths:errors_operator_paths ()
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
    (* [error_contract] is deliberately NOT written here — see below, after the
       call/exn transaction commits. The [error_config_*] keys describe the
       CONFIG, which is fully known at this point, so they stay. *)
    [
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
  let stored_module_paths = ref [] in
  ignore
    (Sqlite3.exec_not_null
       db
       ~cb:(fun row _h ->
         let path = row.(0) in
         stored_module_paths := path :: !stored_module_paths ;
         Hashtbl.replace mod_name_to_path (module_name_of_path path) path)
       "SELECT path FROM modules") ;
  (* Roadmap 1.6 (R3 detector). The unit-name registry is populated at the only
     [insert_module] call site, so it should be COMPLETE with respect to the
     stored [modules] rows. If it ever is not, every qualified reference into the
     missing unit stops resolving and — because an unresolved qualified head
     falls through to the external-leaf arm — is emitted as kind=MUST with a NULL
     callee: a resolver miss dressed as a proven external leaf, which is exactly
     the shape the abandoned branch shipped 582 of.

     That failure is silent by nature, so it gets a loud counter rather than
     trust. Reported, not raised: a diagnostic that aborts indexing would turn a
     precision bug into an outage, and the number is actionable on its own. *)
  let registry_gaps =
    List.filter
      (fun path ->
        not
          (List.exists
             (fun unit_name ->
               List.mem path (Arch_index_cmt.paths_of_unit unit_name))
             (Arch_index_cmt.known_unit_names ())))
      !stored_module_paths
  in
  if registry_gaps <> [] then
    Arch_io.eprintf
      "WARNING: %d stored module(s) have no compilation-unit-name entry, so \
       every qualified reference into them will fail to resolve and be emitted \
       as a MUST external leaf: %s\n"
      (List.length registry_gaps)
      (String.concat ", " registry_gaps) ;
  (* Compilation units whose [modules] row was rejected have no path in
     [mod_name_to_path] — the table is built from STORED rows — so they must be
     recognised by name. Derived through the same function as the stored names
     so the two agree by construction. *)
  let dropped_unit_names = Hashtbl.create 8 in
  List.iter
    (fun path ->
      Hashtbl.replace dropped_unit_names (module_name_of_path path) ())
    (Arch_index_cmt.dropped_unit_paths ()) ;
  (* Roadmap 1.6 (S7, found by the proto_alpha corpus run — see the resolver
     below). A reference can reach a module through a RE-EXPORT FACADE that
     lives in a DIFFERENT library, and then the reference and the defining unit
     share no prefix at all:

       reference:      Tezos_protocol_alpha.Protocol.Script_int.of_zint
       defining unit:  Tezos_raw_protocol_alpha__Script_int   (script_int.ml)

     [tezos_protocol_alpha] re-exports [tezos_raw_protocol_alpha] through a
     nested module [Protocol]. No "__"-join of a PREFIX of the reference can
     ever name that unit, so the prefix readings alone cannot bridge it — and
     the old bare-segment walk bridged it only as a side effect of the same
     basename erasure that mis-attributed homonyms.

     Index every known unit by its LAST "__" component, so a bare module name
     can find the units that could define it. Unlike the old basename table
     this is a MULTI-map: when several libraries define a [Script_int], all of
     them are candidates and the function table arbitrates, rather than one
     silently overwriting the other. *)
  let unit_last_component unit_name =
    let n = String.length unit_name in
    let rec go i last =
      if i + 1 >= n then last
      else if unit_name.[i] = '_' && unit_name.[i + 1] = '_' then go (i + 2) (i + 2)
      else go (i + 1) last
    in
    (* A wrapper spelled [Lib__] has no component after the separator; it names
       itself. Guarding on [j < n] also keeps [String.sub] total. *)
    let j = go 0 0 in
    if j > 0 && j < n then String.sub unit_name j (n - j) else unit_name
  in
  let units_by_last_component : (string, string list) Hashtbl.t = Hashtbl.create 128 in
  List.iter
    (fun unit_name ->
      let key = unit_last_component unit_name in
      let existing =
        Option.value ~default:[] (Hashtbl.find_opt units_by_last_component key)
      in
      Hashtbl.replace units_by_last_component key (unit_name :: existing))
    (Arch_index_cmt.known_unit_names ()) ;
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
          (* Roadmap 1.6. Every way of reading [Root.File.…] as (compilation
             unit, name within it).

             dune spells a wrapped library's module [Lib__Mod], so a reference
             [A.B.c] can mean unit [A] holding a nested [B.c], or unit [A__B]
             holding [c] — and for deeper qualification, any split in between
             (nested wrappers, [include_subdirs qualified]). Which one holds is
             not decidable from the reference alone, so all are enumerated and
             the FUNCTION TABLE decides, below.

             The candidate unit is always the "__"-join of a PREFIX. A bare
             later segment is deliberately never a candidate: that was the old
             behaviour, and it is precisely the erasure this change removes —
             looking up bare ["Api"] is what let [Liba.Api.run] land in
             libb/api.ml. *)
          let unit_readings mod_name name =
            let parts = String.split_on_char '.' mod_name in
            let rec go acc prefix_rev rest =
              match rest with
              | [] -> List.rev acc
              | seg :: deeper ->
                  let prefix_rev = seg :: prefix_rev in
                  (* Join on "__", EXCEPT after a segment that already ends in
                     "__". dune names a library's wrapper after the library
                     ([Arch_index]) unless one of its own modules already owns
                     that exact name — a library's "main module" — in which case
                     the wrapper is disambiguated to [Arch_index__]. External
                     references then spell it [Arch_index__.Arch_index_db], and
                     a naive "__"-join yields [Arch_index____Arch_index_db] (four
                     underscores), which names nothing. Measured cost of getting
                     this wrong: 86 in-project references falling through to
                     MUST-with-NULL, i.e. resolver misses stamped as proven
                     external leaves. *)
                  let join a b =
                    if String.length a >= 2 && String.ends_with ~suffix:"__" a then a ^ b
                    else a ^ "__" ^ b
                  in
                  let unit_name =
                    match List.rev prefix_rev with
                    | [] -> seg
                    | first :: more -> List.fold_left join first more
                  in
                  let residual = String.concat "." (deeper @ [name]) in
                  go ((unit_name, residual) :: acc) prefix_rev deeper
            in
            go [] [] parts
          in
          (* Resolve a qualified reference to the ONE function it names, or say
             honestly that it cannot.

             Every reading is evaluated and the DISTINCT function ids they reach
             are collected — not the first hit, which would silently prefer
             whichever reading happened to be tried first. The count is the
             verdict:

               1  -> resolved. Two readings landing on the SAME function are not
                     ambiguous; that is the common alias case ([module Bar = Bar]
                     in a library's main module), where the alias itself defines
                     no function and only the implementation's reading has a row.
               2+ -> genuinely ambiguous: the reference names units that ARE in
                     this index and nothing in a .cmt says which one the caller
                     linked against. ⊤, never a guess.
               0  -> no indexed unit answers to it. That is an EXTERNAL, handled
                     by the caller's existing leaf path — deliberately NOT ⊤.
                     Conflating "not in the index" with "in the index but
                     unidentifiable" is what took the abandoned branch's
                     repo-wide MAY_TOP from 660 to 875. *)
          (* Second tier, consulted only when no prefix reading answers: read
             each SUFFIX segment as a bare module name and ask which known
             compilation units END in it. This is what bridges a cross-library
             re-export facade (see [units_by_last_component]).

             It is NOT the old bare-segment lookup restored. The old code keyed
             [capitalize (basename path)] in a last-writer-wins table, so a
             second [api.ml] silently evicted the first and the survivor
             answered for BOTH — the defect this whole change exists to remove.
             Here a bare segment maps to EVERY unit that could define it, and
             the function table arbitrates by the same 1 / 2+ / 0 rule as the
             prefix tier: a genuine homonym reaches two ids and goes to ⊤
             instead of being guessed. *)
          let facade_readings mod_name name =
            let parts = String.split_on_char '.' mod_name in
            let rec go acc rest =
              match rest with
              | [] -> acc
              | seg :: deeper ->
                  let residual = String.concat "." (deeper @ [name]) in
                  let units =
                    Option.value ~default:[] (Hashtbl.find_opt units_by_last_component seg)
                  in
                  go (List.map (fun u -> (u, residual)) units @ acc) deeper
            in
            go [] parts
          in
          let ids_of_readings readings =
            List.concat_map
              (fun (unit_name, residual) ->
                List.filter_map
                  (fun path -> Hashtbl.find_opt fn_lookup (path, residual))
                  (Arch_index_cmt.paths_of_unit unit_name))
              readings
            |> List.sort_uniq compare
          in
          let resolve_qualified_unit mod_name name =
            (* Tier order matters and is not an optimisation. A prefix reading
               names the unit EXACTLY as dune spells it, so when one answers it
               is the reference's own account of where the callee lives. The
               facade tier infers a unit from a bare segment, which is weaker
               evidence, so it is consulted only where the strong evidence is
               silent — never allowed to outvote it or to add ambiguity to it. *)
            match ids_of_readings (unit_readings mod_name name) with
            | [id] -> `Resolved id
            | _ :: _ :: _ -> `Ambiguous
            | [] -> (
                match ids_of_readings (facade_readings mod_name name) with
                | [id] -> `Resolved id
                | [] -> `Not_found
                | _ -> `Ambiguous)
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
          (* Roadmap 1.6 (FR-005): re-targeted onto [unit_readings] in the SAME
             commit as the resolver above, deliberately. These two walks must
             agree on what a reference can mean — if the resolver enumerates
             unit-name readings while this one still walked bare segments, a
             dropped callee could be invisible here and get emitted as a proven
             external leaf, which is the precise failure FR-005 guards. *)
          let dropped_qualified mod_name name =
            List.exists
              (fun (unit_name, residual) ->
                let paths = Arch_index_cmt.paths_of_unit unit_name in
                (* A whole dropped unit indexed nothing, so it has no stored
                   path and no per-function entry — it is matched by the unit
                   owning a dropped path, not by a function lookup. *)
                List.exists
                  (fun p -> List.mem p (Arch_index_cmt.dropped_unit_paths ()))
                  paths
                || List.exists
                     (fun p ->
                       Arch_index_cmt.is_dropped_node ~module_path:p ~name:residual)
                     paths)
              (unit_readings mod_name name @ facade_readings mod_name name)
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
                    match resolve_qualified_unit mod_name n with
                    | `Resolved id ->
                        incr n_resolved ;
                        (Some id, display_name, kind, None)
                    | `Ambiguous ->
                        (* The reference names units that ARE in this index and
                           more than one distinct function answers to it. ⊤ —
                           and ⊤ regardless of [demoted]: MAY_ENUMERATED claims a
                           candidate set of ONE, which is exactly what is not
                           true here. Degrading to a bounded candidate would
                           understate the frontier. *)
                        (None, display_name, "MAY_TOP", Some "ambiguous_unit")
                    | `Not_found ->
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
              (* The handler scopes enclosing THIS call site, linked to this
                 call's own rowid — written back to back with the call so no
                 other insert can slip in between. Up to TWO rows: a call can
                 sit inside a `try` (exception channel) AND have its result
                 matched on (a value channel). [call_exn_scopes] keys on
                 (call_id, scope_id), so both fit; before that only one did
                 and the value-channel one was dropped. *)
              List.iter
                (fun scope_id ->
                  Arch_index_db.insert_call_exn_scope db stmt_call_scope ~call_id ~scope_id)
                (List.filter_map Fun.id [call.exn_scope; call.errch_scope]) ;
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
  (* FIX (coverage-matrix review, HIGH): [error_contract] is a claim that these
     channels WERE ANALYSED, so it may only be recorded once the transaction
     that writes the channel rows has committed. It used to be written before
     [BEGIN TRANSACTION] above, which made it a statement of intent rather than
     of fact: a producer that died mid-analysis left a database carrying the
     contract and none of the rows, and any consumer reading the key — the
     coverage matrix does exactly this — reported the analysis as complete on
     evidence that was never written. Reproduced by deleting the scope rows and
     leaving the key.

     Its presence is now a completion marker by construction. Consumers must
     NOT try to infer completeness by counting rows instead: a small corpus
     legitimately produces zero scopes on a fully successful run. *)
  (let stmt_contract =
     Sqlite3.prepare db "INSERT OR REPLACE INTO comment_db_meta (key, value) VALUES (?, ?)"
   in
   Arch_index_db.bind_text stmt_contract 1 "error_contract" ;
   Arch_index_db.bind_text stmt_contract 2 error_contract ;
   Arch_index_db.exec_stmt db ~what:"comment_db_meta" stmt_contract ;
   ignore (Sqlite3.finalize stmt_contract)) ;
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
module Arch_index_support = Arch_index_support

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
