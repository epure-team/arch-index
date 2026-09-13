type application_kind = Apply | Apply_unit

val selected_inputs : string list -> string list
(** Exact-string sorting and deduplication, without canonicalizing paths or contents. *)

type occurrence = {
  ordinal : int;
  application_kind : application_kind;
  location : string;
  head : string;
  argument : string;
  diagnostics : string;
}

val collect :
  ?on_application:
    (ordinal:int ->
     application_kind:application_kind ->
     head_application_ordinal:int option ->
     head:Typedtree.module_expr ->
     argument:Typedtree.module_expr option ->
     unit) ->
  Typedtree.structure ->
  occurrence list
(** The optional callback observes the same typed application sites from which
    catalogue rows are produced.  Omitting it retains catalogue-only behavior. *)

val location_json : Location.t -> string * bool

val store_collected :
  Sqlite3.db ->
  producer_run_id:int ->
  artifact:string ->
  source:string ->
  compiler_unit:string ->
  module_id:int ->
  occurrence list ->
  unit

val store_outcome :
  Sqlite3.db -> producer_run_id:int -> artifact:string -> outcome:string -> unit

val clear_contract : Sqlite3.db -> unit
(** Clear eligibility before schema replacement. Safe on a fresh database. *)

val finalize_contract : Sqlite3.db -> selected_inputs:int -> bool
(** Validate persisted counts/provenance after data commit, then write the v1
    marker separately. Returns whether eligibility was earned. *)
