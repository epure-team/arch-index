(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** decision-lint — PoC for the static MC/DC dual described in
    [docs/research/mcdc-coverage-feasibility.md].

    Extracts every boolean DECISION from an OCaml source tree, canonicalises its
    atomic CONDITIONS (§3.2 rungs 0/2/3), and reports conditions and subterms
    that provably cannot influence the outcome — either on their own (§3.3) or
    given the guards holding on every path to them (§6.2, syntactic form).

    Frontend is the PARSETREE, not the Typedtree: the tool parses sources
    directly, so it needs no build of the analysed project and no dependency
    beyond [compiler-libs]. The cost is rung 1 (alias/copy propagation), which
    needs [Ident] stamps — see [armed_rungs] and the capability line in the
    report: a degraded run must never look like a clean one (§8.4).

    Output is NDJSON on stdout, one record per finding plus one census record. *)

let cap_vars = 6 (* §3.1 CAP: decisions above this arity report UNKNOWN *)
let cap_combos = 4096 (* §6.5 budget: enumeration combinations per decision *)

(* -------------------------------------------------------------------------- *)
(* Boolean terms over condition OCCURRENCES                                    *)
(* -------------------------------------------------------------------------- *)

open Parsetree

(* Occurrences, not variables: two occurrences of the same canonical atom share
   a variable but keep distinct occurrence ids, so substituting "this one leaf"
   is exact and can never accidentally rewrite its twin. *)
type bexp =
  | BTrue
  | BFalse
  | BOcc of int
  | BNot of bexp
  | BAnd of bexp * bexp
  | BOr of bexp * bexp

(* A relational atom [subject OP constant] over integers, when we can see one.
   This is what lets §3.2 rung 3 replace free-boolean semantics with interval
   semantics for same-subject comparisons. *)
type rel = {r_subject : string; r_op : string; r_const : int}

