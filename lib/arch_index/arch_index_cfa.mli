module String_set : Set.S with type elt = string

type reason = Callback_param | Dropped_node
module Reason_set : Set.S with type elt = reason

type residual = {target : string; consumed : int}
module Residual_set : Set.S with type elt = residual

type value = {
  targets : String_set.t;
  reasons : Reason_set.t;
  residuals : Residual_set.t;
}
type cell
type t

val create : unit -> t
val clone : t -> t
val fresh : t -> cell
val seed_target : t -> cell -> string -> unit
val seed_reason : t -> cell -> reason -> unit
val seed_residual : t -> cell -> residual -> unit
val copy : t -> src:cell -> dst:cell -> unit
val on_target : t -> cell -> (t -> string -> unit) -> unit
val on_reason : t -> cell -> (t -> reason -> unit) -> unit
val on_residual : t -> cell -> (t -> residual -> unit) -> unit
val solve : t -> unit
val value : t -> cell -> value
