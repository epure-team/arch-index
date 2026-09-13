open Asttypes
open Typedtree
module D = Guard_domain

(* This pass cannot choose which sites exist: its results are reconciled with
   the independent inventory by physical expression identity. *)
let primitive e =
  match e.exp_desc with
  | Texp_ident (_, _, {Types.val_kind = Val_prim p; _}) -> Some p.Primitive.prim_name
  | _ -> None

let target = function
  | "%divint" | "%modint" -> Some true
  | "%int32_div" | "%int32_mod" | "%int64_div" | "%int64_mod"
  | "%nativeint_div" | "%nativeint_mod" -> Some false
  | _ -> None

let has_type env ty path =
  let matches ty = match Types.get_desc ty with
    | Tconstr (p, [], _) -> Path.same p path | _ -> false in
  if matches ty then true
  else
    try
      (* CMT expression environments retain summaries, not lookup tables. *)
      matches (Ctype.expand_head (Envaux.env_of_only_summary env) ty)
    with Envaux.Error _ | Not_found -> false

let native e = has_type e.exp_env e.exp_type Predef.path_int
let simple_pattern p = match p.pat_desc with Tpat_var _ | Tpat_any -> true | _ -> false
let unit_pattern p =
  match p.pat_desc with
  | Tpat_construct (_, _, [], _) -> has_type p.pat_env p.pat_type Predef.path_unit
  | _ -> false

let function_supported params =
  List.for_all
    (fun p ->
      match p.fp_arg_label, p.fp_kind with
      | Optional _, _ | _, Tparam_optional_default _ -> false
      | (Nolabel | Labelled _), Tparam_pat pat ->
          p.fp_partial = Total && (simple_pattern pat || unit_pattern pat)) params

let constructor_constant e =
  match e.exp_desc with
  | Texp_construct (_, _, []) ->
      has_type e.exp_env e.exp_type Predef.path_bool
      || has_type e.exp_env e.exp_type Predef.path_unit
  | _ -> false

let exclusion e =
  match e.exp_desc with
  | Texp_function (params, body) ->
      (if function_supported params then [] else ["unsupported_function_parameters"])
      @ (match body with Tfunction_cases _ -> ["unsupported_function_cases"] | _ -> [])
  | Texp_let (flag, bindings, _) ->
      (if flag = Recursive then ["unsupported_recursive_binding"] else [])
      @ (if List.for_all (fun b -> simple_pattern b.vb_pat) bindings then []
         else ["unsupported_binding_pattern"])
  | Texp_apply (head, _) -> (
      match primitive head with
      | Some ("%sequand" | "%sequor") -> ["unsupported_short_circuit"]
      | Some ("%perform" | "%resume" | "%runstack" | "%reperform") -> ["unsupported_effect_primitive"]
      | _ -> [])
  | Texp_constant _ | Texp_ident _ | Texp_sequence _ | Texp_ifthenelse _ -> []
  | Texp_construct _ when constructor_constant e -> []
  | other ->
      let name = match other with
        | Texp_match _ -> "Texp_match" | Texp_try _ -> "Texp_try"
        | Texp_tuple _ -> "Texp_tuple" | Texp_construct _ -> "Texp_construct"
        | Texp_variant _ -> "Texp_variant" | Texp_record _ -> "Texp_record"
        | Texp_field _ -> "Texp_field" | Texp_setfield _ -> "Texp_setfield"
        | Texp_array _ -> "Texp_array" | Texp_while _ -> "Texp_while"
        | Texp_for _ -> "Texp_for" | Texp_send _ -> "Texp_send"
        | Texp_new _ -> "Texp_new" | Texp_instvar _ -> "Texp_instvar"
        | Texp_setinstvar _ -> "Texp_setinstvar" | Texp_override _ -> "Texp_override"
        | Texp_letmodule _ -> "Texp_letmodule" | Texp_letexception _ -> "Texp_letexception"
        | Texp_assert _ -> "Texp_assert" | Texp_lazy _ -> "Texp_lazy"
        | Texp_object _ -> "Texp_object" | Texp_pack _ -> "Texp_pack"
        | Texp_letop _ -> "Texp_letop" | Texp_unreachable -> "Texp_unreachable"
        | Texp_extension_constructor _ -> "Texp_extension_constructor"
        | Texp_open _ -> "Texp_open"
        | Texp_ident _ | Texp_constant _ | Texp_let _ | Texp_function _
        | Texp_apply _ | Texp_sequence _ | Texp_ifthenelse _ -> assert false
      in ["unsupported_expression:" ^ name]

let lookup env id =
  match List.find_opt (fun (key, _) -> Ident.same key id) env with
  | Some (_, value) -> value | None -> D.Top

let eligibility is_native args =
  (if List.length args = 2 then [] else ["unsupported_arity"])
  @ (if List.for_all (fun (label, _) -> label = Nolabel) args then [] else ["unsupported_labels"])
  @ (if List.length args < 2 || List.exists (fun (_, v) -> Option.is_none v) args
     then ["missing_operand"] else [])
  @ (if is_native then [] else ["unsupported_integer_kind"])
  @ (if is_native && not (List.for_all (fun (_, v) -> Option.fold ~none:false ~some:native v) args)
     then ["unsupported_operand_type"] else [])

let status reachable value reasons =
  if reasons <> [] then ("UNSUPPORTED", List.sort_uniq String.compare reasons)
  else if not reachable then ("UNREACHABLE", ["contradictory_supported_branch"])
  else match value with
    | D.Const 0L -> ("ZERO", ["divisor_zero_if_reached"])
    | D.Const _ | D.Nonzero -> ("NONZERO", ["divisor_nonzero_if_reached"])
    | D.Top -> ("MAY_ZERO", ["divisor_may_be_zero"])
    | D.Bottom -> invalid_arg "reachable guard state has bottom divisor"

