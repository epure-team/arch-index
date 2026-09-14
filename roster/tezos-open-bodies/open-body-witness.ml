(* Independent compiler-native evidence for structural open-body applications.
   This intentionally links compiler-libs only: it neither imports arch-index nor
   performs a database lookup.  It independently derives canonical spelling and
   ownership from compiler traversal, then records the identity/cardinality facts
   a separate consumer must discharge before using a transition witness. *)
open Typedtree

let quote s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter (function
    | '"' -> Buffer.add_string b "\\\"" | '\\' -> Buffer.add_string b "\\\\"
    | '\n' -> Buffer.add_string b "\\n" | '\r' -> Buffer.add_string b "\\r"
    | '\t' -> Buffer.add_string b "\\t"
    | c when Char.code c < 32 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
    | c -> Buffer.add_char b c) s;
  Buffer.add_char b '"'; Buffer.contents b

let obj xs = "{" ^ String.concat "," (List.map (fun (k, v) -> quote k ^ ":" ^ v) xs) ^ "}"
let arr xs = "[" ^ String.concat "," xs ^ "]"
let option f = function None -> "null" | Some x -> f x
let bool = string_of_bool
let uid u = quote (Format.asprintf "%a" Shape.Uid.print u)
let ident i = obj ["name", quote (Ident.name i); "unique_name", quote (Ident.unique_name i);
                   "persistent", bool (Ident.persistent i)]

let pos p = obj ["file", quote p.Lexing.pos_fname; "line", string_of_int p.pos_lnum;
                 "offset", string_of_int p.pos_cnum;
                 "column", string_of_int (p.pos_cnum - p.pos_bol)]
let loc l = obj ["start", pos l.Location.loc_start; "end", pos l.loc_end;
                 "start_offset", string_of_int l.loc_start.pos_cnum;
                 "end_offset", string_of_int l.loc_end.pos_cnum;
                 "ghost", bool l.loc_ghost]
let arrow t = match Types.get_desc t with Types.Tarrow _ -> true | _ -> false
let label = function Asttypes.Nolabel -> "" | Labelled s -> "~" ^ s | Optional s -> "?" ^ s

let rec function_arity e =
  match e.exp_desc with
  | Texp_function (params, Tfunction_body body) -> List.length params + function_arity body
  | Texp_function (params, Tfunction_cases _) -> List.length params + 1
  | _ -> 0

let rec terminal_cases e = match e.exp_desc with
  | Texp_function (_, Tfunction_cases _) -> true
  | Texp_function (_, Tfunction_body body) -> terminal_cases body
  | _ -> false

let extra_tag = function
  | Texp_constraint _ -> "constraint" | Texp_coerce _ -> "coerce"
  | Texp_poly _ -> "poly" | Texp_newtype _ -> "newtype"

type candidate = {
  binder : Ident.t; binder_name : string; binder_uid : Shape.Uid.t;
  binder_loc : Location.t; open_loc : Location.t; root : expression;
  module_path : Path.t; root_arity : int; root_result_arrow : bool;
  root_cases : bool; recursive_binding : bool; root_extra_tags : string list;
}

type binding_context = { context_binder : Ident.t; context_name : string;
                         context_loc : Location.t; context_rhs : expression;
                         context_is_structure : bool }

type owner = { owner_index : int; owner_expr : expression; owner_loc : Location.t;
               owner_arity : int; owner_cases : bool; owner_binding : binding_context option;
               parent_owner_index : int option; canonical_owner_name : string;
               stored_owner_loc : Location.t; stored_range_basis : string;
               owner_kind : string; allocation_base : string option;
               allocation_ordinal : int option }

type app = { app_index : int; app_expr : expression; head : expression;
             args : (Asttypes.arg_label * expression option) list; caller : owner option;
             enclosing_binding : binding_context option }

let candidate_json c root_owner body_cardinality = obj [
  "binder", ident c.binder; "binder_uid", uid c.binder_uid;
  "binding_name", quote c.binder_name; "binder_loc", loc c.binder_loc;
  "recursive_binding", bool c.recursive_binding;
  "open_loc", loc c.open_loc; "module_path", quote (Path.name c.module_path);
  "root_function_loc", loc c.root.exp_loc;
  "root_function_arity", string_of_int c.root_arity;
  "root_function_terminal_cases", bool c.root_cases;
  "root_function_result_arrow", bool c.root_result_arrow;
  "root_function_extra_tags", arr (List.map quote c.root_extra_tags);
  "actual_root_owner", option (fun x -> string_of_int x.owner_index) root_owner;
  "actual_root_body_cardinality", string_of_int body_cardinality]

