(** Selectors: [file:<glob>], [fn:<glob>], [module:<glob>], [ext:<glob>].

    Shared so that [file:test/**] means the same thing in [arch-rules], [arch-mutants] and
    [arch-coverage]. *)

type kind = File | Fn | Module | Ext
type t = kind * string

let kind_name = function File -> "file" | Fn -> "fn" | Module -> "module" | Ext -> "ext"
let all_kinds = [ File; Fn; Module; Ext ]
let kinds_doc allow = String.concat ", " (List.map (fun k -> kind_name k ^ ":<glob>") allow)

(** [allow] is MANDATORY, and that is the point.

    [ext:] is meaningful in exactly one position — the TARGET of a [forbid reach]. An external
    leaf has no body, hence no outgoing edge and no file, so as a [reach] SOURCE, an [exported]
    allow-list, an [effect] cone or a [dep] operand it selects keys that can never participate:
    the rule then reports a green verdict it never earned. That is the failure this tool exists to
    prevent, so a caller cannot get it by omission — the compiler makes every call site name the
    kinds it can honestly serve, and a rejection is loud and specific rather than a silent empty
    set. Asymmetry that is recorded is fine; asymmetry that is silent is the bug. *)
let parse ~allow tok =
  match String.index_opt tok ':' with
  | None -> Error (Printf.sprintf "bad selector %S — expected one of: %s" tok (kinds_doc allow))
  | Some i -> (
      let k = String.sub tok 0 i and pat = String.sub tok (i + 1) (String.length tok - i - 1) in
      match List.find_opt (fun c -> kind_name c = k) all_kinds with
      | None ->
          Error
            (Printf.sprintf "bad selector kind %S — expected one of: %s" k
               (String.concat ", " (List.map kind_name allow)))
      | Some c when not (List.mem c allow) ->
          (* Named separately from an unknown kind: `ext` IS a selector kind, it is just not
             answerable here, and "expected file, fn or module" would send the author looking for
             a typo that is not there. *)
          Error
            (Printf.sprintf "selector kind %S is not valid in this position — only %s. %s" k
               (String.concat ", " (List.map kind_name allow))
               (match c with
                | Ext -> "`ext:` matches external leaves, which have no body, no outgoing edge and no file, so it is answerable only as the target of `forbid reach`. Here it would match nothing that can participate, and the rule would report a green verdict it never earned."
                | File | Fn | Module -> "This position reads a different population."))
      | Some c -> Ok (c, pat))

let to_string (k, p) = kind_name k ^ ":" ^ p

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
    except [forbid dep] — which reads declared module paths from a table, not from the graph.

    [ext:] is the one kind that does NOT range over [Arch_graph.nodes]: external leaves are not
    nodes (see [Arch_graph.ext_keys]), so it ranges over the external keys and matches the glob
    against the callee name with any ["ext:"] prefix stripped — the name as written at the call
    site, which is what a report shows and what a rule author can be asked to type. *)
let select (g : Arch_graph.t) ((k, pat) : t) =
  match k with
  | Ext ->
      Arch_graph.SS.filter
        (fun key -> glob_match pat (Arch_graph.ext_name key))
        (Arch_graph.ext_keys g)
  | File | Fn | Module ->
      List.fold_left
        (fun acc (n : Arch_graph.node) ->
          let target = match k with Fn -> Some n.name | File | Module -> n.file | Ext -> None in
          match target with
          | Some v when glob_match pat v -> Arch_graph.SS.add n.key acc
          | _ -> acc)
        Arch_graph.SS.empty (Arch_graph.nodes g)
