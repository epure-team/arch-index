(** arch-body-compare — proof of syntactic duplication via body-hash.

    A2's measures (large-files, god-modules, ...) never claim a verdict — "too big" is a human
    judgement. Body-hash is different in kind: two occurrences whose normalised bodies hash
    identically ARE the same source text, which is a fact, not a threshold call. This is the CLI
    surface for {!Arch_index.Arch_index_compare.compare_bodies}, which existed in the tree with no
    consumer at all before this tool.

    Requires the MAIN schema (a [modules] table with source line spans) — a flat [arch-load] index
    has no source-file mapping to read bodies from. *)

open Arch_index

let usage =
  {|arch-body-compare — proof of syntactic duplication via body-hash (main schema only).

Usage:
  arch-body-compare <db> <name> [--repo DIR]
      Compare every occurrence of a single function NAME across the index.

  arch-body-compare <db> duplicates [N] [--repo DIR] [--format text|json]
      Sweep every name defined more than once; report the ones PROVEN identical (normalised
      body-hash match) as duplicates, sorted by name, top-N (default 25).

  --repo DIR      repository root prepended to indexed paths when reading source (default ".")
  --format FMT    text (default) | json  — duplicates mode only

This is a PROOF (body-hash), not a heuristic: never "roughly similar", always "byte-identical
after whitespace normalisation". An occurrence whose body could not be read (missing file, or an
empty line span) is EXCLUDED from the duplicate verdict and reported separately as unverifiable —
two unreadable bodies hash the same as each other by construction, and that is not evidence of
duplication, it is evidence of nothing.|}

let die code msg =
  prerr_endline msg ;
  exit code

let format_occ (o : Arch_index_compare.occurrence) = Printf.sprintf "%s:%d-%d" o.path o.line_start o.line_end

let take n l = List.filteri (fun i _ -> i < n) l

(* ------------------------------------------------------------------ *)
(* single-name mode                                                    *)
(* ------------------------------------------------------------------ *)

let run_single db ~repo name =
  match Arch_index_compare.compare_bodies db ~project_root:repo name with
  | Arch_index_compare.Not_found -> Printf.printf "NOT FOUND: no function named %s in this index\n" name
  | Arch_index_compare.Identical [ one ] ->
      Printf.printf "SINGLE: only one definition of %s (%s) — nothing to compare\n" name (format_occ one)
  | Arch_index_compare.Identical occs -> (
      match List.filter (fun (o : Arch_index_compare.occurrence) -> o.body = "") occs with
      | [] ->
          Printf.printf "DUPLICATE: %d occurrence(s) of %s share an identical body (proof, body-hash)\n"
            (List.length occs) name ;
          List.iter (fun o -> Printf.printf "  %s\n" (format_occ o)) occs
      | empties ->
          Printf.printf
            "UNVERIFIABLE: %d occurrence(s) of %s hash identical, but %d could not be read \
             (missing file or empty span) — not proof of duplication\n"
            (List.length occs) name (List.length empties) ;
          List.iter
            (fun o ->
              Printf.printf "  %s%s\n" (format_occ o)
                (if o.Arch_index_compare.body = "" then "  [unreadable/empty]" else ""))
            occs)
  | Arch_index_compare.Differs groups ->
      let total = List.fold_left (fun acc (_, os) -> acc + List.length os) 0 groups in
      Printf.printf "DIFFERS: %d occurrence(s) of %s across %d distinct bodies — not duplicates\n" total
        name (List.length groups) ;
      List.iter
        (fun (digest, occs) ->
          Printf.printf "  body %s:\n" (String.sub digest 0 8) ;
          List.iter (fun o -> Printf.printf "    %s\n" (format_occ o)) occs)
        (List.sort (fun (d1, _) (d2, _) -> compare d1 d2) groups)

(* ------------------------------------------------------------------ *)
(* duplicates mode: sweep every name defined more than once             *)
(* ------------------------------------------------------------------ *)

let candidate_names db =
  let stmt = Sqlite3.prepare db "SELECT name FROM functions GROUP BY name HAVING count(*) > 1 ORDER BY name" in
  let acc = ref [] in
  let rec loop () =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        (match Sqlite3.column stmt 0 with Sqlite3.Data.TEXT s -> acc := s :: !acc | _ -> ()) ;
        loop ()
    | _ -> ()
  in
  loop () ;
  ignore (Sqlite3.finalize stmt) ;
  List.rev !acc

