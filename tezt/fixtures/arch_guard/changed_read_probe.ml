let read_implementation reads path =
  incr reads ;
  match Cmt_format.read path with
  | _, Some {Cmt_format.cmt_annots = Implementation _; _} as result -> result
  | _ -> failwith "expected an implementation CMT"

let file_digest path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr channel) @@ fun () ->
  Digestif.SHA256.(to_hex (digest_string (really_input_string channel (in_channel_length channel))))

let stable path =
  let digests = ref 0 and reads = ref 0 in
  let digest path = incr digests ; file_digest path in
  ignore
    (Arch_guard__Guard_input.read_checked ~digest
       ~read:(read_implementation reads) path) ;
  if !digests <> 2 || !reads <> 1 then failwith "stable read did not run digest/read/digest exactly once" ;
  exit 0

let changed path =
  let digests = ref 0 and reads = ref 0 in
  let digest _ =
    incr digests ;
    if !digests = 1 then "before" else "after"
  in
  try
    ignore
      (Arch_guard__Guard_input.read_checked ~digest
         ~read:(read_implementation reads) path) ;
    prerr_endline "changed_read_probe: expected changed-input rejection" ;
    exit 1
  with Arch_guard__Guard_input.Changed ->
    if !digests <> 2 || !reads <> 1 then (
      prerr_endline "changed_read_probe: mismatch check did not surround exactly one read" ;
      exit 1) ;
    prerr_endline "changed_read_probe: input changed while being read" ;
    exit 2

let () =
  match Array.to_list Sys.argv with
  | [_; "--stable"; path] -> stable path
  | [_; path] -> changed path
  | _ ->
      prerr_endline "usage: changed_read_probe [--stable] FILE.cmt" ;
      exit 2
