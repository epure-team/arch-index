module type S = sig val n : int end
module A = struct let n = 1 end
module F (X : S) = struct let n = X.n end
module Outer = F (A)
module Make (X : S) = struct
  module A = struct let n = 2 end
  module Alias = A
  module From_parameter = F (X)
  module Inner = struct
    module A = Alias
    module From_shadowed_a = F (A)
  end
  module After_inner = F (A)
end
