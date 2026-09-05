(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** CMT file processing for architecture indexing.

    Parses .cmt/.cmti files to extract module structure, functions, types,
    call graph, and module dependencies. *)

open Arch_index_db

(* -------------------------------------------------------------------------- *)
(* Type printing helper                                                       *)
(* -------------------------------------------------------------------------- *)

let type_to_string ty = Format.asprintf "%a" Printtyp.type_expr ty

(* -------------------------------------------------------------------------- *)
(* Dropped-node registry                                                      *)
(* -------------------------------------------------------------------------- *)

(* When an insert is rejected the indexer skips the row's dependents rather
   than filing them under a neighbour. That keeps the stored rows honest, but
   it leaves a second problem behind: the call resolver later looks a callee up
   in the STORED functions and, finding nothing, concludes "external" and emits
   a MUST edge to a leaf. For a genuine external — Stdlib, a C stub — that is
   correct: the body is outside the index and reachability legitimately stops.
   For a node this run analysed and then dropped it is a false claim. The body
   exists, it was never read into the graph, and anything it calls is invisible;
   terminating reachability there is exactly the unsound answer.

   So every drop is remembered here, and the resolver consults it: a callee it
   cannot resolve but knows was dropped is the ⊤ frontier, recorded MAY_TOP, and
   a query that reaches it answers UNKNOWN rather than UNREACHABLE.

   Process-global, like [Arch_index_db.statement_failures], and reset per run by
   [Arch_index.run] for the same reason. *)

(* Individual (module rel_path, function name) pairs whose [functions] row was
   refused. *)
let dropped_nodes : (string * string, unit) Hashtbl.t = Hashtbl.create 16

(* rel_paths of compilation units whose [modules] row was refused. Nothing at
   all was indexed from these, so no per-function entry can exist: the unit as a
   whole is the frontier. *)
let dropped_units : (string, unit) Hashtbl.t = Hashtbl.create 8

(* Roadmap 1.6: the compiler-assigned compilation-unit name ([cmt_modname]) ->
   every rel_path bearing it.

   This exists because qualified-call resolution otherwise has no way to know
   which LIBRARY owns a file. It used to key on [capitalize (basename path)] in a
   last-writer-wins table, so [Liba.Api] and [Libb.Api] both looked up ["Api"] and
   whichever api.ml was indexed last won for both — a reference into one library
   silently attributed to another, and stamped MUST.

   The unit name is the fix because dune already encodes ownership in it
   ([Liba__Api] vs [Libb__Api]), and the compiler hands it to us directly. It must
   come from [cmt_modname], NEVER from the .cmt FILENAME: on disk those are
   lowercase-prefixed ([arch_index__Arch_index_cfg.cmt]), so deriving a unit name
   from the path reintroduces a guess in the middle of the thing removing guesses.

   Populated at the two sites — and only the two — that decide a compilation
   unit's fate: the [insert_module] success arm, and [record_dropped_unit]. Since
   the DB is dropped and recreated every run and there is exactly one
   [insert_module] call site, the registry is COMPLETE by construction with
   respect to the [modules] table: no schema column, no migration, and no way for
   a stale row to survive into the next run.

   A name maps to a LIST because unit names are not guaranteed unique in
   general — scenario C (`tezt/tests/qualified_library_scoping.ml`) pins two
   [(wrapped false)] libraries that both compile a unit named [Api]. The
   qualitative claim stands; an earlier revision of this comment attached a
   number to it — "a census of this repository found one such name in 93:
   [Dune__exe]" — that does NOT reproduce and, per its own commit's evidence
   trail, never did.

   Measured (round-5 review), by iterating {!known_unit_names} and
   {!paths_of_unit} from inside a run of [arch_callgraph_ocaml --build-dir
   _build/default] over THIS repository's own build: 88 unit names, ZERO with
   more than one registered path — including [Dune__exe] itself, whose bare,
   suffix-less form is shared by several executables' wrapper modules at the
   RAW-`.cmt` level (confirmed separately with `ocamlobjinfo` across every
   `.cmt`/`.cmti` under `_build/default`) but never reaches {!record_unit} more
   than once for the same name with two DIFFERENT paths, because
   [insert_module] only registers units this indexer actually stores as
   [modules] rows, and a dune-generated empty wrapper alias is not one. Same
   zero on octez-manager (353 units) and proto_alpha (468 units). Multiplicity
   must mean "genuinely distinct source files bear this unit name", never "the
   same file was reached twice", so insertion de-duplicates on rel_path —
   without that, indexing a build dir containing more than one dune context
   would register every module twice and read as ambiguity everywhere. *)
let unit_paths : (string, string list) Hashtbl.t = Hashtbl.create 128

let record_unit ~unit_name ~rel_path =
  let existing = Option.value ~default:[] (Hashtbl.find_opt unit_paths unit_name) in
  if not (List.mem rel_path existing) then
    Hashtbl.replace unit_paths unit_name (rel_path :: existing)

let paths_of_unit unit_name =
  Option.value ~default:[] (Hashtbl.find_opt unit_paths unit_name)
  |> List.sort String.compare

let known_unit_names () =
  Hashtbl.fold (fun k _ acc -> k :: acc) unit_paths [] |> List.sort String.compare

let reset_dropped () =
  Hashtbl.reset dropped_nodes ;
  Hashtbl.reset dropped_units ;
  Hashtbl.reset unit_paths

let record_dropped_node ~module_path ~name =
  Hashtbl.replace dropped_nodes (module_path, name) ()

let record_dropped_unit ~rel_path = Hashtbl.replace dropped_units rel_path ()

let is_dropped_node ~module_path ~name =
  Hashtbl.mem dropped_nodes (module_path, name)
  || Hashtbl.mem dropped_units module_path

let dropped_unit_paths () =
  Hashtbl.fold (fun k () acc -> k :: acc) dropped_units [] |> List.sort String.compare

(* -------------------------------------------------------------------------- *)
(* Error-channels config validation collector (specs/error-channels.md,       *)
(* slice 0). [Arch_index.run] sets this to a [Arch_errors_config.seen] built  *)
(* from the effective config before walking any .cmt, and clears it after —   *)
(* same process-global-reset-per-run pattern as [dropped_nodes] above. [None] *)
(* (no run in flight, or a caller that never sets it) makes every note a      *)
(* cheap no-op, so callers other than [Arch_index.run] pay nothing. *)
let seen_collector : Arch_errors_config.seen option ref = ref None

let set_seen_collector (s : Arch_errors_config.seen option) = seen_collector := s

let note_seen_value_path (p : string) =
  match !seen_collector with
  | Some s -> Arch_errors_config.note_value_path s p
  | None -> ()

let note_seen_type_path (p : string) =
  match !seen_collector with
  | Some s -> Arch_errors_config.note_type_path s p
  | None -> ()

