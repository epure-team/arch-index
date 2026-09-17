type formal_kind = Named | Unit

type formal = {
  position : int;
  kind : formal_kind;
  binder_key : string option;
  name : string option;
}

type declaration = {
  declaration_key : string;
  name : string;
  location : string;
  formals : formal list;
}

type result = {
  ordinal : int;
  status : string;
  reason : string option;
  declaration_key : string option;
  formal_position : int option;
  head_application_ordinal : int option;
  actual_root_key : string option;
}

type collection = {
  declarations : declaration list;
  results : result list;
}

type matched_actual = {
  application_ordinal : int;
  declaration_key : string;
  formal_position : int;
  formal_key : string;
  formal_id : Ident.t;
  actual_root_key : string;
  actual_path : Path.t;
}

type collection_with_actuals = {
  bindings : collection;
  matched_actuals : matched_actual list;
}

val collect_with_actuals : Typedtree.structure -> collection_with_actuals
(** The persisted binding collection plus same-CMT compiler identities used
    transiently by target correspondence. Ephemeral identities never cross an
    artifact boundary and are emitted only for already-matched named formals
    with supported local module-ident actuals. *)

val collect : Typedtree.structure -> collection
(** Collect local named functor declarations and account for every catalogue
    application using the catalogue collector's exact ordinals. Local Pident
    aliases are followed by compiler identity, and consecutive literal
    functor results advance one formal per nested application. Identity
    conflicts and malformed named binders raise before results are returned. *)

val store_collected : Sqlite3.db -> producer_run_id:int -> artifact:string -> collection -> unit
val store_failed : Sqlite3.db -> producer_run_id:int -> artifact:string -> unit
val finalize_contract : Sqlite3.db -> selected_inputs:int -> bool
(** Call only after all producer data transactions have committed. Clears any
    previous binding marker, validates the complete catalogue and binding facts
    in a new transaction, then writes v1 only when valid. Returns false for
    inconsistent data; SQL and transaction failures raise. *)

type target_witness = {
  application_ordinal : int;
  declaration_key : string;
  formal_position : int;
  formal_key : string;
  actual_root_key : string;
  actual_path : string list;
  member_path : string list;
  caller_name : string;
  call_location : string;
  occurrence_ordinal : int;
  target_occurrence_ordinal : int;
  target_key : string;
  target_function_id : int;
  candidate_call_id : int;
}

type target_occurrence = {
  ordinal : int;
  source : string;
  compiler_unit : string;
  caller_name : string;
  call_location : string;
  physical_ordinal : int;
  member_path : string list;
  occurrence_shape : string;
  representative_artifact : string option;
  representative_ordinal : int option;
  top_call_id : int option;
}

type target_candidate = {
  occurrence_ordinal : int;
  target_key : string;
  actual_path : string list;
  member_path : string list;
  target_function_id : int;
  candidate_call_id : int;
}

val store_target_collected :
  Sqlite3.db -> producer_run_id:int -> artifact:string ->
  ?binding_refusals:int -> ?member_refusals:int ->
  ?reconciliation_refusals:int -> target_occurrence list ->
  target_candidate list -> target_witness list -> unit
val store_target_failed : Sqlite3.db -> producer_run_id:int -> artifact:string -> unit
val mark_target_contract : Sqlite3.db -> selected_inputs:int -> bool
(** Validate and write the v2 marker inside the caller's active transaction. *)
val finalize_target_contract : Sqlite3.db -> selected_inputs:int -> bool
