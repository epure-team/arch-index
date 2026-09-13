module type S = sig val value : int end
module A = struct let value = 1 end
module Container = struct
  module Make (X : S) = struct module Member = X end
  module Curried (X : S) (Y : S) = struct module Member = Y end
end
module Alias_container = Container
module Local = Container.Make (A)
module Local_again = Container.Make (A)
module Persistent = Set.Make (Int)
module Alias_use = Alias_container.Make (A)
module Curried_use = Container.Curried (A) (A)
module type FACTORY = sig module Make : functor (X : S) -> sig module Member : S end end
module Outer (P : FACTORY) = struct
  module Parameter = P.Make (A)
end
let shadow_one =
  let module Same = Container in
  let module Use = Same.Make (A) in
  Use.Member.value
let shadow_two =
  let module Same = Container in
  let module Use = Same.Make (A) in
  Use.Member.value
module Direct (X : S) = X
module Direct_use = Direct (A)
