exception Changed

val read_checked :
  digest:(string -> string) -> read:(string -> 'a) -> string -> string * 'a