(* Frontend-neutral term IR (§8.3: "don't invent an IR — SMT-LIB already is
   one"). A frontend lowers its own AST into this; the enumeration engine and
   the SMT encoder consume it and never learn which language, or which tree,
   produced it. This is what lets a Parsetree frontend and a Typedtree frontend
   share every downstream tier. *)
type sterm =
  | TConst of int  (** integer or char literal, by value *)
  | TLit of string  (** closed literal: a constant, distinct from other literals *)
  | TVar of string  (** stable subexpression, keyed canonically — merges *)
  | TFresh of string  (** unstable: a fresh constant per occurrence, never merges *)
  | TAdd of sterm * sterm
  | TSub of sterm * sterm
  | TMul of sterm * sterm
  | TLen of string  (** a length: keyed canonically, and asserted non-negative *)

type satom =
  | ARel of string * sterm * sterm  (** OCaml comparison operator, lhs, rhs *)
  | AOpaque  (** no relational content; a boolean keyed by [a_key] *)

type atom = {
  a_key : string; (* canonical form; unique string when unstable *)
  a_stable : bool; (* §3.2: provably same value at two evaluation points *)
  a_rel : rel option;
  a_line : int;
  a_col : int;
  a_src : string;
  a_term : satom;  (* frontend-neutral payload for the SMT tier *)
}

(* -------------------------------------------------------------------------- *)
(* Canonicalisation — §3.2 rungs 0 and 2                                       *)
(* -------------------------------------------------------------------------- *)

let long_ident_string (l : Longident.t) =
  String.concat "." (Longident.flatten l)

let ident_of (e : expression) =
  match e.pexp_desc with Pexp_ident {txt; _} -> Some (long_ident_string txt) | _ -> None

(* Qualified-only allowlist. An unqualified name (`length`, `abs`) can be
   shadowed by an ordinary `let`, which the Parsetree cannot see through; a
   qualified one could only be shadowed by a local module alias of the same
   name, which is vanishingly rare. Conservative by construction: anything not
   listed makes its atom UNSTABLE, and unstable atoms are never merged. *)
(* FIRST-ORDER only. [List.exists]/[List.for_all] were here and should not have
   been: they take a function argument whose purity we cannot check, so
   `List.exists f l` is stable only if `f` is. Keeping them was a latent
   false-positive source — removing them costs recall and buys soundness. *)
let pure_allowlist =
  [
    (* structure/size *)
    "List.length"; "List.mem"; "List.assoc_opt"; "List.assoc"; "List.hd";
    "List.tl"; "List.nth_opt"; "List.rev"; "List.compare_lengths";
    "Array.length"; "Array.to_list"; "Bytes.length";
    (* strings — pure and first-order under -safe-string *)
    "String.length"; "String.equal"; "String.get"; "String.sub";
    "String.starts_with"; "String.ends_with"; "String.contains";
    "String.trim"; "String.lowercase_ascii"; "String.uppercase_ascii";
    "String.concat"; "String.split_on_char"; "String.index_opt";
    "String.rindex_opt"; "String.escaped"; "String.make"; "String.compare";
    (* scalars *)
    "Int.equal"; "Int.compare"; "Int.abs"; "Int.to_string"; "Char.code";
    "Char.chr"; "Char.lowercase_ascii"; "Char.uppercase_ascii";
    "Float.equal"; "Float.abs"; "Bool.to_string";
    (* option / result *)
    "Option.is_some"; "Option.is_none"; "Option.value";
    "Result.is_ok"; "Result.is_error";
    (* paths — pure string manipulation, no filesystem access *)
    "Filename.check_suffix"; "Filename.basename"; "Filename.extension";
    "Filename.dirname"; "Filename.concat"; "Filename.is_relative";
    "Filename.remove_extension";
  ]

(* --- purity, from the index rather than from a list ------------------------

   The allowlist can only ever cover stdlib names, and the census says the
   dominant reason an atom is refused a merge is a call to a PROJECT function —
   48.5% on octez-manager, 41.3% on arch-index. Those are exactly what the
   index's own effects analysis can certify.

   Fail closed: an empty set means "purity unavailable", which reproduces the
   allowlist-only behaviour. [purity_available] exists so the run can SAY which
   of the two it was — a clean result from a run that could not consult purity
   is much weaker evidence than one that could. *)
(* Certified-pure functions under two keys: the bare name, and "Module.name" where Module is the
   basename of the defining file. Each key carries how many functions it covers and how many of
   those are pure — because the only sound answer for a key that covers several functions is
   "pure iff they ALL are". *)
let pure_total : (string, int) Hashtbl.t = Hashtbl.create 512
let pure_yes : (string, int) Hashtbl.t = Hashtbl.create 512
let n_pure = ref 0
let purity_available = ref false

let bump_key tbl k = Hashtbl.replace tbl k (1 + Option.value ~default:0 (Hashtbl.find_opt tbl k))

(* `Foo.bar` was once certified pure whenever ANY function called `bar` was pure anywhere in the
   index — the qualifier was simply dropped, so `Hashtbl.replace` matched a project function
   named `replace`. A pure head is what allows two atoms to merge, so a false positive here
   manufactures a "removable subterm" and tells someone to delete live code.

   The module key is a file BASENAME, so `lib/a/utils.ml` and `lib/b/utils.ml` both key as
   `Utils` and one pure `Utils.f` could still vouch for an effectful one. Rather than resolve the
   ambiguity — which needs the access path, not the defining file — a key answers "pure" only
   when every function it covers is pure. Ambiguity then costs recall instead of soundness. *)
let all_pure_under key =
  match (Hashtbl.find_opt pure_total key, Hashtbl.find_opt pure_yes key) with
  | Some t, Some y -> t > 0 && t = y
  | _ -> false

let is_pure_fn name =
  match String.rindex_opt name '.' with
  | None -> all_pure_under name
  | Some i ->
      let base = String.sub name (i + 1) (String.length name - i - 1) in
      let prefix = String.sub name 0 i in
      (* The last module component is the one v_pure_functions can name: `A.B.f` is keyed as
         `B.f`, since module_path gives the defining file, not the full access path. *)
      let last_mod =
        match String.rindex_opt prefix '.' with
        | Some j -> String.sub prefix (j + 1) (String.length prefix - j - 1)
        | None -> prefix
      in
      all_pure_under (last_mod ^ "." ^ base)

let comparison_ops = ["="; "<>"; "<"; "<="; ">"; ">="; "=="; "!="]
let arith_ops = ["+"; "-"; "*"; "/"; "mod"; "land"; "lor"; "lxor"; "lsl"; "lsr"; "asr"]

(* An expression is STABLE when its value provably cannot change between two
   evaluation points in the same decision: built only from identifiers,
   literals, constructors, tuples, field projections, string indexing (strings
   are immutable under -safe-string), comparison/arithmetic operators, and
   allowlisted pure calls. Any other application, any deref (`!`), assignment,
   array access, or mutation makes it unstable. *)
let rec is_stable (e : expression) =
  match e.pexp_desc with
  | Pexp_ident _ | Pexp_constant _ -> true
  | Pexp_construct (_, None) -> true
  | Pexp_construct (_, Some a) -> is_stable a
  | Pexp_tuple l -> List.for_all is_stable l
  | Pexp_field (a, _) -> is_stable a
  | Pexp_constraint (a, _) -> is_stable a
  | Pexp_variant (_, None) -> true
  | Pexp_variant (_, Some a) -> is_stable a
  | Pexp_apply (f, args) -> (
      let stable_args () =
        List.for_all (fun (_, a) -> is_stable a) args
      in
      match ident_of f with
      | Some name ->
          if List.mem name comparison_ops || List.mem name arith_ops then
            stable_args ()
          else if List.mem name pure_allowlist then stable_args ()
          else if name = "not" then stable_args ()
          else false
      | None -> false)
  | _ -> false

(* --- §3.2 rung 1: alias / copy propagation ---------------------------------

   The design doc computes this over the Typedtree, where [Ident] stamps make
   shadowing safe for free. On the Parsetree we only have names, so we maintain
   an explicit lexical environment and, whenever ANY binder rebinds a name, we
   DROP it from the environment rather than risk merging across a shadow. That
   is the conservative direction: we lose aliases we could have kept, we never
   invent one. Anything the walker forgets to unbind would be a false positive,
   so every binding construct must unbind -- see the walker. *)

let alias_env : (string, expression) Hashtbl.t = Hashtbl.create 64

let rec pattern_names (p : pattern) acc =
  match p.ppat_desc with
  | Ppat_var {txt; _} -> txt :: acc
  | Ppat_alias (q, {txt; _}) -> pattern_names q (txt :: acc)
  | Ppat_tuple l -> List.fold_left (fun a q -> pattern_names q a) acc l
  | Ppat_construct (_, Some (_, q)) -> pattern_names q acc
  | Ppat_variant (_, Some q) -> pattern_names q acc
  | Ppat_record (l, _) -> List.fold_left (fun a (_, q) -> pattern_names q a) acc l
  | Ppat_array l -> List.fold_left (fun a q -> pattern_names q a) acc l
  | Ppat_or (a, b) -> pattern_names a (pattern_names b acc)
  | Ppat_constraint (q, _) | Ppat_lazy q | Ppat_open (_, q) | Ppat_exception q ->
      pattern_names q acc
  | _ -> acc

(* Replace an aliased identifier by the expression it was bound to, so
   `let a = x in a && x` canonicalises both atoms to `x`. Depth-capped: a
   pathological binding cannot loop. *)
let rec resolve_aliases ?(depth = 0) (e : expression) =
  if depth > 4 then e
  else
    match e.pexp_desc with
    | Pexp_ident {txt = Longident.Lident n; _} -> (
        match Hashtbl.find_opt alias_env n with
        | Some rhs -> resolve_aliases ~depth:(depth + 1) rhs
        | None -> e)
    | Pexp_apply (f, args) ->
        {
          e with
          pexp_desc =
            Pexp_apply
              ( resolve_aliases ~depth f,
                List.map (fun (l, a) -> (l, resolve_aliases ~depth a)) args );
        }
    | Pexp_field (a, l) -> {e with pexp_desc = Pexp_field (resolve_aliases ~depth a, l)}
    | Pexp_constraint (a, t) ->
        {e with pexp_desc = Pexp_constraint (resolve_aliases ~depth a, t)}
    | Pexp_tuple l ->
        {e with pexp_desc = Pexp_tuple (List.map (resolve_aliases ~depth) l)}
    | _ -> e

let print_expr (e : expression) =
  let b = Buffer.create 64 in
  let fmt = Format.formatter_of_buffer b in
  Pprintast.expression fmt e ;
  Format.pp_print_flush fmt () ;
  (* squash whitespace so canonical keys are layout-insensitive *)
  let s = Buffer.contents b in
  let out = Buffer.create (String.length s) in
  let prev_sp = ref false in
  String.iter
    (fun c ->
      let c = if c = '\n' || c = '\t' then ' ' else c in
      if c = ' ' then begin
        if not !prev_sp then Buffer.add_char out c ;
        prev_sp := true
      end
      else begin
        Buffer.add_char out c ;
        prev_sp := false
      end)
    s ;
  String.trim (Buffer.contents out)

(* Rung 3 needs an integer-valued constant. A char literal IS one — its code
   point — and comparisons like `c >= 'a' && c <= 'z'` are exactly the shape
   interval semantics decides. Handling only [Pconst_integer] is why an
   identifier-character predicate reported HIGH_ARITY instead of a verdict. *)
let int_literal (e : expression) =
  match e.pexp_desc with
  | Pexp_constant {pconst_desc = Pconst_integer (s, None); _} -> int_of_string_opt s
  | Pexp_constant {pconst_desc = Pconst_char c; _} -> Some (Char.code c)
  | _ -> None

let flip_op = function
  | "<" -> ">"
  | ">" -> "<"
  | "<=" -> ">="
  | ">=" -> "<="
  | op -> op

(* §3.2 rung 2, relational half: orient `k < x` to `x > k` so the two spellings
   share a canonical key, and expose (subject, op, constant) for rung 3. *)
let as_relational (e : expression) =
  match e.pexp_desc with
  | Pexp_apply (f, [(Nolabel, l); (Nolabel, r)]) -> (
      match ident_of f with
      | Some op when List.mem op ["="; "<>"; "<"; "<="; ">"; ">="] -> (
          match (int_literal l, int_literal r) with
          | None, Some k when is_stable l ->
              Some {r_subject = print_expr l; r_op = op; r_const = k}
          | Some k, None when is_stable r ->
              Some {r_subject = print_expr r; r_op = flip_op op; r_const = k}
          | _ -> None)
      | _ -> None)
  | _ -> None

let rel_key r = Printf.sprintf "%s %s %d" r.r_subject r.r_op r.r_const

(* §3.2 rung 2, boolean half: `e = true` / `e <> false` reduce to `e`, and their
   negated forms to `not e`; commutative equality gets its operands sorted so
   `a = b` and `b = a` share a key. Returns (canonical_key, negated?). *)
let rec canon_atom (e : expression) : string * bool =
  match e.pexp_desc with
  | Pexp_constraint (a, _) -> canon_atom a
  | Pexp_apply (f, [(Nolabel, l); (Nolabel, r)]) -> (
      let bool_lit x =
        match x.pexp_desc with
        | Pexp_construct ({txt = Lident "true"; _}, None) -> Some true
        | Pexp_construct ({txt = Lident "false"; _}, None) -> Some false
        | _ -> None
      in
      match ident_of f with
      | Some (("=" | "<>") as op) -> (
          match (bool_lit l, bool_lit r) with
          | Some b, None ->
              let k, n = canon_atom r in
              (k, if op = "=" then n <> not b else n <> b)
          | None, Some b ->
              let k, n = canon_atom l in
              (k, if op = "=" then n <> not b else n <> b)
          | _ ->
              (* commutative: sort operands *)
              let sl = print_expr l and sr = print_expr r in
              let a, b = if sl <= sr then (sl, sr) else (sr, sl) in
              (Printf.sprintf "%s %s %s" a op b, false))
      | Some (("<" | "<=" | ">" | ">=") as op) -> (
          match as_relational e with
          | Some r -> (rel_key r, false)
          | None ->
              (* No constant, so rung 3 does not apply — but `x < y` and
                 `y > x` still denote the same value. Orient the operands so
                 both spellings share a key; without this only the SMT tier
                 relates them. *)
              let sl = print_expr l and sr = print_expr r in
              if sl <= sr then (Printf.sprintf "%s %s %s" sl op sr, false)
              else (Printf.sprintf "%s %s %s" sr (flip_op op) sl, false))
      | _ -> (
          match as_relational e with
          | Some r -> (rel_key r, false)
          | None -> (print_expr e, false)))
  | _ -> (
      match as_relational e with
      | Some r -> (rel_key r, false)
      | None -> (print_expr e, false))

(* -------------------------------------------------------------------------- *)
(* Decision building                                                           *)
(* -------------------------------------------------------------------------- *)

type builder = {
  mutable atoms : atom list; (* reversed *)
  mutable natoms : int;
  mutable fresh : int;
}

let new_builder () = {atoms = []; natoms = 0; fresh = 0}

let unstable_heads : (string, int) Hashtbl.t = Hashtbl.create 256

let bump_head k =
  Hashtbl.replace unstable_heads k
    (1 + Option.value ~default:0 (Hashtbl.find_opt unstable_heads k))

(* Why is this atom unstable? Collect the applied heads the stability predicate
   refused, so we can tell apart "a locally-defined predicate a purity ANALYSIS
   could certify" from "genuinely effectful, no analysis will ever help". This
   is the datum that decides whether investing in purity/R3 buys recall. *)
let rec collect_unstable_heads (e : expression) =
  (* Only record a node that is ITSELF the reason for instability. An earlier
     version recorded every leaf inside an unstable atom, which counted benign
     nullary constructors as "walker gap" and inflated that bucket badly. *)
  if is_stable e then ()
  else
    match e.pexp_desc with
    | Pexp_apply (f, args) ->
        (match ident_of f with
        | Some n
          when not
                 (List.mem n comparison_ops || List.mem n arith_ops
                || List.mem n pure_allowlist || n = "not") ->
            bump_head n
        | Some _ -> () (* head is fine; an argument is the culprit *)
        | None -> bump_head "<computed head>") ;
        List.iter (fun (_, a) -> collect_unstable_heads a) args
    | Pexp_field (a, _) | Pexp_constraint (a, _) -> collect_unstable_heads a
    | Pexp_tuple l -> List.iter collect_unstable_heads l
    | Pexp_construct (_, Some a) | Pexp_variant (_, Some a) -> collect_unstable_heads a
    | d ->
        let tag =
          match d with
          | Pexp_let _ -> "let" | Pexp_match _ -> "match" | Pexp_ifthenelse _ -> "if"
          | Pexp_function _ -> "fun" | Pexp_sequence _ -> "sequence" | Pexp_try _ -> "try"
          | Pexp_array _ -> "array" | Pexp_record _ -> "record" | Pexp_setfield _ -> "setfield"
          | Pexp_while _ -> "while" | Pexp_for _ -> "for" | Pexp_send _ -> "method-send"
          | Pexp_new _ -> "new" | Pexp_assert _ -> "assert" | Pexp_lazy _ -> "lazy"
          | Pexp_open _ -> "open" | Pexp_letmodule _ -> "letmodule" | Pexp_letop _ -> "letop"
          | Pexp_extension _ -> "extension(ppx)" | Pexp_object _ -> "object"
          | Pexp_coerce _ -> "coerce" | Pexp_pack _ -> "pack" | Pexp_newtype _ -> "newtype"
          | Pexp_setinstvar _ -> "setinstvar" | Pexp_override _ -> "override"
          | Pexp_letexception _ -> "letexception" | _ -> "other"
        in
        bump_head ("<construct:" ^ tag ^ ">")

let is_op (e : expression) names =
  match ident_of e with Some n -> List.mem n names | None -> false

(* --- Parsetree frontend: lower an atom to the neutral IR (§8.3) ----------- *)

let length_fns = ["String.length"; "List.length"; "Array.length"; "Bytes.length"]

let rec is_closed_literal (e : expression) =
  match e.pexp_desc with
  | Pexp_constant _ -> true
  | Pexp_construct (_, None) -> true
  | Pexp_construct (_, Some a) -> is_closed_literal a
  | Pexp_variant (_, None) -> true
  | Pexp_variant (_, Some a) -> is_closed_literal a
  | Pexp_tuple l -> List.for_all is_closed_literal l
  | Pexp_constraint (a, _) -> is_closed_literal a
  | _ -> false

let rec lower_term (e : expression) : sterm =
  match e.pexp_desc with
  | Pexp_constraint (a, _) -> lower_term a
  | _ -> (
      match int_literal e with
      | Some k -> TConst k
      | None -> (
          match e.pexp_desc with
          | Pexp_apply (f, [(Nolabel, l); (Nolabel, r)]) when is_op f ["+"] ->
              TAdd (lower_term l, lower_term r)
          | Pexp_apply (f, [(Nolabel, l); (Nolabel, r)]) when is_op f ["-"] ->
              TSub (lower_term l, lower_term r)
          | Pexp_apply (f, [(Nolabel, l); (Nolabel, r)]) when is_op f ["*"] ->
              TMul (lower_term l, lower_term r)
          | Pexp_apply (f, [(Nolabel, _)])
            when (match ident_of f with
                 | Some n -> List.mem n length_fns
                 | None -> false) ->
              TLen (print_expr e)
          | _ ->
              if is_closed_literal e then TLit (print_expr e)
              else if is_stable e then TVar (print_expr e)
              else TFresh (print_expr e)))

(* `x <> x` and `x = x` are the idiomatic NaN test in OCaml — for a float they
   are NOT constant, and treating them relationally proves live code dead. §6.3
   said to decline floats and this PoC never did; running on a third corpus is
   what exposed it. Without types we cannot tell a float from an int, so decline
   the SHAPE: a comparison whose two sides are the same expression is never
   given a relational encoding. Costs a genuine non-float tautology; a false
   "delete this code" costs much more. *)
let self_compare l r = print_expr l = print_expr r

let lower_atom (e : expression) : satom =
  match e.pexp_desc with
  | Pexp_apply (f, [(Nolabel, l); (Nolabel, r)]) -> (
      match ident_of f with
      | Some (("=" | "<>") as _op) when self_compare l r -> AOpaque
      | Some (("=" | "<>" | "<" | "<=" | ">" | ">=") as op) ->
          ARel (op, lower_term l, lower_term r)
      | _ -> AOpaque)
  | _ -> AOpaque

let add_atom b (e0 : expression) =
  (* Canonicalise the ALIAS-RESOLVED form (rung 1) but report the source as
     written, so a finding still points at what the author typed. *)
  let e = resolve_aliases e0 in
  let key, negated = canon_atom e in
  let stable = is_stable e in
  if not stable then collect_unstable_heads e ;
  let key =
    if stable then key
    else begin
      b.fresh <- b.fresh + 1 ;
      (* unstable: a fresh key per occurrence, so it can never merge *)
      Printf.sprintf "#unstable%d#%s" b.fresh key
    end
  in
  let loc = e0.pexp_loc in
  let a =
    {
      a_key = key;
      a_stable = stable;
      a_rel = (if stable then as_relational e else None);
      a_line = loc.loc_start.pos_lnum;
      a_col = loc.loc_start.pos_cnum - loc.loc_start.pos_bol + 1;
      a_src =
        (let written = print_expr e0 and resolved = print_expr e in
         if written = resolved then written
         else Printf.sprintf "%s [= %s]" written resolved);
      a_term = lower_atom e;
    }
  in
  let id = b.natoms in
  b.atoms <- a :: b.atoms ;
  b.natoms <- b.natoms + 1 ;
  let occ = BOcc id in
  if negated then BNot occ else occ

(* Lower a condition expression to a boolean term. `not (not e)` collapses on
   the way (§3.2 rung 2). Anything that is not a boolean connective becomes an
   atom — including a nested `if`, which is correct: we do not model it, so it
   is an opaque leaf, never an assumption. *)
let rec build b (e : expression) : bexp =
  match e.pexp_desc with
  | Pexp_constraint (a, _) -> build b a
  | Pexp_construct ({txt = Lident "true"; _}, None) -> BTrue
  | Pexp_construct ({txt = Lident "false"; _}, None) -> BFalse
  | Pexp_apply (f, [(Nolabel, l); (Nolabel, r)]) when is_op f ["&&"; "&"] ->
      BAnd (build b l, build b r)
  | Pexp_apply (f, [(Nolabel, l); (Nolabel, r)]) when is_op f ["||"; "or"] ->
      BOr (build b l, build b r)
  | Pexp_apply (f, [(Nolabel, a)]) when is_op f ["not"] -> (
      match build b a with BNot x -> x | x -> BNot x)
  | _ -> add_atom b e

(* -------------------------------------------------------------------------- *)
(* Evaluation: free-boolean (rungs 0/2) or interval (rung 3)                   *)
(* -------------------------------------------------------------------------- *)

(* Variables are canonical atom keys. Occurrence -> variable is the merge that
   rungs 0/2 perform; rung 3 goes further and gives relational variables an
   integer-region semantics instead of a free boolean one. *)
type env = {
  occ_var : int array; (* occurrence id -> variable index *)
  nvars : int;
  var_rel : rel option array; (* variable -> relational shape, if any *)
  subjects : (string * int list) list; (* subject -> candidate integer values *)
  subj_of_var : int array; (* variable -> subject index, or -1 *)
  bool_vars : int list; (* variables evaluated as free booleans *)
}

let rec eval (en : env) (assign : bool array) (subj : int array)
    (subj_val : int array) (e : bexp) =
  match e with
  | BTrue -> true
  | BFalse -> false
  | BNot x -> not (eval en assign subj subj_val x)
  | BAnd (x, y) -> eval en assign subj subj_val x && eval en assign subj subj_val y
  | BOr (x, y) -> eval en assign subj subj_val x || eval en assign subj subj_val y
  | BOcc i -> (
      let v = en.occ_var.(i) in
      match en.var_rel.(v) with
      | Some r when en.subj_of_var.(v) >= 0 && subj.(en.subj_of_var.(v)) >= 0 ->
          let x = subj_val.(subj.(en.subj_of_var.(v))) in
          (match r.r_op with
          | "<" -> x < r.r_const
          | "<=" -> x <= r.r_const
          | ">" -> x > r.r_const
          | ">=" -> x >= r.r_const
          | "=" -> x = r.r_const
          | "<>" -> x <> r.r_const
          | _ -> assign.(v))
      | _ -> assign.(v))
  [@@warning "-27"]

(* Variables actually occurring in a term. Enumerating only these is both faster
   and necessary for correctness of the budget: a decision nested inside several
   guards shares one variable table with them, and counting the guards' variables
   against the decision's own budget produced spurious UNKNOWNs. All terms
   compared with each other must be enumerated over the SAME variable list. *)
let vars_of (en : env) (e : bexp) =
  let rec go acc = function
    | BOcc i -> en.occ_var.(i) :: acc
    | BNot x -> go acc x
    | BAnd (x, y) | BOr (x, y) -> go (go acc x) y
    | _ -> acc
  in
  List.sort_uniq compare (go [] e)

(* Enumerate every (boolean assignment x subject-value) combination over [vars]
   and return the truth vector of [e]. [None] when the space exceeds the budget. *)
let truth_vector_over (en : env) (vars : int list) (e : bexp) : bool array option =
  let bool_vars = List.filter (fun v -> List.mem v en.bool_vars) vars in
  let subjects =
    List.filteri
      (fun i _ -> List.exists (fun v -> en.subj_of_var.(v) = i) vars)
      en.subjects
  in
  let nb = List.length bool_vars in
  let subj_sizes = List.map (fun (_, vs) -> List.length vs) subjects in
  let total = List.fold_left (fun acc n -> acc * n) (1 lsl nb) subj_sizes in
  if nb > cap_vars || total > cap_combos || total <= 0 then None
  else begin
    let bool_arr = Array.of_list bool_vars in
    let subj_arr = Array.of_list (List.map (fun (_, vs) -> Array.of_list vs) subjects) in
    let nsubj = Array.length subj_arr in
    (* remap global subject index -> position in the filtered list *)
    let subj_pos = Array.make (max 1 (List.length en.subjects)) (-1) in
    List.iteri
      (fun pos (name, _) ->
        List.iteri (fun gi (gname, _) -> if gname = name then subj_pos.(gi) <- pos) en.subjects)
      subjects ;
    let assign = Array.make (max 1 en.nvars) false in
    let subj_val = Array.make (max 1 (max nsubj (Array.length subj_pos))) 0 in
    let out = Array.make total false in
    let idx = ref 0 in
    let rec go_subj s =
      if s = nsubj then begin
        for m = 0 to (1 lsl nb) - 1 do
          Array.iteri (fun bi v -> assign.(v) <- m land (1 lsl bi) <> 0) bool_arr ;
          out.(!idx) <- eval en assign subj_pos subj_val e ;
          incr idx
        done
      end
      else
        Array.iter
          (fun v ->
            subj_val.(s) <- v ;
            go_subj (s + 1))
          subj_arr.(s)
    in
    go_subj 0 ;
    Some out
  end

(* -------------------------------------------------------------------------- *)
(* Substitution by PATH — exact, no aliasing between shared subtrees           *)
(* -------------------------------------------------------------------------- *)

let rec subst (e : bexp) (path : int list) (c : bool) =
  match path with
  | [] -> if c then BTrue else BFalse
  | i :: rest -> (
      match e with
      | BNot x -> BNot (subst x rest c)
      | BAnd (x, y) -> if i = 0 then BAnd (subst x rest c, y) else BAnd (x, subst y rest c)
      | BOr (x, y) -> if i = 0 then BOr (subst x rest c, y) else BOr (x, subst y rest c)
      | _ -> e)

let rec occs_of = function
  | BOcc i -> [i]
  | BNot x -> occs_of x
  | BAnd (x, y) | BOr (x, y) -> occs_of x @ occs_of y
  | _ -> []

(* -------------------------------------------------------------------------- *)
(* Findings                                                                    *)
(* -------------------------------------------------------------------------- *)

type finding = {
  f_kind : string;
  f_file : string;
  f_line : int;
  f_col : int;
  f_form : string;
  f_arity : int;
      (* Atomic conditions in the decision. Written to decisions.arity, which used to be
         hardcoded to 0 for every row — so the column the schema documents as "number of atomic
         conditions" said every decision in the project had none, and HIGH_ARITY findings (whose
         whole content IS the arity) recorded it as zero. *)
  f_detail : string;
  f_snippet : string;
  f_evidence : string;
}

