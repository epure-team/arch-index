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
      "INSERT INTO modules (path, lines, last_analyzed, has_mli, unit_name, \
       compile_scope, quint_module_raw) VALUES (?, ?, ?, ?, ?, ?, ?)"
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
  (* Capitalised basename → source path. Lossy BY CONSTRUCTION: two libraries
     can each hold an `api.ml`, and `Hashtbl.replace` keeps whichever was
     scanned last, so `Api` designates one of them at random. That is why it is
     no longer the primary key — {!unit_to_path} below is — and why the only
     thing still reached through here is the residue that has no unit identity
     at all (a path rooted at a local `let module`). *)
  let mod_name_to_path = Hashtbl.create 128 in
  (* Compilation-unit identity → source path(s). Far more discriminating than
     the basename map — `rootlib__Api` and `sublib__Api` are distinct keys for
     the two `api.ml`, and the key is written by the toolchain as the .cmt
     filename, so it is a fact about the build rather than an inference from
     the source layout.

     A LIST, not one path, because it is not injective either. Every
     `(executable (name main))` stanza mangles to `dune__exe__Main`, so two
     programs in one workspace collide exactly as two `api.ml` do. Keeping one
     of them — which `Hashtbl.replace` would do silently — reinstates the
     original defect on a different key: a review demonstrated a MUST edge from
     one program into a *different program it never links*, and `reaches`
     answering `PATH EXISTS`. A collided key resolves to nothing and degrades,
     which is the whole point of the change. *)
  let unit_to_path : (string, string list) Hashtbl.t = Hashtbl.create 128 in
  (* Source path → the dune compilation scope (object directory) it was built
     in. Absent for a producer that does not know it, and an absent scope never
     contributes to the straddle test below — unknown is not a second scope. *)
  let path_to_scope : (string, string) Hashtbl.t = Hashtbl.create 128 in
  ignore
    (Sqlite3.exec_not_null
       db
       ~cb:(fun row _h ->
         let path = row.(0) in
         let base = Filename.basename path in
         let name = Filename.remove_extension base |> String.capitalize_ascii in
         Hashtbl.replace mod_name_to_path name path ;
         (match row.(2) with "" -> () | l -> Hashtbl.replace path_to_scope path l) ;
         match row.(1) with
         | "" -> ()
         | unit_name ->
             let prev =
               match Hashtbl.find_opt unit_to_path unit_name with
               | Some l -> l
               | None -> []
             in
             Hashtbl.replace unit_to_path unit_name (path :: prev))
       "SELECT path, COALESCE(unit_name,''), COALESCE(compile_scope,'') FROM modules") ;
  (* Resolve a CANDIDATE LIST of unit readings against the units actually
     indexed, rather than trusting one guess. `A.Inner.f` reads as
     `a__Inner`.`f` under a wrapped library and as `a`.`Inner.f` under a
     `(wrapped false)` one, and `Foo__` is dune's alias for library `foo` but
     also the wrapper of a library legitimately named `foo__`. Preferring one
     reading binds MUST edges into libraries the caller does not even link — the
     defect this whole change removes, re-created one level up.

     Within a group a candidate counts only if its unit exists AND provides the
     name. The unit alone is not enough: as soon as a library has a hand-written
     `rootlib.ml`, that wrapper is itself an indexed unit called `rootlib`, so
     the `(wrapped false)` reading of `Rootlib__.Api.run` — unit `rootlib`, name
     `Api.run` — always names a real unit and every intra-library reference
     would go ambiguous. The wrapper holds no value called `Api.run`, so asking
     for the name settles it. That shortcut is sound only BETWEEN READINGS OF
     ONE SPELLING, which name modules of a single library; see {!resolve_units}
     for why it must not be applied across spellings, and {!resolve_group} for
     why it must not be applied to a collided key.

     Three verdicts, and each collapse of them has been a demonstrated bug:

     - [`Absent]: no reading names a unit we hold. Identity was checked and came
       back negative, so the callee is genuinely outside the index — an external
       leaf, kind preserved. The basename map is NOT consulted: it is reachable
       only when there is no unit identity at all.
     - [`Missing]: a unit matched but holds no such name — an `include`, a
       re-export, an alias. The target is very likely indexed under another row,
       so a leaf would read as external and let `arch-rules` pass. ⊤.
     - [`Ambiguous]: several readings resolve, or a unit name is shared by two
       modules. Deferring hands the reference to whichever module the basename
       map kept. ⊤. *)
  (* One root spelling's readings. A collided unit key is `Ambiguous BEFORE the
     name filter, and that ordering is the fix to a demonstrated forged proof:
     holding the name is not evidence of IDENTITY. Two `(executable (name main))`
     stanzas both mangle to `dune__exe__Util`; if one program's `util.ml` is an
     `include` (so it owns no row for the name) and the other's defines it, the
     filter leaves exactly one survivor and elects a different program. A review
     produced precisely that: `MUST` from e1 into e2, which never links it. The
     collision is the answer — filtering by name only picks a winner. *)
  let resolve_group ~lookup (cands : (string * string) list) =
    let unit_hit = ref false in
    let collided = ref false in
    (* Compilation scopes the LIVE readings belong to. Preferring the reading
       that resolves is sound only inside one scope: there, a wrong pick still
       lands in a library the caller demonstrably links. Across scopes it is the
       original defect. `A.Inner.f` reads as unit `a` name `Inner.f` and as unit
       `a__Inner` name `f`; when `a` is a `(wrapped false)` module of library
       `flat` and `a__Inner` belongs to a library literally named `a`, those are
       two scopes, and `flat` need not link `a`. With `flat/a.ml` an `include`,
       only the foreign reading held the name — one survivor, and a review
       measured `reaches` answering PATH EXISTS through a library the caller
       never links, with `escapes` empty so the proof looked total. *)
    let scopes = ref [] in
    let hits =
      List.concat_map
        (fun (u, inner) ->
          match Hashtbl.find_opt unit_to_path u with
          | None -> []
          | Some paths ->
              unit_hit := true ;
              List.iter
                (fun p ->
                  match Hashtbl.find_opt path_to_scope p with
                  | Some s when not (List.mem s !scopes) -> scopes := s :: !scopes
                  | _ -> ())
                paths ;
              if List.compare_length_with paths 1 > 0 then (
                collided := true ;
                [])
              else
                List.filter_map
                  (fun p -> Option.map (fun id -> (p, id)) (lookup p inner))
                  paths)
        cands
      |> List.sort_uniq compare
    in
    if !collided then `Ambiguous
    else
      match hits with
      | [(_, id)] ->
          (* One reading resolved. If the live readings straddle two scopes,
             that single hit is a choice between them, not a deduction. *)
          if List.compare_length_with !scopes 1 > 0 then `Ambiguous else `One id
      | [] -> if !unit_hit then `Missing else `Absent
      | _ -> `Ambiguous
  in
  (* Combine the root spellings. A group naming no indexed unit at all is not
     evidence against the others — `Foo__.Bar` on a tree holding only library
     `foo` leaves the `foo__` group empty, and that is simply the wrong guess
     being unavailable. But once two groups are LIVE they denote two different
     libraries, and only unanimity resolves: anything else is the tool choosing
     a library for the user. *)
  let resolve_units ~lookup (groups : (string * string) list list) =
    match
      List.filter (fun v -> v <> `Absent) (List.map (resolve_group ~lookup) groups)
    with
    | [] -> `Absent
    | [v] -> v
    | live -> (
        (* Unanimity is kept for the rule it states, not for traffic it carries:
           a review showed it cannot fire. Agreement would need two distinct
           unit names resolving to one module id, and `modules.path` is UNIQUE
           with one `unit_name` per row, so distinct keys have distinct paths.
           Deleting the branch leaves every test green — correctly, since it is
           unreachable rather than untested. *)
        match List.sort_uniq compare live with
        | [(`One _ as v)] -> v
        | _ -> `Ambiguous)
  in
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
                 source of ⊤ for an UNKNOWABLE HEAD — computed heads,
                 parameter/local-value calls, dynamic roots, over-application
                 residuals. It is no longer the only source: a qualified head
                 whose compilation unit is indexed but holds no row for the
                 name (an `include`, a re-export) is also ⊤, below.
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
            | Arch_index_cmt.Head_qualified (mod_opt, n, unit_opt) -> (
                let display_name =
                  match mod_opt with Some m -> m ^ "." ^ n | None -> n
                in
                let kind = if demoted then "MAY_ENUMERATED" else "MUST" in
                (* Resolution by COMPILATION-UNIT IDENTITY first, and it is an
                   exact equality, not a search. `Sublib.Api.run` carries
                   ("sublib__Api", "run"); `rootlib__Api` is a different key, so
                   the two `api.ml` cannot be confused however they are laid out
                   on disk.

                   The decisive property is what happens when the unit IS known
                   and the function is not in it. That is NOT a reason to look
                   elsewhere — it means the name is provided by something this
                   index does not own a row for (an `include`, a re-export, an
                   alias) or is genuinely external. Falling back to the basename
                   map there is exactly how a reference to sublib's `run` ends up
                   bound to rootlib's, with kind MUST: a forged proof pointing at
                   another library. So a known unit is terminal — resolve within
                   it or record an unresolved leaf, never a neighbour. *)
                let by_unit =
                  if unit_opt = [] then `No_identity
                  else
                    match
                      resolve_units unit_opt ~lookup:(fun p n ->
                          Hashtbl.find_opt fn_lookup (p, n))
                    with
                    (* No reading names a unit we hold, and we DO have a unit
                       identity to check — so the callee lives in a compilation
                       unit outside this index. That is the definition of
                       external, and the honest record is a leaf. Walking the
                       basename map here is what forged `Stdlib.Buffer.add_string`
                       into a local `buffer.ml`: any project owning a `result.ml`,
                       `option.ml` or `queue.ml` had stdlib calls bound to it,
                       with kind MUST. The map cannot be right in this branch —
                       it is consulted precisely when identity says no. *)
                    | `Absent -> `External
                    | `Ambiguous | `Missing -> `Top
                    | `One id -> `Id id
                in
                match by_unit with
                | `Id id -> incr n_resolved ; (Some id, display_name, kind)
                | `External -> (None, display_name, kind)
                | `Top ->
                    (* Unit known and INDEXED, name not in it. Terminal, per
                       above — but not a leaf.

                       An unresolved callee is stored as `callee_id = NULL`,
                       which is bit-for-bit how a genuine external like
                       `Stdlib.+` is stored, and the read model turns both into
                       an inert `ext:` node. For a unit we do not index that is
                       the truth. Here it is a lie: the unit is in the index,
                       so the name is provided by something we hold no row for
                       — an `include`, a re-export, an alias — and the target is
                       very likely an indexed function. Recording it as an
                       external leaf would let `arch-rules` answer `pass` and
                       `unreachable` answer UNREACHABLE about a call that
                       really does land inside the index.

                       ⊤ is the honest encoding: bounded to nothing we can
                       name, never traversed, and it degrades the verdicts that
                       must not be trusted here. It costs precision only where
                       we genuinely cannot see the target. *)
                    (None, display_name, "MAY_TOP")
                | `No_identity -> (
                    (* No unit identity to key on — a path rooted at a local
                       `let module`, or a unit this index never scanned. The
                       basename walk is the residue, and it is only ever
                       consulted here. *)
                    match mod_opt with
                    | None -> (
                        match resolve_local n with
                        | Some id -> incr n_resolved ; (Some id, n, kind)
                        | None ->
                            ( None,
                              n,
                              (if demoted then "MAY_ENUMERATED" else "MAY_TOP") ))
                    | Some mod_name -> (
                        match resolve_qualified mod_name n with
                        | Some id ->
                            incr n_resolved ;
                            (Some id, display_name, kind)
                        | None -> (None, display_name, kind))))
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
          (* Unit identity first, as on the call and type paths. `open
             Sublib.Api` carries "sublib__Api", which is a different key from
             "rootlib__Api" — and this resolver decides what a path-shaped
             `forbid dep` rule sees, so binding it to the wrong library turns a
             real violation green and invents one that is not there. *)
          let target_id =
            match
              (* A dep names a MODULE, so the "name it provides" is the module
                 itself: the lookup is the module id. *)
              match
                resolve_units
                  (List.map (List.map (fun u -> (u, ""))) dep.target_unit)
                  ~lookup:(fun p _ -> Hashtbl.find_opt mod_path_to_id p)
              with
              | `One id -> `Resolved id
              (* Terminal, exactly as on the call path. Letting these fall
                 through to the basename walk below is what the walk's own
                 comment calls actively harmful: a review demonstrated
                 `open Util` inside one executable binding to a DIFFERENT
                 program's util.ml, because the two mangle alike and the
                 basename map keeps the last. The call path already treated
                 them as terminal; the dep path did not, and deps are what a
                 path-shaped `forbid dep` rule reads.

                 [`Missing] is listed for the exhaustiveness the type demands,
                 not because it fires: `unit_to_path` and `mod_path_to_id` are
                 built from the same `SELECT … FROM modules`, so a path that
                 came out of the first is always a key of the second. A review
                 mutated this arm and no test moved — correctly, since the arm
                 is unreachable rather than untested. *)
              | `Ambiguous | `Missing -> `Terminal
              (* Identity checked and no reading names a unit we hold: the
                 target module is outside the index. Terminal for the same
                 reason as on the call path — the basename map is consulted
                 exactly when identity has already said no, so it can only
                 invent. `Fallback` is left for a dep carrying NO identity. *)
              | `Absent when dep.target_unit <> [] -> `Terminal
              | `Absent -> `Fallback
            with
            | `Resolved id ->
                incr n_deps_resolved ;
                Some id
            | `Terminal -> None
            | `Fallback -> (
                match Hashtbl.find_opt mod_path_to_id dep.target_path with
                | Some id ->
                    incr n_deps_resolved ;
                    Some id
                | None -> (
                    (* Residue only: a target with no unit identity. The
                       basename walk collapses homonyms by construction, which
                       is why it is no longer reached for anything the
                       toolchain named. *)
                    let parts = String.split_on_char '.' dep.target_path in
                    let name = List.hd (List.rev parts) in
                    match Hashtbl.find_opt mod_name_to_path name with
                    | Some path -> (
                        match Hashtbl.find_opt mod_path_to_id path with
                        | Some id ->
                            incr n_deps_resolved ;
                            Some id
                        | None -> None)
                    | None -> None))
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
  let type_by_unit : (string * string, int) Hashtbl.t = Hashtbl.create 256 in
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
         (* Basename key: same collapse as everywhere else, kept only as the
            residue for paths with no unit identity. *)
         Hashtbl.replace type_lookup (mod_name, type_name) type_id ;
         (* Unit key: injective across libraries, the primary. *)
         Hashtbl.replace type_by_unit (mod_path, type_name) type_id)
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
        (* Unit identity first, exactly as on the call path: `Rootlib.Api.t`
           carries ("rootlib__Api", "t"), which cannot be confused with
           sublib's `t` however the two api.ml are laid out. A known unit is
           terminal here too — if the type is not in it, we do not go looking
           in a namesake. Unlike a call, an unresolved type usage degrades
           nothing (type_usage feeds no soundness closure and no consumer in
           bin/ reads it), so NULL is the honest answer rather than ⊤. *)
        let by_unit =
          if usage.type_unit = [] then None
          else
            match
              resolve_units usage.type_unit ~lookup:(fun p n ->
                  Hashtbl.find_opt type_by_unit (p, n))
            with
            (* Terminal here too: `Sqlite3.Rc.t` bound to a local `rc.ml`
               through the basename map is the same forgery as on the call
               path, and a review reproduced it on an ordinary opam
               dependency. *)
            | `Absent -> Some None
            | `Ambiguous | `Missing -> Some None
            | `One id -> Some (Some id)
        in
        match by_unit with
        | Some (Some id) -> incr n_type_usages_resolved ; Some id
        | Some None -> None
        | None -> (
            match Hashtbl.find_opt type_lookup (mod_name, type_name) with
            | Some id ->
                incr n_type_usages_resolved ;
                Some id
            | None -> None)
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
