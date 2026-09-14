(* Independent compiler-native witness for one-hop local value aliases.
   This program links compiler-libs only; it deliberately does not reuse any
   arch-index table or resolver.  It reports disagreements for a later,
   fail-closed consumer instead of repairing them by name. *)
open Typedtree

let quote s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter (function
    | '"' -> Buffer.add_string b "\\\""
    | '\\' -> Buffer.add_string b "\\\\"
    | '\n' -> Buffer.add_string b "\\n"
    | '\r' -> Buffer.add_string b "\\r"
    | '\t' -> Buffer.add_string b "\\t"
    | c when Char.code c < 32 ->
        Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
    | c -> Buffer.add_char b c) s;
  Buffer.add_char b '"'; Buffer.contents b

let obj fields =
  "{" ^ String.concat "," (List.map (fun (k, v) -> quote k ^ ":" ^ v) fields) ^ "}"
let arr xs = "[" ^ String.concat "," xs ^ "]"
let option f = function None -> "null" | Some x -> f x
let uid u = quote (Format.asprintf "%a" Shape.Uid.print u)
let ident i = obj ["name", quote (Ident.name i); "unique_name", quote (Ident.unique_name i);
  "persistent", string_of_bool (Ident.persistent i)]
let longident x = quote (Format.asprintf "%a" Pprintast.longident x)

let position p = obj [
  "file", quote p.Lexing.pos_fname; "line", string_of_int p.pos_lnum;
  "bol", string_of_int p.pos_bol; "offset", string_of_int p.pos_cnum;
  "column", string_of_int (p.pos_cnum - p.pos_bol)]
let loc l = obj ["file", quote l.Location.loc_start.pos_fname;
  "start", position l.loc_start; "end", position l.loc_end;
  (* Old-style scalar fields are retained for consumers of uid-witness output. *)
  "start_line", string_of_int l.loc_start.pos_lnum;
  "end_line", string_of_int l.loc_end.pos_lnum;
  "start_offset", string_of_int l.loc_start.pos_cnum;
  "end_offset", string_of_int l.loc_end.pos_cnum;
  "column", string_of_int (l.loc_start.pos_cnum - l.loc_start.pos_bol);
  "ghost", string_of_bool l.loc_ghost]

let resolution = function
  | Shape_reduce.Resolved u -> obj ["kind", quote "Resolved"; "uid", uid u]
  | Shape_reduce.Resolved_alias (u, _) ->
      obj ["kind", quote "Resolved_alias"; "uid", uid u]
  | Shape_reduce.Unresolved _ -> obj ["kind", quote "Unresolved"]
  | Shape_reduce.Approximated u ->
      obj ["kind", quote "Approximated"; "uid", option uid u]
  | Shape_reduce.Internal_error_missing_uid ->
      obj ["kind", quote "Internal_error_missing_uid"]

let syntactic_arity e = match e.exp_desc with
  | Texp_function (params, body) ->
      List.length params + (match body with Tfunction_cases _ -> 1 | _ -> 0)
  | _ -> 0

let arrow_type e = match Types.get_desc e.exp_type with
  | Types.Tarrow _ -> true | _ -> false
let type_is_arrow t = match Types.get_desc t with Types.Tarrow _ -> true | _ -> false

let same_location a b =
  a.Location.loc_start.pos_fname = b.Location.loc_start.pos_fname &&
  a.loc_start.pos_cnum = b.loc_start.pos_cnum &&
  a.loc_end.pos_cnum = b.loc_end.pos_cnum && a.loc_ghost = b.loc_ghost

type binding = {
  binder : Ident.t; name : string; binding_uid : Shape.Uid.t;
  binding_loc : Location.t; rhs_loc : Location.t; arity : int;
  rhs_is_function : bool; rhs_is_arrow : bool;
}

type identifier_use = {
  path : Path.t; lid : Longident.t Location.loc;
  value : Types.value_description; expression : expression;
}

type application = {
  app_head : identifier_use; app_loc : Location.t;
  args : (Asttypes.arg_label * expression option) list;
}

type callback = { callback_use : identifier_use; outer_loc : Location.t; slot : int }

let binding_json b = obj [
  "ident", ident b.binder; "uid", uid b.binding_uid; "binding_uid", uid b.binding_uid;
  "name", quote b.name; "binding_loc", loc b.binding_loc; "body_loc", loc b.rhs_loc;
  "rhs_loc", loc b.rhs_loc; "arity", string_of_int b.arity;
  "syntactic_arity", string_of_int b.arity;
  "rhs_is_function", string_of_bool b.rhs_is_function;
  "rhs_is_arrow", string_of_bool b.rhs_is_arrow]

let label = function Asttypes.Nolabel -> ""
  | Labelled s -> "~" ^ s | Optional s -> "?" ^ s

