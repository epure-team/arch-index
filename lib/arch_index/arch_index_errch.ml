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

let error_arg_ok (c : Arch_errors_config.channel) args =
  match c.error_arg with
  | None -> true (* alias carrier / identity channel: not applicable *)
  | Some pos -> (
      match List.nth_opt args (pos - 1) with
      | None -> false
      | Some argty ->
          if is_type_var argty then true
          else (
            match c.error_type with
            | None | Some "" -> true (* unset/identity: any argument matches *)
            | Some et -> (
                match Types.get_desc argty with
                | Tconstr (ep, _, _) -> Path.name ep = et
                | _ -> false)))

let carrier_channel_of_type ~channels ty =
  match Types.get_desc (strip_arrows ty) with
  | Tconstr (p, args, _) ->
      let pname = Path.name p in
      List.find_opt
        (fun (c : Arch_errors_config.channel) -> List.mem pname c.type_paths && error_arg_ok c args)
        channels
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
let rec classify_value_pat ~canon_type ~canon_exn ~bare_ctor ~arg_pos
    (p : Typedtree.value Typedtree.general_pattern) =
  match p.pat_desc with
  | Tpat_any -> Some (None, [])
  | Tpat_var (id, _, _) -> Some (None, [Ident.unique_name id])
  | Tpat_alias (inner, id, _, _) -> (
      match classify_value_pat ~canon_type ~canon_exn ~bare_ctor ~arg_pos inner with
      | Some (caught, bound) -> Some (caught, Ident.unique_name id :: bound)
      | None -> None)
  | Tpat_or (a, b, _) -> (
      match
        ( classify_value_pat ~canon_type ~canon_exn ~bare_ctor ~arg_pos a,
          classify_value_pat ~canon_type ~canon_exn ~bare_ctor ~arg_pos b )
      with
      | Some (ca, ba), Some (cb, bb) ->
          let caught =
            match (ca, cb) with
            | None, _ | _, None -> None
            | Some x, Some y -> if x = y then Some x else None
          in
          Some (caught, ba @ bb)
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
          Some (Some path, [])
      | n, _ when n > 0 -> (
          match List.nth_opt sub (n - 1) with
          | Some subpat ->
              let path =
                match literal_ctor_path_of_pat ~canon_type ~canon_exn subpat with
                | Some pth -> Some pth
                | None -> None (* non-literal argument pattern: catch-all for this ctor *)
              in
              Some (path, pat_bound_idents subpat)
          | None -> Some (None, []))
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

type origin = {o_channel : string; o_path : string option; o_line : int; o_col : int}

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

let add_origin acc ~channel ~path ~loc =
  let line, col = pos loc in
  acc.origins <- {o_channel = channel; o_path = path; o_line = line; o_col = col} :: acc.origins

let finalize acc = (List.rev acc.scopes, List.rev acc.origins)
