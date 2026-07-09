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

(** What is statically known about a call's TARGET, independent of whether the
    call is conditional. Conditionality ([pending_call.cond]) is computed by
    CFG post-dominance; the final edge kind is decided at resolution time from
    the (head × cond × partial) facts. *)
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
  | Head_unknown of string
      (** Unknowable target: applied parameter/local closure, computed head,
          dynamic-root qualified path (functor/first-class-module), or an
          over-application residual — display name or ["*TOP*"]. *)

(** Collected call information before resolution. *)
type pending_call = {
  caller_module : string; (* Module path, e.g. "src/foo.ml" *)
  caller_name : string; (* Function name *)
  head : call_head; (* target facts (resolution identity preserved) *)
  partial : bool; (* under-saturated / returns-a-function → body deferred *)
  cond : bool; (* call block does NOT post-dominate entry (or is deferred) *)
  call_site : string; (* file:line *)
}

(** Flat display of a pending call's callee: [(name, module)] — the qualified
    module component when the head preserves one, for kind-less consumers
    (LSP fallback path). *)
let pending_display (p : pending_call) =
  match p.head with
  | Head_local n | Head_enumerated n | Head_unknown n -> (n, None)
  | Head_qualified (m, n) -> (n, m)

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

(** Walk a value binding expression to collect all function calls.
    [local_fn_stamps] is the set of [Ident.stamp]s of same-module top-level
    function-body bindings; an applied unqualified identifier counts as a
    resolvable (MUST-candidate) call only if its stamp is in this set —
    otherwise it is a parameter / local binding / closure and is MAY_TOP.
    Returns a list of pending calls. *)