let process file =
  let cmt = Cmt_format.read_cmt file in
  let bindings = ref [] and identifiers = ref [] and applications = ref []
  and callbacks = ref [] and letops = ref [] and functions = ref [] in
  let default = Tast_iterator.default_iterator in
  let iterator = { default with
    value_binding = (fun self vb ->
      (match vb.vb_pat.pat_desc with
       | Tpat_var (id, name, binding_uid) ->
           let arity = syntactic_arity vb.vb_expr in
           bindings := {binder=id; name=name.txt; binding_uid;
             binding_loc=vb.vb_loc; rhs_loc=vb.vb_expr.exp_loc; arity;
             rhs_is_function=(arity > 0); rhs_is_arrow=arrow_type vb.vb_expr} :: !bindings
       | _ -> ());
      default.value_binding self vb);
    expr = (fun self e ->
      (match e.exp_desc with
       | Texp_function _ -> functions := e.exp_loc :: !functions
       | Texp_ident (path, lid, value) ->
           identifiers := {path; lid; value; expression=e} :: !identifiers
       | Texp_apply (head, args) ->
           (match head.exp_desc with
            | Texp_ident (path, lid, value) ->
                applications := {app_head={path;lid;value;expression=head}; app_loc=e.exp_loc; args} :: !applications
            | _ -> ());
           List.iteri (fun slot (_, arg) -> match arg with
             | Some ({exp_desc=Texp_ident (path,lid,value); _} as expression) ->
                 callbacks := {callback_use={path;lid;value;expression}; outer_loc=e.exp_loc; slot} :: !callbacks
             | _ -> ()) args
       | Texp_letop {let_; ands; _} ->
           letops := (e.exp_loc, let_, ands) :: !letops
       | _ -> ());
      default.expr self e)
  } in
  (match cmt.cmt_annots with Implementation structure -> iterator.structure iterator structure | _ -> ());
  let bindings = List.rev !bindings and identifiers = List.rev !identifiers
  and applications = List.rev !applications and callbacks = List.rev !callbacks
  and letops = List.rev !letops in
  let occurrence_matches (lid : Longident.t Location.loc) =
    cmt.cmt_ident_occurrences
    |> List.filter (fun ((candidate : Longident.t Location.loc), _) ->
         candidate.txt = lid.txt && same_location candidate.loc lid.loc)
  in
  let bindings_by_uid wanted = List.filter (fun b -> b.binding_uid = wanted) bindings in
  let bindings_by_ident wanted = List.filter (fun b -> Ident.same b.binder wanted) bindings in
  let occurrences_json lid = occurrence_matches lid |> List.map
    (fun ((candidate : Longident.t Location.loc), result) ->
    let resolved = match result with
      | Shape_reduce.Resolved u | Resolved_alias (u, _) -> bindings_by_uid u
      | _ -> [] in
    obj ["longident", longident candidate.txt; "name_loc", loc candidate.loc;
      "result", resolution result; "resolved_bindings", arr (List.map binding_json resolved)]) |> arr
  in
  let declarations wanted = match Shape.Uid.Tbl.find_opt cmt.cmt_uid_to_decl wanted with
    | None -> []
    | Some (Value value) -> [obj ["kind",quote "Value";"uid",uid wanted;
        "name",quote value.val_name.txt;"ident",ident value.val_id;
        "loc",loc value.val_loc;"is_arrow",string_of_bool (type_is_arrow value.val_val.val_type)]]
    | Some (Value_binding vb) -> [obj ["kind",quote "Value_binding";"uid",uid wanted;
        "loc",loc vb.vb_loc;"is_arrow",string_of_bool (arrow_type vb.vb_expr)]]
    | Some _ -> [obj ["kind",quote "Other";"uid",uid wanted]]
  in
  let contexts use =
    callbacks |> List.filter_map (fun c ->
      if c.callback_use.expression == use.expression then
        Some (obj ["application_loc",loc c.outer_loc;"argument_slot",string_of_int c.slot])
      else None) |> arr
  in
  let use_fields use = [
    "path", quote (Path.name use.path); "longident", longident use.lid.txt;
    "loc", loc use.expression.exp_loc; "name_loc", loc use.lid.loc;
    "val_uid", uid use.value.val_uid;
    "val_uid_bindings", arr (List.map binding_json (bindings_by_uid use.value.val_uid));
    "val_uid_declarations", arr (declarations use.value.val_uid);
    "occurrences", occurrences_json use.lid;
    "callback_contexts", contexts use]
  in
  let body_for_ident target = bindings_by_ident target |> List.filter (fun b -> b.rhs_is_function) in
  let alias_json b vb_expr = match vb_expr.exp_desc with
    | Texp_ident (Path.Pident target, lid, value) ->
        let bodies = body_for_ident target in
        obj ["alias", binding_json b; "rhs_path", quote (Path.name (Path.Pident target));
          "rhs_kind", quote "local_pident";
          "rhs_ident", ident target; "rhs_longident", longident lid.txt;
          "rhs_name_loc", loc lid.loc; "rhs_val_uid", uid value.val_uid;
          "rhs_occurrences", occurrences_json lid;
          "target_ident_bindings", arr (List.map binding_json (bindings_by_ident target));
          "actual_function_bodies", arr (List.map binding_json bodies);
          "eligible_form", string_of_bool b.rhs_is_arrow;
          "one_hop_body_count", string_of_int (List.length bodies)]
    | _ -> assert false
  in
  (* Revisit only top-level iterator-visible value bindings to retain the RHS
     expression needed for exact syntactic classification. *)
  let aliases = ref [] and unsupported_alias_candidates = ref [] in
  let rhs_kind e = match e.exp_desc with
    | Texp_ident (Path.Pident id, _, _) when Ident.persistent id -> "persistent_pident"
    | Texp_ident (Path.Pident _, _, _) -> "local_pident"
    | Texp_ident _ -> "qualified_ident"
    | Texp_apply _ -> "application"
    | Texp_function _ -> "function_body"
    | Texp_pack _ -> "pack"
    | _ -> "computed_or_other"
  in
  let alias_iterator = { default with value_binding = (fun self vb ->
    (match vb.vb_pat.pat_desc with
     | Tpat_var (id, _, _) ->
         List.iter (fun b -> if Ident.same b.binder id && b.rhs_is_arrow && not b.rhs_is_function then
           match vb.vb_expr.exp_desc with
           | Texp_ident (Path.Pident target, _, _) when not (Ident.persistent target) ->
               aliases := alias_json b vb.vb_expr :: !aliases
           | _ -> unsupported_alias_candidates := obj ["binding",binding_json b;
               "rhs_kind",quote (rhs_kind vb.vb_expr);"rhs_loc",loc vb.vb_expr.exp_loc;
               "reason",quote "unsupported_alias_rhs"] :: !unsupported_alias_candidates) bindings
     | _ -> ());
    default.value_binding self vb) } in
  (match cmt.cmt_annots with Implementation structure -> alias_iterator.structure alias_iterator structure | _ -> ());
  let applications_json = applications |> List.map (fun a -> obj
    (use_fields a.app_head @ ["application_loc",loc a.app_loc;
      "head_loc",loc a.app_head.expression.exp_loc;
      "supplied",string_of_int (List.length (List.filter (fun (_,x)->Option.is_some x) a.args));
      "supplied_some",string_of_int (List.length (List.filter (fun (_,x)->Option.is_some x) a.args));
      "slots",string_of_int (List.length a.args);
      "arguments",arr (List.mapi (fun slot (lbl,arg) -> obj ["slot",string_of_int slot;
        "label",quote (label lbl);"supplied",string_of_bool (Option.is_some arg);
        "loc",option (fun e -> loc e.exp_loc) arg]) a.args)])) in
  let bop_json role bop =
    let candidates = cmt.cmt_ident_occurrences |> List.filter
      (fun ((x : Longident.t Location.loc),_) ->
      same_location x.loc bop.bop_op_name.loc && Longident.last x.txt = bop.bop_op_name.txt) in
    obj ["role",quote role;"path",quote (Path.name bop.bop_op_path);
      "name",quote bop.bop_op_name.txt;"name_loc",loc bop.bop_op_name.loc;
      "bop_loc",loc bop.bop_loc;"val_uid",uid bop.bop_op_val.val_uid;
      "val_uid_bindings",arr (List.map binding_json (bindings_by_uid bop.bop_op_val.val_uid));
      "val_uid_declarations",arr (declarations bop.bop_op_val.val_uid);
      "located_longident_candidates",arr (List.map
        (fun ((x : Longident.t Location.loc),r) -> obj [
        "longident",longident x.txt;"name_loc",loc x.loc;"result",resolution r]) candidates)]
  in
  let letops_json = letops |> List.map (fun (expression_loc, let_, ands) ->
    obj ["loc",loc expression_loc; "operators",arr
      (bop_json "let" let_ :: List.map (bop_json "and") ands)]) in
  obj ["schema_version","1";"cmt",quote file;
    "source",option quote cmt.cmt_sourcefile;"builddir",quote cmt.cmt_builddir;
    "source_digest",option (fun d -> quote (Digest.to_hex d)) cmt.cmt_source_digest;
    "bindings",arr (List.map binding_json bindings);"aliases",arr (List.rev !aliases);
    "unsupported_alias_candidates",arr (List.rev !unsupported_alias_candidates);
    "identifiers",arr (List.map (fun use -> obj (use_fields use)) identifiers);
    "applications",arr applications_json;"letops",arr letops_json;
    "functions",arr (List.rev_map loc !functions);
    "uid_to_decl_count",string_of_int (Shape.Uid.Tbl.length cmt.cmt_uid_to_decl);
    "occurrence_count",string_of_int (List.length cmt.cmt_ident_occurrences)]

let () =
  let records = ref [] in
  for i = 1 to Array.length Sys.argv - 1 do records := process Sys.argv.(i) :: !records done;
  print_endline (arr (List.rev !records))