let findings : finding list ref = ref []
let emit f = findings := f :: !findings

(* Arity by decision site. The identical-arms check emits at the SAME (file, line, col) as the
   analysis that just ran over the same condition, so it can recover the arity rather than
   invent one. *)
let decision_arity : (string * int * int, int) Hashtbl.t = Hashtbl.create 256
let arity_at file line col = Option.value ~default:0 (Hashtbl.find_opt decision_arity (file, line, col))

(* census *)
let n_decisions = ref 0
let n_multi = ref 0
let n_unknown = ref 0
let n_files = ref 0
let n_parse_fail = ref 0

(* A file that PARSED but whose analysis raised. It used to be swallowed by `with _ -> ()`, so
   the file was counted as analysed and contributed no decisions — "clean" and "crashed" produced
   the same census. Counted and reported, like every other degradation here. *)
let n_walk_fail = ref 0
let n_unstable_atoms = ref 0
let frontend_cmt = ref false
let n_smt_decisions = ref 0
let n_smt_findings = ref 0
let n_atoms = ref 0
let arity_hist : (int, int) Hashtbl.t = Hashtbl.create 16

let bump h k = Hashtbl.replace h k (1 + Option.value ~default:0 (Hashtbl.find_opt h k))

(* -------------------------------------------------------------------------- *)
(* Decision analysis                                                           *)
(* -------------------------------------------------------------------------- *)

let build_env (b : builder) (terms : bexp list) =
  let atoms = Array.of_list (List.rev b.atoms) in
  let tbl = Hashtbl.create 16 in
  let nvars = ref 0 in
  let occ_var = Array.make (max 1 (Array.length atoms)) 0 in
  Array.iteri
    (fun i a ->
      match Hashtbl.find_opt tbl a.a_key with
      | Some v -> occ_var.(i) <- v
      | None ->
          let v = !nvars in
          incr nvars ;
          Hashtbl.replace tbl a.a_key v ;
          occ_var.(i) <- v)
    atoms ;
  let var_rel = Array.make (max 1 !nvars) None in
  Array.iteri (fun i a -> if a.a_rel <> None then var_rel.(occ_var.(i)) <- a.a_rel) atoms ;
  (* group relational variables by subject; candidate values are k-1,k,k+1 for
     every constant, plus one below and one above -- exact for integer
     comparisons against constants (small-model property). *)
  let subj_tbl = Hashtbl.create 8 in
  Array.iteri
    (fun v r ->
      match r with
      | Some r ->
          let prev = Option.value ~default:[] (Hashtbl.find_opt subj_tbl r.r_subject) in
          Hashtbl.replace subj_tbl r.r_subject ((r.r_const, v) :: prev)
      | None -> ())
    var_rel ;
  let subjects =
    Hashtbl.fold
      (fun s entries acc ->
        let ks = List.sort_uniq compare (List.map fst entries) in
        let cands =
          List.concat_map (fun k -> [k - 1; k; k + 1]) ks
          @ [List.fold_left min max_int ks - 2; List.fold_left max min_int ks + 2]
        in
        (s, List.sort_uniq compare cands) :: acc)
      subj_tbl []
  in
  let subj_index = List.mapi (fun i (s, _) -> (s, i)) subjects in
  let subj_of_var = Array.make (max 1 !nvars) (-1) in
  Array.iteri
    (fun v r ->
      match r with
      | Some r -> (
          match List.assoc_opt r.r_subject subj_index with
          | Some i -> subj_of_var.(v) <- i
          | None -> ())
      | None -> ())
    var_rel ;
  let bool_vars = ref [] in
  for v = !nvars - 1 downto 0 do
    if subj_of_var.(v) < 0 then bool_vars := v :: !bool_vars
  done ;
  ignore terms ;
  ( {
      occ_var;
      nvars = !nvars;
      var_rel;
      subjects;
      subj_of_var;
      bool_vars = !bool_vars;
    },
    atoms )

let all_same v = Array.for_all (fun x -> x = v.(0)) v

let vec_eq a b = a = b

(* Find topmost dead proper subterms: report the largest, do not recurse into a
   dead one (§3.3 -- detection is leaf-driven, presentation is subterm-driven). *)
let find_dead_subterms en (root : bexp) (base : bool array) =
  let vs = vars_of en root in
  let acc = ref [] in
  let rec go e path =
    let dead =
      match
        ( truth_vector_over en vs (subst root path true),
          truth_vector_over en vs (subst root path false) )
      with
      | Some t, Some f -> vec_eq t base || vec_eq f base
      | _ -> false
    in
    if dead && path <> [] then acc := (path, e) :: !acc
    else
      match e with
      | BNot x -> go x (path @ [0])
      | BAnd (x, y) | BOr (x, y) ->
          go x (path @ [0]) ;
          go y (path @ [1])
      | _ -> ()
  in
  go root [] ;
  List.rev !acc

(* Render the dead atoms with their own line:col so a reviewer can jump to the
   exact condition, not just the enclosing decision. *)
let snippet_of atoms occs =
  String.concat ", "
    (List.sort_uniq compare
       (List.map
          (fun i ->
            let a = atoms.(i) in
            Printf.sprintf "%s @%d:%d" a.a_src a.a_line a.a_col)
          occs))

(* -------------------------------------------------------------------------- *)
(* SMT tier — §6 of the design doc                                            *)
(* -------------------------------------------------------------------------- *)

(* Escalation tier for what enumeration cannot decide: coupling between atoms
   that are syntactically DIFFERENT, so no canonicalisation rung merges them.
   `s = "a" && s <> "a"`, `i < n && n <= i`, `x + 1 > y && x >= y`,
   `v = None && v = Some 3` -- all invisible to rungs 0-3, all decided here.

   Transport is SMT-LIB over a pipe to an external solver (§6.6 option B): the
   static release build stays untouched, the solver is an OPTIONAL runtime
   dependency (absent -> UNKNOWN, never a gate failure), and the query text is
   the natural cache key.

   Encoding rule (§6.3): ABSTRACT BY FREENESS, NEVER BY ASSUMPTION. The encoding
   must over-approximate the reachable state space, so `unsat` in the
   abstraction implies `unsat` in reality and a "dead" verdict is a real proof.
   Anything not modelled becomes a fresh constant, never an axiom. *)

let smt_rlimit = 2_000_000
(* Deterministic resource budget, NOT a wall-clock timeout: the same commit must
   produce the same verdict on every machine, or a CI gate flaps (§6.4). *)

let bv_width = 63
(* OCaml's native int is 63-bit and WRAPS. Encoding it as SMT `Int` (LIA) would
   be unsound: `x + 1 > x` is LIA-valid but false at max_int, so an LIA encoding
   would prove a real guard dead. Producer-declared in the real design (§8.3);
   hardcoded here because this frontend only ever sees OCaml. *)

type smt = {
  s_fd : Unix.file_descr;
  s_pending : Buffer.t;  (* bytes read past the end of the last line *)
  s_out : out_channel;
  s_cache : (string, bool) Hashtbl.t; (* query text -> unsat? *)
  mutable s_queries : int;
  mutable s_hits : int;
  mutable s_unknown : int;
  mutable s_dead : bool;  (* the solver stopped answering; stop asking, never guess *)
}

(* Wall-clock ceiling on ONE read from the solver. [smt_rlimit] is a deterministic budget the
   solver applies to its own search; it says nothing about a solver that answers nothing at all.
   A stub that replies to the handshake and then goes silent used to block [input_line] forever,
   and the analysis with it — the fuel in [read_verdict] bounds the LINES read, not the waiting.
   Reads therefore go through the raw fd with a deadline rather than through the channel, whose
   buffering would make a readiness check meaningless. *)
let smt_read_timeout = 30.0

(* One line, or [None] on timeout / EOF. Bytes past the newline are kept for the next call. *)
let smt_read_line st =
  let deadline = Unix.gettimeofday () +. smt_read_timeout in
  let chunk = Bytes.create 4096 in
  let rec take () =
    let buffered = Buffer.contents st.s_pending in
    match String.index_opt buffered '\n' with
    | Some i ->
        Buffer.clear st.s_pending ;
        Buffer.add_string st.s_pending
          (String.sub buffered (i + 1) (String.length buffered - i - 1)) ;
        Some (String.sub buffered 0 i)
    | None ->
        let left = deadline -. Unix.gettimeofday () in
        if left <= 0. then None
        else (
          match Unix.select [ st.s_fd ] [] [] (min left 1.0) with
          | exception Unix.Unix_error (Unix.EINTR, _, _) -> take ()
          | [], _, _ -> take ()
          | _ -> (
              match Unix.read st.s_fd chunk 0 (Bytes.length chunk) with
              | 0 -> None (* EOF: the solver is gone *)
              | n ->
                  Buffer.add_subbytes st.s_pending chunk 0 n ;
                  take ()
              | exception Unix.Unix_error _ -> None))
  in
  take ()

let smt : smt option ref = ref None

(* Writing to a solver that is not there must not kill the analysis.
   [Unix.open_process] spawns a SHELL, so it succeeds even when z3 is not installed: the shell
   exits, and the first write to its stdin raises SIGPIPE, whose default action terminates the
   process. The whole run then died by signal 13 with no output — indistinguishable, to a script
   reading exit codes, from a crash in the analysis itself. Ignoring the signal turns it into an
   EPIPE exception the code below can handle. *)
let () = try Sys.set_signal Sys.sigpipe Sys.Signal_ignore with Invalid_argument _ -> ()

(* Read up to the next CHECK-SAT VERDICT, skipping anything else the solver printed.

   z3 answers a `(check-sat)` with exactly one of sat/unsat/unknown, but it also writes
   `(error "…")` lines to STDOUT for a malformed assertion, and some builds emit a banner. The
   old reader took literally the next line: an error line was reported as unknown and the real
   verdict stayed in the buffer, becoming the answer to the NEXT query — every subsequent result
   shifted by one, silently, with no way to notice from the outside. Fuel-bounded so a solver
   that only ever prints noise cannot hang the analysis. *)
(* [Unknown] is an ANSWER (the solver said so); [Gone] is the absence of one. Collapsing them
   into [None] meant a silent solver cost the full read deadline on every remaining query
   instead of once. *)
type answer = Verdict of bool | Unknown | Gone

let rec read_verdict ?(fuel = 64) st =
  if fuel <= 0 then Gone
  else
    match smt_read_line st with
    | None -> Gone (* timeout or EOF *)
    | Some line -> (
        match String.trim line with
        | "unsat" -> Verdict true
        | "sat" -> Verdict false
        | "unknown" -> Unknown
        | _ -> read_verdict ~fuel:(fuel - 1) st)

let smt_start () =
  match Unix.open_process "z3 -in 2>/dev/null" with
  | ic, oc -> (
      try
        output_string oc "(set-logic ALL)\n" ;
        output_string oc (Printf.sprintf "(set-option :rlimit %d)\n" smt_rlimit) ;
        (* Probe before believing in the solver: the shell above exits successfully when z3 is
           absent, so a live pipe is not evidence that anything is listening on it. A solver
           reported as present but silently dead would make every escalated decision come back
           `unknown`, which the tiering reads as "nothing to prove". The probe asserts nothing,
           so its answer must be `sat` — anything else means the thing on the pipe does not
           speak SMT-LIB, and believing it would be worse than declaring no solver. *)
        output_string oc "(check-sat)\n" ;
        flush oc ;
        let st =
          {s_fd = Unix.descr_of_in_channel ic; s_pending = Buffer.create 256; s_out = oc;
           s_cache = Hashtbl.create 4096; s_queries = 0; s_hits = 0; s_unknown = 0;
           s_dead = false}
        in
        match read_verdict st with
        | Verdict false -> Some st
        | _ -> ignore (Unix.close_process (ic, oc)) ; None
      with _ -> ignore (Unix.close_process (ic, oc)) ; None)
  | exception _ -> None