(* -------------------------------------------------------------------------- *)
(* Nested-module indexing policy (issue #16)                                  *)
(* -------------------------------------------------------------------------- *)

(** [qualify ~prefix name] is the definition path a binding is indexed under.
    The toplevel of a compilation unit carries no prefix, so existing rows keep
    their bare names. *)
let qualify ~prefix name = prefix ^ name

(** [nested_prefix ~prefix module_name] is the prefix in force inside
    [module_name]'s body.  Nesting composes, so a binding two modules deep is
    indexed as [Outer.Inner.f]. *)
let nested_prefix ~prefix module_name = prefix ^ module_name ^ "."

(** [iter_structure_items ~f structure] applies [f ~prefix item] to every
    structure item of a compilation unit, including those nested in modules,
    recursive modules and functor bodies, with [prefix] the enclosing module
    path ([""] at the toplevel, ["Make."] inside [module Make (P : S) = ...]).

    Every walk over a structure goes through this one function -- the indexer,
    the call-graph's local-binding table, and anything added later -- so the
    definition path a binding is indexed under and the path its call sites are
    attributed to cannot drift apart.

    It does not descend into an application ([Make (X)]), an alias
    ([module A = B]) or an unpacked first-class module: those name definitions
    written elsewhere, and indexing them here would produce one set of rows per
    instance instead of one per definition.  [include] is different: its items
    land in the enclosing scope, so they are walked under the {i enclosing}
    prefix rather than a new one. *)
let iter_structure_items ~f (structure : Typedtree.structure) =
  let rec item ~prefix (it : Typedtree.structure_item) =
    f ~prefix it ;
    match it.str_desc with
    | Tstr_module mb -> binding ~prefix mb
    | Tstr_recmodule mbs -> List.iter (binding ~prefix) mbs
    | Tstr_include incl -> module_expr ~prefix incl.incl_mod
    | _ -> ()
  and binding ~prefix (mb : Typedtree.module_binding) =
    match mb.mb_id with
    | Some id ->
        module_expr ~prefix:(nested_prefix ~prefix (Ident.name id)) mb.mb_expr
    | None -> ()
  and module_expr ~prefix (me : Typedtree.module_expr) =
    match me.mod_desc with
    | Tmod_structure s -> List.iter (item ~prefix) s.str_items
    | Tmod_functor (_, body) -> module_expr ~prefix body
    | Tmod_constraint (inner, _, _, _) -> module_expr ~prefix inner
    | Tmod_apply _ | Tmod_apply_unit _ | Tmod_ident _ | Tmod_unpack _ -> ()
  in
  List.iter (item ~prefix:"") structure.str_items

(** The signature counterpart of {!iter_structure_items}: applies [f ~prefix
    item] to every signature item of an interface, including those nested in
    modules and in a functor's result signature, under the same definition
    paths the implementation registers.  The two must agree, or a value ends up
    indexed but not exposed, or exposed with no row.

    A named signature ([module M : S]) is walked by expanding [S] from the
    unit's own [module type] declarations, since that spelling -- not the
    inline [sig ... end] one -- is what most interfaces use.  Expansion is
    guarded against a signature that names itself. *)
let iter_signature_items ~f (sg : Typedtree.signature) =
  let modtypes : (string, Typedtree.module_type) Hashtbl.t = Hashtbl.create 8 in
  let rec collect (items : Typedtree.signature_item list) =
    List.iter
      (fun (it : Typedtree.signature_item) ->
        match it.sig_desc with
        | Tsig_modtype {mtd_id; mtd_type = Some mty; _} ->
            Hashtbl.replace modtypes (Ident.name mtd_id) mty ;
            collect_mty mty
        | Tsig_module {md_type; _} -> collect_mty md_type
        | Tsig_recmodule mds ->
            List.iter (fun (md : Typedtree.module_declaration) -> collect_mty md.md_type) mds
        | _ -> ())
      items
  and collect_mty (m : Typedtree.module_type) =
    match m.mty_desc with
    | Tmty_signature s -> collect s.sig_items
    | Tmty_functor (_, body) -> collect_mty body
    | Tmty_with (inner, _) -> collect_mty inner
    | Tmty_ident _ | Tmty_alias _ | Tmty_typeof _ -> ()
  in
  collect sg.sig_items ;
  let rec item ~prefix ~expanding (it : Typedtree.signature_item) =
    f ~prefix it ;
    match it.sig_desc with
    | Tsig_module md -> (
        match md.md_id with
        | Some id ->
            mty
              ~prefix:(nested_prefix ~prefix (Ident.name id))
              ~expanding md.md_type
        | None -> ())
    | Tsig_recmodule mds ->
        List.iter
          (fun (md : Typedtree.module_declaration) ->
            match md.md_id with
            | Some id ->
                mty
                  ~prefix:(nested_prefix ~prefix (Ident.name id))
                  ~expanding md.md_type
            | None -> ())
          mds
    (* [include S] brings S's items into the enclosing scope, so they keep the
       enclosing prefix. *)
    | Tsig_include incl -> mty ~prefix ~expanding incl.incl_mod
    | _ -> ()
  and mty ~prefix ~expanding (m : Typedtree.module_type) =
    match m.mty_desc with
    | Tmty_signature s -> List.iter (item ~prefix ~expanding) s.sig_items
    | Tmty_functor (_, body) -> mty ~prefix ~expanding body
    | Tmty_with (inner, _) -> mty ~prefix ~expanding inner
    | Tmty_ident (path, _) -> (
        let name = Path.last path in
        if List.mem name expanding then ()
        else
          match Hashtbl.find_opt modtypes name with
          | Some m' -> mty ~prefix ~expanding:(name :: expanding) m'
          | None -> ())
    | Tmty_alias _ | Tmty_typeof _ -> ()
  in
  List.iter (item ~prefix:"" ~expanding:[]) sg.sig_items

let%test "qualify: a toplevel binding keeps its bare name" =
  qualify ~prefix:"" "f" = "f"

let%test "qualify: a nested binding carries its module path" =
  qualify ~prefix:"Make." "spawn" = "Make.spawn"

let%test "nested_prefix: nesting composes" =
  let p = nested_prefix ~prefix:"" "Outer" in
  let p = nested_prefix ~prefix:p "Inner" in
  qualify ~prefix:p "f" = "Outer.Inner.f"

(* -------------------------------------------------------------------------- *)
(* Doc-comment extraction                                                     *)
(* -------------------------------------------------------------------------- *)

(** Extract the first doc-comment line from OCaml attributes.
    Doc comments are stored as [\[@ocaml.doc "..."\]] attributes. *)
let extract_doc (attrs : Parsetree.attributes) =
  List.find_map
    (fun (attr : Parsetree.attribute) ->
      if attr.attr_name.txt = "ocaml.doc" || attr.attr_name.txt = "doc" then
        match attr.attr_payload with
        | PStr
            [{pstr_desc = Pstr_eval ({pexp_desc = Pexp_constant c; _}, _); _}]
          -> (
            match c.pconst_desc with
            | Pconst_string (s, _, _) ->
                let trimmed = String.trim s in
                if trimmed = "" then None else Some trimmed
            | _ -> None)
        | _ -> None
      else None)
    attrs

(* -------------------------------------------------------------------------- *)
(* Scanning .cmt/.cmti files                                                  *)
(* -------------------------------------------------------------------------- *)

(** Is this cmt dune's generated alias module rather than a module someone wrote?

    For a wrapped library [foo] the alias is [foo__.cmt] — the basename ends in [__] — while
    real modules are [foo__Bar.cmt]. That is the only generated wrapper to skip.

    An earlier version filtered on the [dune__] PREFIX instead, which matched nothing in a
    library and matched EVERY module of an EXECUTABLE, since dune names those
    [dune__exe__Main.cmt]. The effect was that arch-index could not index a single one of its
    own binaries — found by trying to index the MCP server with it. *)
let is_dune_alias_module path =
  let base = Filename.remove_extension (Filename.basename path) in
  String.length base >= 2 && String.ends_with ~suffix:"__" base

let find_cmt_files build_dir =
  let files = ref [] in
  let rec walk dir =
    let entries = Sys.readdir dir in
    Array.iter
      (fun entry ->
        let path = Filename.concat dir entry in
        let is_dir = try Sys.is_directory path with Sys_error _ -> false in
        if is_dir then walk path
        else if
          (Filename.check_suffix path ".cmt"
          || Filename.check_suffix path ".cmti")
          && not (is_dune_alias_module path)
        then files := path :: !files)
      entries
  in
  walk build_dir ;
  List.sort String.compare !files

(* -------------------------------------------------------------------------- *)
(* Exposed-name collection from .cmti files                                   *)
(* -------------------------------------------------------------------------- *)

(** Collect names exposed in .cmti (interface) files. Returns two tables:
    - exposed: (module_name, name) -> true
    - docs: (module_name, name) -> doc string *)
let collect_exposed cmti_files =
  let exposed_tbl = Hashtbl.create 256 in
  let doc_tbl = Hashtbl.create 256 in
  let module_quint_tbl = Hashtbl.create 64 in
  List.iter
    (fun path ->
      try
        match Cmt_format.read path with
        | _, Some info -> (
            let modname = info.cmt_modname in
            match info.cmt_annots with
            | Interface sg ->
                (* Mirrors the structure walk in [process_cmt]: a value exposed
                   through a nested module or a functor's result signature is
                   recorded under the same definition path the implementation
                   registers it under, so the two sides meet. *)
                let process_sig_item ~prefix
                    (item : Typedtree.signature_item) =
                    match item.sig_desc with
                    | Tsig_value vd -> (
                        let name = qualify ~prefix (Ident.name vd.val_id) in
                        Hashtbl.replace exposed_tbl (modname, name) true ;
                        match extract_doc vd.val_attributes with
                        | Some doc ->
                            Hashtbl.replace doc_tbl (modname, name) doc
                        | None -> ())
                    | Tsig_type (_, tds) ->
                        List.iter
                          (fun (td : Typedtree.type_declaration) ->
                            let name = qualify ~prefix (Ident.name td.typ_id) in
                            Hashtbl.replace exposed_tbl (modname, name) true ;
                            match extract_doc td.typ_attributes with
                            | Some doc ->
                                Hashtbl.replace doc_tbl (modname, name) doc
                            | None -> ())
                          tds
                    | Tsig_attribute attr -> (
                        (* Look for module-level doc containing {quint-module}.
                           Floating doc comments at the top of a .mli appear as
                           Tsig_attribute items with ocaml.doc or ocaml.text names. *)
                        let is_doc =
                          attr.attr_name.txt = "ocaml.doc"
                          || attr.attr_name.txt = "ocaml.text"
                        in
                        if is_doc then
                          match attr.attr_payload with
                          | PStr
                              [
                                {
                                  pstr_desc =
                                    Pstr_eval
                                      ({pexp_desc = Pexp_constant c; _}, _);
                                  _;
                                };
                              ] -> (
                              match c.pconst_desc with
                              | Pconst_string (s, _, _) -> (
                                  let parsed =
                                    Arch_index_comment_parser.parse s
                                  in
                                  match
                                    parsed.Arch_index_comment_parser.sections
                                      .quint_module
                                  with
                                  | Absent | Present_none -> ()
                                  | Present body ->
                                      if
                                        not
                                          (Hashtbl.mem module_quint_tbl modname)
                                      then
                                        Hashtbl.replace
                                          module_quint_tbl
                                          modname
                                          body)
                              | _ -> ())
                          | _ -> ())
                    | _ -> ()
                in
                iter_signature_items sg ~f:process_sig_item
            | _ -> ())
        | _ -> ()
      with exn ->
        Arch_io.eprintf
          "Warning: failed to read cmti %s: %s\n"
          path
          (Printexc.to_string exn))
    cmti_files ;
  (exposed_tbl, doc_tbl, module_quint_tbl)

(* -------------------------------------------------------------------------- *)
(* CMT signature extraction for LSP enricher                                  *)
(* -------------------------------------------------------------------------- *)

(** Derive the relative source path from a .cmti file path and project root.
    E.g. <project_dir>/_build/default/src/foo.cmti -> src/foo.ml *)
let derive_rel_source_path ~project_dir ~build_default_pfx ~proj_pfx cmti_path
    info =
  let from_cmti_path () =
    let after_build =
      if String.starts_with ~prefix:build_default_pfx cmti_path then
        String.sub
          cmti_path
          (String.length build_default_pfx)
          (String.length cmti_path - String.length build_default_pfx)
      else Filename.basename cmti_path
    in
    let without_ext =
      if Filename.check_suffix after_build ".cmti" then
        Filename.chop_suffix after_build ".cmti"
      else if Filename.check_suffix after_build ".cmt" then
        Filename.chop_suffix after_build ".cmt"
      else after_build
    in
    without_ext ^ ".ml"
  in
  match info.Cmt_format.cmt_sourcefile with
  | Some s when s <> "" ->
      let abs =
        if Filename.is_relative s then Filename.concat project_dir s else s
      in
      if String.starts_with ~prefix:build_default_pfx abs then
        String.sub
          abs
          (String.length build_default_pfx)
          (String.length abs - String.length build_default_pfx)
      else if String.starts_with ~prefix:proj_pfx abs then
        String.sub
          abs
          (String.length proj_pfx)
          (String.length abs - String.length proj_pfx)
      else from_cmti_path ()
  | _ -> from_cmti_path ()

(** Extract (relative_source_path, function_name, type_signature) triples from
    a list of [.cmti] files.  The relative source path is relative to
    [project_dir] and matches the [file_path] column populated by the LSP
    extractor.  Silently skips unreadable or malformed files. *)
let extract_signatures_from_cmti_files ~project_dir cmti_files =
  let build_default_pfx = Filename.concat project_dir "_build/default" ^ "/" in
  let proj_pfx = project_dir ^ "/" in
  let results = ref [] in
  List.iter
    (fun path ->
      try
        match Cmt_format.read path with
        | _, None -> ()
        | _, Some info -> (
            let src_rel =
              derive_rel_source_path
                ~project_dir
                ~build_default_pfx
                ~proj_pfx
                path
                info
            in
            match info.cmt_annots with
            | Interface sg ->
                List.iter
                  (fun (item : Typedtree.signature_item) ->
                    match item.sig_desc with
                    | Tsig_value vd ->
                        let name = Ident.name vd.val_id in
                        let type_str = type_to_string vd.val_val.val_type in
                        results := (src_rel, name, type_str) :: !results
                    | _ -> ())
                  sg.sig_items
            | _ -> ())
      with _ -> ())
    cmti_files ;
  !results

(* -------------------------------------------------------------------------- *)
(* Pending types for deferred resolution                                      *)
(* -------------------------------------------------------------------------- *)

(** Collected module dependency information. *)
type pending_dep = {
  source_module : string; (* Module path, e.g. "src/foo.ml" *)
  target_path : string; (* Module path string, e.g. "Stdlib.List" *)
  dep_kind : string; (* 'open', 'include', 'alias' *)
  alias_name : string option; (* For aliases: the local name *)
  line_number : int;
}

(** What is statically known about a call's TARGET, independent of whether the
    call is conditional. Conditionality ([pending_call.cond]) is computed by
    CFG post-dominance; the final edge kind is decided at resolution time from
    the (head × cond × partial) facts. *)
(* Roadmap 1.4 (⊤-anchor taxonomy): WHY a head is unknowable, decided at the
   point [Head_unknown] is produced — the only two reasons this walker can
   actually tell apart today. [Callback_param] also covers two cases the
   roadmap's own vocabulary distinguishes conceptually but this walker cannot
   yet distinguish structurally: a genuine function PARAMETER, and a local
   [let]-bound lambda whose pattern was a tuple/alias/conditional binding
   rather than a plain [Tpat_var] ("pattern_bound" in the roadmap's
   vocabulary) — [local_lam_stamps] only ever records the [Tpat_var] success
   case, so at a later use site "not stamped" cannot tell a real parameter
   from a pattern-bound lambda without new binding-site tracking. Folding
   both into [Callback_param] is a documented, honest simplification, not a
   silent conflation — see docs/edge-kind-contract.md's ⊤-anchor section. *)
type top_reason =
  | Callback_param
      (** Parameter / local closure whose target this walker cannot compute
          — includes the not-yet-distinguished "pattern_bound" sub-case, AND
          (FIX, review MEDIUM: undocumented until now) a genuinely computed
          function value with no binding site at all — an anonymous
          application head this walker cannot name, or the residual callee
          of an over-application ([f a b c] where [f] has arity 2: the extra
          args apply to [f]'s unknown RETURN value). Both are, like a real
          parameter, "a callable value whose origin this walker did not
          track" — the roadmap's own "closure" wording is read broadly
          enough to cover a fully anonymous computed value, not narrowly as
          "only a named parameter." *)
  | Module_param
      (** Qualified path whose root is a non-persistent ident: a functor
          argument or first-class module value. *)
  | Dropped_node
      (** The callee's own row (or its whole compilation unit) was
          intentionally rejected this run — its body exists but was never
          read, so the honest answer is ⊤, not "no such function." *)
  | Ambiguous_unit
      (** Roadmap 1.6. The reference names a unit that IS in this index, but
          more than one DISTINCT function answers to it and nothing in a
          [.cmt] says which one the caller was linked against.

          Deliberately distinct from the external case: a root naming no
          indexed unit at all (Stdlib, a vendored path, an unindexed
          dependency) is a uniquely-resolved external leaf and keeps its
          MUST — see [`Unknown] handling in {!Arch_index.run}. Collapsing the
          two is what inflated the abandoned branch's repo-wide MAY_TOP from
          660 to 875.

          Rare in practice: measured (round-5 review) by iterating
          {!known_unit_names} and {!paths_of_unit} over this repository's own
          build — 88 unit names, ZERO with more than one registered path (see
          the extended note on {!unit_paths} above, which this line used to
          contradict: an earlier revision claimed "exactly one ambiguous unit
          name out of 93 ([Dune__exe])", which does not reproduce and, per its
          own commit's evidence trail, never did — corrected round-6 review).
          [Dune__exe] itself collides only at the raw-[.cmt] level across
          several executables' wrapper modules, never reaching {!record_unit}
          with two different paths for the same name, because a dune-generated
          empty wrapper alias is not stored as a [modules] row. It is the
          corpora, not this repo, where a genuine two-path collision fires
          (scenario C, `tezt/tests/qualified_library_scoping.ml`). *)

let top_reason_to_string = function
  | Callback_param -> "callback_param"
  | Module_param -> "module_param"
  | Dropped_node -> "dropped_node"
  | Ambiguous_unit -> "ambiguous_unit"

type call_head =
  | Head_local of string
      (** Unqualified name resolving (stamp-based) to a same-module top-level
          function body — a MUST candidate when unconditional and saturated. *)
  | Head_qualified of string option * string
      (** Resolved qualified path [(module, name)] with a persistent root —
          a MUST candidate (external leaf or in-index) when unconditional. *)
  | Head_enumerated of string
      (** A named local function passed as a function-typed ARGUMENT: the
          callee (e.g. [List.map]) may invoke it → bounded candidate set. *)
  | Head_unknown of string * top_reason
      (** Unknowable target: applied parameter/local closure, computed head,
          dynamic-root qualified path (functor/first-class-module), or an
          over-application residual — display name or ["*TOP*"], plus WHY. *)

(** Collected call information before resolution. *)
type pending_call = {
  caller_module : string; (* Module path, e.g. "src/foo.ml" *)
  caller_name : string; (* Function name *)
  head : call_head; (* target facts (resolution identity preserved) *)
  partial : bool; (* under-saturated / returns-a-function → body deferred *)
  cond : bool; (* call block does NOT post-dominate entry (or is deferred) *)
  dead : bool;
      (* this call can never execute: its block is reachable neither from the
         CFG entry nor from any DEFERRED entry point ([Arch_index_cfg.may_run]).
         The deferred half matters — lazy thunks, object methods, functor bodies
         and optional-argument defaults are lowered into isolated blocks, so
         entry-reachability alone would report all of them as dead.
         Under-approximate by construction: constructs the walker does not model
         degrade to opaque straight-line nodes, so they stay reachable — the
         analysis under-reports dead code and never over-claims. *)
  call_site : string; (* file:line *)
  exn_scope : int option;
      (* Innermost EXCEPTION-handler scope enclosing the call site, in the
         caller node: an [Arch_index_exn] local id during the walk, rewritten
         to the [exn_scopes] row id by [process_cmt] before resolution. *)
  errch_scope : int option;
      (* Innermost VALUE-CHANNEL scope covering THIS call's head
         (specs/error-channels.md "Handler scopes"), in its own local id space
         — [Arch_index_errch] mints ids independently of [Arch_index_exn] —
         rewritten to the [exn_scopes] row id the same way.

         A SEPARATE FIELD, not the same one (review round 2, MEDIUM). The two
         ids used to share [exn_scope], the value-channel one distinguished by
         being stored NEGATED, and the exception scope simply won when both
         were present — because [call_exn_scopes] had [PRIMARY KEY (call_id)]
         and could hold only one link per call. The key is now
         [(call_id, scope_id)], so both are stored, and neither an id-space
         sign trick nor a dropped fact is needed. *)
  errch_propagates : string option;
      (* [Some channel]: this call is a propagating edge candidate on
         [channel] — caller and callee are both c-carriers at this site, and
         the call is not to a declared [binds] path (specs/error-channels.md
         "Propagating edges" / "Binds"). Rewritten to nothing further; the
         caller (arch_index.ml) turns a [Some] here straight into an
         [exn_edges] row once dropped calls are known. *)
  edge_form : string option;
      (* [Some "value_alias"]: this edge came from a point-free binding
         ([let f = M.g]), not from an application. Orthogonal to [kind] — see
         the [calls.edge_form] comment in architecture-schema.sql for why it is
         not a [kind] value. [None] for every ordinary call. *)
}

(** Flat display of a pending call's callee: [(name, module)] — the qualified
    module component when the head preserves one, for kind-less consumers
    (LSP fallback path). *)
let pending_display (p : pending_call) =
  match p.head with
  | Head_local n | Head_enumerated n | Head_unknown (n, _) -> (n, None)
  | Head_qualified (m, n) -> (n, m)

(** A synthetic function node for a nested [fun …]/[function] literal:
    [lam_name] chains through every enclosing node
    ([parent.<fun:LINE:COL>], 1-based column, [#N] in-marker ordinal on a
    same-position collision). The literal's body has its own CFG; its calls are
    attributed to this node. *)
type lambda_node = {
  lam_name : string;
  lam_line_start : int;
  lam_line_end : int;
  lam_arity : int;
}

(* Per-node lowering context (internal): one CFG per function or lambda node. *)
type lctx = {
  cid : int; (* unique id, keys the solved verdicts *)
  lg : Arch_index_cfg.t;
  mutable lblk : int; (* current block *)
  mutable lhandlers : int list; (* active try-dispatch blocks, innermost first *)
  mutable ldeferred : int list;
      (* blocks that are entry-unreachable BY DESIGN: the isolated root of a
         lazy thunk, an object method, a functor body, an optional argument's
         default. They must stay unreachable (that is what demotes their calls
         to conditional) while not counting as dead code. *)
  lcaller : string; (* attribution: top-level name or lambda chain *)
  lexn : Arch_index_exn.acc;
      (* exception origins / handler scopes of THIS node: a lambda literal gets
         a fresh, empty accumulator, so a parent's [try] never covers its body *)
  lchannel : Arch_errors_config.channel option;
      (* THIS node's own value channel (specs/error-channels.md "Carrier
         check"), from its own (curried) type — [None] if it is not a
         c-carrier of any declared value channel. *)
  lerrch : Arch_index_errch.acc;
      (* value-channel origins / handler scopes of THIS node. *)
}

(** Collected type usage information.
    We store function_id directly since we have it when processing value bindings.
    type_path is the full path (e.g., "Epure_lib.Types.story") for resolution. *)
type pending_type_usage = {
  function_id : int;
  type_path : string; (* Full path, e.g. "Stdlib.result" or "Types.story" *)
  usage_role : string; (* 'param', 'return' *)
  position : int option; (* Parameter position for params *)
}

(* -------------------------------------------------------------------------- *)
(* Call graph extraction helpers                                              *)
(* -------------------------------------------------------------------------- *)

(** Extract module path string from a module_expr. *)
let rec module_path_of_expr (me : Typedtree.module_expr) =
  match me.mod_desc with
  | Tmod_ident (path, _longident) -> Some (Path.name path)
  | Tmod_constraint (inner, _, _, _) -> module_path_of_expr inner
  | _ -> None

(** Format a Path.t to a module-qualified name. *)
let path_to_module_name path =
  match path with
  | Path.Pident id -> (None, Ident.name id)
  | Path.Pdot (prefix, name) ->
      let rec module_path = function
        | Path.Pident id -> Ident.name id
        | Path.Pdot (p, s) -> module_path p ^ "." ^ s
        | Path.Papply _ | Path.Pextra_ty _ -> "<apply>"
      in
      (Some (module_path prefix), name)
  | Path.Papply _ | Path.Pextra_ty _ -> (None, Path.name path)

(* -------------------------------------------------------------------------- *)
(* Mutability metrics (R8)                                                    *)
(* -------------------------------------------------------------------------- *)

(** Count mutation sites (writes) and deref sites (ref reads) in one function
    body. These are DIAGNOSTIC complexity signals, not correctness verdicts: a
    high count means the function is hard to reason about — for a reader and for
    any static analysis, since a condition on mutable state is opaque to both.

    Detection is on the RESOLVED [Path], so a local rebinding of [incr] or [!]
    is not miscounted — the same shadow-proof rule the noreturn-head detection
    uses. Unresolved heads are simply not counted (under-approximate, never
    over-claim). *)
let count_mutability (e : Typedtree.expression) =
  let mutations = ref 0 and derefs = ref 0 in
  let stdlib_write =
    [":="; "incr"; "decr"]
  and container_write =
    [
      "Array.set"; "Bytes.set"; "Hashtbl.replace"; "Hashtbl.add";
      "Hashtbl.remove"; "Hashtbl.reset"; "Hashtbl.clear"; "Buffer.add_string";
      "Buffer.add_char"; "Buffer.add_bytes"; "Queue.push"; "Queue.add";
      "Stack.push";
    ]
  in
  let head_name (fn : Typedtree.expression) =
    match fn.exp_desc with
    | Texp_ident (path, _, _) -> (
        (* persistent root only: a local shadow resolves to a different path *)
        match path_to_module_name path with
        | Some m, n -> Some (m ^ "." ^ n)
        | None, n -> Some n)
    | _ -> None
  in
  let open Tast_iterator in
  let it =
    {
      default_iterator with
      expr =
        (fun self (ex : Typedtree.expression) ->
          (match ex.exp_desc with
          | Texp_setfield _ -> incr mutations
          | Texp_apply (fn, _) -> (
              match head_name fn with
              | Some n ->
                  let base = Filename.basename n in
                  let short =
                    match String.rindex_opt n '.' with
                    | Some i -> String.sub n (i + 1) (String.length n - i - 1)
                    | None -> n
                  in
                  ignore base ;
                  if List.mem short stdlib_write then incr mutations
                  else if
                    List.exists
                      (fun c ->
                        let cs = String.length c in
                        String.length n >= cs
                        && String.sub n (String.length n - cs) cs = c)
                      container_write
                  then incr mutations
                  else if short = "!" then incr derefs
              | None -> ())
          | _ -> ()) ;
          default_iterator.expr self ex);
    }
  in
  it.expr it e ;
  (!mutations, !derefs)

(** Extract type path from a Path.t.
    Returns full path like "Stdlib.List" or "Types.story". *)
let type_path_of_path path = Path.name path

(** Extract types used in a function signature.
    Returns list of (type_path, role, position) where type_path is fully qualified. *)
let extract_types_from_signature ty =
  let types = ref [] in
  let add_type path role pos = types := (path, role, pos) :: !types in
  let rec extract_constr ty role pos =
    match Types.get_desc ty with
    | Tconstr (path, args, _) ->
        let p = type_path_of_path path in
        add_type p role pos ;
        note_seen_type_path p ;
        (* Also extract type arguments (e.g., 'a list -> extract list) *)
        List.iter (fun arg -> extract_constr arg role pos) args
    | Tarrow (_, arg_ty, ret_ty, _) ->
        (* For arrow types nested in params (higher-order functions) *)
        extract_constr arg_ty role pos ;
        extract_constr ret_ty role pos
    | Ttuple tys -> List.iter (fun t -> extract_constr t role pos) tys
    | Tlink ty -> extract_constr ty role pos
    | Tpoly (ty, _) -> extract_constr ty role pos
    | _ -> ()
  in
  (* Walk the type, tracking parameter position *)
  let rec walk ty param_pos =
    match Types.get_desc ty with
    | Tarrow (_, arg_ty, ret_ty, _) ->
        (* arg_ty is a parameter, ret_ty is the rest of the function *)
        extract_constr arg_ty "param" (Some param_pos) ;
        walk ret_ty (param_pos + 1)
    | _ ->
        (* This is the return type *)
        extract_constr ty "return" None
  in
  walk ty 0 ;
  List.rev !types

(** [true] iff [ty] is SYNTACTICALLY a function type. No alias expansion:
    .cmt-restored environments do not carry manifest type declarations, so
    [type unary = int -> int] cannot be expanded here. Shared by the alias
    pre-pass below and by [collect_calls_from_expr]'s own [is_arrow], so the
    binder admitted by the first and the RHS accepted by the second are judged
    against ONE definition of "arrow-typed" — two would let a binding enter the
    table and then be refused at emission, or the reverse. *)
let is_arrow_ty ty = match Types.get_desc ty with Tarrow _ -> true | _ -> false

(** [true] iff the binding RHS is a syntactic function body — the only shape we
    can treat as a statically-callable node. A function-TYPED value with a
    non-function RHS (e.g. [let f = if c then g else h], or a plain alias
    [let f = g]) is NOT: a call through it could dispatch to any of several
    targets we do not track, so it must classify MAY_TOP, not MUST. *)
let is_function_rhs (e : Typedtree.expression) =
  (* A `(fun … : t)` / coercion keeps its [Texp_function] desc — the constraint
     lives in [exp_extra], not wrapping [exp_desc] — so matching the desc is
     enough. *)
  match e.exp_desc with Texp_function _ -> true | _ -> false

(** Syntactic arity of a function binding's RHS: the number of parameters across
    its leading [fun]/[function] chain. A `function <cases>` matches one extra
    argument, so it contributes 1. Used to detect partial (under-saturated)
    applications of same-module functions without relying on type expansion,
    which is unreliable on .cmt-restored environments (arrow type aliases like
    [type unary = int -> int] do not expand there). *)
let rec fn_arity (e : Typedtree.expression) =
  match e.exp_desc with
  | Texp_function (params, Tfunction_body b) -> List.length params + fn_arity b
  | Texp_function (params, Tfunction_cases _) -> List.length params + 1
  | _ -> 0

(** [build_binding_names structure] maps each top-level value binding's
    [Ident.unique_name] to the name its [functions] row is written under
    (issue #41: two top-level [let f = ...] previously merged into one
    [functions] row via [INSERT OR REPLACE] on [UNIQUE(module_id, name)], and
    both bodies' outbound calls landed on whichever definition survived). The
    LAST (source-order-final) binding at a colliding position keeps the bare
    qualified name; every earlier binding takes a [#N] suffix (N counting up
    in source order among the shadowed occurrences only) — mirroring
    [lambda_name]'s ordinal precedent, but with the opposite occurrence kept
    bare. This direction is required, not cosmetic: a cross-module caller can
    only ever reference the bare syntactic name (see [add_path_call]), and
    [fn_lookup] (arch_index.ml) resolves that name with no ordinal awareness,
    so the bare name must denote whichever definition is actually reachable —
    the last one, per OCaml's own same-level shadowing semantics. A binding
    with no same-level collision maps to its plain qualified name, byte-
    identical to pre-fix naming. *)
let build_binding_names (structure : Typedtree.structure) =
  let order : (string, string list ref) Hashtbl.t = Hashtbl.create 64 in
  let record base stamp =
    match Hashtbl.find_opt order base with
    | Some occurrences -> occurrences := stamp :: !occurrences
    | None -> Hashtbl.add order base (ref [ stamp ])
  in
  iter_structure_items structure ~f:(fun ~prefix (it : Typedtree.structure_item) ->
      match it.str_desc with
      | Tstr_value (_, vbs) ->
          List.iter
            (fun (vb : Typedtree.value_binding) ->
              match vb.vb_pat.pat_desc with
              | Tpat_var (id, _, _) when Ident.name id <> "_" ->
                  record (qualify ~prefix (Ident.name id)) (Ident.unique_name id)
              | _ -> ())
            vbs
      | _ -> ()) ;
  let names = Hashtbl.create 64 in
  Hashtbl.iter
    (fun base occurrences_rev ->
      let occurrences = List.rev !occurrences_rev in
      let total = List.length occurrences in
      List.iteri
        (fun i stamp ->
          let bind_name =
            if i = total - 1 then base else Printf.sprintf "%s#%d" base (i + 1)
          in
          Hashtbl.replace names stamp bind_name)
        occurrences)
    order ;
  names

(** [binding_name names ~prefix id] looks up [id]'s assigned name in [names]
    (built by {!build_binding_names} over the same structure). Falls back to
    the plain qualified name if [id] is absent — reachable in practice from
    {!build_local_fn_stamps} below, whose own [Tpat_var] match filters on
    [is_function_rhs] only (not on [Ident.name id <> "_"]), while
    [build_binding_names] excludes wildcard bindings from [names]; harmless
    since [qualify ~prefix "_" = "_"], matching pre-fix behavior. *)
let binding_name names ~prefix id =
  match Hashtbl.find_opt names (Ident.unique_name id) with
  | Some name -> name
  | None -> qualify ~prefix (Ident.name id)

(** Pre-pass shared by the main indexer and the LSP fallback: the table of
    top-level bindings whose RHS is a real function body, mapping the binder's
    [Ident.unique_name] stamp to its syntactic arity. A same-module unqualified
    call resolves to a MUST candidate only if the callee's stamp is in this
    table; everything else (parameters, locals, function-typed values with
    non-function RHS) is unknowable. Whole-structure pass so forward references
    and [let rec … and …] groups are all covered. *)
(* Maps a binding's [Ident.unique_name] to the definition path it is indexed
   under and its arity.  Carrying the path here is what lets a call site name
   its target the way the target is registered: a sibling call inside a functor
   records [Make.spawn], which is the row's name, instead of the bare [spawn],
   which is nothing's name. *)
let build_local_fn_stamps (structure : Typedtree.structure) =
  (* Same-level shadowing (issue #41): a call site must name its target the
     way the target's OWN row is registered, or an intra-module call that
     lexically resolves to an earlier (shadowed) binding gets attributed to
     the later, unrelated one instead — the same misattribution class #41
     fixes, on the inbound/intra-module edge instead of the outbound one. *)
  let binding_names = build_binding_names structure in
  let local_fn_stamps = Hashtbl.create 64 in
  iter_structure_items structure ~f:(fun ~prefix (it : Typedtree.structure_item) ->
      match it.str_desc with
      | Tstr_value (_, vbs) ->
          List.iter
            (fun (vb : Typedtree.value_binding) ->
              match vb.vb_pat.pat_desc with
              | Tpat_var (id, _, _) when is_function_rhs vb.vb_expr ->
                  Hashtbl.replace
                    local_fn_stamps
                    (Ident.unique_name id)
                    (binding_name binding_names ~prefix id, fn_arity vb.vb_expr)
              | _ -> ())
            vbs
      | _ -> ()) ;
  local_fn_stamps

(** Companion to {!build_local_fn_stamps} for the one construct that table
    cannot hold: a top-level binding whose RHS is itself a bare arrow-typed
    identifier — [let t2 = t1], where [t1] is another such binder. Maps the
    binder's [Ident.unique_name] to the definition path it is indexed under,
    exactly as {!build_local_fn_stamps} does, so an edge naming it resolves to
    the row that actually exists.

    Why a SEPARATE table rather than widening [local_fn_stamps]: that table's
    meaning is "a same-module top-level function BODY", and two things read it
    for that meaning — [ident_is_local_fn], which promotes an applied
    identifier to a MUST candidate, and [local_fn_arity], the syntactic arity
    that detects under-saturated applications. An alias binder has no body and
    no syntactic arity ([fn_arity] returns 0 for it), so admitting it there
    would promote every ordinary application of an alias to MUST and hand the
    arity check a 0 that makes every application of it look saturated. Neither
    is this feature's subject. This table is therefore read at exactly ONE site
    — the point-free alias emission in [walk_function_root] — and answers only
    "is this bare identifier a same-module top-level alias binder I can name?".

    No fixpoint and no transitive closure here, and none is needed: each binder
    emits ONE edge to its immediate RHS, so a chain [t3 -> t2 -> t1 -> target]
    is three ordinary edges that every consumer's existing graph traversal
    follows. The chain is bounded by the call graph — and by the cycle handling
    the exception fixpoint already has for [let rec] — not by anything here. *)
let build_local_alias_stamps (structure : Typedtree.structure) =
  let binding_names = build_binding_names structure in
  let local_alias_stamps = Hashtbl.create 16 in
  iter_structure_items structure ~f:(fun ~prefix (it : Typedtree.structure_item) ->
      match it.str_desc with
      | Tstr_value (_, vbs) ->
          List.iter
            (fun (vb : Typedtree.value_binding) ->
              match (vb.vb_pat.pat_desc, vb.vb_expr.exp_desc) with
              (* The same two conditions the emission site applies — a bare
                 identifier RHS ([root == e0]: nothing was peeled, so this is
                 point-free) of arrow type. A wildcard binder is [Tpat_any],
                 not [Tpat_var], so [let _ = g] is excluded structurally. *)
              | Tpat_var (id, _, _), Texp_ident _ when is_arrow_ty vb.vb_expr.exp_type ->
                  Hashtbl.replace
                    local_alias_stamps
                    (Ident.unique_name id)
                    (binding_name binding_names ~prefix id)
              | _ -> ())
            vbs
      | _ -> ()) ;
  local_alias_stamps

(** Module aliases, keyed on BINDER IDENTITY: [Ident.unique_name] of the bound
    module identifier maps to the aliased target's path string.

    The sibling of {!build_local_alias_stamps} — same shape, same reason.  A
    path rooted at a local module binder ([S.safe_int] where the file declares
    [module S = Saturation_repr]) is judged dynamic by [qualified_is_dynamic]
    and sent to ⊤ for "I cannot tell what this module is".  This table answers
    exactly that question, at the site where the ⊤ is decided, so the head can
    be rewritten to the qualified name it denotes before any classification
    happens (specs/reexport-resolution.md D1-quater).

    Keyed on the stamp and NOT on the alias name (D1-bis, FR-012): a nested
    [module S = Test_stub] beside a toplevel [module S = Saturation_repr] would
    be one key under a name and is two keys here, so a production call cannot be
    pointed at a test stub by shadowing.  {b Stamps are unique within a
    compilation unit and not across them}, which is why this table is built per
    [.cmt] and consumed inside that same walk — its scope IS the per-file
    scoping the spec requires, rather than a field that could be forgotten in a
    join.

    Nested binders are included deliberately: [iter_structure_items] descends,
    and the [prefix = ""] gate that (correctly) keeps nested aliases out of
    [module_deps] — a dependency is a property of the FILE — has no business
    here, where the question is what one identifier denotes. *)
let build_module_alias_stamps (structure : Typedtree.structure) =
  let module_alias_stamps = Hashtbl.create 16 in
  iter_structure_items structure ~f:(fun ~prefix:_ (it : Typedtree.structure_item) ->
      match it.str_desc with
      | Tstr_module {mb_id = Some id; mb_expr; _} -> (
          match module_path_of_expr mb_expr with
          | Some target -> Hashtbl.replace module_alias_stamps (Ident.unique_name id) target
          | None ->
              (* A functor application, a literal structure, an unpack: these
                 do not NAME a module defined elsewhere, so there is nothing to
                 rewrite a head to.  The ⊤ stands, which is the honest answer —
                 not a miss to be recovered later. *)
              ())
      | _ -> ()) ;
  module_alias_stamps

(** Walk a value binding expression to collect all function calls.
    [local_fn_stamps] is the set of [Ident.stamp]s of same-module top-level
    function-body bindings; an applied unqualified identifier counts as a
    resolvable (MUST-candidate) call only if its stamp is in this set —
    otherwise it is a parameter / local binding / closure and is MAY_TOP.
    Returns a list of pending calls. *)
let collect_calls_from_expr ?(canon_exn = fun p -> Path.name p) ?(value_channels = [])
    ?(local_alias_stamps = Hashtbl.create 0) ?(module_alias_stamps = Hashtbl.create 0)
    ~src_path ~caller_module ~caller_name
    ~local_fn_stamps (expr : Typedtree.expression) =
  (* Per-node CFG: every function — the top-level binding AND each nested
     lambda node — gets its own lowering context with its own graph, current
     block, and try-dispatch stack. Calls record their (context, block); after
     the walk each graph is solved and a call is conditional unless its block
     post-dominates ITS OWN node's entry. Non-promoted deferred bodies (lazy
     thunks, object methods, functor bodies) walk in ISOLATED blocks of the
     current context — entry-unreachable, hence never always-exec — which
     forces [cond] while guaranteeing the calls are still recorded. *)
  let carrier_of ty = Arch_index_errch.carrier_channel_of_type ~channels:value_channels ty in
  let next_ctx_id = ref 0 in
  let new_ctx caller channel =
    let id = !next_ctx_id in
    incr next_ctx_id ;
    {
      cid = id;
      lg = Arch_index_cfg.create ();
      lblk = Arch_index_cfg.entry;
      lhandlers = [];
      ldeferred = [];
      lcaller = caller;
      lexn = Arch_index_exn.create ();
      lchannel = channel;
      lerrch = Arch_index_errch.create ();
    }
  in
  let root_ctx = new_ctx caller_name (carrier_of expr.exp_type) in
  let all_ctxs = ref [root_ctx] in
  let cur = ref root_ctx in
  (* raw record: (ord, ctx id, block, caller, head, partial, site, exn_scope,
     errch_candidate) — [cond] is resolved after solving every context's
     graph. [ord] is a globally unique, creation-order call id used ONLY to
     retroactively mark a call sunk / handler-covered on a value channel
     (specs/error-channels.md "Sinks" / "Handler scopes") once the AST site
     that determines that (an [ignore], a wildcard [let], a [match]) is
     reached — which happens strictly after the call itself was walked (the
     scrutinee/argument is walked before the site that classifies it). *)
  let raw = ref [] in
  let next_call_ord = ref 0 in
  (* [Texp_apply] location -> the ord of ITS OWN head call, set the instant
     [record_head] emits it — used to resolve a [match]/sink's scrutinee
     back to "the call whose result this is", when that scrutinee IS a call
     (not merely bound to one through a chain of single-variable lets). *)
  let apply_head_ord : (Location.t, int) Hashtbl.t = Hashtbl.create 32 in
  (* Ident stamp -> the ord of the call its single-variable-let chain
     resolves to (specs/error-channels.md "Handler scopes": "a variable
     bound by a chain of single-variable lets to a call"). Absent = not such
     a chain — the safe default (uncovered, propagates). *)
  let let_head_call : (string, int) Hashtbl.t = Hashtbl.create 16 in
  let sunk_ords : (int, unit) Hashtbl.t = Hashtbl.create 8 in
  (* call ord -> (channel, local errch scope id) covering its head. *)
  let errch_call_scope : (int, string * int) Hashtbl.t = Hashtbl.create 8 in
  (* Every ident ever bound by a value-case pattern in THIS walk, by
     [Ident.unique_name]. OCaml's static scoping means such a stamp can only
     ever be referenced from inside that same arm's guard/RHS, so a single
     accumulate-only set (no push/pop discipline) is exactly as precise as a
     properly-scoped stack here — see arch_index_errch.mli's [idents_occur]
     and the "re-return" origin-suppression rule below. *)
  let arm_bound_idents : (string, unit) Hashtbl.t = Hashtbl.create 16 in
  let resolve_head_call (e : Typedtree.expression) =
    match e.exp_desc with
    | Texp_apply _ -> Hashtbl.find_opt apply_head_ord e.exp_loc
    | Texp_ident (Path.Pident id, _, _) -> Hashtbl.find_opt let_head_call (Ident.unique_name id)
    | _ -> None
  in
  let mark_sunk (e : Typedtree.expression) =
    match resolve_head_call e with Some ord -> Hashtbl.replace sunk_ords ord () | None -> ()
  in
  (* [Head_local n]: a SAME-MODULE call, where [n] is already the definition
     path the target is indexed under (e.g. ["Ec_a.add_err"] — see
     [build_local_fn_stamps]/[binding_name]) — the same qualified spelling a
     [binds]/[transforms]/[converters]/[handlers] declaration names, so it
     matches here too (widening this from slice 2's Stdlib-only [binds]
     checks changes nothing for them: no declared path is ever spelled like
     a bare same-module name). *)
  let head_qualified_name = function
    | Head_qualified (Some m, n) -> Some (m ^ "." ^ n)
    | Head_qualified (None, n) -> Some n
    | Head_local n -> Some n
    | _ -> None
  in
  let is_declared_bind (c : Arch_errors_config.channel) head =
    match head_qualified_name head with
    | Some qn -> List.exists (fun p -> Arch_errors_config.path_matches p qn) c.binds
    | None -> false
  in
  (* Bare constructor name off a declared origin path ("Stdlib.Error" ->
     "Error"; "None" -> "None"). *)
  let bare_ctor_name p =
    match String.rindex_opt p '.' with
    | Some i -> String.sub p (i + 1) (String.length p - i - 1)
    | None -> p
  in
  let add_call ?(partial = false) ?is_head_of ?callee_ty ?edge_form head loc =
    let line = loc.Location.loc_start.pos_lnum in
    let call_site = Printf.sprintf "%s:%d" src_path line in
    let c = !cur in
    let exn_scope = Arch_index_exn.current_scope c.lexn in
    let ord = !next_call_ord in
    incr next_call_ord ;
    (match is_head_of with
    | Some hloc -> Hashtbl.replace apply_head_ord hloc ord
    | None -> ()) ;
    let errch_candidate =
      match (c.lchannel, callee_ty) with
      | Some caller_c, Some cty -> (
          match carrier_of cty with
          | Some callee_c
            when callee_c.Arch_errors_config.name = caller_c.Arch_errors_config.name
                 && not (is_declared_bind caller_c head) ->
              Some caller_c.Arch_errors_config.name
          | _ -> None)
      | _ -> None
    in
    raw :=
      ( ord, c.cid, c.lblk, c.lcaller, head, partial, call_site, exn_scope,
        errch_candidate, edge_form )
      :: !raw
  in
  (* Current-context CFG shorthands. *)
  let blk () = (!cur).lblk in
  let set_blk b = (!cur).lblk <- b in
  let new_blk () = Arch_index_cfg.new_block (!cur).lg in
  (* A fresh block that is a DEFERRED entry point rather than an accident of the
     lowering. Isolation is deliberate — it is what makes the enclosed calls
     conditional — but the block is registered so it is not also read as
     unreachable-hence-deletable. *)
  let deferred_blk () =
    let b = new_blk () in
    (!cur).ldeferred <- b :: (!cur).ldeferred ;
    b
  in
  let edge a b = Arch_index_cfg.add_edge (!cur).lg a b in
  (* Collected synthetic lambda nodes. *)
  let lambdas = ref [] in
  (* marker → occurrence count, for the [#N] collision ordinal *)
  let markers = Hashtbl.create 8 in
  (* literal loc → assigned node name (filled at visit; read by apply heads) *)
  let lam_names = Hashtbl.create 8 in
  (* locs of literals that are a let-binding RHS: the BINDING itself is not an
     occurrence — a never-referenced lambda gets no parent→lambda edge. *)
  let binding_literals = Hashtbl.create 8 in
  (* Local let-bound literals: [Ident.unique_name] stamp → (lambda node name,
     syntactic arity). Stamps are globally unique per binder (every OCaml [let]
     introduces a fresh Ident), so a flat table is scope-correct: shadowing and
     rebinding create NEW stamps that simply are not in the table. Only a
     [Tpat_var] pattern with a SINGLE literal RHS is recorded — conditional
     bindings, tuple patterns, and aliases stay unknowable (MAY_TOP). *)
  let local_lam_stamps = Hashtbl.create 8 in
  let lam_stamp id = Hashtbl.find_opt local_lam_stamps (Ident.unique_name id) in
  (* locs of stamped idents consumed as APPLY HEADS: their edge is emitted by
     the head classification (Head_local, possibly MUST); the generic
     Texp_ident occurrence case must not also emit an escape edge for them. *)
  let head_idents = Hashtbl.create 8 in
  (* forward ref: walks a promoted literal's peeled body in the current ctx
     (defined after the iterator, which it mutually uses). *)
  let walk_fn_body_ref =
    ref (fun (_ : Typedtree.expression) ->
        invalid_arg "walk_fn_body_ref used before initialization")
  in
  (* Node name for a literal at [loc], chained under the current caller:
     [<caller>.<fun:LINE:COL>] with 1-based column and a [#N] in-marker ordinal
     on a same-position collision (ghost/ppx locs). *)
  let lambda_name (loc : Location.t) =
    let p = loc.loc_start in
    let line = p.pos_lnum and col = p.pos_cnum - p.pos_bol + 1 in
    let base = Printf.sprintf "%s.<fun:%d:%d" (!cur).lcaller line col in
    let n = (try Hashtbl.find markers base with Not_found -> 0) + 1 in
    Hashtbl.replace markers base n ;
    if n = 1 then base ^ ">" else Printf.sprintf "%s#%d>" base n
  in
  (* An applied [Path.Pident] resolves to a MUST-candidate only if it is a
     same-module top-level function body; otherwise it is a parameter / local
     closure with an unknowable target → MAY_TOP. *)
  let ident_is_local_fn id = Hashtbl.mem local_fn_stamps (Ident.unique_name id) in
  let local_fn_arity id =
    Option.map snd (Hashtbl.find_opt local_fn_stamps (Ident.unique_name id))
  in
  (* The definition path the target is indexed under: what a call site must
     record for the edge to resolve. *)
  let local_fn_name id =
    match Hashtbl.find_opt local_fn_stamps (Ident.unique_name id) with
    | Some (name, _) -> name
    | None -> Ident.name id
  in
  (* The definition path of a same-module top-level ALIAS binder (see
     {!build_local_alias_stamps}), or [None] when this identifier is not one.
     Deliberately NOT folded into [ident_is_local_fn]/[local_fn_name]: those
     answer "is this a function body I may treat as a MUST candidate", and an
     alias binder is not. Read at one site only. *)
  let local_alias_name id = Hashtbl.find_opt local_alias_stamps (Ident.unique_name id) in
  (* True iff [ty] is SYNTACTICALLY a function type. No alias expansion:
     .cmt-restored environments do not carry manifest type declarations, so
     [type unary = int -> int] cannot be expanded here. Same-module partial
     applications are protected by the SYNTACTIC arity tables instead
     (local_fn_stamps / local_lam_stamps); the residual is a CROSS-module
     partial application whose result arrow hides behind an alias in the
     callee's interface — its head stays MUST (documented residual). *)
  let is_arrow ty = is_arrow_ty ty in
  (* Number of leading arrows in a function type = its (maximal) arity. Uses
     the raw type — no env-based expansion, which is unreliable on .cmt-restored
     environments (they do not carry manifest type declarations, so an alias
     like [type unary = int -> int] will not expand). A callee's own type is a
     concrete arrow chain, so counting arrows there is reliable. *)
  let rec arrow_arity ty =
    match Types.get_desc ty with
    | Tarrow (_, _, res, _) -> 1 + arrow_arity res
    | _ -> 0
  in
  (* A qualified call whose module-path ROOT is a non-persistent ident is
     resolved through a first-class-module / functor parameter or local module —
     the target is caller-supplied / dynamic, so it MUST be MAY_TOP, not a
     closed MUST leaf (persistent roots = real compilation units: List, Stdlib,
     in-repo modules — those stay resolvable). *)
  let rec path_root = function
    | Path.Pident id -> Some id
    | Path.Pdot (p, _) | Path.Papply (p, _) | Path.Pextra_ty (p, _) -> path_root p
  in
  let qualified_is_dynamic path =
    match path_root path with Some id -> not (Ident.persistent id) | None -> false
  in
  (* [S.safe_int] where this file declares [module S = Saturation_repr] is
     dynamic by the test above — the root binder is not persistent — and would
     go to ⊤ with reason [Module_param] for "I cannot tell what this module is".
     But the binder's stamp is in hand RIGHT HERE, and
     {!build_module_alias_stamps} answers exactly that question, so the head can
     be rewritten to the qualified name it denotes and classified normally
     (specs/reexport-resolution.md D1-quater).

     Returns the rewritten [(module, name)] pair, or [None] to leave the ⊤
     standing.  [None] is the answer whenever anything is not certain:
     - the root binder is not an alias (a genuine functor parameter — the
       conflation [qualified_is_dynamic] makes is sound, and this only splits
       off the half we now have evidence for);
     - the path contains a functor application or an extra-type node, which
       name no module this table could denote.

     The rewritten edge carries [edge_form = "module_alias"] at every emission
     site, which the kind matrix demotes (FR-011): the rewrite discharges the
     NAMING conjunct of MUST and leaves uniqueness and saturation standing, so
     no rewritten edge may be MUST however its head classifies. *)
  let segments_below_root path =
    let rec go = function
      | Path.Pident _ -> Some []
      | Path.Pdot (p, seg) -> (
          match go p with Some segs -> Some (segs @ [seg]) | None -> None)
      | Path.Papply _ | Path.Pextra_ty _ -> None
    in
    go path
  in
  let alias_rewrite path =
    match path_root path with
    | Some id when not (Ident.persistent id) -> (
        match Hashtbl.find_opt module_alias_stamps (Ident.unique_name id) with
        | None -> None
        | Some target -> (
            match segments_below_root path with
            | Some (_ :: _ as segs) ->
                (* The last segment is the value name; any segments between the
                   root and it extend the target's module path — [S.Syntax.+]
                   becomes [<target>.Syntax] / [+]. *)
                let rec split_last acc = function
                  | [last] -> (List.rev acc, last)
                  | seg :: tl -> split_last (seg :: acc) tl
                  | [] -> assert false
                in
                let mods, name = split_last [] segs in
                Some (String.concat "." (target :: mods), name)
            | _ -> None))
    | _ -> None
  in
  (* A function-typed argument may be invoked by the callee. A named local
     function → bounded candidate (Head_enumerated); a parameter / external /
     computed function value → unknowable (Head_unknown). Conditionality is a
     separate fact, decided by the block. *)
  let add_arg_escapes (args : (_ * Typedtree.expression option) list) loc =
    List.iter
      (fun (_, arg_opt) ->
        match arg_opt with
        | Some ae when is_arrow ae.Typedtree.exp_type -> (
            match ae.exp_desc with
            | Texp_function _ ->
                (* Literal argument: the literal's own visit emits the
                   parent→lambda MAY_ENUMERATED edge — the old ⊤ arg-escape
                   row is REPLACED by that enumerated edge (FR-012). *)
                ()
            | Texp_ident (Path.Pident id, _, _) when ident_is_local_fn id ->
                add_call ~callee_ty:ae.exp_type (Head_enumerated (local_fn_name id)) loc
            | Texp_ident (Path.Pident id, _, _) when lam_stamp id <> None ->
                (* Let-bound lambda passed by name: the generic Texp_ident
                   occurrence case emits the enumerated edge — nothing here. *)
                ()
            | Texp_ident (Path.Pident id, _, _) ->
                add_call ~callee_ty:ae.exp_type (Head_unknown (Ident.name id, Callback_param)) loc
            | Texp_ident ((Path.Pdot _ as p), _, _) ->
                (* FIX (review, LOW): the other two Module_param sites
                   (add_path_call, record_head) display the qualified name
                   ["module.name"]; this one displayed the bare name only,
                   so the same functor member showed up under two different
                   spellings depending on which syntactic position invoked
                   it. *)
                let m, n = path_to_module_name p in
                let disp = match m with Some m -> m ^ "." ^ n | None -> n in
                (match alias_rewrite p with
                | Some (m, n) ->
                    add_call ~callee_ty:ae.exp_type ~edge_form:"module_alias"
                      (Head_qualified (Some m, n)) loc
                | None ->
                    let reason =
                      if qualified_is_dynamic p then Module_param else Callback_param
                    in
                    add_call ~callee_ty:ae.exp_type (Head_unknown (disp, reason)) loc)
            | _ -> add_call ~callee_ty:ae.exp_type (Head_unknown ("*TOP*", Callback_param)) loc
            (* computed function value *))
        | _ -> ())
      args
  in
  (* Emit a call to a function named by a resolved [Path.t] — e.g. a let*/and*
     bind operator, which is applied but is not a [Texp_apply] node. *)
  let add_path_call ?edge_form (path : Path.t) loc =
    (* An alias-rewritten head must be demoted (FR-011), but a caller that
       already named a form has said something narrower about the SITE — a
       point-free [let f = S.g] is a [value_alias] whether or not [S] is an
       alias — so the caller's form wins.  Both values demote identically, so
       precedence changes the recorded reason, never the kind. *)
    let alias_form = match edge_form with Some _ -> edge_form | None -> Some "module_alias" in
    let add_call_aliased head loc = add_call ?edge_form:alias_form head loc in
    let add_call = add_call ?edge_form in
    note_seen_value_path (Path.name path) ;
    match path with
    | Path.Pident id when ident_is_local_fn id ->
        add_call (Head_local (local_fn_name id)) loc
    | Path.Pident id -> add_call (Head_unknown (Ident.name id, Callback_param)) loc
    | _ ->
        let callee_module, callee_name = path_to_module_name path in
        match alias_rewrite path with
        | Some (m, n) -> add_call_aliased (Head_qualified (Some m, n)) loc
        | None ->
            if qualified_is_dynamic path then
              let disp =
                match callee_module with
                | Some m -> m ^ "." ^ callee_name
                | None -> callee_name
              in
              add_call (Head_unknown (disp, Module_param)) loc
            else add_call (Head_qualified (callee_module, callee_name)) loc
  in
  (* SLICE 3 (specs/error-channels.md "Binds"/"Transforms"/"Converters"):
     classify an application's head the same way [record_head] eventually
     will, but WITHOUT emitting anything — used only to look the head up
     against declared [binds]/[transforms]/[converters]/[handlers] paths and
     against [Arch_index_errch.bind_shape_channel]'s undeclared-bind check.
     Mirrors [record_head]'s [Texp_ident] cases (a lambda-stamp head never
     names a declared config path, so that branch is folded into
     [Head_unknown] here — harmless, it just never matches). *)
  let classify_head_path (fn_expr : Typedtree.expression) : call_head option =
    match fn_expr.exp_desc with
    | Texp_ident (Path.Pident id, _, _) when ident_is_local_fn id ->
        Some (Head_local (local_fn_name id))
    | Texp_ident (Path.Pident id, _, _) -> Some (Head_unknown (Ident.name id, Callback_param))
    | Texp_ident (path, _, _) ->
        let callee_module, callee_name = path_to_module_name path in
        if qualified_is_dynamic path then
          let disp =
            match callee_module with Some m -> m ^ "." ^ callee_name | None -> callee_name
          in
          Some (Head_unknown (disp, Module_param))
        else Some (Head_qualified (callee_module, callee_name))
    | _ -> None
  in
  let path_declared paths head =
    match head_qualified_name head with
    | Some qn -> List.exists (fun p -> Arch_errors_config.path_matches p qn) paths
    | None -> false
  in
  let find_transform head =
    match head_qualified_name head with
    | None -> None
    | Some qn ->
        List.find_map
          (fun (ch : Arch_errors_config.channel) ->
            List.find_map
              (fun (p, mode, argpos) ->
                if Arch_errors_config.path_matches p qn then Some (ch, mode, argpos) else None)
              ch.Arch_errors_config.transforms)
          value_channels
  in
  let find_converter head =
    match head_qualified_name head with
    | None -> None
    | Some qn ->
        List.find_map
          (fun (ch : Arch_errors_config.channel) ->
            List.find_map
              (fun (p, from_, to_, argpos, err) ->
                if Arch_errors_config.path_matches p qn then Some (from_, to_, argpos, err)
                else None)
              ch.Arch_errors_config.converters)
          value_channels
  in
  let find_handler head =
    match head_qualified_name head with
    | None -> None
    | Some qn ->
        List.find_map
          (fun (ch : Arch_errors_config.channel) ->
            List.find_map
              (fun (p, argpos) ->
                if Arch_errors_config.path_matches p qn then Some (ch, argpos) else None)
              ch.Arch_errors_config.handlers)
          value_channels
  in
  (* SLICE 4 (specs/error-channels.md "Origins"): a declared origin that is
     an ordinary FUNCTION, not a constructor (the Tezos idiom [error E]/
     [tzfail E]/[error_when cond E] — [Texp_construct] only covers the
     [Stdlib.Error]/[None]-style channels). The literal argument at [argpos]
     names the error the same way a transform's [Add] argument does. *)
  let find_origin head =
    match head_qualified_name head with
    | None -> None
    | Some qn ->
        List.find_map
          (fun (ch : Arch_errors_config.channel) ->
            List.find_map
              (fun (p, argpos) ->
                if Arch_errors_config.path_matches p qn then Some (ch, argpos) else None)
              ch.Arch_errors_config.origins)
          value_channels
  in
  (* Peel a lambda literal's curried parameters down to its final body
     expression; [None] for a [function | p -> …] (pattern-matching mapper —
     unsupported, the caller falls back to ⊤, the safe side). *)
  let rec literal_return_of_lambda (e : Typedtree.expression) =
    match e.exp_desc with
    | Texp_function (_, Tfunction_body b) -> literal_return_of_lambda b
    | Texp_function (_, Tfunction_cases _) -> None
    | _ -> Some e
  in
  (* SLICE 4 (found by the proto_alpha oracle smoke, O-5 — [catch_f]): a
     [handlers]/[converters] "guarded argument" is usually a CALL or an
     alias to one ([resolve_head_call] handles both), but the Tezos [catch]/
     [catch_f]/[catch_s] idiom guards a THUNK LITERAL — [fun () -> risky ()]
     — which is not itself a call, so [resolve_head_call] on the lambda
     expression answers [None] and the scope never covers anything. Peel
     the thunk to its body first (arguments are walked, hence
     [apply_head_ord] populated, before this code runs — see
     [record_head]'s ordering note above) and resolve THAT. *)
  let resolve_guarded_call (e : Typedtree.expression) =
    match resolve_head_call e with
    | Some _ as r -> r
    | None -> (
        match e.exp_desc with
        | Texp_function _ -> (
            match literal_return_of_lambda e with Some body -> resolve_head_call body | None -> None)
        | _ -> None)
  in
  (* Diverging (noreturn) application head: a SATURATED call whose head Path
     resolves to a Stdlib primitive that never returns. Path-based detection is
     shadow-proof (a local [let failwith x = …] resolves to a Pident, not
     Stdlib); [raise] as an argument / partial / eta-expanded is not an applied
     head here. All listed heads have arity 1. *)
  let noreturn_head (fn : Typedtree.expression) nargs =
    nargs >= 1
    && (* Any [%raise] primitive never returns, whatever path re-exports it
          (the protocol environment's [raise]) — the same recogniser the
          exception-identity pass uses, so the two cannot disagree on what a
          raise is. The Stdlib-path cases below add failwith/invalid_arg/exit,
          which are ordinary functions, not primitives. *)
       Arch_index_exn.is_raise_head fn
       ||
       match fn.exp_desc with
    | Texp_ident (path, _, _) -> (
        (* The root must be the PERSISTENT Stdlib compilation unit — a local
           module named Stdlib (non-persistent root) must not terminate. *)
        (not (qualified_is_dynamic path))
        &&
        match path_to_module_name path with
        | ( Some "Stdlib",
            ("raise" | "raise_notrace" | "failwith" | "invalid_arg" | "exit") )
          ->
            true
        | _ -> false)
    | _ -> false
  in
  (* Terminate the current block as diverging: inside a [try] body it FIRST
     edges to the innermost handler dispatch (the handler may catch — added
     before [terminate], which freezes successors) and always flows to the
     virtual exit (the handler may not match / no handler). Execution resumes
     in a fresh block with NO incoming edge: code after the divergence is
     entry-unreachable → recorded, demoted, never dropped. *)
  let diverge () =
    (match (!cur).lhandlers with
    | dispatch :: _ -> edge (blk ()) dispatch
    | [] -> ()) ;
    Arch_index_cfg.terminate (!cur).lg (blk ()) ;
    set_blk (new_blk ())
  in
  (* [&&] and [||] short-circuit: the right operand runs only conditionally. *)
  let short_circuit_arity (fn : Typedtree.expression) =
    match fn.exp_desc with
    | Texp_ident (path, _, _) -> (
        let _, name = path_to_module_name path in
        match name with "&&" | "||" -> Some () | _ -> None)
    | _ -> None
  in
  let open Tast_iterator in
  let iter =
    {
      default_iterator with
      expr =
        (fun self expr ->
          (* Walk [e] in a fresh CONDITIONAL block branching off the current
             one: current → b …(walk)… → join, current → join. The walked
             region never post-dominates the entry (the join bypass exists),
             so its calls are demoted; execution continues in [join]. *)
          let walk_conditional e =
            let b = new_blk () in
            let join = new_blk () in
            edge (blk ()) b ;
            edge (blk ()) join ;
            set_blk b ;
            self.expr self e ;
            edge (blk ()) join ;
            set_blk join
          in
          (* Walk [e] in an ISOLATED block (no incoming edge): a deferred body
             (closure/lazy/object) whose calls are recorded but can never be
             always-exec. The current block is untouched. *)
          let walk_isolated_default () =
            let saved = (blk ()) in
            set_blk (deferred_blk ()) ;
            (* A deferred body runs outside any lexically enclosing handler:
               its exception scope stack is cleared in lockstep with the CFG
               block isolation. *)
            Arch_index_exn.with_cleared_scopes (!cur).lexn (fun () ->
                default_iterator.expr self expr) ;
            set_blk saved
          in
          (* A match/try case walked inside an already-conditional block:
             guard and RHS execute only if the pattern matches. *)
          let walk_case_in : type k. k Typedtree.case -> unit =
           fun c ->
            (match c.c_guard with Some gd -> self.expr self gd | None -> ()) ;
            self.expr self c.c_rhs
          in
          match expr.exp_desc with
          | Texp_function _ ->
              (* A nested [fun …]/[function] literal is PROMOTED to its own
                 synthetic node: register the node, emit a parent→lambda
                 occurrence edge (unless this literal is a let-binding RHS —
                 zero-occurrence lambdas get no edge; head applications and
                 escapes of the bound name emit per-occurrence edges instead),
                 and walk the body in the lambda's OWN context (own CFG: its
                 calls attribute to the node and MUST = post-dominates the
                 LAMBDA's entry). *)
              let name = lambda_name expr.exp_loc in
              Hashtbl.replace lam_names expr.exp_loc name ;
              lambdas :=
                {
                  lam_name = name;
                  lam_line_start = expr.exp_loc.loc_start.pos_lnum;
                  lam_line_end = expr.exp_loc.loc_end.pos_lnum;
                  lam_arity = fn_arity expr;
                }
                :: !lambdas ;
              if not (Hashtbl.mem binding_literals expr.exp_loc) then
                add_call ~callee_ty:expr.exp_type (Head_enumerated name) expr.exp_loc ;
              let saved = !cur in
              let c = new_ctx name (carrier_of expr.exp_type) in
              all_ctxs := c :: !all_ctxs ;
              cur := c ;
              !walk_fn_body_ref expr ;
              cur := saved
          | Texp_let (_, vbs, body) ->
              (* Single-literal [Tpat_var] binding RHSs: the BINDING is not an
                 occurrence (a never-referenced lambda gets no edge). Each RHS
                 walk assigns the literal's node name; the binder's stamp is
                 then recorded → (node, arity) BEFORE the let body walks, so
                 head applications of the bound name resolve to the lambda node
                 (MUST when always-exec + saturated) and escapes of the name
                 become enumerated occurrence edges. Stamps are unique per
                 binder (fresh Ident per [let]), so shadowing/rebinding create
                 new stamps and no eviction is needed. *)
              List.iter
                (fun (vb : Typedtree.value_binding) ->
                  (match (vb.vb_pat.pat_desc, vb.vb_expr.exp_desc) with
                  | Tpat_var _, Texp_function _ ->
                      Hashtbl.replace binding_literals vb.vb_expr.exp_loc ()
                  | _ -> ()) ;
                  default_iterator.value_binding self vb ;
                  (match (vb.vb_pat.pat_desc, vb.vb_expr.exp_desc) with
                  | Tpat_var (id, _, _), Texp_function _ -> (
                      match Hashtbl.find_opt lam_names vb.vb_expr.exp_loc with
                      | Some node_name ->
                          Hashtbl.replace
                            local_lam_stamps
                            (Ident.unique_name id)
                            (node_name, fn_arity vb.vb_expr)
                      | None -> ())
                  | _ -> ()) ;
                  (* Value-channel single-variable-let alias chain
                     (specs/error-channels.md "Handler scopes"): [id] resolves
                     to a head call's ord either directly (its RHS IS that
                     call) or by chaining through an earlier such stamp. *)
                  (match vb.vb_pat.pat_desc with
                  | Tpat_var (id, _, _) -> (
                      match vb.vb_expr.exp_desc with
                      | Texp_apply _ -> (
                          match Hashtbl.find_opt apply_head_ord vb.vb_expr.exp_loc with
                          | Some ord -> Hashtbl.replace let_head_call (Ident.unique_name id) ord
                          | None -> ())
                      | Texp_ident (Path.Pident aliased, _, _) -> (
                          match Hashtbl.find_opt let_head_call (Ident.unique_name aliased) with
                          | Some ord -> Hashtbl.replace let_head_call (Ident.unique_name id) ord
                          | None -> ())
                      | _ -> ())
                  | _ -> ()) ;
                  (* Sinks (specs/error-channels.md "Sinks"): [let _ = E in …]
                     — the head call of [E] does not propagate. *)
                  (match vb.vb_pat.pat_desc with
                  | Tpat_any -> mark_sunk vb.vb_expr
                  | Tpat_var (id, _, _) when Ident.name id = "_" -> mark_sunk vb.vb_expr
                  | _ -> ()))
                vbs ;
              self.expr self body
          | Texp_ident (Path.Pident id, _, _)
            when lam_stamp id <> None
                 && not (Hashtbl.mem head_idents expr.exp_loc) ->
              (* ANY non-head occurrence of a let-bound lambda's name — as an
                 argument, in a record field, tuple, ref store, or return
                 position — is an escape site: the lambda may be invoked from
                 wherever the value flows, so emit a parent→lambda
                 MAY_ENUMERATED edge here. Without this, a stored lambda's node
                 is orphaned and everything reachable only through its body
                 falsely reads as dead/unreachable. *)
              (match lam_stamp id with
              | Some (node_name, _) ->
                  add_call ~callee_ty:expr.exp_type (Head_enumerated node_name) expr.exp_loc
              | None -> ())
          | Texp_lazy _ | Texp_object _ ->
              (* Non-promoted deferred boundaries: a lazy thunk or an object's
                 method bodies run only if forced/invoked — walked in an
                 isolated (never always-exec) block so their calls are
                 recorded, demoted, never dropped. *)
              walk_isolated_default ()
          | Texp_ifthenelse (cond, e_then, e_else) ->
              (* Condition runs unconditionally; each branch is a CFG arm. *)
              self.expr self cond ;
              let c_end = (blk ()) in
              let join = new_blk () in
              let bt = new_blk () in
              edge c_end bt ;
              set_blk bt ;
              self.expr self e_then ;
              edge (blk ()) join ;
              (match e_else with
              | Some e ->
                  let bf = new_blk () in
                  edge c_end bf ;
                  set_blk bf ;
                  self.expr self e ;
                  edge (blk ()) join
              | None -> edge c_end join) ;
              set_blk join
          | Texp_match (scrut, comp_cases, val_cases, partiality) ->
              (* Scrutinee runs unconditionally; every arm is a CFG branch.
                 A single TOTAL unguarded arm post-dominates the entry (it
                 always runs — e.g. [match e with () -> body]) and its calls
                 are legitimately MUST. A [Partial] match (refutable pattern /
                 guard) additionally gets a Match_failure BYPASS edge so a
                 lone arm can never forge a MUST. *)
              (* Exception arms cover the SCRUTINEE only: the scope is entered
                 around it and left before any arm walks. *)
              let exn_arms = Arch_index_exn.exception_arms comp_cases in
              let scoped = exn_arms <> [] in
              if scoped then
                ignore
                  (Arch_index_exn.enter_scope (!cur).lexn ~canon:canon_exn
                     ~form:Arch_index_exn.Match_exception ~loc:expr.exp_loc ~arms:exn_arms
                    : int) ;
              self.expr self scrut ;
              if scoped then Arch_index_exn.leave_scope (!cur).lexn ;
              (* Value-channel handler scopes (specs/error-channels.md
                 "Handler scopes"): [match E with Error p -> rhs | …] covers
                 the HEAD CALL of [E] — resolvable only once [scrut] above has
                 been walked (a direct call sets [apply_head_ord] during that
                 walk; an alias chain was set earlier, at its own [let]). *)
              (* Ordinary value arms of a [match] live in [comp_cases],
                 wrapped [Tpat_value] (Typedtree.mli: only an [effect P k] arm
                 lands in [val_cases]) — but an arm-level or-pattern is a
                 [Tpat_or] AT THIS LEVEL, so the wrapper has to be stripped
                 through the disjunction rather than off the top.
                 [Arch_index_exn.value_pats_of_computation] does that, over the
                 same traversal the exception side uses; its .mli states the
                 rule and the shape once. Behaviour pinned by [arm_level_or]
                 and [arm_level_or_wild] in tezt/tests/error_channels.ml. *)
              let value_arms = Arch_index_exn.value_pats_of_computation comp_cases in
              (* The scrutinee's OWN type picks at most one channel — scanning
                 every declared channel's origin constructor NAME against
                 every arm (without this) would let an unrelated same-named
                 constructor of a totally different type (any user type
                 happening to also declare an [Error] case) spuriously
                 "match" a channel it has nothing to do with. *)
              (match carrier_of scrut.exp_type with
              | None -> ()
              | Some c ->
                  List.iter
                    (fun (opath, pos) ->
                      let bare = bare_ctor_name opath in
                      let matched =
                        List.filter_map
                          (fun (pat, guard, rhs) ->
                            match
                              Arch_index_errch.classify_value_pat ~canon_type:canon_exn ~canon_exn
                                ~bare_ctor:bare ~arg_pos:pos pat
                            with
                            | Some (cls, bound) -> Some ((guard, rhs), cls, bound)
                            | None -> None)
                          value_arms
                      in
                      if matched <> [] then begin
                        List.iter
                          (fun (_, _, bound) ->
                            List.iter (fun id -> Hashtbl.replace arm_bound_idents id ()) bound)
                          matched ;
                        let catch_all = ref false and caught = ref [] in
                        List.iter
                          (fun ((guard, rhs), (cls : Arch_index_errch.pat_class), bound) ->
                            let closing =
                              guard = None && not (Arch_index_errch.idents_occur ~idents:bound rhs)
                            in
                            (* An empty [caught] with [catch_all = false]
                               closes nothing: the arm matches a real subset we
                               cannot name, so subtracting anything here would
                               drop an error the call can still return. *)
                            if closing then (
                              if cls.catch_all then catch_all := true ;
                              caught := cls.caught @ !caught))
                          matched ;
                        match resolve_head_call scrut with
                        | Some ord ->
                            let local_id =
                              Arch_index_errch.add_scope
                                (!cur).lerrch
                                ~channel:c.Arch_errors_config.name
                                ~catch_all:!catch_all
                                ~caught:!caught
                                ~loc:expr.exp_loc
                            in
                            Hashtbl.replace errch_call_scope ord (c.Arch_errors_config.name, local_id)
                        | None -> ()
                      end)
                    c.Arch_errors_config.origins) ;
              if partiality = Partial then
                Arch_index_exn.record_partial (!cur).lexn ~loc:expr.exp_loc ;
              let s_end = (blk ()) in
              let join = new_blk () in
              if partiality = Partial then edge s_end join ;
              let walk_arm : type k. k Typedtree.case -> unit =
               fun c ->
                let arm = new_blk () in
                edge s_end arm ;
                set_blk arm ;
                walk_case_in c ;
                edge (blk ()) join
              in
              List.iter walk_arm comp_cases ;
              List.iter walk_arm val_cases ;
              set_blk join
          | Texp_try (body, val_cases, eff_cases) ->
              (* The try body runs unconditionally. Handlers hang off a
                 dispatch block that BRANCHES from the body's end (an exception
                 "may or may not" occur), so a handler never post-dominates the
                 entry. A diverging terminator inside the body (step 3) also
                 edges to the dispatch: the handler may catch — and to the
                 virtual exit: it may not match. *)
              let dispatch = new_blk () in
              (!cur).lhandlers <- dispatch :: (!cur).lhandlers ;
              (* The exception scope is the BODY, lexically — pushed and popped
                 in lockstep with the CFG dispatch block so the two cannot
                 drift. Effect arms are not exception handlers. *)
              ignore
                (Arch_index_exn.enter_scope (!cur).lexn ~canon:canon_exn
                   ~form:Arch_index_exn.Try ~loc:expr.exp_loc
                   ~arms:(Arch_index_exn.value_arms val_cases)
                  : int) ;
              self.expr self body ;
              Arch_index_exn.leave_scope (!cur).lexn ;
              (match (!cur).lhandlers with
              | _ :: tl -> (!cur).lhandlers <- tl
              | [] -> ()) ;
              let b_end = (blk ()) in
              let join = new_blk () in
              edge b_end join ;
              edge b_end dispatch ;
              let walk_handler : type k. k Typedtree.case -> unit =
               fun c ->
                let h = new_blk () in
                edge dispatch h ;
                set_blk h ;
                walk_case_in c ;
                edge (blk ()) join
              in
              List.iter walk_handler val_cases ;
              List.iter walk_handler eff_cases ;
              set_blk join
          | Texp_while (cond, body) ->
              (* head → {body → head, after}: condition evaluated on every
                 iteration path; body may run zero times. No constant folding —
                 [while true] keeps its exit edge (documented termination-
                 insensitivity residual). *)
              let head = new_blk () in
              edge (blk ()) head ;
              set_blk head ;
              self.expr self cond ;
              let c_end = (blk ()) in
              let bodyb = new_blk () in
              let after = new_blk () in
              edge c_end bodyb ;
              edge c_end after ;
              set_blk bodyb ;
              self.expr self body ;
              edge (blk ()) head ;
              set_blk after
          | Texp_for (_, _, lo, hi, _, body) ->
              (* Bounds run unconditionally; body may run zero times. *)
              self.expr self lo ;
              self.expr self hi ;
              let head = new_blk () in
              edge (blk ()) head ;
              let bodyb = new_blk () in
              let after = new_blk () in
              edge head bodyb ;
              edge head after ;
              set_blk bodyb ;
              self.expr self body ;
              edge (blk ()) head ;
              set_blk after
          | Texp_assert (e, _) -> (
              Arch_index_exn.record_assert (!cur).lexn ~loc:expr.exp_loc ;
              match e.exp_desc with
              | Texp_construct (_, {cstr_name = "false"; _}, _) ->
                  (* [assert false] is NEVER elided by -noassert (compiler
                     special case) and always diverges → block terminator. *)
                  diverge ()
              | _ ->
                  (* Ordinary assertion: condition elided under -noassert →
                     conditional; fall-through only (may-raise is the accepted
                     exception-insensitivity residual). *)
                  walk_conditional e)
          | Texp_letop {let_; ands; body; _} ->
              (* [let* y = e and* z = e' in body]: the operands run eagerly and
                 the bind operators are applied AFTER them — so the operand
                 expressions are walked first and the operator calls recorded in
                 the block reached afterwards (a diverging operand like
                 [let* y = raise Exit in …] demotes the operator, same ordering
                 rule as Texp_apply). [body] is the continuation the bind
                 operator may or may not invoke → a conditional region. *)
              self.expr self let_.bop_exp ;
              List.iter
                (fun (b : Typedtree.binding_op) -> self.expr self b.bop_exp)
                ands ;
              add_path_call let_.bop_op_path let_.bop_loc ;
              List.iter
                (fun (b : Typedtree.binding_op) ->
                  add_path_call b.bop_op_path b.bop_loc)
                ands ;
              let c = new_blk () in
              let join = new_blk () in
              edge (blk ()) c ;
              edge (blk ()) join ;
              set_blk c ;
              walk_case_in body ;
              edge (blk ()) join ;
              set_blk join
          | Texp_apply (fn_expr, args) ->
              (* A partial application supplies fewer arguments than the callee's
                 arity: it builds a closure and does NOT run the callee's body,
                 so it must never be a MUST edge. We cannot read a callee's
                 syntactic arity at the call site, but the application's own
                 result type tells us: if it is still a function (arrow), the
                 call is under-saturated (or returns a function whose body runs
                 later) → treat as deferred (MAY_TOP), never MUST. *)
              (* Callee arity: for a same-module function use its *syntactic*
                 arity (pre-pass), reliable even when a type-alias-hidden arrow
                 defeats type inspection on a .cmt-restored env; otherwise use
                 the callee's type arrow arity. *)
              let nargs = List.length args in
              (* A literal head's edge is emitted by record_head (Head_local to
                 the node) — suppress the literal visit's occurrence edge. *)
              (match fn_expr.exp_desc with
              | Texp_function _ ->
                  Hashtbl.replace binding_literals fn_expr.exp_loc ()
              | _ -> ()) ;
              let head_arity =
                match fn_expr.exp_desc with
                | Texp_ident (Path.Pident id, _, _) when ident_is_local_fn id ->
                    (match local_fn_arity id with
                     | Some a -> a
                     | None -> arrow_arity fn_expr.exp_type)
                | Texp_ident (Path.Pident id, _, _) -> (
                    match lam_stamp id with
                    | Some (_, a) ->
                        (* head consumption of a stamped lambda: the head
                           classification emits its edge — suppress the generic
                           occurrence case for this loc. *)
                        Hashtbl.replace head_idents fn_expr.exp_loc () ;
                        a
                    | None -> arrow_arity fn_expr.exp_type)
                | _ -> arrow_arity fn_expr.exp_type
              in
              (* Under-saturated (partial) application → builds a closure, the
                 callee body does not run → never MUST. A result that is itself
                 a function (arrow) is also under-saturated / returns-a-function. *)
              let partial = is_arrow expr.exp_type || nargs < head_arity in
              (* SLICE 3: a declared [transforms]/[converters] path, or an
                 UNDECLARED bind-shaped operator (specs/error-channels.md
                 "Binds": [inferred_bind]), is excluded from the ordinary
                 carrier-matching propagating-edge check on THIS call — set by
                 the [None]-branch classification below, read by
                 [record_head]. [Some _] (the default) is the unchanged
                 slice-2 behaviour. *)
              let callee_ty_for_channel = ref (Some fn_expr.exp_type) in
              (* The call fires AFTER its arguments evaluate, so the head (and
                 the residual/escape records) belong to the block reached AFTER
                 descending into fn + args: if an argument diverges
                 ([h (raise A)]) or branches, the head lands in the resulting
                 block and is demoted accordingly — never a false MUST. *)
              let record_head () =
                (match fn_expr.exp_desc with
                | Texp_ident (Path.Pident id, _, _) when ident_is_local_fn id ->
                    (* Same-module top-level function — MUST candidate; [cond]
                       and [partial] decide the final kind at resolution. *)
                    add_call ~partial ~is_head_of:expr.exp_loc ?callee_ty:!callee_ty_for_channel
                      (Head_local (local_fn_name id)) expr.exp_loc
                | Texp_ident (Path.Pident id, _, _) -> (
                    match lam_stamp id with
                    | Some (node_name, _) ->
                        (* Head application of a let-bound literal: resolves to
                           the lambda node — MUST when unconditional+saturated,
                           MAY_ENUMERATED otherwise (same rule as top-level). *)
                        add_call ~partial ~is_head_of:expr.exp_loc ?callee_ty:!callee_ty_for_channel
                          (Head_local node_name) expr.exp_loc
                    | None ->
                        (* Parameter / local / shadowing binding → unknowable. *)
                        add_call
                          ~partial
                          ~is_head_of:expr.exp_loc
                          ?callee_ty:!callee_ty_for_channel
                          (Head_unknown (Ident.name id, Callback_param))
                          expr.exp_loc)
                | Texp_ident (path, _, _) ->
                    note_seen_value_path (Path.name path) ;
                    let callee_module, callee_name = path_to_module_name path in
                    (match alias_rewrite path with
                    | Some (m, n) ->
                        add_call ~partial ~is_head_of:expr.exp_loc
                          ?callee_ty:!callee_ty_for_channel ~edge_form:"module_alias"
                          (Head_qualified (Some m, n))
                          expr.exp_loc
                    | None ->
                    if qualified_is_dynamic path then
                      let disp =
                        match callee_module with
                        | Some m -> m ^ "." ^ callee_name
                        | None -> callee_name
                      in
                      add_call ~partial ~is_head_of:expr.exp_loc ?callee_ty:!callee_ty_for_channel
                        (Head_unknown (disp, Module_param)) expr.exp_loc
                    else
                      add_call
                        ~partial
                        ~is_head_of:expr.exp_loc
                        ?callee_ty:!callee_ty_for_channel
                        (Head_qualified (callee_module, callee_name))
                        expr.exp_loc)
                | Texp_function _ -> (
                    (* Immediately-applied literal (beta-redex): the head IS
                       the lambda node named during the descent — a resolved
                       target, never ⊤ (MUST when always-exec + saturated). *)
                    match Hashtbl.find_opt lam_names fn_expr.exp_loc with
                    | Some node_name ->
                        add_call ~partial ~is_head_of:expr.exp_loc ?callee_ty:!callee_ty_for_channel
                          (Head_local node_name) expr.exp_loc
                    | None ->
                        add_call ~partial ~is_head_of:expr.exp_loc ?callee_ty:!callee_ty_for_channel
                          (Head_unknown ("*TOP*", Callback_param)) expr.exp_loc)
                | _ ->
                    (* Computed function head → unresolvable. *)
                    add_call ~partial ~is_head_of:expr.exp_loc ?callee_ty:!callee_ty_for_channel
                      (Head_unknown ("*TOP*", Callback_param)) expr.exp_loc) ;
                (* Over-application [f a b c] where [f] has arity 2: the head
                   call is saturated (handled above), but the extra args are
                   applied to the (unknown) returned function value — a residual
                   call to an unknowable target. Record it as ⊤ so [unreachable]
                   stays sound. *)
                if head_arity > 0 && nargs > head_arity then
                  add_call (Head_unknown ("*TOP*", Callback_param)) expr.exp_loc ;
                add_arg_escapes args expr.exp_loc
              in
              (match short_circuit_arity fn_expr with
              | Some () -> (
                  (* Short-circuit [&&]/[||]: the operator itself runs after its
                     FIRST operand; the right operand(s) run conditionally → a
                     conditional CFG region. *)
                  self.expr self fn_expr ;
                  match args with
                  | (_, first) :: rest ->
                      Option.iter (self.expr self) first ;
                      record_head () ;
                      let r = new_blk () in
                      let join = new_blk () in
                      edge (blk ()) r ;
                      edge (blk ()) join ;
                      set_blk r ;
                      List.iter (fun (_, a) -> Option.iter (self.expr self) a) rest ;
                      edge (blk ()) join ;
                      set_blk join
                  | [] -> record_head ())
              | None ->
                  (* Descend into fn + args FIRST (argument evaluation precedes
                     the call; nested constructs split blocks), then record. *)
                  default_iterator.expr self expr ;
                  (* Sink (specs/error-channels.md "Sinks"): [ignore (E)] — the
                     head call of [E] does not propagate. *)
                  (match fn_expr.exp_desc with
                  | Texp_ident (path, _, _)
                    when (not (qualified_is_dynamic path))
                         && path_to_module_name path = (Some "Stdlib", "ignore") -> (
                      match args with
                      | [(_, Some arg)] -> mark_sunk arg
                      | _ -> ())
                  | _ -> ()) ;
                  (* SLICE 3 (specs/error-channels.md "Transforms" /
                     "Converters" / "Binds"): a declared transform/converter
                     head, or an undeclared bind-shaped operator, is handled
                     here instead of (in the first two cases) letting the
                     ordinary carrier-matching rule treat this call as a
                     ⊤-external/opaque propagating edge to itself. *)
                  let head_opt = classify_head_path fn_expr in
                  let transform_hit =
                    match head_opt with Some h -> find_transform h | None -> None
                  in
                  let converter_hit =
                    match head_opt with Some h -> find_converter h | None -> None
                  in
                  let handler_hit =
                    match head_opt with Some h -> find_handler h | None -> None
                  in
                  let origin_hit = match head_opt with Some h -> find_origin h | None -> None in
                  (* SLICE 4 ("Sinks", declared [sinks]): a call whose OWN
                     head is a declared sink (e.g. the Tezos profile's
                     [Result_syntax.return] — a plain value wrapped into a
                     carrier, not itself a source of error) never
                     propagates, exactly like [ignore (E)]/[let _ = E in]
                     but for the call's OWN head rather than an argument's. *)
                  let sink_hit =
                    match head_opt with
                    | Some h ->
                        List.exists
                          (fun (ch : Arch_errors_config.channel) ->
                            path_declared ch.Arch_errors_config.sinks h)
                          value_channels
                    | None -> false
                  in
                  (* A DECLARED bind APPLIED as an ordinary function. Found
                     while adding the strict-over-an-extended-builtin test
                     (review round 2): such a path had no
                     [note_seen_value_path] anywhere — only let-operator binds
                     were noted, through [add_path_call] — so
                     [binds = ["my_bind"]] reported "matched nothing" however
                     many times the corpus called it, and [--errors-strict]
                     failed on a declaration that was in fact matching. Same
                     root as round 1's [lift]/[unwrap] miscategorisation: a
                     declared path whose actual occurrence form is never
                     noted. *)
                  let bind_hit =
                    match head_opt with
                    | Some h ->
                        List.exists
                          (fun (ch : Arch_errors_config.channel) ->
                            path_declared ch.Arch_errors_config.binds h)
                          value_channels
                    | None -> false
                  in
                  let bind_shape_hit =
                    match Arch_index_errch.bind_shape_channel ~channels:value_channels
                            fn_expr.exp_type
                    with
                    | Some bc ->
                        let declared =
                          match head_opt with
                          | Some h -> path_declared bc.Arch_errors_config.binds h
                          | None -> false
                        in
                        if declared then None else Some bc
                    | None -> None
                  in
                  (match head_opt with
                  | Some h -> (
                      match head_qualified_name h with
                      | Some qn
                        when transform_hit <> None || converter_hit <> None
                             || handler_hit <> None || origin_hit <> None || sink_hit
                             || bind_hit ->
                          note_seen_value_path qn
                      | _ -> ())
                  | None -> ()) ;
                  (* (b) Declared handler: the value argument at [argpos] is a
                     catch-all handler scope on [ch] covering its head call. *)
                  (match handler_hit with
                  | Some (ch, argpos) -> (
                      match List.nth_opt args (argpos - 1) with
                      | Some (_, Some argexpr) -> (
                          match resolve_guarded_call argexpr with
                          | Some ord ->
                              let local_id =
                                Arch_index_errch.add_scope (!cur).lerrch
                                  ~channel:ch.Arch_errors_config.name ~catch_all:true ~caught:[]
                                  ~loc:expr.exp_loc
                              in
                              Hashtbl.replace errch_call_scope ord (ch.Arch_errors_config.name, local_id)
                          | None -> ())
                      | _ -> ())
                  | None -> ()) ;
                  (* Converters: [arg] is BOTH a catch-all handler on [from]
                     and an origin on [to] (specs/error-channels.md
                     "Converters"). *)
                  (match converter_hit with
                  | Some (from_, to_, argpos, err) ->
                      (match List.nth_opt args (argpos - 1) with
                      | Some (_, Some argexpr) -> (
                          match resolve_guarded_call argexpr with
                          | Some ord ->
                              let local_id =
                                Arch_index_errch.add_scope (!cur).lerrch ~channel:from_
                                  ~catch_all:true ~caught:[] ~loc:expr.exp_loc
                              in
                              Hashtbl.replace errch_call_scope ord (from_, local_id)
                          | None -> ())
                      | _ -> ()) ;
                      (* SLICE 4 ("Converters", Tezos [catch_f] — the ONLY
                         real converter instance in proto_alpha, oracle O-5):
                         when [err] is not statically declared, try the
                         NEXT argument (a [catch_f]-shaped converter's own
                         handler function, [exn -> error]) as a literal
                         mapper, same rule as a "replace" transform's mapper
                         — its literal return names the error, per call
                         site. A one-argument converter like Tezos [catch]
                         (or the fixture's [opt_of_res]) has no such next
                         argument and falls back to the opaque identity, as
                         before (US-2.11's [t5]). *)
                      let literal_of_next () =
                        match List.nth_opt args argpos with
                        | Some (_, Some next_expr) -> (
                            match next_expr.exp_desc with
                            | Texp_function _ -> (
                                match literal_return_of_lambda next_expr with
                                | Some final ->
                                    Arch_index_errch.literal_ctor_path_of_expr
                                      ~canon_type:canon_exn ~canon_exn final
                                | None -> None)
                            | _ -> None)
                        | _ -> None
                      in
                      let path =
                        match err with
                        | Some e -> Some e
                        | None -> (
                            match literal_of_next () with
                            | Some p -> Some p
                            | None -> Some (Printf.sprintf "%s:converted_%s" to_ from_))
                      in
                      Arch_index_errch.add_origin (!cur).lerrch ~channel:to_ ~path ~form:"raise"
                        ~loc:expr.exp_loc ()
                  | None -> ()) ;
                  (* Transforms: "add" unions in the literal at [arg] (the
                     inner set survives, via the OTHER argument's own
                     ordinary propagating edge if it is itself a carrier
                     call — no special-casing needed for that half);
                     "replace" sinks every OTHER argument (the inner set does
                     NOT survive) and takes the literal-constructor return of
                     the mapper at [arg] when it is a lambda literal, else ⊤
                     (a named/parameter mapper — sound over-approximation;
                     the "named function whose own set is Known" refinement
                     is a deliberately unimplemented, always-⊤-safe residual). *)
                  (match transform_hit with
                  | Some (ch, Arch_errors_config.Add, argpos) -> (
                      match List.nth_opt args (argpos - 1) with
                      | Some (_, Some argexpr) ->
                          let path =
                            Arch_index_errch.literal_ctor_path_of_expr ~canon_type:canon_exn
                              ~canon_exn argexpr
                          in
                          Arch_index_errch.add_origin (!cur).lerrch
                            ~channel:ch.Arch_errors_config.name ~path ~loc:expr.exp_loc ()
                      | _ -> ())
                  | Some (ch, Arch_errors_config.Replace, argpos) ->
                      List.iteri
                        (fun i (_, argexpr_opt) ->
                          if i <> argpos - 1 then
                            match argexpr_opt with Some ae -> mark_sunk ae | None -> ())
                        args ;
                      let literal_path =
                        match List.nth_opt args (argpos - 1) with
                        | Some (_, Some mapper_expr) -> (
                            match mapper_expr.exp_desc with
                            | Texp_function _ -> (
                                match literal_return_of_lambda mapper_expr with
                                | Some final ->
                                    Arch_index_errch.literal_ctor_path_of_expr
                                      ~canon_type:canon_exn ~canon_exn final
                                | None -> None)
                            | _ -> None)
                        | _ -> None
                      in
                      Arch_index_errch.add_origin (!cur).lerrch ~channel:ch.Arch_errors_config.name
                        ~path:literal_path ~loc:expr.exp_loc ()
                  | None -> ()) ;
                  (* [inferred_bind]: NEVER silently treat an undeclared
                     bind-shaped operator as a bind — record a ⊤ witness on
                     the caller node instead. *)
                  (match bind_shape_hit with
                  | Some bc ->
                      let site =
                        Printf.sprintf "%s:%d" src_path expr.exp_loc.Location.loc_start.pos_lnum
                      in
                      Arch_index_errch.add_origin (!cur).lerrch ~channel:bc.Arch_errors_config.name
                        ~path:(Some site) ~form:"inferred_bind" ~loc:expr.exp_loc ()
                  | None -> ()) ;
                  (* SLICE 4: a declared FUNCTION origin (Tezos [error]/
                     [tzfail]/[error_when]/…): the literal at [argpos] names
                     the error, same rule as a transform's [Add] argument. *)
                  (match origin_hit with
                  | Some (ch, argpos) -> (
                      match List.nth_opt args (argpos - 1) with
                      | Some (_, Some argexpr) ->
                          let path =
                            Arch_index_errch.literal_ctor_path_of_expr ~canon_type:canon_exn
                              ~canon_exn argexpr
                          in
                          Arch_index_errch.add_origin (!cur).lerrch
                            ~channel:ch.Arch_errors_config.name ~path ~loc:expr.exp_loc ()
                      | _ -> ())
                  | None -> ()) ;
                  if
                    transform_hit <> None || converter_hit <> None || bind_shape_hit <> None
                    || origin_hit <> None || sink_hit
                  then callee_ty_for_channel := None ;
                  record_head () ;
                  (* Exception origin (identity-aware; primitive-keyed for
                     [raise], Stdlib-path-keyed for failwith/invalid_arg). *)
                  if Arch_index_exn.is_raise_head fn_expr then
                    Arch_index_exn.record_raise_head (!cur).lexn ~canon:canon_exn ~args
                      ~loc:expr.exp_loc
                  else (
                    match Arch_index_exn.stdlib_head fn_expr with
                    | Some head ->
                        Arch_index_exn.record_stdlib_head (!cur).lexn ~canon:canon_exn ~head
                          ~args ~loc:expr.exp_loc
                    | None ->
                        Arch_index_exn.record_prim_head (!cur).lexn ~fn:fn_expr ~args
                          ~loc:expr.exp_loc) ;
                  (* Diverging head (raise/failwith/…): terminate AFTER the
                     head call was recorded in this block (the raise itself
                     runs), so post-divergence code lands entry-unreachable. *)
                  if noreturn_head fn_expr nargs then diverge ())
          | Texp_sequence (e1, e2) ->
              (* Both run unconditionally, same block; [e1] is a NON-FINAL
                 position — a sink (specs/error-channels.md "Sinks"): the
                 head call of [e1] does not propagate, nested calls still
                 do. *)
              self.expr self e1 ;
              mark_sunk e1 ;
              self.expr self e2
          | Texp_construct (_, cstr_desc, args) ->
              (* Value-channel origin (specs/error-channels.md "Origins"): an
                 application of the channel's origin constructor. The
                 constructed value's OWN type ([cstr_res]) decides the
                 channel — the same carrier check used for functions, just
                 without stripping arrows (a constructor's type never is
                 one). *)
              (match carrier_of cstr_desc.cstr_res with
              | Some c -> (
                  match
                    List.find_opt
                      (fun (opath, _) -> bare_ctor_name opath = cstr_desc.cstr_name)
                      c.Arch_errors_config.origins
                  with
                  | None -> ()
                  | Some (opath, 0) ->
                      note_seen_value_path opath ;
                      Arch_index_errch.add_origin
                        (!cur).lerrch
                        ~channel:c.Arch_errors_config.name
                        ~path:(Some opath)
                        ~loc:expr.exp_loc
                        ()
                  | Some (opath, pos) -> (
                      note_seen_value_path opath ;
                      match List.nth_opt args (pos - 1) with
                      | None -> ()
                      | Some argexpr -> (
                          match argexpr.exp_desc with
                          | Texp_ident (Path.Pident vid, _, _)
                            when Hashtbl.mem arm_bound_idents (Ident.unique_name vid) ->
                              (* "re-return" ([Error e -> Error e]): the
                                 non-closing arm rule already keeps this
                                 forwarded through the uncovered edge —
                                 recording it again here would double-count
                                 it as a fresh origin of THIS node. *)
                              ()
                          | _ ->
                              let path =
                                Arch_index_errch.literal_ctor_path_of_expr ~canon_type:canon_exn
                                  ~canon_exn argexpr
                              in
                              Arch_index_errch.add_origin
                                (!cur).lerrch
                                ~channel:c.Arch_errors_config.name
                                ~path
                                ~loc:expr.exp_loc
                                ())))
              | None -> ()) ;
              default_iterator.expr self expr
          | _ -> default_iterator.expr self expr);
      module_expr =
        (fun self me ->
          match me.mod_desc with
          | Tmod_functor (_, _) ->
              (* A functor body only runs when the functor is applied → walked
                 in an isolated (never always-exec) block. *)
              let saved = (blk ()) in
              set_blk (deferred_blk ()) ;
              Arch_index_exn.with_cleared_scopes (!cur).lexn (fun () ->
                  default_iterator.module_expr self me) ;
              set_blk saved
          | _ -> default_iterator.module_expr self me);
    }
  in
  (* The binding value is `fun <params> -> BODY` (or `function <cases>`); those
     params are THIS function's own, so BODY / the case RHSs are its direct body
     (depth 0). Peel the leading parameter lambdas before walking, otherwise the
     function's own arms would be mistaken for nested closures and every call
     would be demoted to MAY_TOP. Genuinely-nested function literals inside BODY
     still raise [nested]. *)
  (* Walk a FUNCTION ROOT (the top-level binding's RHS, or a promoted lambda
     literal) inside the CURRENT context: peel its own leading parameter
     lambdas (they are this node's params, not nested closures), walk each
     optional-argument default expression in an isolated block (it runs only
     when the caller omits the argument — recorded, demoted, never dropped),
     then walk the peeled body: a [Tfunction_cases] root is sugar for
     [fun x -> match x with <cases>] — each arm is a CFG branch, with a
     Match_failure bypass edge when the compiler marks it Partial so a lone
     refutable/guarded arm cannot forge a MUST (a single TOTAL unguarded arm
     always runs and is legitimately MUST). *)
  let walk_function_root (e0 : Typedtree.expression) =
    let opt_defaults = ref [] in
    let collect_param_defaults params =
      List.iter
        (fun (p : Typedtree.function_param) ->
          match p.fp_kind with
          | Tparam_optional_default (_, de) ->
              opt_defaults := de :: !opt_defaults
          | Tparam_pat _ -> ())
        params
    in
    (* A refutable parameter pattern ([fun (Some x) -> …]) raises
       Match_failure on the function's own entry: an origin of this node. *)
    let record_param_partials params =
      List.iter
        (fun (p : Typedtree.function_param) ->
          if p.fp_partial = Partial then
            Arch_index_exn.record_partial (!cur).lexn ~loc:p.fp_loc)
        params
    in
    let rec peel (e : Typedtree.expression) =
      match e.exp_desc with
      | Texp_function (params, Tfunction_body b) ->
          collect_param_defaults params ;
          record_param_partials params ;
          peel b
      | Texp_function (params, Tfunction_cases _) ->
          collect_param_defaults params ;
          record_param_partials params ;
          e
      | _ -> e
    in
    let root = peel e0 in
    (* specs/point-free-aliases.md S1 — the LOCAL alias slice.

       A point-free binding ([let f = g]) peels to a bare [Texp_ident]: there is
       no application anywhere in the body, so the expression iterator's
       catch-all sees it and emits nothing, and [f]'s node ends up with no
       outgoing edge at all. Its raise-set then comes back empty and the node
       reads BOUNDED: {} — not because [g] raises nothing, but because nobody
       ever asked [g].

       Three exclusions, each measured rather than assumed (briefs/…-s0.md):

       - NOT arrow-typed → not an alias of a function. [let k = M.pi] transfers
         a value; there is no body to inherit. Half of all point-free bindings
         on both corpora (390/376), so this is the common case, not a corner.
       - [Path.Pdot] → resolves through [resolve_qualified], which roadmap 1.6
         is rewriting. Deferred to S3 so this slice does not straddle that merge.
       - [Path.Pident] NOT in [local_fn_stamps] → a third class S0 found and no
         upstream artefact had named (38 on proto_alpha, 10 on octez-manager).
         It is either a function PARAMETER — not an alias at all — or an
         [open]-mediated reference needing qualified resolution. Excluded
         explicitly here rather than allowed to fall into either slice.
       - [root != e0], i.e. [peel] stripped parameters → NOT point-free.
         [let make () = island] is a combinator that RETURNS [island]; nothing
         is applied at that site and [make] does not inherit [island]'s body.
         Without this guard the alias edge fired on every function whose body
         happens to be a bare identifier, which is a different construct with
         a different meaning. The dominance corpus caught it: the edge made
         [computed_map]'s deliberately-⊤ island REACHABLE through
         [make], turning a stated unknown into a claim. Physical equality is
         the honest test — [peel] returns its argument unchanged exactly when
         there was nothing to peel.

       The head classification is [add_path_call]'s, unchanged: it already
       distinguishes same-module / qualified / functor-parameter and it is
       tested. What makes an alias MAY_ENUMERATED rather than MUST is a
       DEMOTION in the kind matrix keyed on [edge_form] (arch_index.ml), not a
       different head — because "which function is this" and "may I treat this
       as a definite call" are different questions, and the matrix is where the
       second one is answered. Routing an alias through a head constructor
       chosen for its kind side-effect would have answered the second question
       by lying about the first. *)
    (match root.exp_desc with
    | Texp_ident (path, _, _) when root == e0 && is_arrow root.exp_type -> (
        match path with
        | Path.Pident id when not (ident_is_local_fn id) -> (
            (* The third class: a bare identifier that is not a same-module
               top-level function BODY. It splits in two, and only the second
               half is outside this feature.

               (i) An ALIAS BINDER — [let t2 = t1] where [t1] is itself
               [let t1 = target]. This is the feature's OWN construct one hop
               along, and dropping it was the original bug in miniature: [t1]
               read BOUNDED: {Boom} while [t2], meaning exactly the same thing,
               read BOUNDED: {} — a stated certainty about a body nobody read,
               sitting beside the correct answer. [local_alias_stamps] names
               these (it is the reason that table exists) and the edge is
               emitted like any other alias edge. One hop per binder; the chain
               closes because the consumers traverse the resulting edges.

               (ii) A function PARAMETER or a local closure. No top-level row
               names it, so there is nothing to point an edge at. Still a
               silent drop, and still a residual — named in
               specs/point-free-aliases.md and pinned by a test rather than
               left to be rediscovered. It is NOT the alias case: nothing here
               transfers a same-module body. *)
            match local_alias_name id with
            | Some name ->
                note_seen_value_path (Ident.name id) ;
                add_call ~edge_form:"value_alias" (Head_local name) root.exp_loc
            | None -> ())
        | _ -> add_path_call ~edge_form:"value_alias" path root.exp_loc)
    | _ -> ()) ;
    (match root.exp_desc with
    | Texp_function (_, Tfunction_cases {cases; partial; _}) ->
        if partial = Partial then
          Arch_index_exn.record_partial (!cur).lexn ~loc:root.exp_loc ;
        let s_end = blk () in
        let join = new_blk () in
        if partial = Partial then edge s_end join ;
        List.iter
          (fun (c : Typedtree.value Typedtree.case) ->
            let arm = new_blk () in
            edge s_end arm ;
            set_blk arm ;
            (match c.c_guard with Some gd -> iter.expr iter gd | None -> ()) ;
            iter.expr iter c.c_rhs ;
            edge (blk ()) join)
          cases ;
        set_blk join
    | _ -> iter.expr iter root) ;
    List.iter
      (fun de ->
        set_blk (deferred_blk ()) ;
        iter.expr iter de)
      !opt_defaults
  in
  walk_fn_body_ref := walk_function_root ;
  walk_function_root expr ;
  (* Solve every context's post-dominance and finalize: a call is conditional
     unless its block runs on every execution of ITS OWN node. *)
  let verdicts = Hashtbl.create 8 in
  List.iter
    (fun c ->
      Hashtbl.replace verdicts c.cid
        (Arch_index_cfg.solve ~deferred:c.ldeferred c.lg))
    !all_ctxs ;
  let calls =
    List.rev_map
      (fun ( ord, cid, block, caller, head, partial, call_site, exn_scope,
             errch_candidate, edge_form ) ->
        let cond =
          match Hashtbl.find_opt verdicts cid with
          | Some v -> not (Arch_index_cfg.always_exec v block)
          | None -> true (* unknown ctx: demote, never promote *)
        in
        let dead =
          match Hashtbl.find_opt verdicts cid with
          (* [may_run], NOT [reachable]: the lowering makes every deferred body
             entry-unreachable on purpose, so [reachable] would report an
             optional argument's default, a lazy thunk, an object method and a
             functor body as code that can never execute. That is the wrong
             direction for a verdict whose only use is "delete this". *)
          | Some v -> not (Arch_index_cfg.may_run v block)
          | None -> false (* unknown ctx: never claim dead *)
        in
        (* A call whose head is SUNK (specs/error-channels.md "Sinks") never
           propagates on any channel — override the type-based candidate. *)
        let errch_propagates = if Hashtbl.mem sunk_ords ord then None else errch_candidate in
        (* Independent of [exn_scope]: a call can be covered by both, and
           [call_exn_scopes] now has room for both. *)
        let errch_scope =
          match Hashtbl.find_opt errch_call_scope ord with
          | Some (_, local_id) -> Some local_id
          | None -> None
        in
        {
          caller_module;
          caller_name = caller;
          head;
          partial;
          cond;
          dead;
          call_site;
          exn_scope;
          errch_scope;
          errch_propagates;
          edge_form;
        })
      !raw
  in
  (* Exception facts per node, keyed by the node name the calls are attributed
     to — the same key [process_cmt] uses to find the node's [functions] row. *)
  let exn_by_node =
    List.rev_map (fun c -> (c.lcaller, Arch_index_exn.finalize c.lexn)) !all_ctxs
  in
  let errch_by_node =
    List.rev_map (fun c -> (c.lcaller, c.lchannel, Arch_index_errch.finalize c.lerrch)) !all_ctxs
  in
  (calls, List.rev !lambdas, exn_by_node, errch_by_node)

(* -------------------------------------------------------------------------- *)
(* Process a single .cmt file                                                 *)
(* -------------------------------------------------------------------------- *)

(** Process a .cmt file: index modules, functions, types.
    Returns (pending_calls, pending_deps, pending_type_usages) for later resolution.
    
    @param project_root Project root directory for relativizing paths
    @param source_path_of_cmt Function to resolve source path from cmt info
    @param count_code_lines Function to count code lines in a source file *)
let process_cmt db ~project_root ~source_path_of_cmt ~count_code_lines
    ~exposed_tbl ~doc_tbl ~module_quint_tbl ~stmt_mod ~stmt_fn ~stmt_ty
    ~stmt_fld ~stmt_ctor ~stmt_scope ~stmt_catch ~stmt_origin ~stmt_rebind
    ?(value_channels = []) ?stmt_carrier ?(producer_run_id = None) path =
  match Cmt_format.read path with
  | _, None -> ([], [], [])
  | _, Some info -> (
      (* Only process Implementation (not Interface -- we use .cmti for
       exposed-name detection only) *)
      match info.cmt_annots with
      | Implementation structure -> (
          match source_path_of_cmt info with
          | None -> ([], [], [])
          | Some src_path ->
              let modname = info.cmt_modname in
              (* Store path relative to project root if possible *)
              let rel_path =
                if project_root <> "" then
                  let prefix = project_root ^ "/" in
                  if
                    String.length src_path >= String.length prefix
                    && String.sub src_path 0 (String.length prefix) = prefix
                  then
                    String.sub
                      src_path
                      (String.length prefix)
                      (String.length src_path - String.length prefix)
                  else src_path
                else src_path
              in
              (* Count code lines (excludes comments and blank lines) *)
              let lines = count_code_lines src_path in
              (* Check if .mli exists *)
              let has_mli =
                let mli = Filename.remove_extension src_path ^ ".mli" in
                Sys.file_exists mli
              in
              let quint_module_raw =
                Hashtbl.find_opt module_quint_tbl modname
              in
              match
                insert_module
                  db
                  stmt_mod
                  ~path:rel_path
                  ~lines
                  ~has_mli
                  ?quint_module_raw:(Option.map Option.some quint_module_raw)
                  (* Roadmap 1.1: this whole walker only ever processes .cmt/
                     .cmti files, which are structurally always OCaml — there
                     is nothing to detect here, unlike the LSP-based flat-
                     schema path (runner.ml), which genuinely serves several
                     languages and threads its own already-known ~language
                     through instead of hardcoding one. *)
                  ~language:(Some "ocaml")
                  ()
              with
              | None ->
                  (* The modules row was rejected. Every function, type and dep
                     below hangs off [module_id]; with no row of our own the
                     only id available is another module's, so index nothing
                     from this compilation unit rather than file it under a
                     neighbour.

                     The per-table tally records ONE rejected row for this, and
                     one rejected row is what an operator will read in the exit
                     report — while what was actually lost is every function,
                     type, dep and call of a whole compilation unit, which for a
                     large unit is thousands of rows. The tally counts refused
                     statements and cannot say otherwise, so the loss is named
                     here instead, at the only place that knows its extent. *)
                  Arch_io.eprintf
                    "Dropped compilation unit %s (%s): its modules row was \
                     rejected, so none of its functions, types, deps or calls \
                     are indexed. Callers of it resolve to MAY_TOP.\n"
                    modname
                    rel_path ;
                  record_dropped_unit ~rel_path ;
                  (* Roadmap 1.6: a dropped unit still OWNS its name. A caller
                     resolving through it must reach [dropped_node] (⊤, body
                     exists but was never read), not fall through to "no such
                     unit" and be emitted as a proven external leaf. Registering
                     it here is what keeps those two outcomes distinguishable. *)
                  record_unit ~unit_name:modname ~rel_path ;
                  ([], [], [])
              | Some module_id ->
                  record_unit ~unit_name:modname ~rel_path ;
                  (* Collect calls, module deps, and type usages from value bindings *)
                  let pending_calls = ref [] in
                  let pending_deps = ref [] in
                  let pending_type_usages = ref [] in
                  let local_fn_stamps = build_local_fn_stamps structure in
                  let local_alias_stamps = build_local_alias_stamps structure in
                  let module_alias_stamps = build_module_alias_stamps structure in
                  let binding_names = build_binding_names structure in
                  (* Exception identity (specs/exn-raise-sets.md): the idents a
                     structure item of THIS unit declares — exceptions,
                     extension constructors, modules — map to the module-
                     qualified name a cross-unit reference would print, so a
                     raise site here and a handler elsewhere spell the same
                     canonical path. Built over the whole structure first,
                     since a binding may raise an exception declared below
                     it. [exception Alias = Target] is recorded for query-time
                     canonicalisation. *)
                  let unit_declared = Hashtbl.create 16 in
                  let rebinds = ref [] in
                  iter_structure_items structure
                    ~f:(fun ~prefix (it : Typedtree.structure_item) ->
                      let declare (ext : Typedtree.extension_constructor) =
                        let q = qualify ~prefix (Ident.name ext.ext_id) in
                        Hashtbl.replace unit_declared (Ident.unique_name ext.ext_id) q ;
                        match Arch_index_exn.rebind_of ext with
                        | Some target -> rebinds := (modname ^ "." ^ q, target) :: !rebinds
                        | None -> ()
                      in
                      match it.str_desc with
                      | Tstr_exception te -> declare te.tyexn_constructor
                      | Tstr_typext te -> List.iter declare te.tyext_constructors
                      | Tstr_type (_, tds) ->
                          (* Value-channel constructor canonicalisation
                             (specs/error-channels.md "Origins" / "Handler
                             scopes") needs a same-unit TYPE's path too — an
                             ordinary constructor's canonical path is
                             derived from its constructed value's type
                             ([Arch_index_errch.constructor_canonical_path]),
                             which goes through [canon_exn]/[unit_declared]
                             exactly like an exception's path does. *)
                          List.iter
                            (fun (td : Typedtree.type_declaration) ->
                              Hashtbl.replace unit_declared (Ident.unique_name td.typ_id)
                                (qualify ~prefix (Ident.name td.typ_id)))
                            tds
                      | Tstr_module {mb_id = Some id; _} ->
                          Hashtbl.replace unit_declared (Ident.unique_name id)
                            (qualify ~prefix (Ident.name id))
                      | Tstr_recmodule mbs ->
                          List.iter
                            (fun (mb : Typedtree.module_binding) ->
                              match mb.mb_id with
                              | Some id ->
                                  Hashtbl.replace unit_declared (Ident.unique_name id)
                                    (qualify ~prefix (Ident.name id))
                              | None -> ())
                            mbs
                      | Tstr_include incl ->
                          (* [include M] re-exports M's exceptions and modules
                             under fresh idents of THIS unit: a raise of one
                             must print as this unit's path, like a cross-unit
                             handler will. *)
                          List.iter
                            (fun (si : Types.signature_item) ->
                              match si with
                              | Sig_typext (id, _, _, _) | Sig_module (id, _, _, _, _) ->
                                  Hashtbl.replace unit_declared (Ident.unique_name id)
                                    (qualify ~prefix (Ident.name id))
                              | _ -> ())
                            incl.incl_type
                      | _ -> ()) ;
                  let canon_exn =
                    Arch_index_exn.canonical_path
                      ~unit_declared:(Hashtbl.find_opt unit_declared)
                      ~cmt_modname:modname
                  in
                  List.iter
                    (fun (alias_path, target) ->
                      insert_exn_rebind db stmt_rebind ~alias_path
                        ~target_path:(canon_exn target))
                    (List.rev !rebinds) ;
                  let add_dep target_path dep_kind alias_name line_number =
                    pending_deps :=
                      {
                        source_module = rel_path;
                        target_path;
                        dep_kind;
                        alias_name;
                        line_number;
                      }
                      :: !pending_deps
                  in
                  (* Process structure items.
                     [prefix] is the enclosing module path ("Make." inside
                     [module Make (P : S) = struct ... end]), so a function defined
                     in a nested structure is registered under its definition path
                     rather than being dropped.  Qualifying by definition means a
                     functor applied twice still yields one row per definition,
                     which is what the CMT records. *)
                  let process_item ~prefix (item : Typedtree.structure_item) =
                      (* Module dependencies are a property of the file, so only the
                         toplevel contributes: an [open] or an alias local to a
                         nested module is not a dependency of the compilation
                         unit. *)
                      let add_dep path kind alias line =
                        if prefix = "" then add_dep path kind alias line
                      in
                      match item.str_desc with
                      | Tstr_open od -> (
                          (* open Module *)
                          match module_path_of_expr od.open_expr with
                          | Some path ->
                              add_dep
                                path
                                "open"
                                None
                                od.open_loc.loc_start.pos_lnum
                          | None -> ())
                      | Tstr_include id -> (
                          (* include Module *)
                          match module_path_of_expr id.incl_mod with
                          | Some path ->
                              add_dep
                                path
                                "include"
                                None
                                id.incl_loc.loc_start.pos_lnum
                          | None -> ())
                      | Tstr_module mb ->
                          (* module M = SomeModule (alias) *)
                          (match mb.mb_id with
                          | Some id -> (
                              match module_path_of_expr mb.mb_expr with
                              | Some path ->
                                  add_dep
                                    path
                                    "alias"
                                    (Some (Ident.name id))
                                    mb.mb_expr.mod_loc.loc_start.pos_lnum
                              | None -> ())
                          | None -> ())
                          (* What the module itself defines is reached by
                             [iter_structure_items], which walks into it. *)
                      | Tstr_value (_, vbs) ->
                          List.iter
                            (fun (vb : Typedtree.value_binding) ->
                              match vb.vb_pat.pat_desc with
                              | Tpat_var (id, _, _)
                                when Ident.name id <> "_" ->
                                  (* A binding the compiler named "_" is not a
                                     function: it is a wildcard, and `_` is not a
                                     valid OCaml identifier, so no hand-written
                                     definition can produce one. In practice they
                                     come from ppx-generated code — every
                                     [@@deriving ...] emits some — and recording
                                     them was actively destructive, not merely
                                     noisy: `functions` carries a UNIQUE on
                                     (module_id, name), so a module with several of
                                     them re-inserted the same ("_") row, and
                                     `INSERT OR REPLACE` turned each repeat into
                                     DELETE-then-INSERT whose DELETE fired
                                     ON DELETE CASCADE across the eight tables
                                     that reference functions(id) — including
                                     `calls` on both caller_id and callee_id.
                                     Rows already written were deleted, silently:
                                     nothing failed, so nothing was logged.
                                     Measured on a 3-line fixture with three
                                     [@@deriving yojson]: 15 type usages reported,
                                     3 stored. On épure's src/: 96 re-inserts over
                                     4 modules, all named "_". *)
                                  (* Same-level shadowing (issue #41): the LAST
                                     same-name binding keeps the bare qualified
                                     name; earlier ones take a [#N] suffix. See
                                     {!build_binding_names} for why this
                                     direction (not the reverse) is required
                                     for correct cross-module call resolution. *)
                                  let name = binding_name binding_names ~prefix id in
                                  let signature =
                                    Some (type_to_string vb.vb_pat.pat_type)
                                  in
                                  let line_start = vb.vb_loc.loc_start.pos_lnum in
                                  let line_end = vb.vb_loc.loc_end.pos_lnum in
                                  let exposed =
                                    Hashtbl.mem exposed_tbl (modname, name)
                                  in
                                  (* Prefer .mli doc; fall back to .ml doc *)
                                  let intent =
                                    match
                                      Hashtbl.find_opt doc_tbl (modname, name)
                                    with
                                    | Some _ as d -> d
                                    | None -> extract_doc vb.vb_attributes
                                  in
                                  (* Parse doc comment for comment quality score *)
                                  let parsed =
                                    match intent with
                                    | Some doc ->
                                        Some (Arch_index_comment_parser.parse doc)
                                    | None -> None
                                  in
                                  (* R8 mutability metrics: diagnostic only *)
                                  let muts, derefs = count_mutability vb.vb_expr in
                                  (match
                                     insert_function
                                      db
                                      stmt_fn
                                      ~module_id
                                      ~name
                                      ~signature
                                      ~line_start
                                      ~line_end
                                      ~exposed
                                      ~intent
                                      ~mutation_sites:(Some muts)
                                      ~deref_sites:(Some derefs)
                                      ~language:(Some "ocaml")
                                      ~producer_run_id
                                      ?comment_quality_score:
                                        (Option.map
                                           (fun p ->
                                             Some p.Arch_index_comment_parser.score)
                                           parsed)
                                      ~has_pre:
                                        (match parsed with
                                        | Some p ->
                                            p.Arch_index_comment_parser.sections.pre
                                            <> Arch_index_comment_parser.Absent
                                        | None -> false)
                                      ~has_post:
                                        (match parsed with
                                        | Some p ->
                                            p.Arch_index_comment_parser.sections
                                              .post
                                            <> Arch_index_comment_parser.Absent
                                        | None -> false)
                                      ~has_violators:
                                        (match parsed with
                                        | Some p ->
                                            p.Arch_index_comment_parser.sections
                                              .violators
                                            <> Arch_index_comment_parser.Absent
                                        | None -> false)
                                      ~has_violates:
                                        (match parsed with
                                        | Some p ->
                                            p.Arch_index_comment_parser.sections
                                              .violates
                                            <> Arch_index_comment_parser.Absent
                                        | None -> false)
                                      ?violators_raw:
                                        (match parsed with
                                        | Some p ->
                                            let entries =
                                              p.Arch_index_comment_parser.sections
                                                .violators_entries
                                            in
                                            if entries = [] then None
                                            else
                                              Some
                                                (Some
                                                   (`List
                                                      (List.map
                                                         (fun e ->
                                                           `Assoc
                                                             [
                                                               ( "name",
                                                                 `String
                                                                   e
                                                                     .Arch_index_comment_parser
                                                                      .qualified_name
                                                               );
                                                               ( "reason",
                                                                 `String
                                                                   e
                                                                     .Arch_index_comment_parser
                                                                      .reason );
                                                             ])
                                                         entries)
                                                   |> Yojson.Basic.to_string))
                                        | None -> None)
                                      ?violates_raw:
                                        (match parsed with
                                        | Some p ->
                                            let entries =
                                              p.Arch_index_comment_parser.sections
                                                .violates_entries
                                            in
                                            if entries = [] then None
                                            else
                                              Some
                                                (Some
                                                   (`List
                                                      (List.map
                                                         (fun e ->
                                                           `Assoc
                                                             [
                                                               ( "name",
                                                                 `String
                                                                   e
                                                                     .Arch_index_comment_parser
                                                                      .qualified_name
                                                               );
                                                               ( "reason",
                                                                 `String
                                                                   e
                                                                     .Arch_index_comment_parser
                                                                      .reason );
                                                             ])
                                                         entries)
                                                   |> Yojson.Basic.to_string))
                                        | None -> None)
                                      ?tests_raw:
                                        (match parsed with
                                        | Some p ->
                                            let entries =
                                              p.Arch_index_comment_parser.sections
                                                .tests_entries
                                            in
                                            if entries = [] then None
                                            else
                                              Some
                                                (Some
                                                   (`List
                                                      (List.map
                                                         (fun (e :
                                                                Arch_index_comment_parser
                                                                .test_entry)
                                                            ->
                                                           `Assoc
                                                             [
                                                               ( "file",
                                                                 `String e.file );
                                                               ( "case",
                                                                 `String e.case_name
                                                               );
                                                             ])
                                                         entries)
                                                   |> Yojson.Basic.to_string))
                                        | None -> None)
                                      ?quint_raw:
                                        (match parsed with
                                        | Some p -> (
                                            match
                                              p.Arch_index_comment_parser.sections
                                                .quint
                                            with
                                            | Absent | Present_none -> None
                                            | Present body -> Some (Some body))
                                        | None -> None)
                                      ()
                                  with
                                  | None ->
                                      (* The functions row was rejected. Returning
                                         an id here would be another function's id
                                         — [last_insert_rowid] is per-connection
                                         and survives a failed step — and this
                                         binding's type usages would satisfy their
                                         foreign key against it with no rejection
                                         and no count. Drop them. Its calls go too:
                                         they are resolved later by (module, name),
                                         which now finds no row.

                                         Its callers are the remaining problem:
                                         "no row" is also what a genuine external
                                         looks like, and the resolver answers that
                                         with a MUST edge to a leaf. Record the
                                         drop so it can tell the two apart. *)
                                      record_dropped_node
                                        ~module_path:rel_path
                                        ~name
                                  | Some function_id ->
                                      (* node name → functions row id, for the
                                         parent and (below) each lambda node *)
                                      let node_ids = Hashtbl.create 4 in
                                      Hashtbl.replace node_ids name function_id ;
                                      (* Collect type usages from this function's signature *)
                                      let type_usages =
                                        extract_types_from_signature vb.vb_pat.pat_type
                                      in
                                      List.iter
                                        (fun (type_path, usage_role, position) ->
                                          pending_type_usages :=
                                            {
                                              function_id;
                                              type_path;
                                              usage_role;
                                              position;
                                            }
                                            :: !pending_type_usages)
                                        type_usages ;
                                      (* Collect calls (and promoted lambda nodes) from
                                         this function's body *)
                                      let calls, lam_nodes, exn_by_node, errch_by_node =
                                        collect_calls_from_expr
                                          ~canon_exn
                                          ~value_channels
                                          ~src_path:rel_path
                                          ~caller_module:rel_path
                                          ~caller_name:name
                                          ~local_fn_stamps
                                          ~local_alias_stamps
                                          ~module_alias_stamps
                                          vb.vb_expr
                                      in
                                      (* Insert a synthetic functions row per nested
                                         lambda literal: exposed=0, parent module,
                                         comment fields empty — so parent→lambda and
                                         lambda→callee edges resolve to real ids. *)
                                      List.iter
                                        (fun (l : lambda_node) ->
                                          (* A rejected lambda row is not a misattribution
                                             risk: lambda calls are resolved later by
                                             (module, name) lookup, so an absent row
                                             drops its edges rather than moving them
                                             onto another function. It is still a body
                                             the graph no longer covers, so it joins the
                                             dropped set like any other. *)
                                          match
                                            insert_function
                                              db
                                              stmt_fn
                                              ~module_id
                                              ~name:l.lam_name
                                              ~signature:None
                                              ~line_start:l.lam_line_start
                                              ~line_end:l.lam_line_end
                                              ~exposed:false
                                              ~intent:None
                                              ~language:(Some "ocaml")
                                              ~producer_run_id
                                              ()
                                          with
                                          | Some lam_id ->
                                              Hashtbl.replace node_ids l.lam_name lam_id
                                          | None ->
                                              record_dropped_node
                                                ~module_path:rel_path
                                                ~name:l.lam_name)
                                        lam_nodes ;
                                      (* Exception facts, per node, once every
                                         node's row exists: scopes first (minted
                                         parent-before-child, so the parent's
                                         row id is known), then their caught
                                         paths, then origins. A node whose row
                                         was rejected takes its facts with it —
                                         they must not land on another id. *)
                                      let scope_ids = Hashtbl.create 8 in
                                      List.iter
                                        (fun (node, (scopes, origins)) ->
                                          match Hashtbl.find_opt node_ids node with
                                          | None -> ()
                                          | Some fid ->
                                              List.iter
                                                (fun (s : Arch_index_exn.scope) ->
                                                  let parent_id =
                                                    Option.bind s.s_parent (fun p ->
                                                        Hashtbl.find_opt scope_ids (node, p))
                                                  in
                                                  match
                                                    insert_exn_scope db stmt_scope
                                                      ~function_id:fid ~parent_id
                                                      ~form:
                                                        (Arch_index_exn.scope_form_to_string
                                                           s.s_form)
                                                      ~line:s.s_line ~col:s.s_col
                                                      ~catch_all:s.s_catch_all
                                                      (* Slices 0-1: the producer
                                                         emits only the
                                                         [exception] channel
                                                         (specs/error-channels.md
                                                         FR-029). *)
                                                      ~channel:"exception"
                                                  with
                                                  | Some sid ->
                                                      Hashtbl.replace scope_ids (node, s.s_id) sid ;
                                                      List.iter
                                                        (fun exn_path ->
                                                          insert_exn_scope_catch db stmt_catch
                                                            ~scope_id:sid ~exn_path)
                                                        s.s_caught
                                                  | None -> ())
                                                scopes ;
                                              List.iter
                                                (fun (o : Arch_index_exn.origin) ->
                                                  let scope_id =
                                                    Option.bind o.o_scope (fun p ->
                                                        Hashtbl.find_opt scope_ids (node, p))
                                                  in
                                                  insert_exn_origin db stmt_origin ~function_id:fid
                                                    ~scope_id
                                                    ~form:(Arch_index_exn.form_to_string o.o_form)
                                                    ~exn_path:o.o_path ~escapes:o.o_escapes
                                                    ~line:o.o_line ~col:o.o_col
                                                    ~channel:"exception")
                                                origins)
                                        exn_by_node ;
                                      (* Value-channel facts (specs/error-channels.md
                                         "Handler scopes" / "Origins"): same
                                         pattern as the exception channel above,
                                         a SEPARATE local-id space (never
                                         nested, so [parent_id] is always
                                         [None]), the reused ['match_exception']
                                         [form] (irrelevant at query time — see
                                         [Arch_tools.Arch_exn.load], which never
                                         selects [exn_scopes.form]), and the
                                         reused ['raise']/['unknown'] [form]s on
                                         origins (same reason: only ["reraise"]
                                         and a [None] path are special-cased by
                                         the query). *)
                                      let errch_scope_ids = Hashtbl.create 8 in
                                      List.iter
                                        (fun (node, channel_opt, (scopes, origins)) ->
                                          match Hashtbl.find_opt node_ids node with
                                          | None -> ()
                                          | Some fid ->
                                              (match (channel_opt, stmt_carrier) with
                                              | Some c, Some stmt_carrier ->
                                                  insert_channel_carrier
                                                    db
                                                    stmt_carrier
                                                    ~function_id:fid
                                                    ~channel:c.Arch_errors_config.name
                                              | _ -> ()) ;
                                              List.iter
                                                (fun (s : Arch_index_errch.scope) ->
                                                  match
                                                    insert_exn_scope db stmt_scope ~function_id:fid
                                                      ~parent_id:None ~form:"match_exception"
                                                      ~line:s.s_line ~col:s.s_col
                                                      ~catch_all:s.s_catch_all ~channel:s.s_channel
                                                  with
                                                  | Some sid ->
                                                      Hashtbl.replace errch_scope_ids (node, s.s_id) sid ;
                                                      List.iter
                                                        (fun exn_path ->
                                                          insert_exn_scope_catch db stmt_catch
                                                            ~scope_id:sid ~exn_path)
                                                        s.s_caught
                                                  | None -> ())
                                                scopes ;
                                              List.iter
                                                (fun (o : Arch_index_errch.origin) ->
                                                  insert_exn_origin db stmt_origin ~function_id:fid
                                                    ~scope_id:None
                                                    ~form:o.o_form
                                                    ~exn_path:o.o_path ~escapes:true
                                                    ~line:o.o_line ~col:o.o_col ~channel:o.o_channel)
                                                origins)
                                        errch_by_node ;
                                      (* Calls carry the walker's LOCAL scope
                                         ids; rewrite each to its row id (None
                                         if the scope row was rejected: an
                                         unlinked call over-approximates —
                                         sound). Two independent id spaces,
                                         two fields, two tables: no sign
                                         encoding, and neither link displaces
                                         the other. *)
                                      let calls =
                                        List.map
                                          (fun (c : pending_call) ->
                                            {
                                              c with
                                              exn_scope =
                                                Option.bind c.exn_scope (fun local ->
                                                    Hashtbl.find_opt scope_ids
                                                      (c.caller_name, local));
                                              errch_scope =
                                                Option.bind c.errch_scope (fun local ->
                                                    Hashtbl.find_opt errch_scope_ids
                                                      (c.caller_name, local));
                                            })
                                          calls
                                      in
                                      pending_calls :=
                                        List.rev_append calls !pending_calls)
                              | _ -> ())
                            vbs
                      | Tstr_type (_, tds) ->
                          List.iter
                            (fun (td : Typedtree.type_declaration) ->
                              let name = qualify ~prefix (Ident.name td.typ_id) in
                              let line_start = td.typ_loc.loc_start.pos_lnum in
                              let line_end = td.typ_loc.loc_end.pos_lnum in
                              let exposed =
                                Hashtbl.mem exposed_tbl (modname, name)
                              in
                              let kind, manifest =
                                match td.typ_type.type_kind with
                                | Type_record _ -> ("record", None)
                                | Type_variant _ -> ("variant", None)
                                | Type_open -> ("open", None)
                                | Type_abstract _ -> (
                                    match td.typ_type.type_manifest with
                                    | Some ty -> ("alias", Some (type_to_string ty))
                                    | None -> ("abstract", None))
                              in
                              let intent =
                                match Hashtbl.find_opt doc_tbl (modname, name) with
                                | Some _ as d -> d
                                | None -> extract_doc td.typ_attributes
                              in
                              match
                                insert_type
                                  db
                                  stmt_ty
                                  ~module_id
                                  ~name
                                  ~kind
                                  ~line_start
                                  ~line_end
                                  ~exposed
                                  ~manifest
                                  ~intent
                              with
                              | None ->
                                  (* The types row was rejected, so no id of this
                                     type exists. [last_insert_rowid] would hand
                                     back some earlier row's id and every field and
                                     constructor below would be silently filed
                                     under that other type. Drop them instead.

                                     One refused statement is one entry in the
                                     tally, but a record with forty labels loses
                                     forty-one rows. Name the type so the report
                                     and the loss can be reconciled. *)
                                  let n_dependents =
                                    match td.typ_type.type_kind with
                                    | Type_record (labels, _) -> List.length labels
                                    | Type_variant (ctors, _) -> List.length ctors
                                    | _ -> 0
                                  in
                                  Arch_io.eprintf
                                    "Dropped type %s in %s: its types row was \
                                     rejected, so its %d field(s)/constructor(s) \
                                     are not indexed either.\n"
                                    name
                                    rel_path
                                    n_dependents
                              | Some type_id -> (
                                  (* Insert record fields *)
                                  match td.typ_type.type_kind with
                                  | Type_record (labels, _) ->
                                      List.iteri
                                        (fun position (ld : Types.label_declaration) ->
                                          let field_name = Ident.name ld.ld_id in
                                          let field_type = type_to_string ld.ld_type in
                                          insert_field
                                            db
                                            stmt_fld
                                            ~type_id
                                            ~field_name
                                            ~field_type
                                            ~position)
                                        labels
                                  | Type_variant (constrs, _) ->
                                      List.iteri
                                        (fun position
                                             (cd : Types.constructor_declaration)
                                           ->
                                          let constructor_name = Ident.name cd.cd_id in
                                          let arg_types =
                                            match cd.cd_args with
                                            | Cstr_tuple [] -> None
                                            | Cstr_tuple args ->
                                                Some
                                                  (String.concat
                                                     ", "
                                                     (List.map type_to_string args))
                                            | Cstr_record labels ->
                                                Some
                                                  (String.concat
                                                     ", "
                                                     (List.map
                                                        (fun (ld :
                                                               Types.label_declaration)
                                                           ->
                                                          Printf.sprintf
                                                            "%s: %s"
                                                            (Ident.name ld.ld_id)
                                                            (type_to_string ld.ld_type))
                                                        labels))
                                          in
                                          insert_constructor
                                            db
                                            stmt_ctor
                                            ~type_id
                                            ~constructor_name
                                            ~position
                                            ~arg_types)
                                        constrs
                                  | _ -> ()))
                            tds
                      | _ -> ()
                  in
                  iter_structure_items structure ~f:process_item ;
                  (!pending_calls, !pending_deps, !pending_type_usages))
      | _ -> ([], [], []))
