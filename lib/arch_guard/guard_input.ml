exception Changed

let read_checked ~digest ~read path =
  let before = digest path in
  let value = read path in
  if before <> digest path then raise Changed ;
  (before, value)
