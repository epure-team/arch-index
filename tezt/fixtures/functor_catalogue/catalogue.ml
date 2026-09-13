module type S = sig val n : int end

module A = struct let n = 1 end
module B = struct let n = 2 end
module F (X : S) = struct let n = X.n end
module G (X : S) (Y : S) = struct let n = X.n + Y.n end
module U () = struct let u = 0 end
module H (X : S) = X

module Named = F (A)
module Anonymous_argument = F (struct let n = 3 end)
module Chained = G (A) (B)
module Nested = H (F (A))
module Unit = U ()
module Constrained = (F (A) : S)
module Inline_head = (functor (X : S) -> struct let n = X.n end) (A)
module Inline_both = (functor (X : S) -> struct let n = X.n end) (struct let n = 4 end)

module In_functor (X : S) = struct module Local = F (X) end

let local () =
  let module Local = F (A) in
  Local.n

let anonymous () =
  let module _ = F (A) in
  0

let unpacked (module X : S) =
  let module Local = F (X) in
  Local.n

module From_unpack = F ((val (let module Local = F (A) in (module Local : S)) : S))

module type Module_type_of = module type of struct module Local = F (A) end

class contexts = object
  method local_module =
    let module Local = F (A) in
    Local.n
  initializer ignore (let module Local = F (A) in Local.n)
end