(* [unsat decls phi] — is [phi] unsatisfiable under [decls]? [None] on
   `unknown`, on budget exhaustion, or when no solver is present. Never
   guessed. *)
let smt_unsat (st : smt) (decls : string) (phi : string) : bool option =
  let query = decls ^ "\n(assert " ^ phi ^ ")" in
  match Hashtbl.find_opt st.s_cache query with
  | Some b ->
      st.s_hits <- st.s_hits + 1 ;
      Some b
  | None when st.s_dead -> None
  | None -> (
      st.s_queries <- st.s_queries + 1 ;
      match
        output_string st.s_out ("(push 1)\n" ^ query ^ "\n(check-sat)\n(pop 1)\n") ;
        flush st.s_out
      with
      | exception _ ->
          (* The solver died mid-run. Recorded as unknown, and no further queries are sent —
             answering from a dead pipe would be guessing. *)
          st.s_dead <- true ;
          st.s_unknown <- st.s_unknown + 1 ;
          None
      | () -> (
      match read_verdict st with
      | Verdict b ->
          Hashtbl.replace st.s_cache query b ;
          Some b
      | Unknown ->
          st.s_unknown <- st.s_unknown + 1 ;
          None
      | Gone ->
          (* No answer at all — a dead pipe or a solver that stopped talking. Asking again would
             cost the read deadline once per remaining query and still learn nothing. *)
          st.s_dead <- true ;
          st.s_unknown <- st.s_unknown + 1 ;
          None
      | exception _ ->
          st.s_dead <- true ;
          st.s_unknown <- st.s_unknown + 1 ;
          None))

(* --- encoder ------------------------------------------------------------- *)

type ectx = {
  mutable e_decls : string list; (* reversed declaration lines *)
  e_names : (string, string) Hashtbl.t; (* canonical key -> SMT name *)
  mutable e_lits : string list; (* closed-literal constants, asserted distinct *)
  mutable e_fresh : int;
  mutable e_relational : bool; (* did anything encode to a real relation? *)
}

let new_ectx () =
  {e_decls = []; e_names = Hashtbl.create 32; e_lits = []; e_fresh = 0;
   e_relational = false}

let sanitize s =
  String.concat ""
    (List.map
       (fun c ->
         if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
         then String.make 1 c
         else "_")
       (List.init (String.length s) (String.get s)))

