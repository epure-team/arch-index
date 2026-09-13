type t = Bottom | Const of int64 | Nonzero | Top

let min_value width = Int64.shift_left (-1L) (width - 1)
let max_value width = Int64.lognot (min_value width)
let in_range width value = Int64.compare value (min_value width) >= 0 && Int64.compare value (max_value width) <= 0

let join left right =
  match (left, right) with
  | Bottom, value | value, Bottom -> value
  | Top, _ | _, Top -> Top
  | Const a, Const b when a = b -> Const a
  | Const 0L, _ | _, Const 0L -> Top
  | Const _, Const _ | Const _, Nonzero | Nonzero, Const _ | Nonzero, Nonzero -> Nonzero

let restrict_eq_zero = function Bottom -> Bottom | Const 0L | Top -> Const 0L | Const _ | Nonzero -> Bottom
let restrict_ne_zero = function Bottom -> Bottom | Const 0L -> Bottom | Const n -> Const n | Nonzero -> Nonzero | Top -> Nonzero
let contains value concrete = match value with Bottom -> false | Const n -> n = concrete | Nonzero -> concrete <> 0L | Top -> true

let checked_neg width = function
  | Bottom -> Bottom
  | Const n when n <> Int64.min_int -> let r = Int64.neg n in if in_range width r then Const r else Top
  | Const _ -> Top
  | Nonzero | Top -> Top

let checked_add width left right = match (left, right) with
  | Bottom, _ | _, Bottom -> Bottom
  | Const a, Const b ->
      let r = Int64.add a b in
      if ((Int64.logxor a r |> Int64.logand (Int64.logxor b r)) < 0L) || not (in_range width r) then Top else Const r
  | _ -> Top

let checked_sub width left right = match (left, right) with
  | Bottom, _ | _, Bottom -> Bottom
  | Const a, Const b ->
      let r = Int64.sub a b in
      if ((Int64.logxor a b |> Int64.logand (Int64.logxor a r)) < 0L) || not (in_range width r) then Top else Const r
  | _ -> Top

let checked_mul width left right = match (left, right) with
  | Bottom, _ | _, Bottom -> Bottom
  | Const a, Const b ->
      if a = 0L || b = 0L then Const 0L
      else if (a = Int64.min_int && b = -1L) || (b = Int64.min_int && a = -1L) then Top
      else let r = Int64.mul a b in if Int64.div r b <> a || not (in_range width r) then Top else Const r
  | _ -> Top

let to_yojson = function
  | Bottom -> `Assoc [("kind", `String "bottom")]
  | Nonzero -> `Assoc [("kind", `String "nonzero")]
  | Top -> `Assoc [("kind", `String "top")]
  | Const value -> `Assoc [("kind", `String "const"); ("value", `String (Int64.to_string value))]

let of_yojson json =
  let open Yojson.Safe.Util in
  match json |> member "kind" |> to_string with
  | "bottom" -> Bottom | "nonzero" -> Nonzero | "top" -> Top
  | "const" -> Const (json |> member "value" |> to_string |> Int64.of_string)
  | kind -> invalid_arg ("unknown domain kind: " ^ kind)
