(* Direct compiler-libs acceptance probe for synthetic functor-binding shapes.
   Every mutation is asserted before collection and is not claimed source-valid. *)

module Bindings = Arch_index__Arch_index_bindings
module Catalogue = Arch_index__Arch_index_functors
open Typedtree

exception Setup_error of string
exception Assertion_failure of string

let setup fmt = Printf.ksprintf (fun s -> raise (Setup_error s)) fmt
let require condition fmt =
  if condition then Printf.ksprintf ignore fmt
  else Printf.ksprintf (fun s -> raise (Assertion_failure s)) fmt

let read_implementation path =
  match Cmt_format.read path with
  | _, Some {Cmt_format.cmt_annots=Cmt_format.Implementation structure; _} -> structure
  | _ -> setup "%s is not an implementation CMT" path

let rec peel m =
  match m.mod_desc with Tmod_constraint (inner, _, _, _) -> peel inner | _ -> m

let module_bindings structure =
  List.filter_map (fun item ->
    match item.str_desc with Tstr_module binding -> Some binding | _ -> None)
    structure.str_items

let named structure name =
  match List.find_opt
    (fun binding -> binding.mb_name.Location.txt = Some name)
    (module_bindings structure)
  with
  | Some binding -> binding
  | None -> setup "seed module %s is absent" name

let replace structure target replacement =
  {structure with str_items=List.map (fun item ->
    match item.str_desc with
    | Tstr_module binding when binding == target ->
        {item with str_desc=Tstr_module replacement}
    | _ -> item) structure.str_items}

let result_tuple (result : Bindings.result) =
  (result.ordinal, result.status, result.reason, result.declaration_key,
   result.formal_position, result.head_application_ordinal, result.actual_root_key)

let unresolved ?(head = None) ?(root = None) ordinal reason =
  (ordinal, "unresolved", Some reason, None, None, head, root)

let binder_key structure name =
  Ident.unique_name (Option.get (named structure name).mb_id)

let matched ?(head = None) ?(root = None) ordinal key position =
  (ordinal, "matched", None, Some key, Some position, head, root)

let exact_results collection expected label =
  let actual = List.map result_tuple collection.Bindings.results in
  require (actual = expected) "%s result tuples differ" label

let application_parts binding =
  match binding.mb_expr.mod_desc with
  | Tmod_apply (head, argument, coercion) -> (head, argument, coercion)
  | _ -> setup "seed M is not Tmod_apply"

let replace_application structure binding head argument coercion =
  replace structure binding
    {binding with mb_expr={binding.mb_expr with
      mod_desc=Tmod_apply (head, argument, coercion)}}

