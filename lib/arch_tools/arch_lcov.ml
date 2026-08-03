(** LCOV tracefile reader.

    One parser for every language. bisect_ppx ([bisect-ppx-report lcov]), gcov/lcov natively,
    [go test -coverprofile] via gcov2lcov, coverage.py, cargo-llvm-cov and every JS tool via nyc
    all emit it, and [DA:] records are (line, hit-count) — which join to a file path plus line
    spans on every backend with no per-language code at all.

    [FN]/[FNDA] are deliberately ignored: what a producer calls a "function" varies wildly
    (bisect_ppx emits none, gcov one per mangled symbol), while [DA] means the same thing
    everywhere. The call graph already knows where functions begin and end. *)

module SM = Map.Make (String)

type file_cov = (int, int) Hashtbl.t
type t = file_cov SM.t

let starts_with ~prefix s =
  String.length s >= String.length prefix && String.sub s 0 (String.length prefix) = prefix

let parse path =
  let ic = try Some (open_in path) with Sys_error _ -> None in
  match ic with
  | None -> Error (Printf.sprintf "cannot read lcov file: %s" path)
  | Some ic ->
      let files = ref SM.empty in
      let cur = ref None in
      let err = ref None in
      let lineno = ref 0 in
      (try
         while !err = None do
           let raw = String.trim (input_line ic) in
           incr lineno ;
           if starts_with ~prefix:"SF:" raw then (
             let f = String.sub raw 3 (String.length raw - 3) in
             cur := Some f ;
             if not (SM.mem f !files) then files := SM.add f (Hashtbl.create 64) !files)
           else if raw = "end_of_record" then
             (* Closes the current record. Without this a DA line appearing after end_of_record
                and before the next SF — a truncated or concatenated tracefile — was silently
                credited to the PREVIOUS file, inventing coverage for lines it does not have. *)
             cur := None
           else if starts_with ~prefix:"DA:" raw then
             match !cur with
             | None ->
                 err :=
                   Some
                     (Printf.sprintf "%s:%d: DA record before any SF record — malformed tracefile"
                        path !lineno)
             | Some f -> (
                 let body = String.sub raw 3 (String.length raw - 3) in
                 match String.split_on_char ',' body with
                 | l :: h :: _ -> (
                     match (int_of_string_opt (String.trim l), int_of_string_opt (String.trim h)) with
                     | Some l, Some h when l < 1 || h < 0 ->
                         (* A negative hit count is not a producer's way of saying "uncovered" —
                            no LCOV producer emits one. Summing it across duplicate records can
                            cancel a real hit and turn a covered function into a reported gap. *)
                         err :=
                           Some
                             (Printf.sprintf
                                "%s:%d: DA record %S has a non-positive line number or a negative \
                                 hit count — refusing to guess what the producer meant"
                                path !lineno raw)
                     | Some l, Some h ->
                         let tbl = SM.find f !files in
                         (* A file appearing in several records (LCOV allows it, and merged or
                            sharded runs produce it) has its counts SUMMED. Overwriting would
                            silently discard a shard's results. *)
                         Hashtbl.replace tbl l (h + Option.value ~default:0 (Hashtbl.find_opt tbl l))
                     | None, _ ->
                         err := Some (Printf.sprintf "%s:%d: malformed DA record %S" path !lineno raw)
                     | _, None ->
                         err :=
                           Some
                             (Printf.sprintf "%s:%d: DA hit count is not an integer in %S" path
                                !lineno raw))
                 | _ -> err := Some (Printf.sprintf "%s:%d: malformed DA record %S" path !lineno raw))
           else ()
         done
       with End_of_file -> ()) ;
      close_in ic ;
      (match !err with
      | Some e -> Error e
      | None ->
          if SM.is_empty !files then
            (* An empty tracefile and a coverage run that never happened are indistinguishable
               from the data. Reporting 0% for the second is how a green pipeline hides a
               broken one. *)
            Error
              (Printf.sprintf
                 "%s contains no SF records — refusing to report 0%% coverage from an empty \
                  tracefile, which is indistinguishable from a coverage run that never happened"
                 path)
          else Ok !files)
