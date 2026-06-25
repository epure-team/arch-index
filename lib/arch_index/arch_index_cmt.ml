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
          (* Filter out dune-generated wrapper modules *)
          && not (String.starts_with ~prefix:"dune__" (Filename.basename path))
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
                List.iter
                  (fun (item : Typedtree.signature_item) ->
                    match item.sig_desc with
                    | Tsig_value vd -> (
                        let name = Ident.name vd.val_id in
                        Hashtbl.replace exposed_tbl (modname, name) true ;
                        match extract_doc vd.val_attributes with
                        | Some doc ->
                            Hashtbl.replace doc_tbl (modname, name) doc
                        | None -> ())
                    | Tsig_type (_, tds) ->
                        List.iter
                          (fun (td : Typedtree.type_declaration) ->
                            let name = Ident.name td.typ_id in
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
                    | _ -> ())
                  sg.sig_items
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

(** Collected call information before resolution. *)
type pending_call = {
  caller_module : string; (* Module path, e.g. "src/foo.ml" *)
  caller_name : string; (* Function name *)
  callee_name : string; (* Function name *)
  callee_module : string option; (* Module name if qualified, e.g. "List" *)
  call_site : string; (* file:line *)
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
        add_type (type_path_of_path path) role pos ;
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

(** Walk a value binding expression to collect all function calls.
    Returns a list of pending calls. *)
let collect_calls_from_expr ~src_path ~caller_module ~caller_name
    (expr : Typedtree.expression) =
  let calls = ref [] in
  let add_call callee_name callee_module loc =
    let line = loc.Location.loc_start.pos_lnum in
    let call_site = Printf.sprintf "%s:%d" src_path line in
    calls :=
      {caller_module; caller_name; callee_name; callee_module; call_site}
      :: !calls
  in
  (* Use Tast_iterator to walk all subexpressions *)
  let open Tast_iterator in
  let iter =
    {
      default_iterator with
      expr =
        (fun self expr ->
          (match expr.exp_desc with
          | Texp_apply (fn_expr, _args) -> (
              (* This is a function application - extract the callee.
                 Use the application node's location for better accuracy
                 with multiline calls. *)
              match fn_expr.exp_desc with
              | Texp_ident (path, _longident, _vd) ->
                  let callee_module, callee_name = path_to_module_name path in
                  add_call callee_name callee_module expr.exp_loc
              | _ -> ())
          | _ -> ()) ;
          (* Continue walking into subexpressions *)
          default_iterator.expr self expr);
    }
  in
  iter.expr iter expr ;
  !calls

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
    ~stmt_fld ~stmt_ctor path =
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
              let module_id =
                insert_module
                  db
                  stmt_mod
                  ~path:rel_path
                  ~lines
                  ~has_mli
                  ?quint_module_raw:(Option.map Option.some quint_module_raw)
                  ()
              in
              (* Collect calls, module deps, and type usages from value bindings *)
              let pending_calls = ref [] in
              let pending_deps = ref [] in
              let pending_type_usages = ref [] in
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
              (* Process structure items *)
              List.iter
                (fun (item : Typedtree.structure_item) ->
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
                  | Tstr_module mb -> (
                      (* module M = SomeModule (alias) *)
                      match mb.mb_id with
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
                  | Tstr_value (_, vbs) ->
                      List.iter
                        (fun (vb : Typedtree.value_binding) ->
                          match vb.vb_pat.pat_desc with
                          | Tpat_var (id, _, _) ->
                              let name = Ident.name id in
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
                              let function_id =
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
                              in
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
                              (* Collect calls from this function's body *)
                              let calls =
                                collect_calls_from_expr
                                  ~src_path:rel_path
                                  ~caller_module:rel_path
                                  ~caller_name:name
                                  vb.vb_expr
                              in
                              pending_calls :=
                                List.rev_append calls !pending_calls
                          | _ -> ())
                        vbs
                  | Tstr_type (_, tds) ->
                      List.iter
                        (fun (td : Typedtree.type_declaration) ->
                          let name = Ident.name td.typ_id in
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
                          let type_id =
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
                          in
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
                          | _ -> ())
                        tds
                  | _ -> ())
                structure.str_items ;
              (!pending_calls, !pending_deps, !pending_type_usages))
      | _ -> ([], [], []))
