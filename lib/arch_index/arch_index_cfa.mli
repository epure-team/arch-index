module String_set : Set.S with type elt = string

type value = {targets : String_set.t; reasons : String_set.t}
type cell
type t

val create : unit -> t
val fresh : t -> cell
val seed_target : t -> cell -> string -> unit
val seed_reason : t -> cell -> string -> unit
val copy : t -> src:cell -> dst:cell -> unit
val solve : t -> unit
val value : t -> cell -> value
