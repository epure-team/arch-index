(** Shared architecture-rule parsing and evaluation. *)

exception Error of string

type verdict =
  | Pass | Violation | Possible | Unknown | Unknown_no_contract
  | No_source | No_target | Not_computed

val all_verdicts : verdict list
val string_of_verdict : verdict -> string
val verdict_of_string : string -> verdict option
val verdict_vocabulary : string list

type result = {
  rule : string;
  kind : string;
  verdict : string;
  detail : string list;
  detail_total : int;
  note : string option;
  sizes : (int * int) option;
  exact : bool;
  witness : string list;
  top_reasons : string list;
  origin_contexts : Yojson.Safe.t list;
  context_total : int;
  context_omitted : int;
}

(** Evaluate a non-empty rule file against an already-open database. *)
val evaluate_file : Arch_db.t -> string -> bool * result list
