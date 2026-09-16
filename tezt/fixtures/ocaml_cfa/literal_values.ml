let literal_pick choose x =
  let picked = if choose then (fun y -> y) else (fun y -> y + 1) in
  picked x

let literal_mixed choose callback x =
  let picked = if choose then (fun y -> y) else callback in
  picked x

let literal_alias x =
  let base = fun y -> y + 2 in
  let alias = base in
  alias x

let root_flag = true
let root_literal = if root_flag then (fun y -> y) else (fun y -> y + 3)
let root_literal_run x = root_literal x
