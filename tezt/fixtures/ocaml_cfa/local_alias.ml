let local_root x = x
let local_a = local_root
let local_run x = let local_b = local_a in local_b x

let capture_outer x =
  let capture_local = local_a in
  fun y -> capture_local y

let initializer_outer =
  let initializer_local = local_a in
  fun y -> initializer_local y

let unit_outer x = let _ = x in fun y -> local_a y