let binding_context_json b = obj ["ident", ident b.context_binder;
  "name", quote b.context_name; "loc", loc b.context_loc;
  "rhs_loc", loc b.context_rhs.exp_loc;
  "rhs_shape", quote (match b.context_rhs.exp_desc with
    | Texp_function _ -> "function" | Texp_open _ -> "open" | Texp_let _ -> "let" | _ -> "other");
  "is_structure_binding", bool b.context_is_structure]

let owner_json candidates owners o =
  let owner_by_index n = List.find_opt (fun x -> x.owner_index = n) owners in
  let rec parent_chain = function
    | None -> []
    | Some n -> match owner_by_index n with
        | None -> ["<missing-owner:" ^ string_of_int n ^ ">"]
        | Some p -> parent_chain p.parent_owner_index @ [p.canonical_owner_name] in
  let rec root_index o = match o.parent_owner_index with
    | Some n -> (match owner_by_index n with Some p -> root_index p | None -> o.owner_index)
    | None -> o.owner_index in
  let immediate_binding_rhs = match o.owner_binding with
    | Some b -> b.context_is_structure && o.owner_expr == b.context_rhs
    | None -> false in
  let promoted_matches = List.filter (fun c -> c.root == o.owner_expr) candidates in
  obj ["native_function_index", string_of_int o.owner_index;
  "loc", loc o.owner_loc; "arity", string_of_int o.owner_arity;
  "terminal_cases", bool o.owner_cases;
  "binding", option binding_context_json o.owner_binding;
  "parent_owner_index", option string_of_int o.parent_owner_index;
  "canonical_owner_name", quote o.canonical_owner_name;
  "stored_owner_loc", loc o.stored_owner_loc;
  "stored_range_basis", quote o.stored_range_basis;
  "owner_kind", quote o.owner_kind;
  "allocation_base", option quote o.allocation_base;
  "allocation_ordinal", option string_of_int o.allocation_ordinal;
  "canonical_parent_chain", arr (List.map quote (parent_chain o.parent_owner_index));
  "canonical_root_owner_index", string_of_int (root_index o);
  "is_immediate_structural_binding_rhs", bool immediate_binding_rhs;
  "matching_open_body_root_count", string_of_int (List.length promoted_matches);
  "is_promoted_open_body_root", bool (List.length promoted_matches = 1)]

let exactly_open_function e =
  match e.exp_desc with
  | Texp_open (od, ({ exp_desc = Texp_function _; _ } as root)) ->
      (match od.open_expr.mod_desc with
       | Tmod_ident (path, _) -> Some (od.open_expr.mod_loc, path, root)
       | _ -> None)
  | _ -> None

