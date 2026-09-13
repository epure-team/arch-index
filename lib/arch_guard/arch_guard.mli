exception Error of string
(** Raised when an input or completed report violates the bounded CLI contract. *)

module Guard_domain : module type of Guard_domain
(** Internal abstract domain exposed only to private test probes. *)

val render_json : string list -> string
(** [render_json paths] analyzes explicit CMT [paths] and returns schema version 1. *)

val render_text : string list -> string
(** [render_text paths] projects the same completed analysis as human-readable text. *)
