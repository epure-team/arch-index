(* Compiler-native witness for singleton local recursive self-heads.
   This program deliberately imports compiler-libs only.  It observes CMT
   identity, syntax, source ranges and product-shaped lambda allocation; it
   never opens an arch-index database and therefore never claims storage. *)
open Typedtree

let quote s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"' ;
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | c when Char.code c < 32 ->
          Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s ;
  Buffer.add_char b '"' ;
  Buffer.contents b

let obj xs = "{" ^ String.concat "," (List.map (fun (k, v) -> quote k ^ ":" ^ v) xs) ^ "}"
let arr xs = "[" ^ String.concat "," xs ^ "]"
let opt f = function None -> "null" | Some x -> f x
let bool = string_of_bool
let ident i =
  obj
    [ ("name", quote (Ident.name i));
      ("unique_name", quote (Ident.unique_name i));
      ("persistent", bool (Ident.persistent i)) ]
let uid u = quote (Format.asprintf "%a" Shape.Uid.print u)
let pos p =
  obj
    [ ("file", quote p.Lexing.pos_fname); ("line", string_of_int p.pos_lnum);
      ("offset", string_of_int p.pos_cnum);
      ("column", string_of_int (p.pos_cnum - p.pos_bol)) ]
let loc l =
  obj
    [ ("start", pos l.Location.loc_start); ("end", pos l.Location.loc_end);
      ("start_offset", string_of_int l.loc_start.pos_cnum);
      ("end_offset", string_of_int l.loc_end.pos_cnum);
      ("ghost", bool l.loc_ghost) ]
let arrow ty = match Types.get_desc ty with Types.Tarrow _ -> true | _ -> false
let label = function Asttypes.Nolabel -> "" | Labelled s -> "~" ^ s | Optional s -> "?" ^ s

let rec fn_arity e =
  match e.exp_desc with
  | Texp_function (ps, Tfunction_body body) -> List.length ps + fn_arity body
  | Texp_function (ps, Tfunction_cases _) -> List.length ps + 1
  | _ -> 0

let rec terminal_cases e =
  match e.exp_desc with
  | Texp_function (_, Tfunction_cases _) -> true
  | Texp_function (_, Tfunction_body body) -> terminal_cases body
  | _ -> false

let extra_tag = function
  | Texp_constraint _ -> "constraint"
  | Texp_coerce _ -> "coerce"
  | Texp_poly _ -> "poly"
  | Texp_newtype _ -> "newtype"

type binding = {
  binder : Ident.t;
  binder_uid : Shape.Uid.t;
  name : string;
  rhs : expression;
  loc : Location.t;
  structural : bool;
}

type recursive_scope = {
  rs_binding : binding;
  rs_group_size : int;
  rs_direct_function_rhs : bool;
}

type owner = {
  owner_index : int;
  owner_expr : expression;
  owner_name : string;
  owner_parent : int option;
  owner_kind : string;
  owner_arity : int;
  owner_cases : bool;
  owner_alloc_base : string option;
  owner_alloc_ordinal : int option;
}

type application = {
  app_index : int;
  app_expr : expression;
  head : expression;
  args : (Asttypes.arg_label * expression option) list;
  caller : owner option;
  recursive_scopes : recursive_scope list;
}

