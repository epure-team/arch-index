(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** See arch_index_errch.mli. *)

let rec strip_arrows ty =
  match Types.get_desc ty with Tarrow (_, _, res, _) -> strip_arrows res | _ -> ty

let is_type_var ty = match Types.get_desc ty with Tvar _ | Tunivar _ -> true | _ -> false

let matches_any (patterns : string list) (actual : string) =
  List.exists (fun pat -> Arch_errors_config.path_matches pat actual) patterns

(** Strip zero or more single-argument [Tconstr] wrappers whose path matches
    one of [paths] (e.g. [Lwt.t] for [lift], [...Error_monad.trace] for
    [unwrap]) — slice 4 "Carrier check" / "unwrap". *)
let rec strip_wrapper (paths : string list) ty =
  if paths = [] then ty
  else
    match Types.get_desc ty with
    | Tconstr (p, [arg], _) when matches_any paths (Path.name p) -> strip_wrapper paths arg
    | _ -> ty

(** [error_arg_ok c args]: [args] is the (already lift-stripped) carrier
    type's argument list. When [args] is too short for [c.error_arg] (e.g.
    the alias [...Error_monad.tzresult] takes ONE type argument while its
    [underlying] spelling [...Pervasives.result] takes TWO), the error type
    is implied by the declaration itself and the check does not apply — see
    specs/error-channels.md slice 4, "underlying"/"aliases" arity note. When
    the argument IS present, its head is compared to [c.error_type] after
    stripping any [c.unwrap] container (e.g. [...Error_monad.trace<error>]). *)
let error_arg_ok (c : Arch_errors_config.channel) args =
  match c.error_arg with
  | None -> true (* alias carrier / identity channel: not applicable *)
  | Some pos -> (
      match List.nth_opt args (pos - 1) with
      | None -> true (* shorter-arity alias: error type implied by the declaration *)
      | Some argty ->
          if is_type_var argty then true
          else (
            match c.error_type with
            | None | Some "" -> true (* unset/identity: any argument matches *)
            | Some et -> (
                match Types.get_desc (strip_wrapper c.unwrap argty) with
                | Tconstr (ep, _, _) -> matches_any [et] (Path.name ep)
                | _ -> false)))

let carrier_channel_of_type ~channels ty =
  let base = strip_arrows ty in
  List.find_opt
    (fun (c : Arch_errors_config.channel) ->
      match Types.get_desc (strip_wrapper c.Arch_errors_config.lift base) with
      | Tconstr (p, args, _) ->
          matches_any c.Arch_errors_config.type_paths (Path.name p) && error_arg_ok c args
      | _ -> false)
    channels

