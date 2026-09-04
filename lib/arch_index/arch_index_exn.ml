(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Exception-identity recording for one function node (specs/exn-raise-sets.md).

    Pure accumulator: no SQLite, no CFG. The CFG walker in [Arch_index_cmt]
    owns ONE of these per lowering context (top-level binding or promoted
    lambda) and calls in at the same AST sites it already special-cases —
    [Texp_try], [Texp_match], [Texp_assert], [Texp_apply], the root
    [function] — so scope boundaries cannot drift from the walker's own.

    Semantics recorded here are lexical, not control-flow: a scope is the
    [try] BODY (or the [match] SCRUTINEE), never the handlers; an arm is
    closing iff it is unguarded and every raise in its RHS carries a literal
    constructor (an arm that may re-raise the caught value — directly or
    through a nested [match] on it — closes nothing, the over-approximating
    direction). *)

type form =
  | Raise
  | Reraise
  | Unknown
  | Failwith
  | Invalid_arg
  | Assert
  | Partial_match
  | Compare
  | Division
  | Index

let form_to_string = function
  | Raise -> "raise"
  | Reraise -> "reraise"
  | Unknown -> "unknown"
  | Failwith -> "failwith"
  | Invalid_arg -> "invalid_arg"
  | Assert -> "assert"
  | Partial_match -> "partial_match"
  | Compare -> "compare"
  | Division -> "division"
  | Index -> "index"

type scope_form = Try | Match_exception

let scope_form_to_string = function Try -> "try" | Match_exception -> "match_exception"

type origin = {
  o_form : form;
  o_path : string option;
  o_scope : int option;
  o_escapes : bool;
  o_line : int;
  o_col : int;
}

type scope = {
  s_id : int;
  s_parent : int option;
  s_form : scope_form;
  s_line : int;
  s_col : int;
  s_catch_all : bool;
  s_caught : string list;
  s_bound : string list;
}

type arm = {
  a_pat : Typedtree.value Typedtree.general_pattern;
  a_guard : Typedtree.expression option;
  a_rhs : Typedtree.expression;
}

type acc = {
  mutable scopes : scope list; (* reversed *)
  mutable raw_origins : (form * string option * int option * int * int) list;
  mutable stack : int list; (* innermost first *)
  mutable next_id : int;
}

let create () = {scopes = []; raw_origins = []; stack = []; next_id = 0}

let current_scope acc = match acc.stack with s :: _ -> Some s | [] -> None

(* ------------------------------------------------------------------------ *)
(* Recognisers                                                              *)
(* ------------------------------------------------------------------------ *)

let is_raise_prim = function
  | "%raise" | "%raise_notrace" | "%reraise" -> true
  | _ -> false