let bv_lit k =
  (* two's complement literal, width 63 *)
  let m = if k < 0 then (1 lsl bv_width) + k else k in
  Printf.sprintf "(_ bv%d %d)" m bv_width

let declare ctx kind key =
  match Hashtbl.find_opt ctx.e_names key with
  | Some n -> n
  | None ->
      ctx.e_fresh <- ctx.e_fresh + 1 ;
      let n = Printf.sprintf "%s%d_%s" kind ctx.e_fresh
                (let s = sanitize key in
                 if String.length s > 24 then String.sub s 0 24 else s)
      in
      Hashtbl.replace ctx.e_names key n ;
      ctx.e_decls <-
        Printf.sprintf "(declare-fun %s () (_ BitVec %d))" n bv_width :: ctx.e_decls ;
      n

let declare_bool ctx key =
  match Hashtbl.find_opt ctx.e_names key with
  | Some n -> n
  | None ->
      ctx.e_fresh <- ctx.e_fresh + 1 ;
      let n = Printf.sprintf "p%d_%s" ctx.e_fresh
                (let s = sanitize key in
                 if String.length s > 24 then String.sub s 0 24 else s)
      in
      Hashtbl.replace ctx.e_names key n ;
      ctx.e_decls <- Printf.sprintf "(declare-fun %s () Bool)" n :: ctx.e_decls ;
      n

(* --- SMT encoder over the NEUTRAL IR --------------------------------------
   Nothing below mentions Parsetree or Typedtree: the encoder consumes [sterm]
   and [satom], so every frontend shares it unchanged (§8.3). *)

let rec enc_term ctx (t : sterm) : string =
  match t with
  | TConst k -> bv_lit k
  | TLit key ->
      let n = declare ctx "lit" ("lit$" ^ key) in
      if not (List.mem n ctx.e_lits) then ctx.e_lits <- n :: ctx.e_lits ;
      n
  | TVar key -> declare ctx "v" key
  | TFresh key ->
      (* unstable: a fresh constant per occurrence, so it can never merge --
         the never-merge-unstable rule of §3.2, enforced by the encoding *)
      ctx.e_fresh <- ctx.e_fresh + 1 ;
      declare ctx "u" (Printf.sprintf "#unstable%d#%s" ctx.e_fresh key)
  | TAdd (a, b) -> Printf.sprintf "(bvadd %s %s)" (enc_term ctx a) (enc_term ctx b)
  | TSub (a, b) -> Printf.sprintf "(bvsub %s %s)" (enc_term ctx a) (enc_term ctx b)
  | TMul (a, b) -> Printf.sprintf "(bvmul %s %s)" (enc_term ctx a) (enc_term ctx b)
  | TLen key ->
      (* A length is non-negative. That is a fact about OCaml, not an assumption
         about the program, so asserting it is justified — and it is what makes
         `String.length s >= 0` decidable as a tautology. *)
      let n = declare ctx "len" ("len$" ^ key) in
      ctx.e_decls <- Printf.sprintf "(assert (bvsge %s %s))" n (bv_lit 0) :: ctx.e_decls ;
      n

let enc_atom ctx (a : atom) : string =
  match a.a_term with
  | AOpaque -> declare_bool ctx a.a_key
  | ARel (op, l, r) ->
      ctx.e_relational <- true ;
      let smt_op =
        match op with
        | "=" -> "=" | "<>" -> "distinct"
        | "<" -> "bvslt" | "<=" -> "bvsle"
        | ">" -> "bvsgt" | _ -> "bvsge"
      in
      Printf.sprintf "(%s %s %s)" smt_op (enc_term ctx l) (enc_term ctx r)

let rec enc_bexp ctx (smtof : int -> string) = function
  | BTrue -> "true"
  | BFalse -> "false"
  | BOcc i -> smtof i
  | BNot x -> Printf.sprintf "(not %s)" (enc_bexp ctx smtof x)
  | BAnd (x, y) ->
      Printf.sprintf "(and %s %s)" (enc_bexp ctx smtof x) (enc_bexp ctx smtof y)
  | BOr (x, y) ->
      Printf.sprintf "(or %s %s)" (enc_bexp ctx smtof x) (enc_bexp ctx smtof y)

let ectx_decls ctx =
  let lits = List.rev ctx.e_lits in
  let distinct =
    if List.length lits >= 2 then
      [Printf.sprintf "(assert (distinct %s))" (String.concat " " lits)]
    else []
  in
  String.concat "\n" (List.rev ctx.e_decls @ distinct)

(* Analyse one decision. [guards] is the conjunction of conditions holding on
   every path to this decision (§6.2, dominator chain in its syntactic form:
   the enclosing if/when guards). *)
(* Frontend-independent: takes a decision and its guards ALREADY lowered to
   [bexp] over one builder, plus their source text. Both frontends share every
   tier below this point. *)
let analyse_built ~file ~form ~line ~col ~src ~guard_srcs (b : builder)
    (d : bexp) (gs : bexp list) =
  incr n_decisions ;
  let en, atoms = build_env b [d] in
  let n_leaf = List.length (List.sort_uniq compare (occs_of d)) in
  Hashtbl.replace decision_arity (file, line, col) n_leaf ;
  bump arity_hist (min n_leaf 9) ;
  n_atoms := !n_atoms + Array.length atoms ;
  Array.iter (fun a -> if not a.a_stable then incr n_unstable_atoms) atoms ;
  if n_leaf > 1 then incr n_multi ;
  let findings_before = ref (List.length !findings) in
  let smt_escalate ~mk ~atoms ~d ~gs =
    match !smt with
    | None -> ()
    | Some st ->
        let ctx = new_ectx () in
        let cache = Hashtbl.create 16 in
        let smtof i =
          match Hashtbl.find_opt cache i with
          | Some x -> x
          | None ->
              let x = enc_atom ctx atoms.(i) in
              Hashtbl.replace cache i x ;
              x
        in
        (* force encoding of every atom so declarations and the literal-distinct
           assertion are complete before any query is issued *)
        let phi_d = enc_bexp ctx smtof d in
        let phi_gs = List.map (fun g -> enc_bexp ctx smtof g) gs in
        if ctx.e_relational then begin
          incr n_smt_decisions ;
          let decls = ectx_decls ctx in
          let unsat p = smt_unsat st decls p in
          let fired = ref false in
          (* the decision, on its own *)
          (match unsat (Printf.sprintf "(not %s)" phi_d) with
          | Some true ->
              fired := true ;
              mk "SMT_CONSTANT_TRUE"
                "decision is true under every input (proved by SMT)" ""
          | _ -> (
              match unsat phi_d with
              | Some true ->
                  fired := true ;
                  mk "SMT_CONSTANT_FALSE"
                    "decision is false under every input (proved by SMT)" ""
              | _ -> ())) ;
          (* individual conditions that cannot change the outcome *)
          if not !fired then begin
            let leaves = List.sort_uniq compare (occs_of d) in
            let dead =
              List.filter
                (fun i ->
                  let sub c =
                    enc_bexp ctx (fun j -> if j = i then (if c then "true" else "false") else smtof j) d
                  in
                  let equiv a b = unsat (Printf.sprintf "(distinct %s %s)" a b) in
                  equiv phi_d (sub true) = Some true
                  || equiv phi_d (sub false) = Some true)
                leaves
            in
            if dead <> [] then begin
              fired := true ;
              mk "SMT_DEAD_CONDITION"
                (Printf.sprintf
                   "%d condition(s) cannot influence the outcome (proved by SMT; \
                    invisible to syntactic canonicalisation)"
                   (List.length dead))
                (snippet_of atoms dead)
            end
          end ;
          (* settled by the guards on every path here *)
          if (not !fired) && phi_gs <> [] then begin
            let p = Printf.sprintf "(and %s)" (String.concat " " phi_gs) in
            match unsat p with
            | Some true ->
                mk "SMT_UNREACHABLE_PATH"
                  "the guards leading here are contradictory (proved by SMT)" ""
            | _ -> (
                match unsat (Printf.sprintf "(and %s (not %s))" p phi_d) with
                | Some true ->
                    mk "SMT_IMPLIED_TRUE"
                      "decision is already guaranteed by an enclosing guard \
                       (proved by SMT)"
                      (String.concat " && " guard_srcs)
                | _ -> (
                    match unsat (Printf.sprintf "(and %s %s)" p phi_d) with
                    | Some true ->
                        mk "SMT_IMPLIED_FALSE"
                          "decision is already excluded by an enclosing guard \
                           (proved by SMT)"
                          (String.concat " && " guard_srcs)
                    | _ -> ()))
          end ;
          if List.length !findings > !findings_before then incr n_smt_findings
        end
  in
  let d_vars = vars_of en d in
  match truth_vector_over en d_vars d with
  | None ->
      (* Above budget: no logical verdict is possible, but the arity ITSELF is a
         maintainability signal (§6.8 / R8) -- a 9-condition boolean is hard for
         a human to verify by reading. Advisory, never a gate failure. *)
      incr n_unknown ;
      emit
        {
          f_kind = "HIGH_ARITY";
          f_file = file;
          f_line = line;
          f_col = col;
          f_form = form;
          f_arity = n_leaf;
          f_detail =
            Printf.sprintf
              "%d atomic conditions: above the enumeration budget, so no \
               redundancy verdict is possible -- and hard to verify by reading"
              n_leaf;
          f_snippet = src;
          f_evidence = "";
        }
  | Some base ->
      let mk kind detail evidence =
        emit
          {
            f_kind = kind;
            f_file = file;
            f_line = line;
            f_col = col;
            f_form = form;
            f_arity = n_leaf;
            f_detail = detail;
            f_snippet = src;
            f_evidence = evidence;
          }
      in
      (* 1. the decision is constant on its own *)
      if Array.length base > 0 && all_same base then
        mk
          (if base.(0) then "CONSTANT_TRUE" else "CONSTANT_FALSE")
          "decision has the same outcome under every input"
          ""
      else begin
        (* 2. dead conditions / subterms, ignoring the path *)
        let deads =
          List.filter (fun (_, sub) -> occs_of sub <> []) (find_dead_subterms en d base)
        in
        (* One finding per decision. Several occurrences may each be individually
           removable (`a && b && a` -- either `a` can go, not both); listing them
           as alternatives is the honest report, emitting one finding each is
           noise. *)
        (match deads with
        | [] -> ()
        | _ ->
            let alts =
              List.map (fun (_, sub) -> snippet_of atoms (occs_of sub)) deads
            in
            mk "DEAD_SUBTERM"
              (Printf.sprintf
                 "%d removable subterm(s); removing any ONE leaves the decision \
                  logically identical"
                 (List.length deads))
              (String.concat "  |ALT|  " alts)) ;
        (* 3. path-sensitive: is the decision settled by its enclosing guards? *)
        if gs <> [] && deads = [] then begin
          let p = List.fold_left (fun acc g -> BAnd (acc, g)) BTrue gs in
          let pv = vars_of en (BAnd (p, d)) in
          match
            ( truth_vector_over en pv p,
              truth_vector_over en pv (BAnd (p, d)),
              truth_vector_over en pv (BAnd (p, BNot d)) )
          with
          | Some tp, Some tpd, Some tpnd ->
              let sat v = Array.exists (fun x -> x) v in
              if not (sat tp) then
                mk "UNREACHABLE_PATH"
                  "the guards leading here are mutually contradictory" ""
              else if not (sat tpnd) then
                mk "IMPLIED_TRUE"
                  "decision is already guaranteed by an enclosing guard"
                  (String.concat " && " guard_srcs)
              else if not (sat tpd) then
                mk "IMPLIED_FALSE"
                  "decision is already excluded by an enclosing guard"
                  (String.concat " && " guard_srcs)
          | _ -> ()
        end ;
        (* 4. SMT escalation (§6.5 tier 1 -> tier 2). Only for decisions the
           enumeration tier could not settle AND whose atoms carry real
           relational content -- when every atom is an opaque boolean the solver
           can prove nothing enumeration did not already. *)
        if deads = [] && !findings_before = List.length !findings then
          smt_escalate ~mk ~atoms ~d ~gs
      end

(* Parsetree wrapper. *)
let analyse_decision ~file ~form ~(loc : Location.t) (cond : expression)
    (guards : expression list) =
  let b = new_builder () in
  let d = build b cond in
  let gs = List.map (fun g -> build b g) guards in
  analyse_built ~file ~form
    ~line:loc.loc_start.pos_lnum
    ~col:(loc.loc_start.pos_cnum - loc.loc_start.pos_bol + 1)
    ~src:(print_expr cond)
    ~guard_srcs:(List.map print_expr guards)
    b d gs

(* -------------------------------------------------------------------------- *)
(* Structural sibling check: identical arms                                    *)
(* -------------------------------------------------------------------------- *)

let strip_locs_eq (a : expression) (b : expression) = print_expr a = print_expr b

(* -------------------------------------------------------------------------- *)
(* Walker                                                                      *)
(* -------------------------------------------------------------------------- *)

let neg (e : expression) =
  let loc = e.pexp_loc in
  {
    e with
    pexp_desc =
      Pexp_apply
        ( {
            e with
            pexp_desc = Pexp_ident {txt = Longident.Lident "not"; loc};
            pexp_attributes = [];
          },
          [(Nolabel, e)] );
    pexp_attributes = [];
  }

(* Every simple name a guard expression mentions. A guard is only valid while
   the names in it still denote what they denoted when it was pushed. *)
let free_names (e : expression) =
  let acc = ref [] in
  let open Ast_iterator in
  let it =
    {
      default_iterator with
      expr =
        (fun self (x : expression) ->
          (match x.pexp_desc with
          | Pexp_ident {txt = Longident.Lident n; _} -> acc := n :: !acc
          | _ -> ()) ;
          default_iterator.expr self x);
    }
  in
  it.expr it e ;
  !acc

(* Save/restore the alias bindings a scope shadows. Any binder that is not an
   alias-shaped `let` simply removes the name: losing an alias is harmless,
   keeping one across a shadow would be a false positive.

   Removing the rebound NAMES is not enough — the RHS side matters too:

     let x = y in     (* alias_env[x] = y *)
     let y = 5 in     (* removes `y`, but x ↦ y survives; then alias_env[y] = 5 *)
     if x > 0 then …  (* resolve_aliases chases the CURRENT env: x → y → 5,
                         so a live decision reads as `if 5 > 0` — CONSTANT_TRUE *)

   The stored RHS was captured under the OLD meaning of every name it mentions, so
   rebinding any of them invalidates it. Same invariant `guarded_scope` already
   enforces for path guards, via the same `free_names`: a fact is only valid while
   the names in it still denote what they denoted when it was recorded. Without the
   chase it merges instead: `let x = y in let y = f () in x && y` printed both atoms
   to the key "y" and reported one as removable.

   Dropping the dependents costs recall on the rare alias that would still have been
   valid; keeping one produces a "delete this" verdict about live code. *)
let scoped names f =
  let dependents =
    Hashtbl.fold
      (fun k rhs acc ->
        if List.mem k names then acc
        else if List.exists (fun n -> List.mem n names) (free_names rhs) then k :: acc
        else acc)
      alias_env []
  in
  let names = names @ dependents in
  let saved = List.map (fun n -> (n, Hashtbl.find_opt alias_env n)) names in
  List.iter (fun n -> Hashtbl.remove alias_env n) names ;
  Fun.protect
    ~finally:(fun () ->
      List.iter
        (fun (n, v) ->
          match v with
          | Some e -> Hashtbl.replace alias_env n e
          | None -> Hashtbl.remove alias_env n)
        saved)
    f

let param_names (ps : function_param list) =
  List.fold_left
    (fun acc (p : function_param) ->
      match p.pparam_desc with
      | Pparam_val (_, _, pat) -> pattern_names pat acc
      | Pparam_newtype _ -> acc)
    [] ps

let walk_file file (str : structure) =
  (* Path condition (§6.2): the conditions holding on EVERY path to the current
     point. Syntactic form of the dominator chain -- enclosing if/else branches
     and `when` guards. Under-approximating the true path condition is the sound
     direction: omitting a fact can only make a proof harder, never wrong. *)
  let guards : expression list ref = ref [] in
  let seen_conditions : (int * int, unit) Hashtbl.t = Hashtbl.create 64 in
  let mark (e : expression) =
    Hashtbl.replace seen_conditions
      (e.pexp_loc.loc_start.pos_cnum, e.pexp_loc.loc_end.pos_cnum) ()
  in
  (* Mark the whole boolean skeleton, not just the root: otherwise every nested
     `&&`/`||` of an already-analysed condition is re-reported as its own
     decision, and one 11-condition guard yields five overlapping findings. *)
  let rec mark_deep (e : expression) =
    mark e ;
    match e.pexp_desc with
    | Pexp_apply (f, [(Nolabel, l); (Nolabel, r)])
      when is_op f ["&&"; "&"] || is_op f ["||"; "or"] ->
        mark_deep l ;
        mark_deep r
    | Pexp_apply (f, [(Nolabel, a)]) when is_op f ["not"] -> mark_deep a
    | Pexp_constraint (a, _) -> mark_deep a
    | _ -> ()
  in
  let is_marked (e : expression) =
    Hashtbl.mem seen_conditions
      (e.pexp_loc.loc_start.pos_cnum, e.pexp_loc.loc_end.pos_cnum)
  in
  (* A guard survives only while the names it mentions still denote the same
     thing. `let c = compare a b in if c <> 0 then c else let c = compare x y in
     if c <> 0 then ...` rebinds `c`: the outer guard says nothing about the
     inner one, and keeping it proves a live branch dead. This is the single
     most common OCaml idiom there is, and it accounted for 97 of 117 findings
     on a 3.3M-line corpus before this fix. The Typedtree frontend is immune by
     construction — Ident stamps distinguish the two `c`s — which is exactly
     what the stamp-based design was for. *)
  let guarded_scope names f =
    let saved = !guards in
    guards :=
      List.filter
        (fun g -> not (List.exists (fun n -> List.mem n names) (free_names g)))
        !guards ;
    Fun.protect ~finally:(fun () -> guards := saved) f
  in
  (* Reaching arm i means every earlier arm failed. When an earlier arm's pattern
     is IRREFUTABLE (a variable or `_`), the only possible reason is its guard,
     so `not guard` holds from arm i on. A refutable pattern teaches us nothing
     about its guard and is simply skipped -- facts from other irrefutable arms
     still stand. This is what makes
     `| m when m > 100 -> .. | m when m > 5 -> ..` decidable. *)
  let rec is_irrefutable (p : pattern) =
    match p.ppat_desc with
    | Ppat_any | Ppat_var _ -> true
    | Ppat_constraint (q, _) | Ppat_alias (q, _) -> is_irrefutable q
    | _ -> false
  in
  Hashtbl.reset alias_env ;
  let open Ast_iterator in
  let it = ref default_iterator in
  let walk_cases self (cases : case list) =
    let acc = ref [] in
    List.iter
      (fun (c : case) ->
        let pns = pattern_names c.pc_lhs [] in
        let entry =
          List.filter
            (fun g -> not (List.exists (fun n -> List.mem n pns) (free_names g)))
            (!acc @ !guards)
        in
        let saved = !guards in
        scoped pns @@ fun () ->
        (match c.pc_guard with
        | Some g ->
            mark_deep g ;
            analyse_decision ~file ~form:"when" ~loc:g.pexp_loc g entry ;
            guards := entry ;
            self.expr self g ;
            guards := g :: entry ;
            self.expr self c.pc_rhs
        | None ->
            guards := entry ;
            self.expr self c.pc_rhs) ;
        guards := saved ;
        self.pat self c.pc_lhs ;
        match (c.pc_guard, is_irrefutable c.pc_lhs) with
        | Some g, true -> acc := neg g :: !acc
        | _ -> ())
      cases
  in
  let expr self (e : expression) =
    match e.pexp_desc with
    | Pexp_ifthenelse (c, t, f) ->
        mark_deep c ;
        analyse_decision ~file ~form:"if" ~loc:e.pexp_loc c !guards ;
        (match f with
        | Some fe when strip_locs_eq t fe ->
            emit
              {
                f_kind = "IDENTICAL_ARMS";
                f_file = file;
                f_line = e.pexp_loc.loc_start.pos_lnum;
                f_col = e.pexp_loc.loc_start.pos_cnum - e.pexp_loc.loc_start.pos_bol + 1;
                f_form = "if";
                f_arity =
                  arity_at file e.pexp_loc.loc_start.pos_lnum
                    (e.pexp_loc.loc_start.pos_cnum - e.pexp_loc.loc_start.pos_bol + 1);
                f_detail = "both branches are structurally identical";
                f_snippet = print_expr c;
                f_evidence = "";
              }
        | _ -> ()) ;
        self.expr self c ;
        guards := c :: !guards ;
        self.expr self t ;
        guards := List.tl !guards ;
        (match f with
        | Some fe ->
            guards := neg c :: !guards ;
            self.expr self fe ;
            guards := List.tl !guards
        | None -> ())
    | Pexp_while (c, body) ->
        mark_deep c ;
        (* `while true do ... done` is the idiomatic OCaml unbounded loop, left
           by an exception. Flagging it as a constant decision is a false
           positive, and a lint with false positives does not get used. *)
        (match c.pexp_desc with
        | Pexp_construct ({txt = Lident "true"; _}, None) -> ()
        | _ -> analyse_decision ~file ~form:"while" ~loc:e.pexp_loc c !guards) ;
        self.expr self c ;
        self.expr self body
    | Pexp_assert a -> (
        match a.pexp_desc with
        | Pexp_construct ({txt = Lident "false"; _}, None) -> ()
        | _ ->
            mark_deep a ;
            analyse_decision ~file ~form:"assert" ~loc:e.pexp_loc a !guards ;
            self.expr self a)
    | Pexp_match (scrut, cases) ->
        self.expr self scrut ;
        walk_cases self cases
    | Pexp_try (body, cases) ->
        self.expr self body ;
        walk_cases self cases
    | Pexp_function (params, _, Pfunction_cases (cases, _, _)) ->
        let ns = param_names params in
        scoped ns @@ fun () -> guarded_scope ns @@ fun () -> walk_cases self cases
    | Pexp_let (rf, vbs, body) ->
        List.iter (fun (vb : value_binding) -> self.expr self vb.pvb_expr) vbs ;
        let names =
          List.fold_left (fun a (vb : value_binding) -> pattern_names vb.pvb_pat a) [] vbs
        in
        scoped names @@ fun () ->
        guarded_scope names @@ fun () ->
        (* An alias-shaped binding — `let n = <stable expr>`, non-recursive,
           name bound exactly once in the file — is recorded; every other
           binding leaves the name unbound (already done by [scoped]). *)
        if rf = Nonrecursive then
          List.iter
            (fun (vb : value_binding) ->
              match vb.pvb_pat.ppat_desc with
              | Ppat_var {txt; _} when is_stable vb.pvb_expr ->
                  Hashtbl.replace alias_env txt (resolve_aliases vb.pvb_expr)
              | _ -> ())
            vbs ;
        self.expr self body
    | Pexp_function (params, _, Pfunction_body body) ->
        let ns = param_names params in
        scoped ns @@ fun () -> guarded_scope ns @@ fun () -> self.expr self body
    | Pexp_open (_, body) | Pexp_letmodule (_, _, body) ->
        (* An `open M` can rebind a value name to `M.<name>` without any pattern
           for the scope walk to see. The only safe response is to drop every
           alias currently in scope. *)
        let live = Hashtbl.fold (fun k _ acc -> k :: acc) alias_env [] in
        scoped live @@ fun () -> self.expr self body
    | Pexp_object _ ->
        (* An object body binds its `val` names for every method, and `inherit` brings in more
           that no pattern in this file shows. Neither is a pattern the scope walk sees, so an
           outer alias survived into the body and a method reading the instance variable `a` was
           resolved to whatever `let a = …` said outside — a false "removable subterm", i.e. a
           verdict telling someone to delete live code. Same response as `open`: drop everything
           in scope. (The Typedtree frontend is immune; it keys on Ident stamps.) *)
        let live = Hashtbl.fold (fun k _ acc -> k :: acc) alias_env [] in
        scoped live @@ fun () -> default_iterator.expr self e
    | Pexp_for (pat, lo, hi, _, body) ->
        self.expr self lo ;
        self.expr self hi ;
        let ns = pattern_names pat [] in
        scoped ns @@ fun () -> guarded_scope ns @@ fun () -> self.expr self body
    | Pexp_letop {let_; ands; body; _} ->
        self.expr self let_.pbop_exp ;
        List.iter (fun (b : binding_op) -> self.expr self b.pbop_exp) ands ;
        let names =
          List.fold_left
            (fun a (b : binding_op) -> pattern_names b.pbop_pat a)
            (pattern_names let_.pbop_pat [])
            ands
        in
        scoped names @@ fun () -> guarded_scope names @@ fun () -> self.expr self body
    | Pexp_apply (f, [(Nolabel, _); (Nolabel, _)])
      when (is_op f ["&&"; "&"] || is_op f ["||"; "or"]) && not (is_marked e) ->
        (* A short-circuit expression outside a decision position is still a
           branch: a redundant conjunct there is exactly as dead. *)
        mark_deep e ;
        analyse_decision ~file ~form:"boolexpr" ~loc:e.pexp_loc e !guards ;
        default_iterator.expr self e
    | _ -> default_iterator.expr self e
  in
  it := {default_iterator with expr} ;
  List.iter (fun si -> !it.structure_item !it si) str

(* ========================================================================== *)
(* Typedtree frontend (.cmt)                                                  *)
(* ========================================================================== *)

(* Everything downstream — canonical merging, the enumeration engine, the SMT
   encoder — consumes the neutral IR, so this frontend only has to lower a
   Typedtree the way the Parsetree one lowers a Parsetree. What it buys:

   - RUNG 1 BECOMES SOUND. Aliases are keyed by [Ident.unique_name], a stamp
     fresh per binder, so shadowing cannot merge two different values. The
     Parsetree frontend approximates this with a lexical environment and has to
     drop aliases defensively on `open`; here the question does not arise.
   - THE ALLOWLIST BECOMES SHADOW-PROOF. Heads are resolved [Path]s, so a local
     `let trim = ...` resolves elsewhere and simply is not matched — the same
     Path-based rule arch-index uses for noreturn heads.
   - It is also the frontend a purity join needs: a resolved Path is what you
     look up in `v_pure_functions`. That step is not taken here. *)

module Tt = struct
  open Typedtree

  (* CANONICAL key: a LOCAL identifier must carry its Ident stamp, or two
     distinct binders that happen to share a name merge — and the compare-chain
     idiom (`let c = … in if c <> 0 … let c = … in if c <> 0 …`) then proves a
     live branch dead. The stamps were already used for aliases; not using them
     here was the same scoping bug the Parsetree frontend had, and the claim
     that this frontend was "immune by construction" was wrong. *)
  let path_name p =
    match p with Path.Pident id -> Ident.unique_name id | _ -> Path.name p



  (* Operator/allowlist matching needs the RESOLVED path, not the stamped key. *)
  let head_path (e : expression) =
    match e.exp_desc with Texp_ident (p, _, _) -> Some (Path.name p) | _ -> None

  (* A resolved path ends with the name, so compare on the tail: the allowlist
     entry `String.trim` must match `Stdlib.String.trim`. *)
  let path_matches full short =
    let lf = String.length full and ls = String.length short in
    (* [full = short], NOT [lf = ls]: an earlier version compared only the
       LENGTHS, so `Stdlib.=` matched `Stdlib.&` and every equality was
       decomposed as a conjunction. That turned each operand into its own atom
       and produced a flood of false DEAD_SUBTERMs. *)
    full = short
    || (lf > ls && String.sub full (lf - ls) ls = short && full.[lf - ls - 1] = '.')

  let is_allowlisted p = List.exists (path_matches p) pure_allowlist

  let is_op_path p names =
    List.exists (fun n -> p = n || path_matches p ("Stdlib." ^ n)) names

  let args_exprs args = List.filter_map (fun (_, a) -> a) args

  let rec t_is_stable (e : expression) =
    match e.exp_desc with
    | Texp_ident _ | Texp_constant _ -> true
    | Texp_construct (_, _, l) | Texp_tuple l -> List.for_all t_is_stable l
    | Texp_field (a, _, _) -> t_is_stable a
    | Texp_variant (_, a) -> ( match a with Some x -> t_is_stable x | None -> true)
    | Texp_apply (f, args) -> (
        match head_path f with
        | Some p ->
            (* The head must be pure; the ARGUMENTS must independently be
               stable. `f !r` is unstable however pure `f` is, so the recursion
               below is unchanged — only the head test gained a source. *)
            (is_op_path p comparison_ops || is_op_path p arith_ops
           || is_op_path p ["not"] || is_allowlisted p || is_pure_fn p)
            && List.for_all t_is_stable (args_exprs args)
        | None -> false)
    | _ -> false

  (* Canonical text. Types are erased — only the value shape matters for
     merging. An unmodelled node is keyed on its own location, so it can never
     collide with a different expression. *)
  let print_e (e : expression) =
    let b = Buffer.create 64 in
    let rec go (e : expression) =
      match e.exp_desc with
      | Texp_ident (p, _, _) -> Buffer.add_string b (path_name p)
      | Texp_constant c -> (
          match c with
          | Const_int i -> Buffer.add_string b (string_of_int i)
          | Const_char c -> Buffer.add_string b (Printf.sprintf "%C" c)
          | Const_string (str, _, _) -> Buffer.add_string b (Printf.sprintf "%S" str)
          | Const_float f -> Buffer.add_string b f
          | Const_int32 i -> Buffer.add_string b (Int32.to_string i)
          | Const_int64 i -> Buffer.add_string b (Int64.to_string i)
          | Const_nativeint i -> Buffer.add_string b (Nativeint.to_string i))
      | Texp_construct (_, cd, l) ->
          Buffer.add_string b cd.cstr_name ;
          if l <> [] then begin
            Buffer.add_char b '(' ;
            List.iteri (fun i x -> if i > 0 then Buffer.add_char b ',' ; go x) l ;
            Buffer.add_char b ')'
          end
      | Texp_field (a, _, ld) ->
          go a ; Buffer.add_char b '.' ; Buffer.add_string b ld.lbl_name
      | Texp_tuple l ->
          Buffer.add_char b '(' ;
          List.iteri (fun i x -> if i > 0 then Buffer.add_char b ',' ; go x) l ;
          Buffer.add_char b ')'
      | Texp_apply (f, args) ->
          Buffer.add_char b '(' ;
          go f ;
          List.iter (fun x -> Buffer.add_char b ' ' ; go x) (args_exprs args) ;
          Buffer.add_char b ')'
      | _ ->
          Buffer.add_string b
            (Printf.sprintf "<@%d:%d>" e.exp_loc.loc_start.pos_lnum
               e.exp_loc.loc_start.pos_cnum)
    in
    go e ; Buffer.contents b

  let t_int_literal (e : expression) =
    match e.exp_desc with
    | Texp_constant (Const_int i) -> Some i
    | Texp_constant (Const_char c) -> Some (Char.code c)
    | _ -> None

  let cmp_of_path p =
    List.find_opt (fun o -> is_op_path p [o]) ["="; "<>"; "<="; ">="; "<"; ">"]

  let t_as_relational (e : expression) =
    match e.exp_desc with
    | Texp_apply (f, args) -> (
        match (head_path f, args_exprs args) with
        | Some p, [l; r] -> (
            match cmp_of_path p with
            | Some op -> (
                match (t_int_literal l, t_int_literal r) with
                | None, Some k when t_is_stable l ->
                    Some {r_subject = print_e l; r_op = op; r_const = k}
                | Some k, None when t_is_stable r ->
                    Some {r_subject = print_e r; r_op = flip_op op; r_const = k}
                | _ -> None)
            | None -> None)
        | _ -> None)
    | _ -> None

  let bool_lit (e : expression) =
    match e.exp_desc with
    | Texp_construct (_, cd, []) when cd.cstr_name = "true" -> Some true
    | Texp_construct (_, cd, []) when cd.cstr_name = "false" -> Some false
    | _ -> None

  let rec canon (e : expression) : string * bool =
    match e.exp_desc with
    | Texp_apply (f, args) -> (
        match (head_path f, args_exprs args) with
        | Some p, [l; r] -> (
            match cmp_of_path p with
            | Some (("=" | "<>") as op) -> (
                match (bool_lit l, bool_lit r) with
                | Some bv, None ->
                    let k, n = canon r in
                    (k, if op = "=" then n <> not bv else n <> bv)
                | None, Some bv ->
                    let k, n = canon l in
                    (k, if op = "=" then n <> not bv else n <> bv)
                | _ ->
                    let sl = print_e l and sr = print_e r in
                    let a, b = if sl <= sr then (sl, sr) else (sr, sl) in
                    (Printf.sprintf "%s %s %s" a op b, false))
            | Some (("<" | "<=" | ">" | ">=") as op) -> (
                match t_as_relational e with
                | Some r -> (rel_key r, false)
                | None ->
                    let sl = print_e l and sr = print_e r in
                    if sl <= sr then (Printf.sprintf "%s %s %s" sl op sr, false)
                    else (Printf.sprintf "%s %s %s" sr (flip_op op) sl, false))
            | _ -> (print_e e, false))
        | _ -> (print_e e, false))
    | _ -> (
        match t_as_relational e with
        | Some r -> (rel_key r, false)
        | None -> (print_e e, false))

  let rec is_closed_lit (e : expression) =
    match e.exp_desc with
    | Texp_constant _ -> true
    | Texp_construct (_, _, l) | Texp_tuple l -> List.for_all is_closed_lit l
    | _ -> false

  let rec lower_term (e : expression) : sterm =
    match t_int_literal e with
    | Some k -> TConst k
    | None -> (
        match e.exp_desc with
        | Texp_apply (f, args) -> (
            let xs = args_exprs args in
            match (head_path f, xs) with
            | Some p, [l; r] when is_op_path p ["+"] -> TAdd (lower_term l, lower_term r)
            | Some p, [l; r] when is_op_path p ["-"] -> TSub (lower_term l, lower_term r)
            | Some p, [l; r] when is_op_path p ["*"] -> TMul (lower_term l, lower_term r)
            | Some p, [_] when List.exists (path_matches p) length_fns -> TLen (print_e e)
            | _ -> fallback e)
        | _ -> fallback e)

  and fallback e =
    if is_closed_lit e then TLit (print_e e)
    else if t_is_stable e then TVar (print_e e)
    else TFresh (print_e e)

  (* The typed frontend can do this properly: §6.3 declines floats because NaN
     breaks the identities one reflexively assumes (`x <> x` is satisfiable,
     `not (x < y)` is not `x >= y`). Only the Typedtree knows an expression is a
     float. *)
  let is_float (e : expression) =
    match Types.get_desc e.exp_type with
    | Types.Tconstr (p, _, _) ->
        let n = Path.name p in
        n = "float" || n = "Stdlib.float"
    | _ -> false

  let lower_atom (e : expression) : satom =
    match e.exp_desc with
    | Texp_apply (f, args) -> (
        match (head_path f, args_exprs args) with
        | Some p, [l; r] when is_float l || is_float r ->
            ignore p ; AOpaque (* float comparison: declined, per §6.3 *)
        | Some p, [l; r] -> (
            match cmp_of_path p with
            | Some op when print_e l = print_e r && (op = "=" || op = "<>") ->
                AOpaque (* self-comparison: the NaN shape *)
            | Some op -> ARel (op, lower_term l, lower_term r)
            | None -> AOpaque)
        | _ -> AOpaque)
    | _ -> AOpaque

  (* --- decision extraction over the Typedtree --------------------------- *)

  (* Rung 1, the SOUND version: keyed by [Ident.unique_name], a stamp that is
     fresh per binder. Shadowing therefore creates a NEW key and can never merge
     two different values — so unlike the Parsetree frontend there is nothing to
     unbind, and `open` is a non-issue. This is exactly the property
     specs/cfg-postdom-dominance.md C-12 relies on. *)
  let aliases : (string, expression) Hashtbl.t = Hashtbl.create 256

  (* Must recurse into subexpressions, not just the head: `let limit = n in
     limit > 5` needs the alias replaced INSIDE the comparison for it to share a
     key with `n > 5`. *)
  let rec resolve ?(depth = 0) (e : expression) =
    if depth > 4 then e
    else
      match e.exp_desc with
      | Texp_ident (Path.Pident id, _, _) -> (
          match Hashtbl.find_opt aliases (Ident.unique_name id) with
          | Some rhs -> resolve ~depth:(depth + 1) rhs
          | None -> e)
      | Texp_apply (f, args) ->
          {
            e with
            exp_desc =
              Texp_apply
                ( resolve ~depth f,
                  List.map (fun (l, a) -> (l, Option.map (resolve ~depth) a)) args );
          }
      | Texp_field (a, l, d) -> {e with exp_desc = Texp_field (resolve ~depth a, l, d)}
      | Texp_tuple l -> {e with exp_desc = Texp_tuple (List.map (resolve ~depth) l)}
      | _ -> e

  let t_add_atom (b : builder) (e0 : expression) =
    let e = resolve e0 in
    let key, negated = canon e in
    let stable = t_is_stable e in
    let key =
      if stable then key
      else begin
        b.fresh <- b.fresh + 1 ;
        Printf.sprintf "#unstable%d#%s" b.fresh key
      end
    in
    let loc = e0.exp_loc in
    let a =
      {
        a_key = key;
        a_stable = stable;
        a_rel = (if stable then t_as_relational e else None);
        a_line = loc.loc_start.pos_lnum;
        a_col = loc.loc_start.pos_cnum - loc.loc_start.pos_bol + 1;
        a_src =
          (* The canonical key carries Ident stamps (`m_317`) so distinct
             binders never merge; the REPORT must not show them. *)
          (let strip t =
             let b = Buffer.create (String.length t) in
             let n = String.length t in
             let i = ref 0 in
             while !i < n do
               if
                 t.[!i] = '_'
                 && !i + 1 < n
                 && t.[!i + 1] >= '0'
                 && t.[!i + 1] <= '9'
               then begin
                 incr i ;
                 while !i < n && t.[!i] >= '0' && t.[!i] <= '9' do
                   incr i
                 done
               end
               else begin
                 Buffer.add_char b t.[!i] ;
                 incr i
               end
             done ;
             Buffer.contents b
           in
           let w = strip (print_e e0) and r = strip (print_e e) in
           if w = r then w else Printf.sprintf "%s [= %s]" w r);
        a_term = lower_atom e;
      }
    in
    let id = b.natoms in
    b.atoms <- a :: b.atoms ;
    b.natoms <- b.natoms + 1 ;
    if negated then BNot (BOcc id) else BOcc id

  let rec t_build b (e : expression) : bexp =
    match e.exp_desc with
    | Texp_construct (_, cd, []) when cd.cstr_name = "true" -> BTrue
    | Texp_construct (_, cd, []) when cd.cstr_name = "false" -> BFalse
    | Texp_apply (f, args) -> (
        match (head_path f, args_exprs args) with
        | Some p, [l; r] when is_op_path p ["&&"; "&"] -> BAnd (t_build b l, t_build b r)
        | Some p, [l; r] when is_op_path p ["||"; "or"] -> BOr (t_build b l, t_build b r)
        | Some p, [a] when is_op_path p ["not"] -> (
            match t_build b a with BNot x -> x | x -> BNot x)
        | _ -> t_add_atom b e)
    | _ -> t_add_atom b e

  (* Guards carry a POLARITY rather than a synthesised `not` node: building a
     Typedtree application of Stdlib.not would need a value_description we do
     not have, and the polarity is all the engine needs. *)
  let t_analyse ~file ~form ~(loc : Location.t) (cond : expression)
      (guards : (expression * bool) list) =
    let b = new_builder () in
    let d = t_build b cond in
    let gs =
      List.map (fun (g, neg) -> if neg then BNot (t_build b g) else t_build b g) guards
    in
    analyse_built ~file ~form
      ~line:loc.loc_start.pos_lnum
      ~col:(loc.loc_start.pos_cnum - loc.loc_start.pos_bol + 1)
      ~src:(print_e cond)
      ~guard_srcs:
        (List.map
           (fun (g, neg) ->
             if neg then "not (" ^ print_e g ^ ")" else print_e g)
           guards)
      b d gs

  let walk_structure file (str : structure) =
    let guards : (expression * bool) list ref = ref [] in
    let seen : (int * int, unit) Hashtbl.t = Hashtbl.create 64 in
    let rec mark_deep (e : expression) =
      Hashtbl.replace seen (e.exp_loc.loc_start.pos_cnum, e.exp_loc.loc_end.pos_cnum) () ;
      match e.exp_desc with
      | Texp_apply (f, args) -> (
          match (head_path f, args_exprs args) with
          | Some p, [l; r] when is_op_path p ["&&"; "&"; "||"; "or"] ->
              mark_deep l ; mark_deep r
          | Some p, [a] when is_op_path p ["not"] -> mark_deep a
          | _ -> ())
      | _ -> ()
    in
    let is_marked (e : expression) =
      Hashtbl.mem seen (e.exp_loc.loc_start.pos_cnum, e.exp_loc.loc_end.pos_cnum)
    in
    let open Tast_iterator in
    let it = ref default_iterator in
    let expr self (e : expression) =
      match e.exp_desc with
      | Texp_ifthenelse (c, t, f) ->
          mark_deep c ;
          t_analyse ~file ~form:"if" ~loc:e.exp_loc c !guards ;
          (match f with
          | Some fe when print_e t = print_e fe ->
              emit
                {
                  f_kind = "IDENTICAL_ARMS";
                  f_file = file;
                  f_line = e.exp_loc.loc_start.pos_lnum;
                  f_col = e.exp_loc.loc_start.pos_cnum - e.exp_loc.loc_start.pos_bol + 1;
                  f_form = "if";
                  f_arity =
                    arity_at file e.exp_loc.loc_start.pos_lnum
                      (e.exp_loc.loc_start.pos_cnum - e.exp_loc.loc_start.pos_bol + 1);
                  f_detail = "both branches are structurally identical";
                  f_snippet = print_e c;
                  f_evidence = "";
                }
          | _ -> ()) ;
          self.expr self c ;
          guards := (c, false) :: !guards ;
          self.expr self t ;
          guards := List.tl !guards ;
          (match f with
          | Some fe ->
              guards := (c, true) :: !guards ;
              self.expr self fe ;
              guards := List.tl !guards
          | None -> ())
      | Texp_while (c, body) ->
          mark_deep c ;
          (match c.exp_desc with
          | Texp_construct (_, cd, []) when cd.cstr_name = "true" -> ()
          | _ -> t_analyse ~file ~form:"while" ~loc:e.exp_loc c !guards) ;
          self.expr self c ;
          self.expr self body
      | Texp_assert (a, _) -> (
          match a.exp_desc with
          | Texp_construct (_, cd, []) when cd.cstr_name = "false" -> ()
          | _ ->
              mark_deep a ;
              t_analyse ~file ~form:"assert" ~loc:e.exp_loc a !guards ;
              self.expr self a)
      | Texp_let (Nonrecursive, vbs, body) ->
          List.iter (fun (vb : value_binding) -> self.expr self vb.vb_expr) vbs ;
          List.iter
            (fun (vb : value_binding) ->
              match vb.vb_pat.pat_desc with
              | Tpat_var (id, _, _) when t_is_stable vb.vb_expr ->
                  Hashtbl.replace aliases (Ident.unique_name id) (resolve vb.vb_expr)
              | _ -> ())
            vbs ;
          self.expr self body
      | Texp_apply (f, args)
        when (match (head_path f, args_exprs args) with
             | Some p, [_; _] -> is_op_path p ["&&"; "&"; "||"; "or"]
             | _ -> false)
             && not (is_marked e) ->
          mark_deep e ;
          t_analyse ~file ~form:"boolexpr" ~loc:e.exp_loc e !guards ;
          default_iterator.expr self e
      | _ -> default_iterator.expr self e
    in
    (* Reaching arm i means every earlier arm failed. When an earlier pattern is
       IRREFUTABLE the only possible reason is its guard, so `not guard` holds
       from arm i on — the same rule as the Parsetree walker, and what makes
       `| m when m > 5 -> .. | m when m > 100 -> ..` decidable. *)
    (* A COMPUTATION pattern wraps its value pattern in [Tpat_value], so
       matching [Tpat_var] directly misses every `match` arm — only `function`
       arms would have been recognised. *)
    let rec is_irrefutable : type k. k general_pattern -> bool =
     fun p ->
      match p.pat_desc with
      | Tpat_any | Tpat_var _ -> true
      | Tpat_alias (q, _, _, _) -> is_irrefutable q
      | Tpat_value vp -> is_irrefutable (vp :> value general_pattern)
      | _ -> false
    in
    let walk_cases : type k. Tast_iterator.iterator -> k case list -> unit =
     fun self cases ->
      let acc = ref [] in
      List.iter
        (fun (c : k case) ->
          let entry = !acc @ !guards in
          let saved = !guards in
          (match c.c_guard with
          | Some g ->
              mark_deep g ;
              t_analyse ~file ~form:"when" ~loc:g.exp_loc g entry ;
              guards := entry ;
              self.expr self g ;
              guards := (g, false) :: entry ;
              self.expr self c.c_rhs
          | None ->
              guards := entry ;
              self.expr self c.c_rhs) ;
          guards := saved ;
          self.pat self c.c_lhs ;
          match (c.c_guard, is_irrefutable c.c_lhs) with
          | Some g, true -> acc := (g, true) :: !acc
          | _ -> ())
        cases
    in
    let expr self (e : expression) =
      match e.exp_desc with
      | Texp_match (scrut, cc, vc, _) ->
          self.expr self scrut ;
          (* SCRUTINEE ALIASING. Every arm filters the SAME scrutinee, so an arm
             whose pattern is a bare variable binds a name that IS the
             scrutinee. Recording that alias is what lets a subsumed `when`
             cascade be related SOUNDLY — by scrutinee identity rather than by
             the name coincidence that produced 97 false positives on Octez.
             Only a bare variable qualifies: a constructor pattern binds a PART
             of the scrutinee, not the scrutinee. *)
          let bind_scrutinee : type k. k case list -> unit =
           fun cases ->
            if t_is_stable scrut then
              List.iter
                (fun (c : k case) ->
                  let rec bare : type j. j general_pattern -> Ident.t option =
                   fun p ->
                    match p.pat_desc with
                    | Tpat_var (id, _, _) -> Some id
                    | Tpat_value vp -> bare (vp :> value general_pattern)
                    | _ -> None
                  in
                  match bare c.c_lhs with
                  | Some id -> Hashtbl.replace aliases (Ident.unique_name id) (resolve scrut)
                  | None -> ())
                cases
          in
          bind_scrutinee cc ;
          bind_scrutinee vc ;
          walk_cases self cc ;
          walk_cases self vc
      | Texp_try (body, vc, ec) ->
          self.expr self body ;
          walk_cases self vc ;
          walk_cases self ec
      | Texp_function (_, Tfunction_cases {cases; _}) -> walk_cases self cases
      | _ -> expr self e
    in
    it := {default_iterator with expr} ;
    List.iter (fun si -> !it.structure_item !it si) str.str_items

  let run_cmt path =
    match Cmt_format.read path with
    | _, Some info -> (
        match info.cmt_annots with
        | Implementation str ->
            let file =
              match info.cmt_sourcefile with Some f -> f | None -> path
            in
            Hashtbl.reset aliases ;
            incr n_files ;
            (try walk_structure file str with _ -> incr n_walk_fail)
        | _ -> ())
    | _ -> ()
    | exception _ -> incr n_parse_fail

end


(* -------------------------------------------------------------------------- *)
(* Driver                                                                      *)
(* -------------------------------------------------------------------------- *)

(* -------------------------------------------------------------------------- *)
(* Mutation census                                                            *)
(* -------------------------------------------------------------------------- *)

(* A deref is unstable only because a MUTATION could occur. Counting the writes,
   not just the reads, tells us two things a deref count cannot:
     - mutation density is the honest maintainability metric (writes are what
       makes reasoning hard; reads are only a symptom);
     - a ref that is never assigned after its binding is EFFECTIVELY IMMUTABLE,
       so `!r` on it is stable and could be merged — recall left on the table by
       the current all-derefs-are-unstable rule.

   THE SECOND CLAIM NEEDS ESCAPE ANALYSIS, and an earlier version did not have it:
   it counted only syntactic `:=` / `incr` / `decr` targets, so a ref handed to a
   FUNCTION read as never-assigned. `let db = ref "" in Arg.parse [("--db",
   Arg.Set_string db, …)]` is the canonical case — the stdlib writes it through a
   closure and no `:=` appears anywhere. Treating that as immutable would license
   exactly the unsound merge this metric is meant to enable.

   So a ref counts as possibly-assigned when it is ASSIGNED **or** when it ESCAPES:
   any occurrence of the name that is not the operand of `!` hands the cell to code
   this analysis cannot see. That is deliberately conservative — "abstract by
   freeness, never by assumption" — and it makes `never_assigned` mean what it says
   rather than "no `:=` was visible from here". *)

let mutation_kinds : (string, int) Hashtbl.t = Hashtbl.create 16
let ref_bindings : (string, int) Hashtbl.t = Hashtbl.create 256 (* name -> count *)
let assigned_names : (string, int) Hashtbl.t = Hashtbl.create 256
let escaped_names : (string, int) Hashtbl.t = Hashtbl.create 256
let n_mut_sites = ref 0

let bump_h h k = Hashtbl.replace h k (1 + Option.value ~default:0 (Hashtbl.find_opt h k))

let mutation_census (str : structure) =
  let open Ast_iterator in
  let note_kind k = incr n_mut_sites ; bump_h mutation_kinds k in
  let note_target (e : expression) =
    match e.pexp_desc with
    | Pexp_ident {txt = Longident.Lident n; _} -> bump_h assigned_names n
    | _ -> ()
  in
  let it =
    {
      default_iterator with
      expr =
        (fun self (e : expression) ->
          match e.pexp_desc with
          (* `!r` READS the cell; it does not hand it out. Recursion stops here on purpose —
             descending would visit the bare `r` and count the read as an escape, which would
             make every ref escape and the metric always zero. Both `!` and `r` are leaves, so
             nothing is lost by not descending. *)
          | Pexp_apply (f, [(Nolabel, {pexp_desc = Pexp_ident _; _})])
            when ident_of f = Some "!" ->
              ()
          | _ ->
          (* Any OTHER bare occurrence of a name hands the cell to code this analysis cannot
             see, so the ref must be assumed assignable. *)
          (match e.pexp_desc with
          | Pexp_ident {txt = Longident.Lident n; _} -> bump_h escaped_names n
          | _ -> ()) ;
          (match e.pexp_desc with
          | Pexp_apply (f, [(Nolabel, lhs); (Nolabel, _)]) when ident_of f = Some ":=" ->
              note_kind ":=" ; note_target lhs
          | Pexp_apply (f, [(Nolabel, a)])
            when ident_of f = Some "incr" || ident_of f = Some "decr" ->
              note_kind (Option.value ~default:"incr" (ident_of f)) ;
              note_target a
          | Pexp_setfield _ -> note_kind "record field <-"
          | Pexp_apply (f, _) when ident_of f = Some "Array.set" ->
              note_kind "array .() <-"
          | Pexp_apply (f, _) when ident_of f = Some "Bytes.set" ->
              note_kind "bytes .[] <-"
          | Pexp_apply (f, _)
            when (match ident_of f with
                 | Some n ->
                     List.mem n
                       ["Hashtbl.replace"; "Hashtbl.add"; "Hashtbl.remove";
                        "Hashtbl.reset"; "Hashtbl.clear"; "Buffer.add_string";
                        "Buffer.add_char"; "Queue.push"; "Stack.push"]
                 | None -> false) ->
              note_kind "container mutation"
          | _ -> ()) ;
          default_iterator.expr self e);
      value_binding =
        (fun self (vb : value_binding) ->
          (match (vb.pvb_pat.ppat_desc, vb.pvb_expr.pexp_desc) with
          | Ppat_var {txt; _}, Pexp_apply (f, [(Nolabel, _)]) when ident_of f = Some "ref" ->
              bump_h ref_bindings txt
          | _ -> ()) ;
          default_iterator.value_binding self vb);
    }
  in
  List.iter (fun si -> it.structure_item it si) str

(* -------------------------------------------------------------------------- *)
(* DB writer (--db) — persistence, study §5                                   *)
(* -------------------------------------------------------------------------- *)

(* Findings only become a feature once they are queryable. This writes them into
   an existing arch-index database, attributing each to the INNERMOST function
   whose line range contains the site — innermost so a finding inside a nested
   lambda lands on the lambda node, matching how the call graph already
   attributes. A finding matching no function is stored with a NULL function_id:
   recorded, never dropped. *)

let db_exec db sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> ()
  | rc -> failwith (Printf.sprintf "sqlite: %s (%s)" (Sqlite3.Rc.to_string rc) sql)

let sq s = "'" ^ String.concat "''" (String.split_on_char '\'' s) ^ "'"

(* module path -> (function_id, name, line_start, line_end) list *)
let load_functions db =
  let tbl : (string, (int * string * int * int) list) Hashtbl.t = Hashtbl.create 64 in
  let stmt =
    Sqlite3.prepare db
      "SELECT f.id, f.name, f.line_start, f.line_end, m.path FROM functions f \
       JOIN modules m ON m.id = f.module_id"
  in
  let rec go () =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        let i n = match Sqlite3.column stmt n with
          | Sqlite3.Data.INT v -> Int64.to_int v | _ -> 0 in
        let t n = match Sqlite3.column stmt n with
          | Sqlite3.Data.TEXT v -> v | _ -> "" in
        let path = t 4 in
        Hashtbl.replace tbl path ((i 0, t 1, i 2, i 3) :: Option.value ~default:[] (Hashtbl.find_opt tbl path)) ;
        go ()
    | _ -> ()
  in
  go () ;
  ignore (Sqlite3.finalize stmt) ;
  tbl

(* Innermost containing function: smallest range that covers the line. *)
let attribute tbl file line =
  let base = Filename.basename file in
  let candidates =
    Hashtbl.fold
      (fun path fns acc ->
        if path = file || Filename.basename path = base then fns @ acc else acc)
      tbl []
  in
  let covering =
    List.filter (fun (_, _, ls, le) -> ls <= line && line <= le) candidates
  in
  match List.sort (fun (_, _, a, b) (_, _, c, d) -> compare (b - a) (d - c)) covering with
  | (id, _, _, _) :: _ -> Some id
  | [] -> None

(* Load certified-pure functions from an index that carries the effects tables.
   Absent tables are not an error: the set stays empty and the analyser keeps its
   allowlist, which is exactly today's behaviour. *)
let load_purity path =
  match Sqlite3.db_open path with
  | db ->
      Fun.protect
        ~finally:(fun () -> ignore (Sqlite3.db_close db))
        (fun () ->
          (* FALSE-CONFIDENCE GUARD. v_pure_functions declares a function pure
             iff it has NO row in function_effects — so on an index where the
             effects extractor never ran, the table is empty and the view
             certifies EVERYTHING as pure. Trusting that would merge atoms with
             arbitrarily effectful heads and manufacture false redundancy
             claims. Same failure the loader guards against with "0 call edges
             -> abort": empty input must not become a trusted verdict. *)
          let effects_rows =
            match Sqlite3.prepare db "SELECT count(*) FROM function_effects" with
            | stmt ->
                let n =
                  match Sqlite3.step stmt with
                  | Sqlite3.Rc.ROW -> (
                      match Sqlite3.column stmt 0 with
                      | Sqlite3.Data.INT v -> Int64.to_int v
                      | _ -> 0)
                  | _ -> 0
                in
                ignore (Sqlite3.finalize stmt) ;
                n
            | exception _ -> 0
          in
          if effects_rows = 0 then purity_available := false
          else
          (* EVERY function, not only the pure ones: the count of same-named functions is what
             makes a bare-name answer trustworthy or not, and it cannot be derived from the pure
             ones alone. *)
          match
            Sqlite3.prepare db
              "SELECT function_name, module_path, is_pure FROM v_pure_functions"
          with
          | stmt ->
              let module_of_path p =
                let b = Filename.remove_extension (Filename.basename p) in
                if b = "" then b else String.make 1 (Char.uppercase_ascii b.[0]) ^ String.sub b 1 (String.length b - 1)
              in
              let rec go () =
                match Sqlite3.step stmt with
                | Sqlite3.Rc.ROW ->
                    (match (Sqlite3.column stmt 0, Sqlite3.column stmt 1, Sqlite3.column stmt 2) with
                    | Sqlite3.Data.TEXT n, mp, pure ->
                        let is_pure = match pure with Sqlite3.Data.INT v -> v = 1L | _ -> false in
                        let keys =
                          n
                          :: (match mp with
                             | Sqlite3.Data.TEXT p -> [ module_of_path p ^ "." ^ n ]
                             | _ -> [])
                        in
                        List.iter
                          (fun k ->
                            bump_key pure_total k ;
                            if is_pure then bump_key pure_yes k)
                          keys ;
                        if is_pure then incr n_pure
                    | _ -> ()) ;
                    go ()
                | _ -> ()
              in
              go () ;
              ignore (Sqlite3.finalize stmt) ;
              purity_available := !n_pure > 0
          | exception _ -> purity_available := false)
  | exception _ -> purity_available := false

let write_db path (armed : string) (frontend : string) (solver : string) =
  let db = Sqlite3.db_open path in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.db_close db))
    (fun () ->
      let tbl = load_functions db in
      db_exec db "BEGIN" ;
      db_exec db "DELETE FROM conditions" ;
      db_exec db "DELETE FROM decisions" ;
      List.iter
        (fun f ->
          let fid =
            match attribute tbl f.f_file f.f_line with
            | Some id -> string_of_int id
            | None -> "NULL"
          in
          let decided_by =
            if String.length f.f_kind >= 4 && String.sub f.f_kind 0 4 = "SMT_" then "smt"
            else if f.f_kind = "HIGH_ARITY" then "budget_exhausted"
            else "enumeration"
          in
          db_exec db
            (Printf.sprintf
               "INSERT INTO decisions (function_id, file_path, line, col, form, arity, \
                verdict, decided_by, evidence, snippet) VALUES (%s,%s,%d,%d,%s,%d,%s,%s,%s,%s)"
               fid (sq f.f_file) f.f_line f.f_col (sq f.f_form) f.f_arity (sq f.f_kind)
               (sq decided_by) (sq f.f_evidence) (sq f.f_snippet)))
        (List.rev !findings) ;
      (* Degradation must be visible (§8.4): a clean result on a run where the
         solver was absent must not look like a clean result on one where it
         ran. *)
      List.iter
        (fun (k, v) ->
          db_exec db
            (Printf.sprintf
               "INSERT OR REPLACE INTO comment_db_meta (key, value) VALUES (%s,%s)"
               (sq k) (sq v)))
        [
          ("decision_analysis", "v1");
          ("decision_armed_rungs", armed);
          ("decision_frontend", frontend);
          ("decision_solver", solver);
          (* Files the analysis could not read or could not walk. Stamped on the index so a
             consumer reading `useless-branches` sees that some code was never examined —
             otherwise a partial run and a clean one are the same empty result. *)
          ("decision_parse_failures", string_of_int !n_parse_fail);
          ("decision_analysis_failures", string_of_int !n_walk_fail);
        ] ;
      db_exec db "COMMIT" ;
      Printf.eprintf "decision-lint: wrote %d decisions to %s\n"
        (List.length !findings) path)

let json_escape s =
  let b = Buffer.create (String.length s + 8) in
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | c when Char.code c < 32 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s ;
  Buffer.contents b

let rec collect_ml dir acc =
  match Sys.readdir dir with
  | entries ->
      Array.fold_left
        (fun acc e ->
          let p = Filename.concat dir e in
          if e = "_build" || e = ".git" || e = "_opam" || e = "node_modules" then acc
          else if Sys.is_directory p then collect_ml p acc
          else if Filename.check_suffix e ".ml" then p :: acc
          else acc)
        acc entries
  | exception _ -> acc

let rec collect_ext ext dir acc =
  match Sys.readdir dir with
  | entries ->
      Array.fold_left
        (fun acc e ->
          let p = Filename.concat dir e in
          if e = ".git" || e = "_opam" || e = "node_modules" then acc
          else if Sys.is_directory p then collect_ext ext p acc
          else if Filename.check_suffix e ext then p :: acc
          else acc)
        acc entries
  | exception _ -> acc

let () =
  smt := (if Sys.getenv_opt "NO_SMT" = None then smt_start () else None) ;
  let argv = List.tl (Array.to_list Sys.argv) in
  (* --cmt switches to the Typedtree frontend: reads .cmt instead of .ml, so
     rung 1 is stamp-based rather than scope-based and the allowlist matches on
     resolved paths. Requires the target to have been BUILT. *)
  let cmt_mode = List.mem "--cmt" argv in
  (* --db <path>: persist findings into an existing arch-index database so
     `arch-query useless-branches` can see them (study §5). *)
  let db_path =
    let rec find = function
      | "--db" :: p :: _ -> Some p
      | _ :: tl -> find tl
      | [] -> None
    in
    find argv
  in
  let roots =
    let rec strip = function
      | "--cmt" :: tl -> strip tl
      | "--db" :: _ :: tl -> strip tl
      | a :: tl -> a :: strip tl
      | [] -> []
    in
    strip argv
  in
  frontend_cmt := cmt_mode ;
  (* Before any walking: the stability predicate consults this. *)
  (match db_path with Some p when cmt_mode -> load_purity p | _ -> ()) ;
  (if cmt_mode then
     let cmts =
       List.sort compare (List.fold_left (fun a r -> collect_ext ".cmt" r a) [] roots)
     in
     List.iter Tt.run_cmt cmts
   else
     let files = List.sort compare (List.fold_left (fun acc r -> collect_ml r acc) [] roots) in
     List.iter
    (fun f ->
      incr n_files ;
      match
        let ic = open_in_bin f in
        Fun.protect
          ~finally:(fun () -> close_in_noerr ic)
          (fun () ->
            let lb = Lexing.from_channel ic in
            Location.init lb f ;
            Parse.implementation lb)
      with
      | str ->
          (try walk_file f str with _ -> incr n_walk_fail) ;
          (try mutation_census str with _ -> incr n_walk_fail)
      | exception _ -> incr n_parse_fail)
       files) ;
  let armed =
    Printf.sprintf "0,1,2,3,4 (%s; purity=%s)"
      (if !frontend_cmt then "typedtree" else "parsetree")
      (if !purity_available then
         Printf.sprintf "analysis/%d certified" !n_pure
       else "allowlist only")
  in
  let frontend = if !frontend_cmt then "typedtree" else "parsetree" in
  let solver = match !smt with None -> "absent" | Some _ -> "z3" in
  (match db_path with
  | Some p -> (
      try write_db p armed frontend solver
      with e -> Printf.eprintf "decision-lint: --db failed: %s\n" (Printexc.to_string e))
  | None -> ()) ;
  List.iter
    (fun x ->
      Printf.printf
        {|{"type":"finding","kind":"%s","file":"%s","line":%d,"col":%d,"form":"%s","arity":%d,"detail":"%s","snippet":"%s","evidence":"%s"}
|}
        (json_escape x.f_kind) (json_escape x.f_file) x.f_line x.f_col
        (json_escape x.f_form) x.f_arity (json_escape x.f_detail)
        (json_escape x.f_snippet) (json_escape x.f_evidence))
    (List.rev !findings) ;
  let hist =
    String.concat ","
      (List.map
         (fun (k, v) -> Printf.sprintf {|"%d":%d|} k v)
         (List.sort compare (Hashtbl.fold (fun k v acc -> (k, v) :: acc) arity_hist [])))
  in
  Printf.printf
    {|{"type":"census","files":%d,"parse_failures":%d,"analysis_failures":%d,"decisions":%d,"multi_condition":%d,"unknown_over_cap":%d,"atoms":%d,"unstable_atoms":%d,"arity_histogram":{%s},"armed_rungs":"%s","findings":%d}
|}
    !n_files !n_parse_fail !n_walk_fail !n_decisions !n_multi !n_unknown !n_atoms
    !n_unstable_atoms hist
    armed
    (List.length !findings) ;
  let refs_total = Hashtbl.fold (fun _ v a -> a + v) ref_bindings 0 in
  (* Assigned OR escaped disqualifies: a ref handed to a function may be written through a
     closure the analysis never sees (Arg.Set_string is the canonical case). *)
  let write_once =
    Hashtbl.fold
      (fun n v a ->
        if Hashtbl.mem assigned_names n || Hashtbl.mem escaped_names n then a else a + v)
      ref_bindings 0
  in
  Printf.printf
    {|{"type":"mutations","sites":%d,"by_kind":[%s],"ref_bindings":%d,"never_assigned":%d}
|}
    !n_mut_sites
    (String.concat ","
       (List.sort (fun (_, a) (_, b) -> compare b a)
          (Hashtbl.fold (fun k v acc -> (k, v) :: acc) mutation_kinds [])
       |> List.map (fun (k, v) -> Printf.sprintf {|{"kind":"%s","n":%d}|} (json_escape k) v)))
    refs_total write_once ;
  let heads =
    List.sort (fun (_, a) (_, b) -> compare b a)
      (Hashtbl.fold (fun k v acc -> (k, v) :: acc) unstable_heads [])
  in
  Printf.printf {|{"type":"unstable_heads","distinct":%d,"top":[%s]}
|}
    (List.length heads)
    (String.concat ","
       (List.filteri (fun i _ -> i < 40) heads
       |> List.map (fun (k, v) -> Printf.sprintf {|{"head":"%s","n":%d}|} (json_escape k) v))) ;
  (match !smt with
  | None -> print_string {|{"type":"smt","solver":"absent","note":"SMT tier reported UNKNOWN throughout"}
|}
  | Some st ->
      Printf.printf
        {|{"type":"smt","solver":"z3","rlimit":%d,"bv_width":%d,"decisions_escalated":%d,"queries":%d,"cache_hits":%d,"unknown":%d,"findings":%d}
|}
        smt_rlimit bv_width !n_smt_decisions st.s_queries st.s_hits st.s_unknown
        !n_smt_findings)