let collect_calls_from_expr ~src_path ~caller_module ~caller_name
    ~local_fn_stamps (expr : Typedtree.expression) =
  (* Per-function CFG: calls record their basic block; after the walk we solve
     post-dominance and mark every call whose block is not always-executed as
     conditional ([cond = true]). Deferred bodies (closures, lazy thunks,
     object methods, functor bodies) are walked in ISOLATED blocks with no
     incoming edge — entry-unreachable, hence never always-exec — which forces
     [cond] without a separate counter and guarantees the calls are still
     recorded (never dropped). *)
  let g = Arch_index_cfg.create () in
  let cb = ref Arch_index_cfg.entry in
  (* Active [try] handler-dispatch blocks (innermost first): a diverging
     terminator inside a try body edges to the innermost dispatch (the handler
     may catch) IN ADDITION to the virtual exit (it may not match). *)
  let handler_stack = ref [] in
  (* raw record: block id resolved to [cond] after solving *)
  let raw = ref [] in
  let add_call ?(partial = false) head loc =
    let line = loc.Location.loc_start.pos_lnum in
    let call_site = Printf.sprintf "%s:%d" src_path line in
    raw := (head, partial, !cb, call_site) :: !raw
  in
  (* An applied [Path.Pident] resolves to a MUST-candidate only if it is a
     same-module top-level function body; otherwise it is a parameter / local
     closure with an unknowable target → MAY_TOP. *)
  let ident_is_local_fn id = Hashtbl.mem local_fn_stamps (Ident.unique_name id) in
  let local_fn_arity id = Hashtbl.find_opt local_fn_stamps (Ident.unique_name id) in
  (* True iff [ty] is a function type. Expands type aliases first (via the
     expression's own env) so an arrow hidden behind [type unary = int -> int]
     is still recognised — otherwise a partial application returning [unary]
     would evade the under-saturation check and forge a MUST edge. *)
  let is_arrow ty =
    match Types.get_desc ty with Tarrow _ -> true | _ -> false
  in
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
  (* A function-typed argument may be invoked by the callee. A named local
     function → bounded candidate (Head_enumerated); a parameter / external /
     computed function value → unknowable (Head_unknown). Conditionality is a
     separate fact, decided by the block. *)
  let add_arg_escapes (args : (_ * Typedtree.expression option) list) loc =
    List.iter
      (fun (_, arg_opt) ->
        match arg_opt with
        | Some ae when is_arrow ae.Typedtree.exp_type ->
            let head =
              match ae.exp_desc with
              | Texp_ident (Path.Pident id, _, _) when ident_is_local_fn id ->
                  Head_enumerated (Ident.name id)
              | Texp_ident (Path.Pident id, _, _) -> Head_unknown (Ident.name id)
              | Texp_ident ((Path.Pdot _ as p), _, _) ->
                  let _, n = path_to_module_name p in
                  Head_unknown n
              | _ -> Head_unknown "*TOP*" (* computed function value *)
            in
            add_call head loc
        | _ -> ())
      args
  in
  (* Emit a call to a function named by a resolved [Path.t] — e.g. a let*/and*
     bind operator, which is applied but is not a [Texp_apply] node. *)
  let add_path_call (path : Path.t) loc =
    match path with
    | Path.Pident id when ident_is_local_fn id ->
        add_call (Head_local (Ident.name id)) loc
    | Path.Pident id -> add_call (Head_unknown (Ident.name id)) loc
    | _ ->
        let callee_module, callee_name = path_to_module_name path in
        if qualified_is_dynamic path then
          let disp =
            match callee_module with
            | Some m -> m ^ "." ^ callee_name
            | None -> callee_name
          in
          add_call (Head_unknown disp) loc
        else add_call (Head_qualified (callee_module, callee_name)) loc
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
            let b = Arch_index_cfg.new_block g in
            let join = Arch_index_cfg.new_block g in
            Arch_index_cfg.add_edge g !cb b ;
            Arch_index_cfg.add_edge g !cb join ;
            cb := b ;
            self.expr self e ;
            Arch_index_cfg.add_edge g !cb join ;
            cb := join
          in
          (* Walk [e] in an ISOLATED block (no incoming edge): a deferred body
             (closure/lazy/object) whose calls are recorded but can never be
             always-exec. The current block is untouched. *)
          let walk_isolated_default () =
            let saved = !cb in
            cb := Arch_index_cfg.new_block g ;
            default_iterator.expr self expr ;
            cb := saved
          in
          (* A match/try case walked inside an already-conditional block:
             guard and RHS execute only if the pattern matches. *)
          let walk_case_in : type k. k Typedtree.case -> unit =
           fun c ->
            (match c.c_guard with Some gd -> self.expr self gd | None -> ()) ;
            self.expr self c.c_rhs
          in
          match expr.exp_desc with
          | Texp_function _ | Texp_lazy _ | Texp_object _ ->
              (* Deferred-execution boundaries: a closure body, a [lazy] thunk,
                 or an object's method bodies run only if invoked/forced —
                 walked in an isolated (never always-exec) block so their calls
                 are recorded, demoted, never dropped. *)
              walk_isolated_default ()
          | Texp_ifthenelse (cond, e_then, e_else) ->
              (* Condition runs unconditionally; each branch is a CFG arm. *)
              self.expr self cond ;
              let c_end = !cb in
              let join = Arch_index_cfg.new_block g in
              let bt = Arch_index_cfg.new_block g in
              Arch_index_cfg.add_edge g c_end bt ;
              cb := bt ;
              self.expr self e_then ;
              Arch_index_cfg.add_edge g !cb join ;
              (match e_else with
              | Some e ->
                  let bf = Arch_index_cfg.new_block g in
                  Arch_index_cfg.add_edge g c_end bf ;
                  cb := bf ;
                  self.expr self e ;
                  Arch_index_cfg.add_edge g !cb join
              | None -> Arch_index_cfg.add_edge g c_end join) ;
              cb := join
          | Texp_match (scrut, comp_cases, val_cases, _) ->
              (* Scrutinee runs unconditionally; every arm is a CFG branch. *)
              self.expr self scrut ;
              let s_end = !cb in
              let join = Arch_index_cfg.new_block g in
              let walk_arm : type k. k Typedtree.case -> unit =
               fun c ->
                let arm = Arch_index_cfg.new_block g in
                Arch_index_cfg.add_edge g s_end arm ;
                cb := arm ;
                walk_case_in c ;
                Arch_index_cfg.add_edge g !cb join
              in
              List.iter walk_arm comp_cases ;
              List.iter walk_arm val_cases ;
              cb := join
          | Texp_try (body, val_cases, eff_cases) ->
              (* The try body runs unconditionally. Handlers hang off a
                 dispatch block that BRANCHES from the body's end (an exception
                 "may or may not" occur), so a handler never post-dominates the
                 entry. A diverging terminator inside the body (step 3) also
                 edges to the dispatch: the handler may catch — and to the
                 virtual exit: it may not match. *)
              let dispatch = Arch_index_cfg.new_block g in
              handler_stack := dispatch :: !handler_stack ;
              self.expr self body ;
              (match !handler_stack with
              | _ :: tl -> handler_stack := tl
              | [] -> ()) ;
              let b_end = !cb in
              let join = Arch_index_cfg.new_block g in
              Arch_index_cfg.add_edge g b_end join ;
              Arch_index_cfg.add_edge g b_end dispatch ;
              let walk_handler : type k. k Typedtree.case -> unit =
               fun c ->
                let h = Arch_index_cfg.new_block g in
                Arch_index_cfg.add_edge g dispatch h ;
                cb := h ;
                walk_case_in c ;
                Arch_index_cfg.add_edge g !cb join
              in
              List.iter walk_handler val_cases ;
              List.iter walk_handler eff_cases ;
              cb := join
          | Texp_while (cond, body) ->
              (* head → {body → head, after}: condition evaluated on every
                 iteration path; body may run zero times. No constant folding —
                 [while true] keeps its exit edge (documented termination-
                 insensitivity residual). *)
              let head = Arch_index_cfg.new_block g in
              Arch_index_cfg.add_edge g !cb head ;
              cb := head ;
              self.expr self cond ;
              let c_end = !cb in
              let bodyb = Arch_index_cfg.new_block g in
              let after = Arch_index_cfg.new_block g in
              Arch_index_cfg.add_edge g c_end bodyb ;
              Arch_index_cfg.add_edge g c_end after ;
              cb := bodyb ;
              self.expr self body ;
              Arch_index_cfg.add_edge g !cb head ;
              cb := after
          | Texp_for (_, _, lo, hi, _, body) ->
              (* Bounds run unconditionally; body may run zero times. *)
              self.expr self lo ;
              self.expr self hi ;
              let head = Arch_index_cfg.new_block g in
              Arch_index_cfg.add_edge g !cb head ;
              let bodyb = Arch_index_cfg.new_block g in
              let after = Arch_index_cfg.new_block g in
              Arch_index_cfg.add_edge g head bodyb ;
              Arch_index_cfg.add_edge g head after ;
              cb := bodyb ;
              self.expr self body ;
              Arch_index_cfg.add_edge g !cb head ;
              cb := after
          | Texp_assert (e, _) ->
              (* Assertion condition is elided under -noassert → conditional. *)
              walk_conditional e
          | Texp_letop {let_; ands; body; _} ->
              (* [let* y = e and* z = e' in body]: the bind operators are applied
                 unconditionally, their operands run eagerly, but [body] is the
                 continuation the bind operator may or may not invoke (e.g.
                 [let*] on [None] short-circuits) → a conditional region. *)
              add_path_call let_.bop_op_path let_.bop_loc ;
              List.iter
                (fun (b : Typedtree.binding_op) ->
                  add_path_call b.bop_op_path b.bop_loc)
                ands ;
              self.expr self let_.bop_exp ;
              List.iter
                (fun (b : Typedtree.binding_op) -> self.expr self b.bop_exp)
                ands ;
              let c = Arch_index_cfg.new_block g in
              let join = Arch_index_cfg.new_block g in
              Arch_index_cfg.add_edge g !cb c ;
              Arch_index_cfg.add_edge g !cb join ;
              cb := c ;
              walk_case_in body ;
              Arch_index_cfg.add_edge g !cb join ;
              cb := join
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
              let head_arity =
                match fn_expr.exp_desc with
                | Texp_ident (Path.Pident id, _, _) when ident_is_local_fn id ->
                    (match local_fn_arity id with
                     | Some a -> a
                     | None -> arrow_arity fn_expr.exp_type)
                | _ -> arrow_arity fn_expr.exp_type
              in
              (* Under-saturated (partial) application → builds a closure, the
                 callee body does not run → never MUST. A result that is itself
                 a function (arrow) is also under-saturated / returns-a-function. *)
              let partial = is_arrow expr.exp_type || nargs < head_arity in
              (match fn_expr.exp_desc with
              | Texp_ident (Path.Pident id, _, _) when ident_is_local_fn id ->
                  (* Same-module top-level function — MUST candidate; [cond] and
                     [partial] decide the final kind at resolution. *)
                  add_call ~partial (Head_local (Ident.name id)) expr.exp_loc
              | Texp_ident (Path.Pident id, _, _) ->
                  (* Parameter / local / shadowing binding → unknowable target. *)
                  add_call ~partial (Head_unknown (Ident.name id)) expr.exp_loc
              | Texp_ident (path, _, _) ->
                  let callee_module, callee_name = path_to_module_name path in
                  if qualified_is_dynamic path then
                    let disp =
                      match callee_module with
                      | Some m -> m ^ "." ^ callee_name
                      | None -> callee_name
                    in
                    add_call ~partial (Head_unknown disp) expr.exp_loc
                  else
                    add_call
                      ~partial
                      (Head_qualified (callee_module, callee_name))
                      expr.exp_loc
              | _ ->
                  (* Computed function head → unresolvable. *)
                  add_call ~partial (Head_unknown "*TOP*") expr.exp_loc) ;
              (* Over-application [f a b c] where [f] has arity 2: the head call
                 is saturated (handled above), but the extra args are applied to
                 the (unknown) returned function value — a residual call to an
                 unknowable target. Record it as ⊤ so [unreachable] stays sound. *)
              if head_arity > 0 && nargs > head_arity then
                add_call (Head_unknown "*TOP*") expr.exp_loc ;
              add_arg_escapes args expr.exp_loc ;
              (* Short-circuit [&&]/[||]: the operator itself runs, but the
                 right operand(s) run conditionally → a conditional CFG region. *)
              (match short_circuit_arity fn_expr with
              | Some () -> (
                  self.expr self fn_expr ;
                  match args with
                  | (_, first) :: rest ->
                      Option.iter (self.expr self) first ;
                      let r = Arch_index_cfg.new_block g in
                      let join = Arch_index_cfg.new_block g in
                      Arch_index_cfg.add_edge g !cb r ;
                      Arch_index_cfg.add_edge g !cb join ;
                      cb := r ;
                      List.iter (fun (_, a) -> Option.iter (self.expr self) a) rest ;
                      Arch_index_cfg.add_edge g !cb join ;
                      cb := join
                  | [] -> ())
              | None ->
                  (* Descend into fn + args (nested constructs split blocks). *)
                  default_iterator.expr self expr)
          | _ -> default_iterator.expr self expr);
      module_expr =
        (fun self me ->
          match me.mod_desc with
          | Tmod_functor (_, _) ->
              (* A functor body only runs when the functor is applied → walked
                 in an isolated (never always-exec) block. *)
              let saved = !cb in
              cb := Arch_index_cfg.new_block g ;
              default_iterator.module_expr self me ;
              cb := saved
          | _ -> default_iterator.module_expr self me);
    }
  in
  (* The binding value is `fun <params> -> BODY` (or `function <cases>`); those
     params are THIS function's own, so BODY / the case RHSs are its direct body
     (depth 0). Peel the leading parameter lambdas before walking, otherwise the
     function's own arms would be mistaken for nested closures and every call
     would be demoted to MAY_TOP. Genuinely-nested function literals inside BODY
     still raise [nested]. *)
  (* Optional-argument default expressions (`?(x = e)`) run only when the caller
     omits the argument — conditional, like a nested-closure body. Collect them
     from every peeled parameter layer and walk them with [nested] raised so
     their calls are recorded as MAY_TOP (never dropped → [unreachable] stays
     sound; never a MUST → [reaches] stays honest). *)
  let opt_defaults = ref [] in
  let collect_param_defaults params =
    List.iter
      (fun (p : Typedtree.function_param) ->
        match p.fp_kind with
        | Tparam_optional_default (_, de) -> opt_defaults := de :: !opt_defaults
        | Tparam_pat _ -> ())
      params
  in
  let rec peel (e : Typedtree.expression) =
    match e.exp_desc with
    | Texp_function (params, Tfunction_body b) ->
        collect_param_defaults params ;
        peel b
    | Texp_function (params, Tfunction_cases _) ->
        collect_param_defaults params ;
        e
    | _ -> e
  in
  let root = peel expr in
  (match root.exp_desc with
  | Texp_function (_, Tfunction_cases {cases; _}) ->
      (* A root [function <cases>] is sugar for [fun x -> match x with <cases>]:
         each arm is a CFG branch from the entry (conditional on the argument). *)
      let s_end = !cb in
      let join = Arch_index_cfg.new_block g in
      List.iter
        (fun (c : Typedtree.value Typedtree.case) ->
          let arm = Arch_index_cfg.new_block g in
          Arch_index_cfg.add_edge g s_end arm ;
          cb := arm ;
          (match c.c_guard with Some gd -> iter.expr iter gd | None -> ()) ;
          iter.expr iter c.c_rhs ;
          Arch_index_cfg.add_edge g !cb join)
        cases ;
      cb := join
  | _ -> iter.expr iter root) ;
  (* Optional-arg default expressions run only when the caller omits the
     argument → each walked in an isolated (never always-exec) block: recorded,
     demoted, never dropped. *)
  List.iter
    (fun de ->
      cb := Arch_index_cfg.new_block g ;
      iter.expr iter de)
    !opt_defaults ;
  (* Solve post-dominance and finalize: a call is conditional unless its block
     runs on every execution of this function. *)
  let v = Arch_index_cfg.solve g in
  List.rev_map
    (fun (head, partial, block, call_site) ->
      {
        caller_module;
        caller_name;
        head;
        partial;
        cond = not (Arch_index_cfg.always_exec v block);
        call_site;
      })
    !raw

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
              (* Pre-pass: the set of Ident.stamps of top-level bindings whose
                 RHS is a real function body. A same-module unqualified call
                 resolves to MUST only if the callee's stamp is in this set;
                 everything else (parameters, locals, function-typed values with
                 non-function RHS) is MAY_TOP. Whole-structure pass so forward
                 references and `let rec … and …` groups are all covered. *)
              let local_fn_stamps = Hashtbl.create 64 in
              List.iter
                (fun (it : Typedtree.structure_item) ->
                  match it.str_desc with
                  | Tstr_value (_, vbs) ->
                      List.iter
                        (fun (vb : Typedtree.value_binding) ->
                          match vb.vb_pat.pat_desc with
                          | Tpat_var (id, _, _) when is_function_rhs vb.vb_expr ->
                              Hashtbl.replace
                                local_fn_stamps
                                (Ident.unique_name id)
                                (fn_arity vb.vb_expr)
                          | _ -> ())
                        vbs
                  | _ -> ())
                structure.str_items ;
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
                                  ~local_fn_stamps
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