(** [bind_shape_channel ~channels ty]: [ty] has "bind shape" over some
    declared channel [c] — [c -> ('a -> c) -> c] — iff, without stripping any
    arrows first (unlike {!carrier_channel_of_type}), [ty] is
    [Tarrow(_, c1, Tarrow(_, arg2, _, _), _)] where [c1] and [arg2]'s own
    result (after stripping ITS arrows) and [ty]'s final result all name the
    SAME channel [c] (specs/error-channels.md "Binds": ["inferred_bind"]).
    Used to flag an UNDECLARED bind-shaped operator, never to silently treat
    it as a bind. *)
let bind_shape_channel ~channels ty =
  match Types.get_desc ty with
  | Tarrow (_, arg1, rest, _) -> (
      match Types.get_desc rest with
      | Tarrow (_, arg2, res, _) -> (
          match Types.get_desc arg2 with
          | Tarrow _ -> (
              match
                ( carrier_channel_of_type ~channels arg1,
                  carrier_channel_of_type ~channels arg2,
                  carrier_channel_of_type ~channels res )
              with
              | Some a, Some b, Some c
                when a.Arch_errors_config.name = b.Arch_errors_config.name
                     && b.Arch_errors_config.name = c.Arch_errors_config.name ->
                  Some a
              | _ -> None)
          | _ -> None)
      | _ -> None)
  | _ -> None

let constructor_canonical_path ~canon_type (ty : Types.type_expr) cstr_name =
  match Types.get_desc ty with
  | Tconstr (p, _, _) -> (
      let full = canon_type p in
      match String.rindex_opt full '.' with
      | Some i -> String.sub full 0 i ^ "." ^ cstr_name
      | None -> cstr_name)
  | _ -> cstr_name

let literal_ctor_path_of_expr ~canon_type ~canon_exn (e : Typedtree.expression) =
  match e.exp_desc with
  | Texp_construct (_, {cstr_tag = Cstr_extension (p, _); _}, _) -> Some (canon_exn p)
  | Texp_construct (_, cstr_desc, _) ->
      Some (constructor_canonical_path ~canon_type cstr_desc.cstr_res cstr_desc.cstr_name)
  | (* Polymorphic-variant errors (specs/error-channels.md Clarifications,
       "Polymorphic-variant errors" — 2b, REQUIRED not optional): identity is
       the bare label with a leading backtick, e.g. [`Msg] -> ["`Msg"].
       OCaml's polymorphic variants are structural, so no unit qualification
       and no canonicalisation table — the bare label IS the global
       identity. *)
    Texp_variant (label, _) ->
      Some ("`" ^ label)
  | _ -> None

let literal_ctor_path_of_pat ~canon_type ~canon_exn (p : Typedtree.value Typedtree.general_pattern) =
  match p.pat_desc with
  | Tpat_construct (_, {cstr_tag = Cstr_extension (path, _); _}, _, _) -> Some (canon_exn path)
  | Tpat_construct (_, cstr_desc, _, _) ->
      Some (constructor_canonical_path ~canon_type cstr_desc.cstr_res cstr_desc.cstr_name)
  | Tpat_variant (label, _, _) -> Some ("`" ^ label)
  | _ -> None

let rec pat_bound_idents (p : Typedtree.value Typedtree.general_pattern) =
  match p.pat_desc with
  | Tpat_var (id, _, _) -> [Ident.unique_name id]
  | Tpat_alias (inner, id, _, _) -> Ident.unique_name id :: pat_bound_idents inner
  | Tpat_or (a, b, _) -> pat_bound_idents a @ pat_bound_idents b
  | Tpat_tuple ps -> List.concat_map pat_bound_idents ps
  | Tpat_construct (_, _, ps, _) -> List.concat_map pat_bound_idents ps
  | _ -> []

(** Classify one value-case pattern against a channel's origin constructor
    ([bare_ctor], [arg_pos]). [arg_pos = 0] (identity, e.g. [option]'s
    [None]): matches iff the pattern is exactly that 0-ary constructor —
    catch-all in the sense that there is nothing further to bind, so
    [caught = Some bare_ctor] whenever matched, never a catch-all "any". A
    bare variable / wildcard is a catch-all for the WHOLE channel (any
    error), independent of [bare_ctor]. *)
(* What one match arm demonstrably catches on a value channel.

   SET-valued, and deliberately the same shape the exception channel already
   uses ([Arch_index_exn.pat_class], minus its [bound] field, which this
   function returns alongside). An earlier [string option] had two cases and
   read [None] as "catch-all", so any argument pattern that was not a single
   literal constructor closed the ENTIRE channel; the three-case
   [Catch_all | Caught of string | Unrecognised] that replaced it fixed the
   unsoundness but could still name only ONE identity, so `Error (A | B)`
   closed NEITHER. Everything downstream is already set-valued
   ([add_scope ~caught:(string list)], one [exn_scope_catches] row per path),
   so a set costs nothing and closes both. *)
type pat_class = {caught : string list; catch_all : bool}

let closes_nothing = {caught = []; catch_all = false}

let union a b = {caught = a.caught @ b.caught; catch_all = a.catch_all || b.catch_all}

(* Does a pattern that NAMES an identity also accept every value carrying it?
   `Error (B 0)` names [B] but matches only when the argument is 0, so closing
   [B] would drop `Error (B 1)`. [Arch_index_exn.pat_is_irrefutable] is the
   single definition of "accepts every value of this shape" — both channels
   must agree on it or they will drift apart. The polymorphic-variant case is
   the same rule: `` `Msg "boom" `` catches a strict subset of `` `Msg ``. *)
let names_whole_identity (p : Typedtree.value Typedtree.general_pattern) =
  match p.pat_desc with
  | Tpat_construct (_, _, args, _) -> List.for_all Arch_index_exn.pat_is_irrefutable args
  | Tpat_variant (_, Some arg, _) -> Arch_index_exn.pat_is_irrefutable arg
  | _ -> true

(** Classify the sub-pattern sitting at the channel's error position (the
    [arg_pos]th argument of its origin constructor). A wildcard or variable
    there closes the whole channel; a literal constructor closes exactly its
    own identity, and an or-pattern of literals closes ALL of them; anything
    else — a constant, a record, a constrained constructor — matches a subset
    we cannot name, so it closes nothing. *)
let rec classify_error_arg ~canon_type ~canon_exn
    (p : Typedtree.value Typedtree.general_pattern) =
  match p.pat_desc with
  | Tpat_any | Tpat_var _ -> {caught = []; catch_all = true}
  | Tpat_alias (inner, _, _, _) -> classify_error_arg ~canon_type ~canon_exn inner
  | Tpat_or (a, b, _) ->
      union
        (classify_error_arg ~canon_type ~canon_exn a)
        (classify_error_arg ~canon_type ~canon_exn b)
  | _ -> (
      match literal_ctor_path_of_pat ~canon_type ~canon_exn p with
      | Some pth when names_whole_identity p -> {caught = [pth]; catch_all = false}
      | _ -> closes_nothing)

let rec classify_value_pat ~canon_type ~canon_exn ~bare_ctor ~arg_pos
    (p : Typedtree.value Typedtree.general_pattern) =
  match p.pat_desc with
  | Tpat_any -> Some ({caught = []; catch_all = true}, [])
  | Tpat_var (id, _, _) -> Some ({caught = []; catch_all = true}, [Ident.unique_name id])
  | Tpat_alias (inner, id, _, _) -> (
      match classify_value_pat ~canon_type ~canon_exn ~bare_ctor ~arg_pos inner with
      | Some (c, bound) -> Some (c, Ident.unique_name id :: bound)
      | None -> None)
  | Tpat_or (a, b, _) -> (
      match
        ( classify_value_pat ~canon_type ~canon_exn ~bare_ctor ~arg_pos a,
          classify_value_pat ~canon_type ~canon_exn ~bare_ctor ~arg_pos b )
      with
      | Some (ca, ba), Some (cb, bb) -> Some (union ca cb, ba @ bb)
      | (Some _ as r), None | None, (Some _ as r) -> r
      | None, None -> None)
  | Tpat_construct (lid, cstr_desc, sub, _) when cstr_desc.cstr_name = bare_ctor -> (
      match (arg_pos, sub) with
      | 0, [] ->
          let path =
            match literal_ctor_path_of_pat ~canon_type ~canon_exn p with
            | Some pth -> pth
            | None -> Longident.last lid.Asttypes.txt
          in
          Some ({caught = [path]; catch_all = false}, [])
      | n, _ when n > 0 -> (
          match List.nth_opt sub (n - 1) with
          | Some subpat ->
              Some
                (classify_error_arg ~canon_type ~canon_exn subpat, pat_bound_idents subpat)
          (* Constructor applied with fewer arguments than [arg_pos] names:
             we cannot see the error position at all, so nothing is closed. *)
          | None -> Some (closes_nothing, []))
      | _ -> None)
  | _ -> None

let idents_occur ~idents (e : Typedtree.expression) =
  if idents = [] then false
  else
    let found = ref false in
    let open Tast_iterator in
    let it =
      {
        default_iterator with
        expr =
          (fun self ex ->
            (match ex.exp_desc with
            | Texp_ident (Path.Pident id, _, _) when List.mem (Ident.unique_name id) idents ->
                found := true
            | _ -> ()) ;
            default_iterator.expr self ex);
      }
    in
    it.expr it e ; !found

(* ------------------------------------------------------------------------ *)
(* Recording                                                                 *)
(* ------------------------------------------------------------------------ *)

type origin = {
  o_channel : string;
  o_path : string option;
  o_form : string;
      (* "raise" (a literal path), "unknown" (non-literal argument — ⊤
         [unknown_exn_value]), or "inferred_bind" ([o_path] then carries
         the call-site witness "file:line", not a canonical error path —
         specs/error-channels.md "Binds": an undeclared bind-shaped operator
         over a declared carrier). *)
  o_line : int;
  o_col : int;
}

type scope = {
  s_id : int;
  s_channel : string;
  s_catch_all : bool;
  s_caught : string list;
  s_line : int;
  s_col : int;
}

type acc = {mutable scopes : scope list; mutable origins : origin list; mutable next_id : int}

let create () = {scopes = []; origins = []; next_id = 0}

let pos (loc : Location.t) =
  let p = loc.loc_start in
  (p.pos_lnum, p.pos_cnum - p.pos_bol + 1)

let add_scope acc ~channel ~catch_all ~caught ~loc =
  let id = acc.next_id in
  acc.next_id <- id + 1 ;
  let line, col = pos loc in
  acc.scopes <-
    {
      s_id = id;
      s_channel = channel;
      s_catch_all = catch_all;
      s_caught = List.sort_uniq compare caught;
      s_line = line;
      s_col = col;
    }
    :: acc.scopes ;
  id

let add_origin acc ~channel ~path ?(form = "") ~loc () =
  let line, col = pos loc in
  let form = if form <> "" then form else if path = None then "unknown" else "raise" in
  acc.origins <-
    {o_channel = channel; o_path = path; o_form = form; o_line = line; o_col = col} :: acc.origins

let finalize acc = (List.rev acc.scopes, List.rev acc.origins)