let process file =
  let cmt = Cmt_format.read_cmt file in
  let candidates = ref [] and owners = ref [] and applications = ref [] in
  let structural_names : (Ident.t * string) list ref = ref [] in
  let raw_candidates = ref [] and raw_bindings = ref [] in
  let qualify prefix name = prefix ^ name in
  let nested_prefix prefix name = prefix ^ name ^ "." in
  let rec module_expr prefix me = match me.mod_desc with
    | Tmod_structure s -> structure prefix s
    | Tmod_functor (_, body) -> module_expr prefix body
    | Tmod_constraint (inner, _, _, _) -> module_expr prefix inner
    | Tmod_apply _ | Tmod_apply_unit _ | Tmod_ident _ | Tmod_unpack _ -> ()
  and module_binding prefix mb = match mb.mb_id with
    | Some id -> module_expr (nested_prefix prefix (Ident.name id)) mb.mb_expr
    | None -> ()
  and structure prefix s = List.iter (structure_item prefix) s.str_items
  and structure_item prefix item =
    (match item.str_desc with
     | Tstr_value (rec_flag, bindings) -> List.iter (fun vb ->
         match vb.vb_pat.pat_desc with
         | Tpat_var (id, name, _) ->
             raw_bindings := (id, name.txt, prefix, vb) :: !raw_bindings;
             (match exactly_open_function vb.vb_expr with
              | Some (open_loc, module_path, root) ->
                  raw_candidates := (id, name.txt, prefix, vb, rec_flag, open_loc, module_path, root) :: !raw_candidates
              | None -> ())
         | _ -> ()) bindings
     | _ -> ());
    match item.str_desc with
    | Tstr_module mb -> module_binding prefix mb
    | Tstr_recmodule mbs -> List.iter (module_binding prefix) mbs
    | Tstr_include incl -> module_expr prefix incl.incl_mod
    | _ -> ()
  in
  (match cmt.cmt_annots with Implementation s -> structure "" s | _ -> ());
  let raw_bindings = List.rev !raw_bindings in
  let order = Hashtbl.create 32 in
  List.iter (fun (id, name, prefix, _) ->
    let base = qualify prefix (Ident.name id) in
    match Hashtbl.find_opt order base with
    | Some xs -> xs := (Ident.unique_name id) :: !xs
    | None -> Hashtbl.add order base (ref [Ident.unique_name id])) raw_bindings;
  let rendered = Hashtbl.create 32 in
  Hashtbl.iter (fun base stamps_rev ->
    let stamps = List.rev !stamps_rev and total = List.length !stamps_rev in
    List.iteri (fun i stamp -> Hashtbl.replace rendered stamp
      (if i = total - 1 then base else Printf.sprintf "%s#%d" base (i + 1))) stamps) order;
  structural_names := List.map (fun (id, _, _, _) ->
    (id, Option.value (Hashtbl.find_opt rendered (Ident.unique_name id)) ~default:(Ident.name id))) raw_bindings;
  candidates := List.rev_map (fun (binder, _, _, vb, rec_flag, open_loc, module_path, root) ->
    {binder; binder_name=Option.value (Hashtbl.find_opt rendered (Ident.unique_name binder)) ~default:(Ident.name binder);
     binder_uid=(match vb.vb_pat.pat_desc with Tpat_var (_, _, u) -> u | _ -> assert false);
     binder_loc=vb.vb_loc; open_loc; root; module_path; root_arity=function_arity root;
     root_result_arrow=arrow root.exp_type;
     root_cases=terminal_cases root;
     recursive_binding=(match rec_flag with Asttypes.Recursive -> true | Nonrecursive -> false);
     root_extra_tags=List.map (fun (x, _, _) -> extra_tag x) root.exp_extra}) !raw_candidates;
  let application_index = ref 0 and function_index = ref 0 in
  (* This is intentionally a fresh, native traversal marker table.  Its key is
     the product-shaped base spelling, not a source span: ghost/same-location
     literals collide only when they have the same canonical parent. *)
  let markers : (string, int) Hashtbl.t = Hashtbl.create 32 in
  let lambda_base parent l =
    let p = l.Location.loc_start in
    Printf.sprintf "%s.<fun:%d:%d" parent p.pos_lnum (p.pos_cnum - p.pos_bol + 1) in
  let allocate_lambda parent l =
    let base = lambda_base parent l in
    let ordinal = Option.value (Hashtbl.find_opt markers base) ~default:0 + 1 in
    Hashtbl.replace markers base ordinal;
    ((if ordinal = 1 then base ^ ">" else Printf.sprintf "%s#%d>" base ordinal), base, ordinal) in
  let rec is_leading_chain_member root candidate = match root.exp_desc with
    | Texp_function (_, Tfunction_body body) ->
        body == candidate || is_leading_chain_member body candidate
    | _ -> false in
  let current_owner : owner option ref = ref None in
  let current_binding : binding_context option ref = ref None in
  let default = Tast_iterator.default_iterator in
  let rec iterator = { default with
    value_binding = (fun self vb ->
      let saved = !current_binding in
      let structural_name = List.find_map (fun (id, name) ->
        match vb.vb_pat.pat_desc with
        | Tpat_var (binder, _, _) when Ident.same binder id -> Some name
        | _ -> None) !structural_names in
      (match vb.vb_pat.pat_desc with
       | Tpat_var (id, name, _) ->
           current_binding := Some {context_binder=id;
             context_name=Option.value structural_name ~default:name.txt;
             context_loc=vb.vb_loc; context_rhs=vb.vb_expr;
             context_is_structure=Option.is_some structural_name}
       | _ -> current_binding := None);
      default.value_binding self vb;
      current_binding := saved);
    expr = (fun self e ->
      (match e.exp_desc with
       | Texp_function (_, body) ->
           (* Leading [fun] chains are a single indexed function root.  The
              default iterator still visits each typed node, but the active
              canonical owner deliberately remains the outer root, matching
              root peeling rather than inventing a stored lambda per layer. *)
           let is_leading_chain = match !current_owner with
             | Some parent -> is_leading_chain_member parent.owner_expr e
             | None -> false in
           if is_leading_chain then default.expr self e else (
             incr function_index;
             let direct_binding = match !current_binding with
               | Some b -> b.context_is_structure && e == b.context_rhs
               | None -> false in
             let promoted_candidate = List.find_opt (fun c ->
               c.root == e && match !current_binding with
               | Some b -> b.context_is_structure && Ident.same b.context_binder c.binder
               | None -> false) !candidates in
             let parent_name = match !current_owner with
               | Some p -> p.canonical_owner_name | None -> "<unowned>" in
             let canonical_owner_name, allocation_base, allocation_ordinal,
                 stored_owner_loc, stored_range_basis, owner_kind =
               match !current_binding, promoted_candidate, direct_binding, !current_owner with
               | Some b, _, true, _ ->
                   (b.context_name, None, None, b.context_loc, "binding_loc", "direct_binding_function")
               | Some b, Some _, false, _ ->
                   let name, base, ordinal = allocate_lambda b.context_name e.exp_loc in
                   (name, Some base, Some ordinal, e.exp_loc, "promoted_open_root_loc", "promoted_open_body_root")
               | _, _, _, Some _ ->
                   let name, base, ordinal = allocate_lambda parent_name e.exp_loc in
                   (name, Some base, Some ordinal, e.exp_loc, "nested_function_loc", "nested_function")
               | Some b, _, false, None ->
                   (* A local-let function has no independently established
                      persisted owner.  Keep its raw context for diagnosis,
                      but make its non-stored status explicit. *)
                   ("<local:" ^ Ident.unique_name b.context_binder ^ ">", None, None,
                    e.exp_loc, "no_stored_owner", "local_function_unstored")
               | None, _, _, None ->
                   ("<unowned>", None, None, e.exp_loc, "no_stored_owner", "unowned_function") in
             let mine = {owner_index = !function_index; owner_expr=e; owner_loc=e.exp_loc;
                         owner_arity=function_arity e; owner_cases=terminal_cases e;
                         owner_binding = !current_binding;
                         parent_owner_index=Option.map (fun p -> p.owner_index) !current_owner;
                         canonical_owner_name; stored_owner_loc; stored_range_basis;
                         owner_kind; allocation_base; allocation_ordinal} in
             owners := mine :: !owners;
             let saved = !current_owner in
             current_owner := Some mine;
             default.expr self e;
             current_owner := saved)
       | Texp_apply (head, args) ->
           incr application_index;
           applications := {app_index = !application_index; app_expr=e; head; args;
                            caller = !current_owner; enclosing_binding = !current_binding} :: !applications;
           default.expr self e
       | _ -> default.expr self e))
  } in
  (match cmt.cmt_annots with Implementation s -> iterator.structure iterator s | _ -> ());
  let candidates = List.rev !candidates and owners = List.rev !owners
  and applications = List.rev !applications in
  let owners_for_candidate c = List.filter (fun o ->
    o.owner_expr == c.root && match o.owner_binding with
    | Some b -> b.context_is_structure && Ident.same b.context_binder c.binder
    | None -> false) owners in
  let candidates_for_ident id = List.filter (fun c -> Ident.same c.binder id) candidates in
  let head_ident = function
    | { exp_desc = Texp_ident (Path.Pident id, _, _); _ } -> Some id | _ -> None in
  let classify a = match head_ident a.head with
    | Some id -> (match candidates_for_ident id with
      | [c] when List.length (owners_for_candidate c) = 1 -> "eligible_unique"
      | [] -> "not_structural_binding"
      | _ -> "refuse_ambiguous_body_owner")
    | None -> "not_pident_head" in
  let disposition a = match head_ident a.head with
    | Some id -> (match candidates_for_ident id with
      | [c] when List.length (owners_for_candidate c) = 1 ->
          "eligible_unique:body_function:" ^ string_of_int (List.hd (owners_for_candidate c)).owner_index
      | _ -> classify a)
    | None -> classify a in
  let caller_key a = match a.caller with
    | Some o -> "function:" ^ string_of_int o.owner_index
    | None -> "toplevel" in
  let line_key a include_head =
    let p = a.app_expr.exp_loc.loc_start in
    let base = caller_key a ^ "@" ^ p.pos_fname ^ ":" ^ string_of_int p.pos_lnum in
    if not include_head then base else match head_ident a.head with
    | Some id -> base ^ ":" ^ Ident.name id
    | None -> base ^ ":non-pident" in
  let group_json a include_head =
    let key = line_key a include_head in
    let members = List.filter (fun x -> line_key x include_head = key) applications in
    let dispositions = List.map disposition members in
    obj ["key", quote key; "occurrence_count", string_of_int (List.length members);
      "classifications", arr (List.map (fun x -> quote (classify x)) members);
      "dispositions", arr (List.map quote dispositions);
      "unambiguous", bool (List.length (List.sort_uniq String.compare dispositions) = 1)] in
  let application_json a =
    let head_identity, matches = match a.head.exp_desc with
      | Texp_ident (Path.Pident id, lid, value) ->
          (Some (id, lid, value), candidates_for_ident id)
      | _ -> (None, []) in
    let candidate_details = List.map (fun c ->
      let body_owners = owners_for_candidate c in
      candidate_json c (match body_owners with [x] -> Some x | _ -> None) (List.length body_owners)) matches in
    let supplied = List.length (List.filter (fun (_, x) -> Option.is_some x) a.args) in
    let owner_matches = match a.caller with
      | None -> [] | Some o -> List.filter (fun x -> x.owner_index = o.owner_index) owners in
    let binding_contains_application = match a.enclosing_binding with
      | Some b ->
          let start = b.context_rhs.exp_loc.loc_start.pos_cnum
          and stop = b.context_rhs.exp_loc.loc_end.pos_cnum
          and app_start = a.app_expr.exp_loc.loc_start.pos_cnum
          and app_stop = a.app_expr.exp_loc.loc_end.pos_cnum in
          start <= app_start && app_stop <= stop
      | None -> false in
    let classification = classify a in
    let head_json = match head_identity with
      | None -> "null"
      | Some (id, lid, value) -> obj ["ident", ident id;
          "longident", quote (Format.asprintf "%a" Pprintast.longident lid.txt);
          "head_loc", loc a.head.exp_loc; "name_loc", loc lid.loc;
          "value_uid", uid value.val_uid] in
    obj ["native_occurrence_index", string_of_int a.app_index;
      "application_loc", loc a.app_expr.exp_loc; "head", head_json;
      "caller", option (owner_json candidates owners) a.caller;
      "caller_owner_cardinality", string_of_int (List.length owner_matches);
      "enclosing_binding", option binding_context_json a.enclosing_binding;
      "enclosing_binding_rhs_contains_application", bool binding_contains_application;
      "enclosing_structural_binding_available", bool (match a.caller, a.enclosing_binding with
        | None, Some b -> b.context_is_structure && binding_contains_application
        | _ -> false);
      "caller_site_group", group_json a false;
      "caller_site_head_group", group_json a true;
      "slots", string_of_int (List.length a.args); "supplied_some", string_of_int supplied;
      "result_arrow", bool (arrow a.app_expr.exp_type);
      "arguments", arr (List.mapi (fun slot (lbl, arg) -> obj ["slot", string_of_int slot;
        "label", quote (label lbl); "supplied", bool (Option.is_some arg);
        "loc", option (fun x -> loc x.exp_loc) arg]) a.args);
      "matching_identity_candidate_count", string_of_int (List.length matches);
      "matching_identity_candidates", arr candidate_details;
      "classification", quote classification;
      "target_disposition", quote (disposition a)]
  in
  let candidate_record c =
    let os = owners_for_candidate c in candidate_json c (match os with [x] -> Some x | _ -> None) (List.length os) in
  obj ["schema_version", quote "open-body-witness-v2"; "cmt", quote file;
       "artifact_digest", quote (Digest.to_hex (Digest.file file));
       "artifact_digest_algorithm", quote "md5";
       "source", option quote cmt.cmt_sourcefile;
       "source_digest", option (fun d -> quote (Digest.to_hex d)) cmt.cmt_source_digest;
       "source_digest_algorithm", quote "md5";
       "structural_candidates", arr (List.map candidate_record candidates);
       "native_function_owners", arr (List.map (owner_json candidates owners) owners);
       "all_application_occurrences", arr (List.map application_json applications)]

let () =
  let records = ref [] in
  for i = 1 to Array.length Sys.argv - 1 do records := process Sys.argv.(i) :: !records done;
  print_endline (arr (List.rev !records))
