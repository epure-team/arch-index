let meta_one x = Ok x
let meta_two x y = Ok (x + y)
let meta_tuple (x, y) = Ok (x + y)
let meta_cases = function x -> Ok x
let meta_labeled ~x y = Ok (x + y)
let same_line choose x = let picked = if choose then meta_one else meta_cases in ignore (picked x); picked x
let conditional choose x = let picked = if choose then meta_one else meta_cases in if choose then ignore (picked x)
let dead choose x = let picked = if choose then meta_one else meta_cases in raise Exit; ignore (picked x)
let partial_curried x = let picked = meta_two in picked x
let tuple_call x y = let picked = meta_tuple in picked (x, y)
let cases_call x = let picked = meta_cases in picked x
let labeled_partial x = let picked = meta_labeled in picked x
let meta_over choose x = if choose then (fun y -> Ok (x + y)) else (fun y -> Ok y)
let meta_over2 choose x = if choose then (fun y -> Ok (x - y)) else (fun y -> Ok (y + 1))
let overapply choose callback =
  let picked = if choose = 0 then meta_over else if choose = 1 then meta_over2 else callback in
  picked true 1 2
let match_guard choose x =
  let picked = if choose then meta_one else meta_cases in
  match Some x with
  | Some value when Result.is_ok (picked value) -> picked value
  | _ -> Ok 0
let scoped choose x =
  let picked = if choose then meta_one else meta_cases in
  try match picked x with Error _ -> Ok 0 | Ok value -> Ok value with Exit -> Ok 1
