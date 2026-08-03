(** Selectors: [file:<glob>], [fn:<glob>], [module:<glob>].

    Shared so that [file:test/**] means the same thing in [arch-rules], [arch-mutants] and
    [arch-coverage]. *)

type kind = File | Fn | Module
type t = kind * string

let parse tok =
  match String.index_opt tok ':' with
  | None -> Error (Printf.sprintf "bad selector %S — expected file:<glob>, fn:<glob> or module:<glob>" tok)
  | Some i -> (
      let k = String.sub tok 0 i and pat = String.sub tok (i + 1) (String.length tok - i - 1) in
      match k with
      | "file" -> Ok (File, pat)
      | "fn" -> Ok (Fn, pat)
      | "module" -> Ok (Module, pat)
      | _ -> Error (Printf.sprintf "bad selector kind %S — expected file, fn or module" k))

let to_string (k, p) =
  (match k with File -> "file" | Fn -> "fn" | Module -> "module") ^ ":" ^ p

(** Shell-style glob where [*] stops at ['/'] and [**] crosses it.

    [**/] compiles to [(?:.*/)?] — zero or more {b whole} directory components — so
    [**/parser.ml] matches [lib/parser.ml] and bare [parser.ml] but {b never} [lib/my_parser.ml].
    Getting this wrong is not cosmetic: a rule aimed at one file silently covering a
    differently-named sibling turns an architecture gate into a source of false verdicts in
    both directions. (An earlier version compiled [**/] to [.*/?] and did exactly that.)

    Implemented as a direct matcher rather than via Str, so the library needs no regexp
    dependency and the semantics are visible in one place. *)
let glob_match pattern value =
  let plen = String.length pattern and vlen = String.length value in
  (* memo.(i).(j) = "already proved (i,j) cannot match", so a pattern with several `**` cannot
     blow up exponentially on a long path. *)
  let memo = Array.make_matrix (plen + 1) (vlen + 1) false in
  let rec go i j =
    if memo.(i).(j) then false
    else if i >= plen then j >= vlen
    else
      let ok =
        if i + 2 < plen && pattern.[i] = '*' && pattern.[i + 1] = '*' && pattern.[i + 2] = '/'
        then
          (* zero components, or skip one whole component and retry *)
          go (i + 3) j
          || (let rec skip j =
                if j >= vlen then false
                else if value.[j] = '/' then go (i + 3) (j + 1) || skip (j + 1)
                else skip (j + 1)
              in
              skip j)
        else if i + 1 < plen && pattern.[i] = '*' && pattern.[i + 1] = '*' then
          let rec any j = go (i + 2) j || (j < vlen && any (j + 1)) in
          any j
        else if pattern.[i] = '*' then
          let rec any j =
            go (i + 1) j || (j < vlen && value.[j] <> '/' && any (j + 1))
          in
          any j
        else if pattern.[i] = '?' then j < vlen && value.[j] <> '/' && go (i + 1) (j + 1)
        else j < vlen && pattern.[i] = value.[j] && go (i + 1) (j + 1)
      in
      if not ok then memo.(i).(j) <- true ;
      ok
  in
  go 0 0

(** Resolve a selector to graph keys. [module:] matches the path, like [file:], everywhere
    except [forbid dep] — which reads declared module paths from a table, not from the graph. *)
let select (g : Arch_graph.t) ((k, pat) : t) =
  List.fold_left
    (fun acc (n : Arch_graph.node) ->
      let target = match k with Fn -> Some n.name | File | Module -> n.file in
      match target with
      | Some v when glob_match pat v -> Arch_graph.SS.add n.key acc
      | _ -> acc)
    Arch_graph.SS.empty (Arch_graph.nodes g)
