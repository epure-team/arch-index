let join_f x = x
let join_g x = x + 1
let branch_choice = true
let branch_root = if branch_choice then join_f else join_g
let branch_run x = branch_root x
let join_known choose x = let picked = if choose then join_f else join_g in picked x
let join_unknown choose callback x = let picked = if choose then join_f else callback in picked x
let direct_join choose x = (if choose then join_f else join_g) x
let join_side x = x
let guard_join choose x =
  let picked = if join_side choose = 0 then join_f else join_g in
  picked x
let match_join tag x =
  let picked = match join_side tag with 0 -> join_f | _ -> join_g in
  picked x
let sequence_join x =
  let picked = ignore (join_side 0); join_f in
  picked x
let pattern_join pair x =
  let picked = match pair with callback, true -> callback | _ -> join_f in
  picked x
let exception_join x =
  let picked = match raise Exit with exception Exit -> join_f | _ -> join_g in
  picked x