let analyze structure =
  (* Reconstruct local type aliases using only this compiler's standard library;
     never add arbitrary artifact-recorded include paths or the current directory. *)
  Load_path.init ~auto_include:Load_path.no_auto_include
    ~visible:[Config.standard_library] ~hidden:[] ;
  Envaux.reset_cache () ;
  let results = ref [] in
  let base = Tast_iterator.default_iterator in
  let emit e reachable value reasons =
    match e.exp_desc with
    | Texp_apply (head, args) -> (
        match Option.bind (primitive head) target with
        | None -> ()
        | Some is_native ->
            let s, rs = status reachable value (reasons @ eligibility is_native args) in
            results := (e, s, rs) :: !results)
    | _ -> ()
  in
  let rec eval env reachable inherited e =
    let reasons = exclusion e @ inherited in
    if reasons <> [] then (
      emit e reachable D.Top reasons ;
      let it = iterator env reachable reasons in
      base.expr it e ;
      if reachable then D.Top else D.Bottom)
    else
      let result = match e.exp_desc with
        | Texp_constant (Const_int n) -> D.Const (Int64.of_int n)
        | Texp_ident (Path.Pident id, _, _) when native e -> lookup env id
        | Texp_ident _ | Texp_constant _ | Texp_construct _ -> D.Top
        | Texp_function (_, Tfunction_body body) ->
            ignore (eval [] true [] body) ; D.Top
        | Texp_let (Nonrecursive, bindings, body) ->
            let values = List.map (fun b -> (b.vb_pat, eval env reachable [] b.vb_expr)) bindings in
            let body_env = List.fold_left (fun acc (p, v) -> match p.pat_desc with
              | Tpat_var (id, _, _) -> (id, v) :: acc | _ -> acc) env values in
            eval body_env reachable [] body
        | Texp_sequence (first, second) ->
            ignore (eval env reachable [] first) ; eval env reachable [] second
        | Texp_ifthenelse (cond, yes, no) ->
            ignore (eval env reachable [] cond) ;
            let ey, ry = restrict env reachable cond true in
            let en, rn = restrict env reachable cond false in
            let y = eval ey ry [] yes in
            let n = match no with Some n -> eval en rn [] n | None -> if rn then D.Top else D.Bottom in
            D.join y n
        | Texp_apply (head, args) ->
            ignore (eval env reachable [] head) ;
            let values = List.map (fun (_, arg) -> Option.fold ~none:D.Top
              ~some:(eval env reachable []) arg) args in
            let divisor = match List.nth_opt values 1 with Some v -> v | None -> D.Top in
            emit e reachable divisor [] ;
            let well_typed = List.for_all (fun (label, arg) ->
              label = Nolabel && Option.fold ~none:false ~some:native arg) args in
            if not well_typed then D.Top else (
              match primitive head, values with
              | Some "%negint", [a] -> D.checked_neg Sys.int_size a
              | Some "%addint", [a; b] -> D.checked_add Sys.int_size a b
              | Some "%subint", [a; b] -> D.checked_sub Sys.int_size a b
              | Some "%mulint", [a; b] -> D.checked_mul Sys.int_size a b
              | _ -> D.Top)
        | _ -> invalid_arg "unclassified guard expression constructor"
      in
      if reachable then result else D.Bottom
  and restrict env reachable condition truth =
    if not reachable then (env, false) else
    match condition.exp_desc with
    | Texp_construct (_, c, []) when has_type condition.exp_env condition.exp_type Predef.path_bool ->
        (env, (c.Types.cstr_name = "true") = truth)
    | Texp_apply (head, [(Nolabel, Some a); (Nolabel, Some b)]) when native a && native b -> (
        match primitive head with
        | Some ("%equal" | "%eq" | "%notequal" | "%noteq" as op) ->
            let identifier_zero x z = match x.exp_desc, z.exp_desc with
              | Texp_ident (Path.Pident id, _, _), Texp_constant (Const_int 0) -> Some id
              | _ -> None in
            let id = match identifier_zero a b with Some _ as id -> id | None -> identifier_zero b a in
            (match id with
             | None -> (env, true)
             | Some id ->
                 let equals = (op = "%equal" || op = "%eq") = truth in
                 let value = (if equals then D.restrict_eq_zero else D.restrict_ne_zero) (lookup env id) in
                 ((id, value) :: env, value <> D.Bottom))
        | _ -> (env, true))
    | _ -> (env, true)
  and iterator env reachable inherited =
    {base with
     expr = (fun _ e -> ignore (eval env reachable inherited e));
     value_bindings = (fun _ (flag, bindings) ->
       let rs = if flag = Recursive then "unsupported_recursive_binding" :: inherited else inherited in
       let it = iterator [] true rs in
       List.iter (base.value_binding it) bindings);
     class_expr = (fun _ ce ->
       let name = match ce.cl_desc with
         | Tcl_ident _ -> "Tcl_ident" | Tcl_structure _ -> "Tcl_structure"
         | Tcl_fun _ -> "Tcl_fun" | Tcl_apply _ -> "Tcl_apply" | Tcl_let _ -> "Tcl_let"
         | Tcl_constraint _ -> "Tcl_constraint" | Tcl_open _ -> "Tcl_open" in
       let it = iterator [] true (("unsupported_expression:" ^ name) :: inherited) in
       base.class_expr it ce)}
  in
  let it = iterator [] true [] in
  it.structure it structure ;
  List.rev !results
