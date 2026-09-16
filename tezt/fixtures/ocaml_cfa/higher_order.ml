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

let direct_staged_run x = (ho_identity ho_target) x

let rec direct_pick f n = if n = 0 then f else direct_pick f (n - 1)

let direct_rec_run x =
  let picked = direct_pick rec_target 0 in
  picked x

let local_rec_run x =
  let rec local_left f n = local_right f n
  and local_right f n = if n = 0 then f else local_left f (n - 1) in
  let picked = local_left rec_target 0 in
  picked x

let rec mixed_good f n = if n = 0 then f else mixed_good f (n - 1)
and mixed_bad = function value -> value

let mixed_group_run x =
  let picked = mixed_good rec_target 0 in
  picked x

let over_make () =
  let returned = fun _ -> ho_target in
  returned

let over_downstream x =
  let picked = over_make () x in
  picked x