(** A raise head is recognised by its PRIMITIVE, not its path: Tezos's protocol
    environment (and any [external f : exn -> 'a = "%raise"]) re-exports
    [raise] under its own path. *)
let is_raise_head (e : Typedtree.expression) =
  match e.exp_desc with
  | Texp_ident (_, _, {val_kind = Val_prim {prim_name; _}; _}) -> is_raise_prim prim_name
  | _ -> false

let rec path_root = function
  | Path.Pident id -> Some id
  | Path.Pdot (p, _) | Path.Papply (p, _) | Path.Pextra_ty (p, _) -> path_root p

(** Persistent [Stdlib] root only (a local [module Stdlib] or a shadowing
    [let failwith] resolves elsewhere and is not an origin). *)
let stdlib_member (path : Path.t) =
  match path with
  | Path.Pdot (Path.Pident root, name)
    when Ident.persistent root && Ident.name root = "Stdlib" ->
      Some name
  | Path.Pdot (Path.Pdot (Path.Pident root, "Printexc"), name)
    when Ident.persistent root && Ident.name root = "Stdlib" ->
      Some ("Printexc." ^ name)
  | _ -> None

type stdlib_head = Sl_failwith | Sl_invalid_arg | Sl_raise_with_backtrace

let stdlib_head (e : Typedtree.expression) =
  match e.exp_desc with
  | Texp_ident (path, _, _) -> (
      match stdlib_member path with
      | Some "failwith" -> Some Sl_failwith
      | Some "invalid_arg" -> Some Sl_invalid_arg
      | Some "Printexc.raise_with_backtrace" -> Some Sl_raise_with_backtrace
      | _ -> None)
  | _ -> None

let literal_exn (e : Typedtree.expression) =
  match e.exp_desc with
  | Texp_construct (_, {cstr_tag = Cstr_extension (p, _); _}, _) -> Some p
  | _ -> None

let first_arg (args : (Asttypes.arg_label * Typedtree.expression option) list) =
  match args with (_, Some a) :: _ -> Some a | _ -> None

(* ------------------------------------------------------------------------ *)
(* Canonical exception paths                                                *)
(* ------------------------------------------------------------------------ *)

let rec dot_tail = function
  | Path.Pident _ -> ""
  | Path.Pdot (p, s) -> dot_tail p ^ "." ^ s
  | Path.Papply _ | Path.Pextra_ty _ -> ""

(* The predefined exceptions ([Not_found], [Failure], …) are re-exported by
   [Stdlib], and the initial [open Stdlib] makes a source [Not_found] resolve
   to the path [Stdlib.Not_found]; code compiled with [-nopervasives] (the
   stdlib itself) sees the bare predef ident. Both spell one exception, and
   [failwith] / [assert] / partial matches name it bare, so the bare form is
   canonical. *)
let predef_exn_names =
  List.map Ident.name Predef.all_predef_exns

let strip_stdlib_predef s =
  let prefix = "Stdlib." in
  let lp = String.length prefix in
  if String.length s > lp && String.sub s 0 lp = prefix then
    let rest = String.sub s lp (String.length s - lp) in
    if List.mem rest predef_exn_names then rest else s
  else s

let canonical_path ~unit_declared ~cmt_modname (path : Path.t) =
  match path_root path with
  | None -> "local:" ^ Path.name path
  | Some root ->
      if Ident.is_predef root then Path.name path
      else if Ident.persistent root then strip_stdlib_predef (Path.name path)
      else
        match unit_declared (Ident.unique_name root) with
        | Some qualified -> cmt_modname ^ "." ^ qualified ^ dot_tail path
        | None -> "local:" ^ Ident.unique_name root ^ dot_tail path

let%test "Stdlib.Not_found and the predef ident are one exception" =
  strip_stdlib_predef "Stdlib.Not_found" = "Not_found"
  && strip_stdlib_predef "Stdlib.Exit" = "Stdlib.Exit"
  && strip_stdlib_predef "Not_found" = "Not_found"

let rebind_of (ext : Typedtree.extension_constructor) =
  match ext.ext_kind with Text_rebind (p, _) -> Some p | Text_decl _ -> None

(* ------------------------------------------------------------------------ *)
(* Handler arms                                                             *)
(* ------------------------------------------------------------------------ *)

(** An arm closes iff unguarded and no raise in its RHS applies a raise head
    (or [Printexc.raise_with_backtrace]) to a NON-literal value. A literal
    [raise (E …)] inside the arm is an ordinary origin of the node. *)
let arm_is_closing (a : arm) =
  match a.a_guard with
  | Some _ -> false
  | None ->
      let reraises = ref false in
      let open Tast_iterator in
      let it =
        {
          default_iterator with
          expr =
            (fun self e ->
              (match e.exp_desc with
              | Texp_apply (fn, args)
                when is_raise_head fn || stdlib_head fn = Some Sl_raise_with_backtrace -> (
                  match first_arg args with
                  | Some a when literal_exn a <> None -> ()
                  | _ -> reraises := true)
              | _ -> ()) ;
              default_iterator.expr self e);
        }
      in
      it.expr it a.a_rhs ;
      not !reraises

(* Does this pattern match EVERY value of its type, or only some?

   FIX (review round 2, CRITICAL): [classify_pat] read a constructor pattern's
   identity and discarded its argument patterns, so `try … with Failure "x" ->`
   recorded `Failure` as caught and the solver subtracted every `Failure` the
   body could raise — `Failure "y"` included. A constructor whose arguments
   constrain the value catches a strict SUBSET of that identity, and closing an
   identity we only partly catch deletes a reachable exception from the answer.

   Only irrefutable arguments (wildcards, variables, and tuples/records/lazy
   built from them) leave the identity fully caught. Anything that can fail to
   match — a constant, a nested constructor, an array's length, a polymorphic
   variant — makes the arm close nothing. An or-pattern is irrefutable only if
   both sides are. *)
let rec pat_is_irrefutable (p : Typedtree.value Typedtree.general_pattern) =
  match p.pat_desc with
  | Tpat_any | Tpat_var _ -> true
  | Tpat_alias (inner, _, _, _) -> pat_is_irrefutable inner
  | Tpat_tuple ps -> List.for_all pat_is_irrefutable ps
  | Tpat_record (fields, _) -> List.for_all (fun (_, _, fp) -> pat_is_irrefutable fp) fields
  | Tpat_lazy inner -> pat_is_irrefutable inner
  (* FIX (#60 review): [||], not [&&]. `p1 | p2` accepts a value as soon as
     EITHER alternative does, so one irrefutable side makes the whole pattern
     irrefutable — `Error (A | _)` really does catch every `Error`. Requiring
     both was strictly stronger than irrefutability and made such an arm close
     nothing. Still only a sufficient condition, not a necessary one: `true |
     false` is irrefutable for [bool] while neither side is, and that stays
     conservative on purpose — under-closing loses precision, over-closing
     loses a reachable failure. *)
  | Tpat_or (a, b, _) -> pat_is_irrefutable a || pat_is_irrefutable b
  | _ -> false

type pat_class = {caught : string list; catch_all : bool; bound : string list}

let rec classify_pat ~canon (p : Typedtree.value Typedtree.general_pattern) =
  match p.pat_desc with
  | Tpat_construct (_, {cstr_tag = Cstr_extension (path, _); _}, args, _) ->
      (* Catches this identity only if it accepts every value carrying it —
         see [pat_is_irrefutable]. Otherwise the arm closes nothing: it does
         match some values, but naming the identity here would subtract the
         ones it does not match. *)
      if List.for_all pat_is_irrefutable args then
        {caught = [canon path]; catch_all = false; bound = []}
      else {caught = []; catch_all = false; bound = []}
  | Tpat_or (a, b, _) ->
      let ca = classify_pat ~canon a and cb = classify_pat ~canon b in
      {
        caught = ca.caught @ cb.caught;
        catch_all = ca.catch_all || cb.catch_all;
        bound = ca.bound @ cb.bound;
      }
  | Tpat_alias (inner, id, _, _) ->
      let ci = classify_pat ~canon inner in
      {ci with bound = Ident.unique_name id :: ci.bound}
  | Tpat_var (id, _, _) -> {caught = []; catch_all = true; bound = [Ident.unique_name id]}
  | Tpat_any -> {caught = []; catch_all = true; bound = []}
  | _ -> {caught = []; catch_all = false; bound = []}

let classify_arms ~canon (arms : arm list) =
  List.fold_left
    (fun (catch_all, caught, bound) a ->
      let c = classify_pat ~canon a.a_pat in
      let bound = c.bound @ bound in
      if arm_is_closing a then (catch_all || c.catch_all, c.caught @ caught, bound)
      else (catch_all, caught, bound))
    (false, [], [])
    arms

(* ONE flattener over computation patterns, parameterised by what counts as a
   leaf: two leaf selectors over one traversal, so a change to the recursion
   cannot reach one channel and miss the other. The rule it implements, and the
   pattern shape it exists for, are stated once — on
   {!value_pats_of_computation} in the .mli — and not restated here or at the
   call sites.

   Sound in the closing direction FOR THE ARM IT IS HANDED: OCaml requires every
   alternative of an or-pattern to bind the same variables, and the guard and
   right-hand side are shared, so if that arm closes then each alternative's
   identity really is caught. It says nothing about whether the arm is REACHED —
   arm order is not modelled, and that gap is pinned as a limitation by
   [rr_guarded_passthrough] in tezt/tests/error_channels.ml. *)
let flatten_or :
    type a.
    leaf:(Typedtree.computation Typedtree.general_pattern -> a option) ->
    Typedtree.computation Typedtree.general_pattern ->
    a list =
 fun ~leaf p ->
  let rec go (p : Typedtree.computation Typedtree.general_pattern) =
    match leaf p with
    | Some x -> [x]
    | None -> ( match p.pat_desc with Tpat_or (a, b, _) -> go a @ go b | _ -> [])
  in
  go p

(** The exception arms of a [match]: [Tpat_exception p] cases, flattening a
    computation-level or-pattern. Value arms are not handlers. *)
let exception_arms (cases : Typedtree.computation Typedtree.case list) =
  let leaf (p : Typedtree.computation Typedtree.general_pattern) =
    match p.pat_desc with Tpat_exception v -> Some v | _ -> None
  in
  List.concat_map
    (fun (c : Typedtree.computation Typedtree.case) ->
      List.map
        (fun v -> {a_pat = v; a_guard = c.c_guard; a_rhs = c.c_rhs})
        (flatten_or ~leaf c.c_lhs))
    cases

(* The value-side twin of [exception_arms] — the same rule over the other
   pattern universe, now sharing the traversal rather than restating it. *)
let value_pats_of_computation (cases : Typedtree.computation Typedtree.case list) =
  let leaf (p : Typedtree.computation Typedtree.general_pattern) =
    match p.pat_desc with
    | Tpat_value vp -> Some (vp :> Typedtree.value Typedtree.general_pattern)
    | _ -> None
  in
  List.concat_map
    (fun (c : Typedtree.computation Typedtree.case) ->
      List.map (fun vp -> (vp, c.c_guard, c.c_rhs)) (flatten_or ~leaf c.c_lhs))
    cases

let value_arms (cases : Typedtree.value Typedtree.case list) =
  List.map
    (fun (c : Typedtree.value Typedtree.case) -> {a_pat = c.c_lhs; a_guard = c.c_guard; a_rhs = c.c_rhs})
    cases

(* ------------------------------------------------------------------------ *)
(* Recording                                                                *)
(* ------------------------------------------------------------------------ *)

let pos (loc : Location.t) =
  let p = loc.loc_start in
  (p.pos_lnum, p.pos_cnum - p.pos_bol + 1)

let enter_scope acc ~canon ~form ~(loc : Location.t) ~arms =
  let id = acc.next_id in
  acc.next_id <- id + 1 ;
  let catch_all, caught, bound = classify_arms ~canon arms in
  let line, col = pos loc in
  acc.scopes <-
    {
      s_id = id;
      s_parent = current_scope acc;
      s_form = form;
      s_line = line;
      s_col = col;
      s_catch_all = catch_all;
      s_caught = List.sort_uniq compare caught;
      s_bound = bound;
    }
    :: acc.scopes ;
  acc.stack <- id :: acc.stack ;
  id

let leave_scope acc = match acc.stack with _ :: tl -> acc.stack <- tl | [] -> ()

(** A DEFERRED body — a [lazy] thunk, an object's methods, a functor body —
    runs at force / dispatch / application time, outside any handler that
    lexically encloses its definition. Its origins and calls must therefore
    see NO enclosing scope (review finding, 2026-09-03: [try lazy (raise A)
    with A -> …] had stored the origin as closed). Restored on every exit. *)
let with_cleared_scopes acc f =
  let saved = acc.stack in
  acc.stack <- [] ;
  Fun.protect ~finally:(fun () -> acc.stack <- saved) f

let add acc form path scope (loc : Location.t) =
  let line, col = pos loc in
  acc.raw_origins <- (form, path, scope, line, col) :: acc.raw_origins

(** [raise e] where [e] was bound by a handler arm of THIS node: informational
    re-raise. The non-closing rule already keeps what such an arm forwards. *)
let bound_scope acc (id : Ident.t) =
  let u = Ident.unique_name id in
  List.find_map (fun s -> if List.mem u s.s_bound then Some s.s_id else None) acc.scopes

let record_raise_head acc ~canon ~args ~(loc : Location.t) =
  match first_arg args with
  | None -> ()
  | Some a -> (
      match literal_exn a with
      | Some p -> add acc Raise (Some (canon p)) (current_scope acc) loc
      | None -> (
          match a.exp_desc with
          | Texp_ident (Path.Pident id, _, _) -> (
              match bound_scope acc id with
              | Some s -> add acc Reraise None (Some s) loc
              | None -> add acc Unknown None (current_scope acc) loc)
          | _ -> add acc Unknown None (current_scope acc) loc))

let record_stdlib_head acc ~canon ~head ~args ~loc =
  match head with
  | Sl_failwith -> add acc Failwith (Some "Failure") (current_scope acc) loc
  | Sl_invalid_arg -> add acc Invalid_arg (Some "Invalid_argument") (current_scope acc) loc
  | Sl_raise_with_backtrace -> record_raise_head acc ~canon ~args ~loc

(* Raising PRIMITIVES other than raise itself. Recognised by primitive name,
   like raise heads, so the protocol environment's re-exports count too.
   Polymorphic comparison raises [Invalid_argument] only on functional
   values: at a ground, closure-free argument type it cannot, so no origin is
   recorded there — the typed tree is what makes that precise. *)
type prim_class = P_compare | P_division | P_index

let prim_class = function
  | "%equal" | "%notequal" | "%lessthan" | "%lessequal" | "%greaterthan" | "%greaterequal"
  | "%compare" ->
      Some P_compare
  | "%divint" | "%modint" | "%int32_div" | "%int32_mod" | "%int64_div" | "%int64_mod"
  | "%nativeint_div" | "%nativeint_mod" ->
      Some P_division
  | "%array_safe_get" | "%array_safe_set" | "%string_safe_get" | "%bytes_safe_get"
  | "%bytes_safe_set" ->
      Some P_index
  | _ -> None

(* A type that cannot hold a closure: comparison on it cannot raise. Predef
   ground types, and lists / options / arrays / tuples of such. Anything else
   (type variables, abstract types, records, arrows) is conservatively unsafe. *)
let rec closure_free (ty : Types.type_expr) =
  match Types.get_desc ty with
  | Tconstr (p, args, _) -> (
      match Path.name p with
      | "int" | "char" | "string" | "bytes" | "float" | "bool" | "unit" | "nativeint" | "int32"
      | "int64" ->
          true
      | "list" | "option" | "array" -> List.for_all closure_free args
      | _ -> false)
  | Ttuple tys -> List.for_all closure_free tys
  | _ -> false

let record_prim_head acc ~(fn : Typedtree.expression) ~args ~(loc : Location.t) =
  match fn.exp_desc with
  | Texp_ident (_, _, {val_kind = Val_prim {prim_name; _}; _}) -> (
      match prim_class prim_name with
      | Some P_compare ->
          let unsafe =
            List.exists
              (fun (_, a) ->
                match a with
                | Some (a : Typedtree.expression) -> not (closure_free a.exp_type)
                | None -> true)
              args
          in
          if unsafe then add acc Compare (Some "Invalid_argument") (current_scope acc) loc
      | Some P_division -> add acc Division (Some "Division_by_zero") (current_scope acc) loc
      | Some P_index -> add acc Index (Some "Invalid_argument") (current_scope acc) loc
      | None -> ())
  | _ -> ()

let record_assert acc ~loc = add acc Assert (Some "Assert_failure") (current_scope acc) loc

let record_partial acc ~loc =
  add acc Partial_match (Some "Match_failure") (current_scope acc) loc

(* ------------------------------------------------------------------------ *)
(* Finalize                                                                 *)
(* ------------------------------------------------------------------------ *)

let finalize acc =
  let scopes = List.rev acc.scopes in
  let find id = List.find_opt (fun s -> s.s_id = id) scopes in
  let rec closed_by chain path =
    match chain with
    | None -> false
    | Some id -> (
        match find id with
        | None -> false
        | Some s ->
            s.s_catch_all
            || (match path with Some p -> List.mem p s.s_caught | None -> false)
            || closed_by s.s_parent path)
  in
  let origins =
    List.rev_map
      (fun (form, path, scope, line, col) ->
        let escapes =
          match form with
          | Reraise -> true
          | _ -> not (closed_by scope path)
        in
        {o_form = form; o_path = path; o_scope = scope; o_escapes = escapes; o_line = line; o_col = col})
      acc.raw_origins
  in
  (scopes, origins)

(* ------------------------------------------------------------------------ *)
(* Inline tests                                                             *)
(* ------------------------------------------------------------------------ *)

let%test "enter/leave keep the stack balanced" =
  let acc = create () in
  let loc = Location.none in
  let id = enter_scope acc ~canon:(fun p -> Path.name p) ~form:Try ~loc ~arms:[] in
  let inner = enter_scope acc ~canon:(fun p -> Path.name p) ~form:Try ~loc ~arms:[] in
  let ok1 = current_scope acc = Some inner in
  leave_scope acc ;
  let ok2 = current_scope acc = Some id in
  leave_scope acc ;
  ok1 && ok2 && current_scope acc = None

let%test "an unknown origin escapes unless a catch-all encloses it" =
  let acc = create () in
  let loc = Location.none in
  ignore (enter_scope acc ~canon:(fun p -> Path.name p) ~form:Try ~loc ~arms:[]) ;
  add acc Unknown None (current_scope acc) loc ;
  leave_scope acc ;
  let _, origins = finalize acc in
  match origins with [o] -> o.o_escapes | _ -> false

let%test "a literal origin is closed by an enclosing scope that catches it" =
  let acc = create () in
  let loc = Location.none in
  let id = enter_scope acc ~canon:(fun p -> Path.name p) ~form:Try ~loc ~arms:[] in
  (* simulate a caught path by patching the scope *)
  acc.scopes <-
    List.map (fun s -> if s.s_id = id then {s with s_caught = ["Not_found"]} else s) acc.scopes ;
  add acc Raise (Some "Not_found") (Some id) loc ;
  add acc Raise (Some "Failure") (Some id) loc ;
  leave_scope acc ;
  let _, origins = finalize acc in
  match origins with
  | [a; b] -> (not a.o_escapes) && b.o_escapes
  | _ -> false
