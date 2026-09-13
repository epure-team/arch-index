let respond request =
  let open Yojson.Safe.Util in
  let id = request |> member "id" in
  let width = request |> member "width" |> to_int in
  if width < 2 || width > 63 then invalid_arg "width must be in 2..63" ;
  let op = request |> member "op" |> to_string in
  let module D = Arch_guard.Guard_domain in
  let args = request |> member "args" |> to_list |> List.map D.of_yojson in
  List.iter (function D.Const n when not (D.in_range width n) -> invalid_arg "constant outside selected width" | _ -> ()) args ;
  let unary f = match args with [a] -> f a | _ -> invalid_arg "unary op arity" in
  let binary f = match args with [a; b] -> f a b | _ -> invalid_arg "binary op arity" in
  if op = "contains" then
    let value = request |> member "value" |> to_string |> Int64.of_string in
    let contains = match args with [arg] -> D.contains arg value | _ -> invalid_arg "contains arity" in
    `Assoc [("id", id); ("contains", `Bool contains)]
  else let result = match op with
    | "neg" -> unary (D.checked_neg width)
    | "add" -> binary (D.checked_add width)
    | "sub" -> binary (D.checked_sub width)
    | "mul" -> binary (D.checked_mul width)
    | "join" -> binary D.join
    | "restrict_eq_zero" -> unary D.restrict_eq_zero
    | "restrict_ne_zero" -> unary D.restrict_ne_zero
    | _ -> invalid_arg ("unknown op: " ^ op)
  in `Assoc [("id", id); ("result", D.to_yojson result)]

let () =
  try
    while true do
      let request = Yojson.Safe.from_string (input_line stdin) in
      print_endline (Yojson.Safe.to_string (respond request)) ;
      flush stdout
    done
  with End_of_file -> ()
