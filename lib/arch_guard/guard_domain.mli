type t = Bottom | Const of int64 | Nonzero | Top

val min_value : int -> int64
val max_value : int -> int64
val in_range : int -> int64 -> bool
val join : t -> t -> t
val restrict_eq_zero : t -> t
val restrict_ne_zero : t -> t
val contains : t -> int64 -> bool
val checked_neg : int -> t -> t
val checked_add : int -> t -> t -> t
val checked_sub : int -> t -> t -> t
val checked_mul : int -> t -> t -> t
val to_yojson : t -> Yojson.Safe.t
val of_yojson : Yojson.Safe.t -> t
