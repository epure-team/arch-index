type t = Bottom | Const of int64 | Nonzero | Top
(** Abstract native-int values for the bounded constant-zero analysis. *)

val min_value : int -> int64
(** Signed minimum representable at the given OCaml payload width. *)

val max_value : int -> int64
(** Signed maximum representable at the given OCaml payload width. *)

val in_range : int -> int64 -> bool
(** Whether a concrete integer is representable at the given payload width. *)

val join : t -> t -> t
(** Least abstract upper bound. *)

val restrict_eq_zero : t -> t
(** Sound restriction to values equal to zero. *)

val restrict_ne_zero : t -> t
(** Sound restriction to values unequal to zero. *)

val contains : t -> int64 -> bool
(** Whether an abstract value contains the concrete integer. *)

val checked_neg : int -> t -> t
(** Conservative signed modular negation at the given payload width. *)

val checked_add : int -> t -> t -> t
(** Conservative signed modular addition at the given payload width. *)

val checked_sub : int -> t -> t -> t
(** Conservative signed modular subtraction at the given payload width. *)

val checked_mul : int -> t -> t -> t
(** Conservative signed modular multiplication at the given payload width. *)

val to_yojson : t -> Yojson.Safe.t
(** Encode a private probe value as JSON. *)

val of_yojson : Yojson.Safe.t -> t
(** Decode a private probe value from JSON. *)