let run_duplicates db ~repo ~limit ~fmt =
  let names = candidate_names db in
  let duplicates = ref [] and unverifiable = ref [] and differs = ref 0 in
  List.iter
    (fun name ->
      match Arch_index_compare.compare_bodies db ~project_root:repo name with
      | Arch_index_compare.Identical occs when List.length occs > 1 ->
          if List.exists (fun (o : Arch_index_compare.occurrence) -> o.body = "") occs then
            unverifiable := (name, occs) :: !unverifiable
          else duplicates := (name, occs) :: !duplicates
      | Arch_index_compare.Differs _ -> incr differs
      | Arch_index_compare.Identical _ | Arch_index_compare.Not_found -> ())
    names ;
  let duplicates = List.rev !duplicates and unverifiable = List.rev !unverifiable in
  let shown = take limit duplicates in
  if fmt = "json" then
    print_endline
      (Yojson.Safe.pretty_to_string
         (`Assoc
           [ ("candidates_with_multiple_definitions", `Int (List.length names));
             ( "proven_duplicates",
               `List
                 (List.map
                    (fun (n, occs) ->
                      `Assoc
                        [ ("name", `String n);
                          ( "occurrences",
                            `List
                              (List.map
                                 (fun (o : Arch_index_compare.occurrence) ->
                                   `Assoc
                                     [ ("path", `String o.path); ("line_start", `Int o.line_start);
                                       ("line_end", `Int o.line_end) ])
                                 occs) ) ])
                    shown) );
             ("unverifiable_empty_body", `List (List.map (fun (n, _) -> `String n) unverifiable));
             ("differs_count", `Int !differs);
             ("truncated", `Bool (List.length duplicates > limit)) ]))
  else (
    Printf.printf
      "%d name(s) defined more than once; %d proven duplicate (body-hash), %d differ, %d \
       unverifiable (empty/unreadable body)\n"
      (List.length names) (List.length duplicates) !differs (List.length unverifiable) ;
    List.iter
      (fun (name, occs) ->
        Printf.printf "DUPLICATE %s (%d occurrences):\n" name (List.length occs) ;
        List.iter (fun o -> Printf.printf "  %s\n" (format_occ o)) occs)
      shown ;
    if List.length duplicates > limit then
      Printf.printf "... %d more (raise N to see them)\n" (List.length duplicates - limit) ;
    if unverifiable <> [] then (
      Printf.printf "UNVERIFIABLE (excluded from the duplicate count above):\n" ;
      List.iter (fun (name, _) -> Printf.printf "  %s\n" name) unverifiable))

(* ------------------------------------------------------------------ *)

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  let opt name default =
    let rec go = function a :: v :: _ when a = name -> v | _ :: tl -> go tl | [] -> default in
    go args
  in
  let flags = [ "--repo"; "--format" ] in
  let positional =
    let rec go acc = function
      | a :: v :: tl when List.mem a flags ->
          ignore v ;
          go acc tl
      | a :: tl -> go (a :: acc) tl
      | [] -> List.rev acc
    in
    go [] args
  in
  let db_path, mode_arg, extra =
    match positional with
    | d :: m :: rest -> (d, m, rest)
    | _ ->
        prerr_endline usage ;
        exit 2
  in
  let repo = opt "--repo" "." in
  let fmt = opt "--format" "text" in
  if not (Sys.file_exists db_path) then die 2 (Printf.sprintf "arch-body-compare: no such db: %s" db_path) ;
  let db = Sqlite3.db_open ~mode:`READONLY db_path in
  let has_table name =
    let stmt =
      Sqlite3.prepare db "SELECT count(*) FROM sqlite_master WHERE type IN ('table','view') AND name=?"
    in
    ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT name)) ;
    let r =
      match Sqlite3.step stmt with
      | Sqlite3.Rc.ROW -> ( match Sqlite3.column stmt 0 with Sqlite3.Data.INT n -> n > 0L | _ -> false)
      | _ -> false
    in
    ignore (Sqlite3.finalize stmt) ;
    r
  in
  if not (has_table "functions") then
    die 2 (Printf.sprintf "arch-body-compare: %s has no `functions` table — not an arch-index DB" db_path) ;
  if not (has_table "modules") then
    die 3
      "arch-body-compare: REFUSED — requires the main schema (a `modules` table with source line \
       spans); a flat (arch-load) index has no source-file mapping to read bodies from." ;
  (match mode_arg with
  | "duplicates" ->
      let limit = match extra with n :: _ -> Option.value ~default:25 (int_of_string_opt n) | [] -> 25 in
      run_duplicates db ~repo ~limit ~fmt
  | "" -> die 2 "arch-body-compare: a function NAME (or `duplicates`) is required."
  | name -> run_single db ~repo name) ;
  ignore (Sqlite3.db_close db)
