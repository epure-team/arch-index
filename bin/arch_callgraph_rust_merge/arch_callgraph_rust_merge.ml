(** arch-callgraph-rust-merge — whole-program dyn-dispatch narrowing pass.

    Consumes the UNION of NDJSON streams from every crate in a workspace batch
    (each crate's own `arch-callgraph-rust` run over its own compilation) and
    rewrites `dyn`-dispatch `MAY_TOP` call records — tagged with
    `x_dyn_trait`/`x_dyn_method` by the producer — into one or more
    `MAY_ENUMERATED` edges per matching non-blanket trait impl found anywhere
    in the batch.

    Consumes `trait_impl_fact` records (stripped from the final output —
    `arch-load`'s strict record-type contract must never see them) and the
    `x_dyn_trait`/`x_dyn_method` extension fields on `call` records (also
    stripped, whether or not the site was narrowed).

    Safety gates (spec `specs/rust-soundcg-whole-program.md`):
    - **Publish-boundary gate**: narrow only when every fact for a trait
      agrees its DEFINING crate has `publish = false` — otherwise an
      external, unseen crate could implement it, so the site stays MAY_TOP.
    - **Blanket-impl gate**: any blanket impl for a trait anywhere in the
      batch forces MAY_TOP for every dyn-dispatch site on that trait.
    - **Missing-facts fallback**: coarse, whole-batch (not per-trait) in this
      round — if `--expected-crates` names a crate absent from the batch (no
      function record with a `file_path` under `<crate>/`), every dyn site
      in the whole run stays MAY_TOP. A finer per-trait fallback (only the
      traits touched by the missing crate's facts) is deferred — documented
      residual, see README. *)

type fact = {
  method_name : string;
  impl_fn_stable_name : string;
}

type trait_entry = {
  mutable impls : fact list;
  mutable any_blanket : bool;
  mutable all_publish_false : bool;
}

let get_str obj k =
  match List.assoc_opt k obj with Some (`String s) -> Some s | _ -> None

let get_bool obj k =
  match List.assoc_opt k obj with Some (`Bool b) -> Some b | _ -> None

let parse_line line_num line =
  match Yojson.Safe.from_string line with
  | exception Yojson.Json_error msg ->
    failwith (Printf.sprintf "invalid JSON (line %d): %s" line_num msg)
  | `Assoc obj -> obj
  | _ -> failwith (Printf.sprintf "not a JSON object (line %d)" line_num)

let read_all_lines ic =
  let lines = ref [] in
  (try
     while true do
       let raw = input_line ic in
       let line = String.trim raw in
       if line <> "" then lines := line :: !lines
     done
   with End_of_file -> ());
  List.rev !lines

(* ── CLI ────────────────────────────────────────────────────────────────── *)

let expected_crates = ref []

let parse_args () =
  let argv = Sys.argv in
  let i = ref 1 in
  while !i < Array.length argv do
    (match argv.(!i) with
     | "--expected-crates" when !i + 1 < Array.length argv ->
       expected_crates :=
         String.split_on_char ',' argv.(!i + 1)
         |> List.map String.trim
         |> List.filter (fun s -> s <> "");
       incr i
     | arg ->
       Printf.eprintf "arch-callgraph-rust-merge: unrecognized argument %S\n" arg;
       exit 2);
    incr i
  done

(* ── main ──────────────────────────────────────────────────────────────── *)

let () =
  parse_args ();
  let raw_lines = read_all_lines stdin in
  let parsed =
    List.mapi (fun idx line -> (parse_line (idx + 1) line)) raw_lines
  in

  (* Pass 1: collect facts, function file_paths (presence check + callee_file
     lookup for enumerated candidates), and the trait index. *)
  let facts_by_trait : (string, trait_entry) Hashtbl.t = Hashtbl.create 64 in
  let file_path_by_fn_name : (string, string) Hashtbl.t = Hashtbl.create 512 in
  let fn_file_paths = ref [] in
  List.iter
    (fun obj ->
      match get_str obj "type" with
      | Some "trait_impl_fact" ->
        let trait_path = Option.value (get_str obj "trait_path") ~default:"" in
        let method_name = Option.value (get_str obj "method_name") ~default:"" in
        let impl_fn_stable_name =
          Option.value (get_str obj "impl_fn_stable_name") ~default:""
        in
        let publish_false = Option.value (get_bool obj "publish_false") ~default:false in
        let is_blanket = Option.value (get_bool obj "is_blanket") ~default:false in
        let entry =
          match Hashtbl.find_opt facts_by_trait trait_path with
          | Some e -> e
          | None ->
            let e = { impls = []; any_blanket = false; all_publish_false = true } in
            Hashtbl.add facts_by_trait trait_path e;
            e
        in
        entry.impls <- { method_name; impl_fn_stable_name } :: entry.impls;
        if is_blanket then entry.any_blanket <- true;
        if not publish_false then entry.all_publish_false <- false
      | Some "function" ->
        (match get_str obj "name", get_str obj "file_path" with
         | Some name, Some fp ->
           Hashtbl.replace file_path_by_fn_name name fp;
           fn_file_paths := fp :: !fn_file_paths
         | Some _, None -> ()
         | None, _ -> ())
      | _ -> ())
    parsed;

  (* Missing-facts fallback (coarse, whole-batch): a named expected crate is
     "present" iff some function's file_path begins with "<crate>/" — mirrors
     the harness's own completeness-check heuristic in `arch-callgraph-rust`. *)
  let global_fallback =
    !expected_crates <> []
    && List.exists
         (fun crate ->
           let prefix = crate ^ "/" in
           not
             (List.exists
                (fun fp -> String.length fp >= String.length prefix
                           && String.sub fp 0 (String.length prefix) = prefix)
                !fn_file_paths))
         !expected_crates
  in
  if global_fallback then
    Printf.eprintf
      "arch-callgraph-rust-merge: a named --expected-crates crate has no function \
       record in this batch — falling back to MAY_TOP for every dyn-dispatch site \
       (whole-batch fallback, not per-trait).\n";

  (* Pass 2: emit function/call records verbatim; narrow or defang dyn call
     records; drop trait_impl_fact records entirely. *)
  let buf = Buffer.create (1024 * 64) in
  let n_narrowed = ref 0 in
  let n_kept_top = ref 0 in
  let emit_json (fields : (string * Yojson.Safe.t) list) =
    Buffer.add_string buf (Yojson.Safe.to_string (`Assoc fields));
    Buffer.add_char buf '\n'
  in
  let strip_dyn_fields obj =
    List.filter (fun (k, _) -> k <> "x_dyn_trait" && k <> "x_dyn_method") obj
  in
  List.iteri
    (fun idx obj ->
      match get_str obj "type" with
      | Some "trait_impl_fact" -> ()
      | Some "function" -> emit_json obj
      | Some "call" | None when List.mem_assoc "callee_name" obj ->
        let is_dyn_top =
          get_str obj "kind" = Some "MAY_TOP"
          && List.mem_assoc "x_dyn_trait" obj
        in
        if not is_dyn_top then emit_json obj
        else begin
          let trait_path = Option.value (get_str obj "trait_path") ~default:"" in
          let trait_path =
            match get_str obj "x_dyn_trait" with Some t -> t | None -> trait_path
          in
          let method_name =
            Option.value (get_str obj "x_dyn_method") ~default:""
          in
          let caller_name = List.assoc "caller_name" obj in
          let caller_file =
            match List.assoc_opt "caller_file" obj with Some v -> v | None -> `Null
          in
          let call_site = List.assoc "call_site" obj in
          let entry = Hashtbl.find_opt facts_by_trait trait_path in
          let narrow =
            match entry with
            | None -> false
            | Some e -> (not global_fallback) && (not e.any_blanket) && e.all_publish_false
          in
          if not narrow then begin
            incr n_kept_top;
            emit_json (strip_dyn_fields obj)
          end
          else begin
            let e = Option.get entry in
            let matching =
              List.filter (fun f -> f.method_name = method_name) e.impls
            in
            if matching = [] then begin
              incr n_kept_top;
              emit_json (strip_dyn_fields obj)
            end
            else
              List.iter
                (fun f ->
                  incr n_narrowed;
                  let callee_file =
                    match Hashtbl.find_opt file_path_by_fn_name f.impl_fn_stable_name with
                    | Some fp -> `String fp
                    | None -> `Null
                  in
                  emit_json
                    [
                      ("type", `String "call");
                      ("caller_name", caller_name);
                      ("caller_file", caller_file);
                      ("callee_name", `String f.impl_fn_stable_name);
                      ("callee_file", callee_file);
                      ("call_site", call_site);
                      ("kind", `String "MAY_ENUMERATED");
                    ])
                matching
          end
        end
      | _ ->
        Printf.eprintf
          "arch-callgraph-rust-merge: warning — unrecognized record at line %d, passing through unchanged\n"
          (idx + 1);
        emit_json obj)
    parsed;

  print_string (Buffer.contents buf);
  Printf.eprintf
    "arch-callgraph-rust-merge: %d dyn-dispatch site(s) narrowed to MAY_ENUMERATED, %d kept MAY_TOP%s\n"
    !n_narrowed !n_kept_top
    (if global_fallback then " (global missing-facts fallback active)" else "")
