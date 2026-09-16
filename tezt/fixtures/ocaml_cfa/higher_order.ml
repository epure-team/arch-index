let ho_target x = x
let ho_identity f = f

let ho_run x =
  let picked = ho_identity ho_target in
  picked x

let merge_a x = x + 1
let merge_b x = x + 2
let merge_identity f = f

let merge_run_a x =
  let picked = merge_identity merge_a in
  picked x

let merge_run_b x =
  let picked = merge_identity merge_b in
  picked x

let rec_target x = x + 3

let rec rec_left f n = if n = 0 then f else rec_right f (n - 1)
and rec_right f n = if n = 0 then f else rec_left f (n - 1)

let rec_run x =
  let picked = rec_left rec_target 0 in
  picked x

let staged_target x y = x + y

let staged_run x y =
  let partial = staged_target x in
  partial y
