let literal_nonzero () = 10 / 2
let partial = ( / ) 1
let under_loop d = while false do ignore (10 / d) done
let under_try d = try 10 / d with _ -> 0
let other_integer_family () = Int64.div 10L 2L

type _ Effect.t += Probe : int -> unit Effect.t
let under_effect d = Effect.perform (Probe (10 / d))

let alias_nonzero () = let d = 2 in 10 / d
let guarded_nonzero d = if d <> 0 then 10 / d else 0
let joined_maybe b = let d = if b then 0 else 2 in 10 / d
let contradictory d = if d = 0 then if d <> 0 then 10 / d else 0 else 0
let fresh_nested d = if d <> 0 then (fun () -> 10 / d) else (fun () -> 0)
let literal_zero () = 10 / 0
