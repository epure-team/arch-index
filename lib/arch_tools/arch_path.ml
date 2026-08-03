(** Matching a path as the world sees it against a path as the index recorded it.

    The Go producer records the absolute filename the compiler saw ([packages.Load]); the OCaml
    CMT producer records a repo-relative one; a coverage tool records whatever its build
    directory was. A diff, meanwhile, always speaks repo-relative. So the join is exact-first,
    then longest-suffix.

    Suffix matching is {b ambiguous} in principle — two [main.go] under different directories —
    so a path resolving to several indexed paths keeps {i all} of them. Over-attributing a
    change is the safe direction, and the ambiguity is reported by callers rather than silently
    resolved. *)

module SS = Set.Make (String)
module SM = Map.Make (String)

type t = { by_norm : SS.t SM.t; repo : string }

(* Textual normalisation only: no realpath, no filesystem access. The indexed path may name a
   build directory that no longer exists, and a resolver that needed the file to be present
   would silently stop matching. *)
let normalise p =
  let parts = String.split_on_char '/' p in
  let absolute = String.length p > 0 && p.[0] = '/' in
  (* A leading [..] has nothing to cancel and must be KEPT. Popping it made [../../a] normalise
     to [a] — the same key as a file actually at [a], so a tracefile emitted from a build
     directory two levels down joined to the wrong indexed file. The one exception is an absolute
     path, where POSIX defines [/..] as [/]. *)
  let rec go acc = function
    | [] -> List.rev acc
    | "." :: rest -> go acc rest
    (* Including the LEADING empty component of an absolute path. Keeping it (the guard here used
       to be [when acc <> []]) left "" at the bottom of the accumulator, and the "/" prefix was
       then added on top of it: "/a/b/../c" normalised to "//a/c" and joined to nothing. *)
    | "" :: rest -> go acc rest
    | ".." :: rest -> (
        match acc with
        | x :: tl when x <> ".." -> go tl rest
        | [] when absolute -> go acc rest
        | _ -> go (".." :: acc) rest)
    | x :: rest -> go (x :: acc) rest
  in
  (if absolute then "/" else "") ^ String.concat "/" (go [] parts)

let make ~repo indexed_paths =
  let by_norm =
    List.fold_left
      (fun m p ->
        if p = "" then m
        else
          SM.update (normalise p)
            (function None -> Some (SS.singleton p) | Some s -> Some (SS.add p s))
            m)
      SM.empty indexed_paths
  in
  { by_norm; repo }

let ends_at_boundary ~suffix s =
  let ls = String.length s and lf = String.length suffix in
  lf <= ls && String.sub s (ls - lf) lf = suffix

let resolve t p =
  let exact =
    List.fold_left
      (fun acc cand ->
        match SM.find_opt (normalise cand) t.by_norm with
        | Some s -> SS.union acc s
        | None -> acc)
      SS.empty
      [ p; Filename.concat t.repo p ]
  in
  if not (SS.is_empty exact) then exact
  else
    (* The indexed path must end at a path BOUNDARY, so 'x/main.go' never matches
       'x/domain.go'. *)
    let tail = "/" ^ (if String.length p > 0 && p.[0] = '/' then String.sub p 1 (String.length p - 1) else p) in
    SM.fold
      (fun norm originals acc ->
        if ends_at_boundary ~suffix:tail norm then SS.union acc originals else acc)
      t.by_norm SS.empty
