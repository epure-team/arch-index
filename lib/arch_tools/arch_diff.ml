(** Reading a git diff as (file, changed lines).

    [--unified=0] so a hunk contains only changed lines, not context: attributing three lines of
    untouched context to a function would inflate the changed set on every hunk boundary. *)

module SM = Map.Make (String)

(** [Whole] means "every line of this file" — [--files], where the user asked for the file
    rather than a diff. It must NOT be modelled as an empty set: emptiness collapses into the
    deletion-only case and makes every line-membership test false, so findings would silently
    read as zero. *)
type lines = Whole | Lines of (int, unit) Hashtbl.t

let mem lines n = match lines with Whole -> true | Lines h -> Hashtbl.mem h n
let is_empty = function Whole -> false | Lines h -> Hashtbl.length h = 0

(** Union, for when two diff paths resolve to the SAME indexed file.

    Suffix matching is ambiguous by design (two [main.go] under different directories), so this
    is a normal outcome, not a corner case. Overwriting instead of merging silently dropped
    every line of whichever path was visited first — and the lines that vanished were the input
    to a gate. *)
let union a b =
  match (a, b) with
  | Whole, _ | _, Whole -> Whole
  | Lines x, Lines y ->
      let m = Hashtbl.create (Hashtbl.length x + Hashtbl.length y) in
      Hashtbl.iter (fun k () -> Hashtbl.replace m k ()) x ;
      Hashtbl.iter (fun k () -> Hashtbl.replace m k ()) y ;
      Lines m

let run_git repo args =
  let cmd =
    "git -C "
    ^ Filename.quote repo
    ^ " "
    ^ String.concat " " (List.map Filename.quote args)
    ^ " 2>/dev/null"
  in
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 8192 in
  (try
     while true do
       Buffer.add_channel buf ic 1
     done
   with End_of_file -> ()) ;
  match Unix.close_process_in ic with
  | Unix.WEXITED 0 -> Ok (Buffer.contents buf)
  | _ -> Error (Printf.sprintf "git %s failed in %s" (String.concat " " args) repo)

let starts_with ~prefix s =
  String.length s >= String.length prefix && String.sub s 0 (String.length prefix) = prefix

(* "@@ -a,b +c,d @@" → (c, d); d defaults to 1. Hand-parsed rather than via a regexp so the
   library keeps no regexp dependency. *)
let parse_hunk line =
  match String.index_opt line '+' with
  | None -> None
  | Some plus ->
      let rest = String.sub line (plus + 1) (String.length line - plus - 1) in
      let stop =
        match String.index_opt rest ' ' with Some i -> i | None -> String.length rest
      in
      let spec = String.sub rest 0 stop in
      let start_s, count_s =
        match String.index_opt spec ',' with
        | Some i ->
            (String.sub spec 0 i, String.sub spec (i + 1) (String.length spec - i - 1))
        | None -> (spec, "1")
      in
      (match (int_of_string_opt start_s, int_of_string_opt count_s) with
      | Some s, Some c -> Some (s, c)
      | _ -> None)

let strip_b p = if starts_with ~prefix:"b/" p then String.sub p 2 (String.length p - 2) else p
let strip_a p = if starts_with ~prefix:"a/" p then String.sub p 2 (String.length p - 2) else p

(* Flags accepted in the RANGE position. Everything else starting with '-' is refused.

   An earlier version split any `--`-prefixed range on spaces into separate git tokens, which let
   a caller pass arbitrary git flags: `--output=/path` overwrites a file, `--no-index /etc/passwd
   /dev/null` reads outside the repository. That is reachable from the MCP server, whose whole
   threat model is that a tool takes no path arguments. An allowlist, not a pattern. *)
let allowed_flags = [ "--staged"; "--cached" ]

let changed_lines ~repo ~range =
  if String.length range > 0 && range.[0] = '-' && not (List.mem range allowed_flags) then
    Error
      (Printf.sprintf "refusing diff argument %S — only a git range, or one of [%s], is accepted"
         range (String.concat "; " allowed_flags))
  else
  let args = [ "diff"; "--unified=0"; "--no-color"; "--no-ext-diff"; range ] in
  match run_git repo args with
  | Error e -> Error e
  | Ok out ->
      let acc = ref SM.empty in
      let cur = ref None in
      let prev_old = ref None in
      (* Are we in a file HEADER, i.e. between `diff --git …` and that file's first `@@`?
         `--- ` and `+++ ` are only header markers there. Under --unified=0 a removed line is
         written as `-` ^ content, so a deleted SQL or Lua comment `-- x` arrives as `--- x` and
         a removed `++ x` as `+++ x`. Matching those as headers invented a file named after the
         comment text, or — when the text happened to be `/dev/null` — a spurious deletion.
         Anchoring on `diff --git` closes the whole family rather than special-casing the
         spellings that happen to have been noticed. *)
      let in_header = ref false in
      List.iter
        (fun line ->
          if starts_with ~prefix:"diff --git " line then (
            in_header := true ;
            cur := None ;
            prev_old := None)
          else if !in_header && starts_with ~prefix:"--- " line then (
            let p = String.trim (String.sub line 4 (String.length line - 4)) in
            prev_old := (if p = "/dev/null" then None else Some (strip_a p)))
          else if !in_header && starts_with ~prefix:"+++ " line then (
            let p = String.trim (String.sub line 4 (String.length line - 4)) in
            if p = "/dev/null" then (
              (* A DELETED file has no new side. Recording it under its OLD path with an empty
                 line set puts it in the file-granular branch, which is what a reviewer needs:
                 deleting a file is the most breaking change there is, and an earlier version
                 dropped it entirely and reported "the diff touches no indexed function". *)
              cur := None ;
              match !prev_old with
              | Some old when not (SM.mem old !acc) ->
                  acc := SM.add old (Lines (Hashtbl.create 1)) !acc
              | _ -> ())
            else
              let p = strip_b p in
              cur := Some p ;
              if not (SM.mem p !acc) then
                acc := SM.add p (Lines (Hashtbl.create 16)) !acc)
          else
            match (!cur, starts_with ~prefix:"@@" line) with
            | Some p, true -> (
                in_header := false ;
                match (parse_hunk line, SM.find_opt p !acc) with
                | Some (start, count), Some (Lines h) ->
                    if count = 0 then (
                      (* A PURE-DELETION hunk: `@@ -12,3 +11,0 @@` removes three lines and adds
                         none, so there is no new line to mark and the loop below marked nothing.
                         In a file that is otherwise modified this silently dropped the deletion
                         site — the enclosing function never appeared in the briefing. The two
                         lines straddling the removal are marked instead: over-attributing a
                         change to a neighbour is the safe direction here, dropping it is not. *)
                      Hashtbl.replace h (max 1 start) () ;
                      Hashtbl.replace h (start + 1) ())
                    else
                      for i = start to start + count - 1 do
                        Hashtbl.replace h i ()
                      done
                | _ -> ())
            | _, true -> in_header := false
            | _ -> ())
        (String.split_on_char '\n' out) ;
      Ok !acc

let of_files files =
  List.fold_left (fun m f -> if String.trim f = "" then m else SM.add (String.trim f) Whole m)
    SM.empty files