let identity_cases structure =
  let f = named structure "F" and alias = named structure "Alias"
  and applied = named structure "M" in
  let f_id = Option.get f.mb_id and alias_id = Option.get alias.mb_id in
  require (not (Ident.same f_id alias_id)) "seed F/Alias identities collide" ;
  let duplicate = replace structure alias {alias with mb_id=Some f_id} in
  require (Ident.same (Option.get (named duplicate "Alias").mb_id) f_id)
    "duplicate-binder mutation premise failed" ;
  require
    (try ignore (Bindings.collect duplicate); false with Failure _ -> true)
    "duplicate binder identity did not fail collection" ;
  let collision_expr =
    match f.mb_expr.mod_desc with
    | Tmod_functor (Named (_, name, module_type), body) ->
        {f.mb_expr with mod_desc=Tmod_functor
          (Named (Some f_id, name, module_type), body)}
    | _ -> setup "seed F is not a named literal functor"
  in
  require
    (match collision_expr.mod_desc with
     | Tmod_functor (Named (Some id, _, _), _) -> Ident.same id f_id
     | _ -> false)
    "binder/parameter collision premise failed" ;
  require
    (try ignore (Bindings.collect (replace structure f {f with mb_expr=collision_expr})); false
     with Failure _ -> true)
    "binder/parameter collision did not fail collection" ;
  let self_expr =
    match alias.mb_expr.mod_desc with
    | Tmod_ident (_, lid) ->
        {alias.mb_expr with mod_desc=Tmod_ident (Path.Pident alias_id, lid)}
    | _ -> setup "seed Alias RHS is not an identifier"
  in
  require
    (match self_expr.mod_desc with
     | Tmod_ident (Path.Pident id, _) -> Ident.same id alias_id | _ -> false)
    "self-alias mutation premise failed" ;
  require
    (match (peel (let head, _, _ = application_parts applied in head)).mod_desc with
     | Tmod_ident (Path.Pident id, _) -> Ident.same id alias_id | _ -> false)
    "seed application does not reference Alias identity" ;
  exact_results
    (Bindings.collect (replace structure alias {alias with mb_expr=self_expr}))
    [unresolved ~root:(Some (binder_key structure "A")) 1 "alias_cycle"] "self alias cycle" ;
  `Assoc ["identity_conflicts", `Bool true; "alias_cycle", `Bool true]

let head_cases structure =
  let applied = named structure "M" in
  let head, argument, coercion = application_parts applied in
  let head = peel head in
  let lid = match head.mod_desc with
    | Tmod_ident (_, lid) -> lid | _ -> setup "seed application head is not an identifier" in
  let mutate id =
    let changed = {head with mod_desc=Tmod_ident (Path.Pident id, lid)} in
    replace_application structure applied changed argument coercion
  in
  let actual_root = Some (binder_key structure "A") in
  let missing = Ident.create_local "Missing" in
  require (not (Ident.persistent missing)) "fresh missing identity is persistent" ;
  require
    (List.for_all (fun binding ->
       Option.fold ~none:true ~some:(fun id -> not (Ident.same id missing)) binding.mb_id)
       (module_bindings structure))
    "fresh missing identity equals a seed binder" ;
  exact_results (Bindings.collect (mutate missing))
    [unresolved ~root:actual_root 1 "local_declaration_missing"] "missing local head" ;
  let persistent = Ident.create_persistent "External" in
  require (Ident.persistent persistent) "persistent-head premise failed" ;
  exact_results (Bindings.collect (mutate persistent))
    [unresolved ~root:actual_root 1 "cross_unit_head"] "persistent head" ;
  let unit_structure = replace structure applied
      {applied with mb_expr={applied.mb_expr with mod_desc=Tmod_apply_unit head}} in
  require
    (match (named unit_structure "M").mb_expr.mod_desc with Tmod_apply_unit _ -> true | _ -> false)
    "named-as-unit mutation premise failed" ;
  exact_results (Bindings.collect unit_structure)
    [unresolved 1 "formal_kind_mismatch"] "named/unit mismatch" ;
  `Assoc ["missing_local", `Bool true; "persistent", `Bool true;
          "named_unit_mismatch", `Bool true]

let nested_cases structure =
  let applied = named structure "M" in
  let inner_head, argument, coercion = application_parts applied in
  let inner = {applied.mb_expr with mod_desc=Tmod_apply (inner_head, argument, coercion)} in
  let outer_expr = {applied.mb_expr with mod_desc=Tmod_apply (inner, argument, coercion)} in
  let over = replace structure applied {applied with mb_expr=outer_expr} in
  let occurrences = Catalogue.collect over in
  require (List.map (fun (o : Catalogue.occurrence) -> o.ordinal) occurrences = [1;2])
    "overapplication catalogue ordinals are not outer=1, inner=2" ;
  let declaration_key =
    match (Bindings.collect structure).declarations with
    | [declaration] -> declaration.declaration_key
    | _ -> setup "seed does not have exactly one functor declaration"
  in
  let actual_root = Some (binder_key structure "A") in
  exact_results (Bindings.collect over)
    [unresolved ~head:(Some 2) ~root:actual_root 1 "curried_result_not_functor";
     matched ~root:actual_root 2 declaration_key 1]
    "one-formal overapplication" ;
  let missing = Ident.create_local "InnerMissing" in
  let lid = match (peel inner_head).mod_desc with
    | Tmod_ident (_, lid) -> lid | _ -> setup "inner head is not an identifier" in
  let bad_head = {(peel inner_head) with mod_desc=Tmod_ident (Path.Pident missing, lid)} in
  let bad_inner = {inner with mod_desc=Tmod_apply (bad_head, argument, coercion)} in
  let mismatch_outer = replace structure applied
      {applied with mb_expr={applied.mb_expr with mod_desc=Tmod_apply_unit bad_inner}} in
  require
    (match (named mismatch_outer "M").mb_expr.mod_desc with
     | Tmod_apply_unit {mod_desc=Tmod_apply _; _} -> true | _ -> false)
    "outer-unit/inner-refusal premise failed" ;
  exact_results (Bindings.collect mismatch_outer)
    [unresolved ~head:(Some 2) 1 "local_declaration_missing";
     unresolved ~root:actual_root 2 "local_declaration_missing"]
    "inner refusal precedence" ;
  `Assoc ["overapplication", `Bool true; "inner_refusal_precedence", `Bool true]

let root_cases structure =
  let applied = named structure "M" in
  let head, argument, coercion = application_parts applied in
  let base_path, lid = match (peel argument).mod_desc with
    | Tmod_ident (path, lid) -> (path, lid)
    | _ -> setup "seed argument is not an identifier" in
  let declaration_key =
    match (Bindings.collect structure).declarations with
    | [declaration] -> declaration.declaration_key | _ -> setup "declaration premise failed" in
  let root_id = match base_path with Path.Pident id -> id | _ -> setup "seed A is not Pident" in
  let check label path expected =
    let changed_argument = {(peel argument) with mod_desc=Tmod_ident (path, lid)} in
    let changed = replace_application structure applied head changed_argument coercion in
    require
      (match (peel (let _, a, _ = application_parts (named changed "M") in a)).mod_desc with
       | Tmod_ident (actual, _) -> Path.same actual path | _ -> false)
      "%s path mutation premise failed" label ;
    exact_results (Bindings.collect changed)
      [matched ~root:expected 1 declaration_key 1] label
  in
  let key = Ident.unique_name root_id in
  check "Pident root" (Path.Pident root_id) (Some key) ;
  check "Pdot root" (Path.Pdot (Path.Pident root_id, "Member")) (Some key) ;
  check "Papply root" (Path.Papply (Path.Pident root_id, Path.Pident root_id)) None ;
  check "Pextra_ty root" (Path.Pextra_ty (Path.Pident root_id, Path.Pext_ty)) None ;
  check "persistent root" (Path.Pident (Ident.create_persistent "ExternalArg")) None ;
  `Assoc ["pident_pdot", `Bool true; "papply_pextra_persistent_null", `Bool true]

let formal_cases structure =
  let f = named structure "F" in
  let id, original_name, module_type, body = match f.mb_expr.mod_desc with
    | Tmod_functor (Named (id, name, module_type), body) ->
        (id, name, module_type, body)
    | _ -> setup "seed F formal premise failed" in
  let cases =
    ["key+name", id, original_name.Location.txt;
     "key+null", id, None;
     "null+name", None, original_name.Location.txt;
     "null+null", None, None]
  in
  List.iter (fun (label, binder_id, name) ->
    let parameter_name = {original_name with Location.txt=name} in
    let expr = {f.mb_expr with mod_desc=Tmod_functor
      (Named (binder_id, parameter_name, module_type), body)} in
    let changed = replace structure f {f with mb_expr=expr} in
    require
      (match (named changed "F").mb_expr.mod_desc with
       | Tmod_functor (Named (actual_id, actual_name, _), _) ->
           Option.equal Ident.same actual_id binder_id && actual_name.Location.txt = name
       | _ -> false)
      "%s formal mutation premise failed" label ;
    match (Bindings.collect changed).declarations with
    | [declaration] ->
        (match declaration.formals with
         | [formal] ->
             require (formal.binder_key = Option.map Ident.unique_name binder_id
                      && formal.name = name && formal.kind = Bindings.Named)
               "%s formal nullable projection differs" label
         | _ -> setup "%s did not retain one formal" label)
    | _ -> setup "%s did not retain one declaration" label) cases ;
  `Assoc ["named_nullable_combinations", `Int 4]

let unchanged_catalogue structure =
  let before = Catalogue.collect structure in
  ignore (Bindings.collect structure) ;
  let after = Catalogue.collect structure in
  let cells rows = List.map (fun (o : Catalogue.occurrence) ->
    (o.ordinal, o.head, o.argument)) rows in
  require (cells before = cells after)
    "Bindings.collect changed catalogue ordinal/head/argument descriptors" ;
  `Assoc ["occurrences", `Int (List.length before); "byte_identical", `Bool true]

let run path =
  let structure = read_implementation path in
  let names = List.map (fun binding -> Option.value ~default:"" binding.mb_name.Location.txt)
      (module_bindings structure) in
  require (List.for_all (fun name -> List.mem name names) ["F"; "A"; "Alias"; "M"])
    "seed must define named modules F, A, Alias, M" ;
  require (List.length (Catalogue.collect structure) = 1)
    "seed must contain exactly one module application" ;
  `Assoc
    ["ok", `Bool true;
     "evidence", `String "premise-checked-synthetic-not-source-valid";
     "identity", identity_cases structure;
     "heads", head_cases structure;
     "nested", nested_cases structure;
     "roots", root_cases structure;
     "formals", formal_cases structure;
     "catalogue_unchanged", unchanged_catalogue structure]

let () =
  try
    let seed = match Array.to_list Sys.argv with
      | [_; seed] -> seed
      | _ -> setup "usage: inventory_probe SEED.cmt"
    in
    Yojson.Safe.to_channel stdout (run seed) ; output_char stdout '\n'
  with
  | Assertion_failure message ->
      prerr_endline ("inventory_probe assertion: " ^ message); exit 1
  | Setup_error message | Sys_error message ->
      prerr_endline ("inventory_probe setup: " ^ message); exit 2
  | exn ->
      prerr_endline ("inventory_probe unexpected: " ^ Printexc.to_string exn); exit 2
