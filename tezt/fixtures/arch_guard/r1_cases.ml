let opaque value = value

let alias_before_guard divisor =
  let alias = divisor in
  if divisor <> 0 then 10 / alias else 0

let alias_inside_guard divisor =
  if divisor <> 0 then
    let alias = divisor in
    10 / alias
  else 0

let same_spelling_shadow divisor =
  if divisor <> 0 then
    let divisor = 0 in
    10 / divisor
  else 0

let simultaneous_bindings divisor =
  let divisor = 2 in
  let copied = divisor
  and divisor = 0 in
  (10 / copied) + (10 / divisor)

let nested_capture divisor =
  if divisor <> 0 then (fun () -> 10 / divisor) else (fun () -> 0)

let nested_local divisor =
  if divisor <> 0 then
    fun () ->
      let local = 2 in
      10 / local
  else fun () -> 0

let nested_below_contradiction divisor =
  if divisor = 0 then
    if divisor <> 0 then (fun () -> 10 / divisor) else (fun () -> 0)
    else fun () -> 0

let immediately_applied divisor =
  if divisor <> 0 then (fun value -> 10 / value) divisor else 0

let curried_capture divisor =
  if divisor <> 0 then fun _ -> fun () -> 10 / divisor else fun _ -> fun () -> 0

let alpha_guard_left divisor =
  if divisor <> 0 then 10 / divisor else 0

let alpha_guard_right renamed =
  if renamed <> 0 then 10 / renamed else 0

let immediately_applied_below_contradiction divisor =
  if divisor = 0 then
    if divisor <> 0 then (fun value -> 10 / value) divisor else 0
  else 0

let curried_below_contradiction divisor =
  if divisor = 0 then
    if divisor <> 0 then fun _ -> fun () -> 10 / divisor
    else fun _ -> fun () -> 0
  else fun _ -> fun () -> 0

let optional_default ?(divisor = 10 / 0) () = divisor

let function_cases = function
  | Some divisor -> 10 / divisor
  | None -> 0

let recursive_binding divisor =
  let rec recurse value =
    if value = 0 then 10 / divisor else recurse (value - 1)
  in
  recurse 1

let compound_binding divisor =
  let (numerator, divisor) = (10, divisor) in
  numerator / divisor

let alias_pattern_binding divisor =
  let (copy as alias) = divisor in
  copy / alias

let refutable_parameter = function
  | Some divisor -> 10 / divisor
  | None -> 0

let multiple_unsupported divisor =
  while false do
    try ignore (10 / divisor) with _ -> ()
  done

let sticky_nested_under_unsupported divisor =
  while false do ignore (fun () -> 10 / divisor) done

let sticky_immediate_under_unsupported divisor =
  while false do ignore ((fun value -> 10 / value) divisor) done

let sticky_curried_under_unsupported divisor =
  while false do ignore (fun _ -> fun () -> 10 / divisor) done

let unsupported_then_supported divisor =
  while false do ignore (10 / divisor) done ;
  10 / 2

let while_condition divisor =
  while 10 / divisor > 0 do () done

let for_bounds divisor =
  for index = 10 / divisor to 20 / divisor do
    ignore (30 / divisor) ;
    ignore index
  done

let opaque_result divisor = 10 / opaque divisor
let target_inside_opaque_argument divisor = opaque (10 / divisor)
let target_inside_short_circuit divisor = divisor <> 0 && 10 / divisor > 0
let target_inside_unlisted_primitive divisor = ignore (10 / divisor)

let indirect_division_is_not_inventoried divisor =
  let quotient = ( / ) in
  quotient 10 divisor

class consumer = object
  method consume (_ : int) = ()
end

let target_as_method_argument divisor receiver =
  receiver#consume (10 / divisor)

let target_inside_method_receiver divisor receiver =
  (if 10 / divisor > 0 then receiver else receiver)#consume 0