let process file =
  let cmt = Cmt_format.read_cmt file in
  let structural : (Ident.t * string) list ref = ref [] in
  let raw_structural : (Ident.t * string * string) list ref = ref [] in
  let rec collect_module prefix me =
    match me.mod_desc with
    | Tmod_structure s -> collect_structure prefix s
    | Tmod_functor (_, body) -> collect_module prefix body
    | Tmod_constraint (inner, _, _, _) -> collect_module prefix inner
    | Tmod_apply _ | Tmod_apply_unit _ | Tmod_ident _ | Tmod_unpack _ -> ()
  and collect_structure prefix s = List.iter (collect_item prefix) s.str_items
  and collect_item prefix item =
    (match item.str_desc with
     | Tstr_value (_, vbs) ->
         List.iter
           (fun vb ->
             match vb.vb_pat.pat_desc with
             | Tpat_var (id, _, _) ->
                 raw_structural := (id, prefix ^ Ident.name id, Ident.unique_name id) :: !raw_structural
             | _ -> ())
           vbs
     | _ -> ()) ;
    match item.str_desc with
    | Tstr_module mb ->
        (match mb.mb_id with
         | Some id -> collect_module (prefix ^ Ident.name id ^ ".") mb.mb_expr
         | None -> ())
    | Tstr_recmodule mbs ->
        List.iter
          (fun mb -> match mb.mb_id with
           | Some id -> collect_module (prefix ^ Ident.name id ^ ".") mb.mb_expr
           | None -> ())
          mbs
    | Tstr_include incl -> collect_module prefix incl.incl_mod
    | _ -> ()
  in
  (match cmt.cmt_annots with Implementation s -> collect_structure "" s | _ -> ()) ;
  let raw_structural = List.rev !raw_structural in
  let grouped = Hashtbl.create 32 in
  List.iter
    (fun (_, base, stamp) ->
      match Hashtbl.find_opt grouped base with
      | Some xs -> xs := stamp :: !xs
      | None -> Hashtbl.add grouped base (ref [stamp]))
    raw_structural ;
  let rendered = Hashtbl.create 32 in
  Hashtbl.iter
    (fun base stamps_rev ->
      let stamps = List.rev !stamps_rev in
      let total = List.length stamps in
      List.iteri
        (fun i stamp ->
          Hashtbl.replace rendered stamp
            (if i = total - 1 then base else Printf.sprintf "%s#%d" base (i + 1)))
        stamps)
    grouped ;
  structural :=
    List.map
      (fun (id, base, stamp) ->
        (id, Option.value ~default:base (Hashtbl.find_opt rendered stamp)))
      raw_structural ;
  let name_of_structural id =
    List.find_map (fun (known, name) -> if Ident.same known id then Some name else None) !structural
  in
  let owners = ref [] and applications = ref [] in
  let owner_counter = ref 0 and app_counter = ref 0 in
  let markers : (string, int) Hashtbl.t = Hashtbl.create 32 in
  let current_owner : owner option ref = ref None in
  let current_binding : binding option ref = ref None in
  (* Nested recursive lets do not hide an outer binder from the outer RHS.
     Keep every active group member, then select by compiler Ident at an
     application head.  This also records a mutual group's refusal evidence
     instead of dropping its binders from the native account. *)
  let current_recursive : recursive_scope list ref = ref [] in
  let lambda_base parent l =
    let p = l.Location.loc_start in
    Printf.sprintf "%s.<fun:%d:%d" parent p.pos_lnum (p.pos_cnum - p.pos_bol + 1)
  in
  let allocate_lambda parent l =
    let base = lambda_base parent l in
    let ordinal = Option.value ~default:0 (Hashtbl.find_opt markers base) + 1 in
    Hashtbl.replace markers base ordinal ;
    ((if ordinal = 1 then base ^ ">" else Printf.sprintf "%s#%d>" base ordinal), base, ordinal)
  in
  let rec leading_member root candidate =
    match root.exp_desc with
    | Texp_function (_, Tfunction_body body) -> body == candidate || leading_member body candidate
    | _ -> false
  in
  let default = Tast_iterator.default_iterator in
  let rec iterator =
    { default with
      value_binding =
        (fun self vb ->
          let saved = !current_binding in
          (match vb.vb_pat.pat_desc with
           | Tpat_var (id, _, binder_uid) ->
               current_binding :=
                 Some
                   { binder = id; binder_uid; name = Option.value ~default:(Ident.name id) (name_of_structural id);
                     rhs = vb.vb_expr; loc = vb.vb_loc; structural = Option.is_some (name_of_structural id) }
           | _ -> current_binding := None) ;
          let saved_owner = !current_owner in
          (* A structural binding owns its whole RHS even when that RHS is not
             itself a function.  In particular [let outer = let rec aux =
             fun ...] has an existing structural caller for [aux]'s literal.
             Establish it here, once, so the direct function expression below
             cannot create a duplicate owner. *)
          (match !current_binding with
           | Some b when b.structural ->
               incr owner_counter ;
               let mine =
                 { owner_index = !owner_counter; owner_expr = b.rhs; owner_name = b.name;
                   owner_parent = Option.map (fun o -> o.owner_index) !current_owner;
                   owner_kind = "structural_binding"; owner_arity = fn_arity b.rhs;
                   owner_cases = terminal_cases b.rhs; owner_alloc_base = None;
                   owner_alloc_ordinal = None }
               in
               owners := mine :: !owners ; current_owner := Some mine
           | _ -> ()) ;
          default.value_binding self vb ;
          current_owner := saved_owner ;
          current_binding := saved);
      expr =
        (fun self e ->
          match e.exp_desc with
          | Texp_let (Asttypes.Recursive, vbs, body) ->
              let saved = !current_recursive in
              let group_size = List.length vbs in
              let group_scopes =
                List.filter_map
                  (fun vb ->
                    match vb.vb_pat.pat_desc with
                    | Tpat_var (id, _, binder_uid) ->
                        let b =
                          { binder = id; binder_uid;
                            name = Option.value ~default:(Ident.name id) (name_of_structural id);
                            rhs = vb.vb_expr; loc = vb.vb_loc;
                            structural = Option.is_some (name_of_structural id) }
                        in
                        Some
                          { rs_binding = b; rs_group_size = group_size;
                            rs_direct_function_rhs =
                              (match vb.vb_expr.exp_desc with Texp_function _ -> true | _ -> false) }
                    | _ -> None)
                  vbs
              in
              current_recursive := group_scopes @ saved ;
              List.iter (fun vb -> self.value_binding self vb) vbs ;
              current_recursive := saved ;
              self.expr self body
          | Texp_let (_, vbs, body) ->
              List.iter (fun vb -> self.value_binding self vb) vbs ; self.expr self body
          | Texp_function _ ->
              let leading = match !current_owner with
                | Some parent -> leading_member parent.owner_expr e
                | None -> false
              in
              if leading then default.expr self e
              else (
                incr owner_counter ;
                let root_scope =
                  List.find_opt
                    (fun rs -> rs.rs_direct_function_rhs && rs.rs_binding.rhs == e)
                    !current_recursive
                in
                let direct_structural =
                  match !current_binding with
                  | Some b -> b.structural && b.rhs == e
                  | None -> false
                in
                let parent_name = Option.map (fun o -> o.owner_name) !current_owner in
                let existing_binding_owner =
                  match !current_owner, !current_binding with
                  | Some owner, Some b when e == b.rhs && owner.owner_expr == b.rhs
                                           && owner.owner_kind = "structural_binding" -> true
                  | _ -> false
                in
                let owner_name, owner_kind, alloc_base, alloc_ordinal =
                  match root_scope, direct_structural, parent_name with
                  | Some rs, _, Some parent ->
                      let n, base, ordinal = allocate_lambda parent e.exp_loc in
                      (n, "recursive_root_literal", Some base, Some ordinal)
                  | Some _, _, None ->
                      ("<unowned-recursive-root>", "recursive_root_unowned", None, None)
                  | None, true, _ when existing_binding_owner ->
                      (Option.value ~default:"<unnamed-structure>" (Option.map (fun b -> b.name) !current_binding),
                       "structural_binding_function_root", None, None)
                  | None, true, _ ->
                      (Option.value ~default:"<unowned-structure>" (Option.map (fun b -> b.name) !current_binding),
                       "structural_binding_function_unowned", None, None)
                  | None, false, Some parent ->
                      let n, base, ordinal = allocate_lambda parent e.exp_loc in
                      (n, "nested_function", Some base, Some ordinal)
                  | None, false, None -> ("<unowned-function>", "unowned_function", None, None)
                in
                let mine =
                  { owner_index = !owner_counter; owner_expr = e; owner_name;
                    owner_parent = Option.map (fun o -> o.owner_index) !current_owner;
                    owner_kind; owner_arity = fn_arity e; owner_cases = terminal_cases e;
                    owner_alloc_base = alloc_base; owner_alloc_ordinal = alloc_ordinal }
                in
                if existing_binding_owner then default.expr self e
                else (
                  owners := mine :: !owners ;
                  let saved = !current_owner in
                  current_owner := Some mine ;
                  default.expr self e ;
                  current_owner := saved))
          | Texp_apply (head, args) ->
              incr app_counter ;
              applications :=
                { app_index = !app_counter; app_expr = e; head; args; caller = !current_owner;
                  recursive_scopes = !current_recursive } :: !applications ;
              default.expr self e
          | _ -> default.expr self e) }
  in
  (match cmt.cmt_annots with Implementation s -> iterator.structure iterator s | _ -> ()) ;
  let owners = List.rev !owners and applications = List.rev !applications in
  let head_ident = function
    | {exp_desc = Texp_ident (Path.Pident id, lid, value); _} -> Some (id, lid, value)
    | _ -> None
  in
  let range_within outer inner =
    outer.exp_loc.loc_start.pos_cnum <= inner.exp_loc.loc_start.pos_cnum
    && inner.exp_loc.loc_end.pos_cnum <= outer.exp_loc.loc_end.pos_cnum
  in
  let root_owner rs =
    List.filter
      (fun o -> o.owner_kind = "recursive_root_literal" && o.owner_expr == rs.rs_binding.rhs)
      owners
  in
  let matching_scope a =
    match head_ident a.head with
    | Some (id, _, _) ->
        List.find_opt
          (fun rs -> Ident.same id rs.rs_binding.binder && range_within rs.rs_binding.rhs a.app_expr)
          a.recursive_scopes
    | None -> None
  in
  let classification a =
    match matching_scope a, head_ident a.head with
    | Some rs, Some _ when rs.rs_group_size <> 1 -> "refuse_non_singleton_recursive_group"
    | Some rs, Some _ when not rs.rs_direct_function_rhs -> "refuse_nonfunction_recursive_rhs"
    | Some rs, Some _ ->
        (match root_owner rs with
         | [_] -> "native_self_head_requires_storage_confirmation"
         | [] -> "refuse_root_not_observed"
         | _ -> "refuse_ambiguous_physical_root")
    | None, Some _ when a.recursive_scopes <> [] -> "not_active_recursive_binder"
    | None, Some _ -> "not_in_singleton_recursive_rhs"
    | None, None -> "not_pident_head"
  in
  let disposition a =
    let head_stamp =
      match head_ident a.head with
      | Some (id, _, _) -> ":head=" ^ Ident.unique_name id
      | None -> ":head=<non-pident>"
    in
    match matching_scope a with
    | Some rs ->
        (match root_owner rs with
         | [o] -> classification a ^ ":root=" ^ o.owner_name ^ head_stamp
         | _ -> classification a ^ head_stamp)
    | None -> classification a ^ head_stamp
  in
  let caller_key a = match a.caller with None -> "toplevel" | Some o -> "owner:" ^ string_of_int o.owner_index in
  let head_spelling a =
    match head_ident a.head with
    | Some (_, lid, _) -> Format.asprintf "%a" Pprintast.longident lid.txt
    | None -> "<non-pident>"
  in
  let line_key a =
    let p = a.app_expr.exp_loc.loc_start in
    caller_key a ^ "@" ^ p.pos_fname ^ ":" ^ string_of_int p.pos_lnum
    ^ ":" ^ head_spelling a
  in
  let group_json a =
    let key = line_key a in
    let members = List.filter (fun x -> line_key x = key) applications in
    let ds = List.map disposition members in
    obj
      [ ("key", quote key); ("occurrence_count", string_of_int (List.length members));
        ("member_occurrence_indices", arr (List.map (fun x -> string_of_int x.app_index) members));
        ("member_dispositions", arr (List.map quote ds));
        ("unambiguous", bool (List.length (List.sort_uniq String.compare ds) = 1)) ]
  in
  let owner_json o =
    obj
      [ ("native_owner_index", string_of_int o.owner_index); ("name", quote o.owner_name);
        ("kind", quote o.owner_kind); ("loc", loc o.owner_expr.exp_loc);
        ("arity", string_of_int o.owner_arity); ("terminal_cases", bool o.owner_cases);
        ("parent_owner_index", opt string_of_int o.owner_parent);
        ("allocation_base", opt quote o.owner_alloc_base);
        ("allocation_ordinal", opt string_of_int o.owner_alloc_ordinal) ]
  in
  let scope_json rs =
    let roots = root_owner rs in
    obj
      [ ("binder", ident rs.rs_binding.binder); ("binder_uid", uid rs.rs_binding.binder_uid);
        ("binding_loc", loc rs.rs_binding.loc); ("rhs_loc", loc rs.rs_binding.rhs.exp_loc);
        ("group_size", string_of_int rs.rs_group_size);
        ("direct_tfunction_rhs", bool rs.rs_direct_function_rhs);
        ("rhs_extra_tags", arr (List.map (fun (x, _, _) -> quote (extra_tag x)) rs.rs_binding.rhs.exp_extra));
        ("root_observation_count", string_of_int (List.length roots));
        ("actual_root", opt owner_json (match roots with [o] -> Some o | _ -> None));
        ("storage", quote "unconfirmed_native_oracle_only") ]
  in
  let application_json a =
    let supplied = List.length (List.filter (fun (_, x) -> Option.is_some x) a.args) in
    let head_json =
      match head_ident a.head with
      | None -> "null"
      | Some (id, lid, value) ->
          obj
            [ ("ident", ident id); ("longident", quote (Format.asprintf "%a" Pprintast.longident lid.txt));
              ("head_loc", loc a.head.exp_loc); ("name_loc", loc lid.loc); ("value_uid", uid value.val_uid) ]
    in
    obj
      [ ("native_occurrence_index", string_of_int a.app_index);
        ("application_loc", loc a.app_expr.exp_loc); ("head", head_json);
        ("caller", opt owner_json a.caller);
        ("matching_recursive_scope", opt scope_json (matching_scope a));
        ("active_recursive_scope_count", string_of_int (List.length a.recursive_scopes));
        ("active_recursive_binders", arr (List.map (fun rs -> ident rs.rs_binding.binder) a.recursive_scopes));
        ("caller_site_group", group_json a); ("classification", quote (classification a));
        ("target_disposition", quote (disposition a));
        ("root_syntactic_arity", opt (fun rs -> string_of_int (fn_arity rs.rs_binding.rhs)) (matching_scope a));
        ("result_arrow", bool (arrow a.app_expr.exp_type));
        ("slots", string_of_int (List.length a.args)); ("supplied_some", string_of_int supplied);
        ("arguments", arr (List.mapi (fun slot (lbl, arg) ->
           obj [ ("slot", string_of_int slot); ("label", quote (label lbl));
                 ("supplied", bool (Option.is_some arg)); ("loc", opt (fun x -> loc x.exp_loc) arg) ]) a.args)) ]
  in
  obj
    [ ("schema_version", quote "recursive-witness-v1"); ("cmt", quote file);
      ("artifact_digest", quote (Digest.to_hex (Digest.file file)));
      ("artifact_digest_algorithm", quote "md5");
      ("source", opt quote cmt.cmt_sourcefile);
      ("native_function_owners", arr (List.map owner_json owners));
      ("all_application_occurrences", arr (List.map application_json applications)) ]

let () =
  let records = ref [] in
  for i = 1 to Array.length Sys.argv - 1 do records := process Sys.argv.(i) :: !records done ;
  print_endline (arr (List.rev !records))
