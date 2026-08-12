(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** The Go CHA producer, end to end: arch-callgraph-go → arch-load → arch-query.

    The producer is BUILT from this repository rather than taken from PATH, and
    the Go module under analysis is written here, so the three edge kinds are
    present by construction and each verdict has a known cause:

    - a direct static call in a block that post-dominates the entry is MUST;
    - an interface call is MAY_ENUMERATED over the CHA candidate set;
    - [reflect.Value.Call] is unknowable, so it anchors a MAY_TOP.

    The gated case is the one worth reading twice: [island] is uniquely
    resolved, but it is called only inside an `if`, so the edge must be demoted.
    Demoted to MAY_ENUMERATED — a candidate set of one — not to MAY_TOP, which
    would make every question about it undecidable. *)

open Arch_tezt

let go_module =
  {|package main

import "reflect"

// interface: MAY_ENUMERATED call sites (CHA enumerates ImplA.Do and ImplB.Do)
type Doer interface{ Do() int }
type ImplA struct{}
type ImplB struct{}
func (ImplA) Do() int { return 1 }
func (ImplB) Do() int { return 2 }

func direct() int { return 42 }

// never called: the target for UNREACHABLE
func island() int { return 99 }

func useInterface(d Doer) int { return d.Do() }

// reflect.Value.Call is a soundiness hole: the ⊤ anchor
func dirty(v interface{}) {
	reflect.ValueOf(v).Call(nil)
}

// island is called ONLY inside an if-branch, so the uniquely-resolved edge must
// be demoted rather than recorded as MUST — and never dropped.
func gatedEntry(b bool) int {
	if b {
		return island()
	}
	return direct()
}

func cleanEntry() int   { return direct() + useInterface(ImplA{}) }
func dirtyEntry()       { dirty(nil) }

func main() { cleanEntry() }
|}

(* cgo synthesises _Cfunc_* wrappers INSIDE the user's package. A call through
   one crosses into C, which may call back into arbitrary exported Go, so it has
   to be reclassified as a ⊤ anchor — otherwise `unreachable` can claim
   UNREACHABLE across a C callback. *)
let cgo_module =
  {|package main

/*
extern void goCallback();
static void call_go() { goCallback(); }
*/
import "C"

func island() int { return 1 }

//export goCallback
func goCallback() { island() }

func cgoBranch(b bool) {
	if b {
		C.call_go()
	}
}

func main() { cgoBranch(true) }
|}

let build_producer () =
  let bin = Filename.concat (Temp.dir "cggo_bin") "arch-callgraph-go" in
  let code, output =
    run_command ~cwd:(callgraph_go_src ()) "go" ["build"; "-o"; bin; "."]
  in
  if code <> 0 then Test.fail "building arch-callgraph-go failed (exit %d):\n%s" code output ;
  bin

(* The producer's names are package-qualified (testcg.direct, testcg.(ImplA).Do),
   so the test discovers them rather than hard-coding a mangling that is the
   producer's business. A name that does not resolve is a hard failure, not a
   skipped assertion: every verdict below would otherwise be asked about a
   function that does not exist, and answered vacuously. *)
let discover db ~like ~unlike =
  Db.with_db db (fun conn ->
      let sql =
        match unlike with
        | Some u ->
            Printf.sprintf
              "SELECT name FROM functions WHERE name LIKE '%%%s%%' AND name NOT LIKE '%%%s%%' \
               LIMIT 1"
              like u
        | None -> Printf.sprintf "SELECT name FROM functions WHERE name LIKE '%%%s%%' LIMIT 1" like
      in
      match Db.string_opt conn sql with
      | Some n -> n
      | None -> Test.fail "the producer emitted no function matching %S" like)

let index_go_module ~name source =
  let producer = build_producer () in
  let root = Temp.dir name in
  write_file (Filename.concat root "go.mod") "module testcg\ngo 1.21\n" ;
  write_file (Filename.concat root "main.go") source ;
  let code, ndjson, err = run_command_split producer [Filename.concat root "..."] in
  if code <> 0 then Test.fail "arch-callgraph-go failed (exit %d):\n%s" code err ;
  let db = temp_db name in
  if Sys.file_exists db then Sys.remove db ;
  let code, out = run_command ~stdin:ndjson (arch_load ()) [db] in
  if code <> 0 then Test.fail "arch-load rejected the producer's stream (exit %d):\n%s" code out ;
  db

let register () =
  Test.register ~__FILE__ ~title:"callgraph-go: the three edge kinds and the verdicts they license"
    ~tags:["callgraph"; "go"]
  @@ fun () ->
  if not (runnable "go" ["version"]) then not_exercised "Go: the go toolchain is not runnable"
  else begin
    let db = index_go_module ~name:"cggo" go_module in
    let clean = discover db ~like:"cleanEntry" ~unlike:None in
    let dirty_e = discover db ~like:"dirtyEntry" ~unlike:None in
    let island = discover db ~like:"island" ~unlike:None in
    let direct = discover db ~like:"direct" ~unlike:(Some "dirty") in
    let impl_a = discover db ~like:"(ImplA).Do" ~unlike:None in
    let gated = discover db ~like:"gatedEntry" ~unlike:None in
    Batch.run (fun b ->
        Db.with_db db (fun conn ->
            Batch.eq_string_opt b ~msg:"the produced index must carry the ⊤-marking contract"
              (Db.string_opt conn
                 "SELECT value FROM comment_db_meta WHERE key='callgraph_contract'")
              (Some "v1") ;
            Batch.ge_int b ~msg:"the producer must emit functions"
              (Db.int conn "SELECT count(*) FROM functions") 1 ;
            (* The loader is supposed to reject an un-kinded edge, so a single
               one here means enforcement failed upstream of the query layer. *)
            Batch.eq_int b ~msg:"no edge may carry a missing or invalid kind"
              (Db.int conn
                 "SELECT count(*) FROM calls WHERE kind IS NULL OR kind NOT IN \
                  ('MUST','MAY_ENUMERATED','MAY_TOP')")
              0) ;

        (* reaches: MUST only. *)
        Batch.contains b ~msg:"cleanEntry -> direct is a MUST path"
          ~haystack:(query db ["reaches"; clean; direct]) "PATH EXISTS (must-reach)" ;
        Batch.contains b ~msg:"cleanEntry -> ImplA.Do goes through an interface, so no MUST path"
          ~haystack:(query db ["reaches"; clean; impl_a]) "no MUST path" ;

        (* unreachable: sound over-approximation. *)
        Batch.contains b ~msg:"cleanEntry's closure holds no ⊤, so island is UNREACHABLE"
          ~haystack:(query db ["unreachable"; clean; island]) "UNREACHABLE:" ;
        Batch.contains b ~msg:"ImplA.Do is in the CHA candidate set, so REACHABLE"
          ~haystack:(query db ["unreachable"; clean; impl_a]) "REACHABLE (may-reach)" ;
        let dirty_island = query db ["unreachable"; dirty_e; island] in
        Batch.contains b ~msg:"dirtyEntry reaches reflect.Value.Call, so island is UNKNOWN"
          ~haystack:dirty_island "UNKNOWN:" ;
        Batch.not_contains b
          ~msg:"island must never read UNREACHABLE from dirtyEntry while a ⊤ is reachable"
          ~haystack:dirty_island "UNREACHABLE:" ;

        (* escapes: the ⊤ frontier, and its absence. *)
        Batch.ge_int b ~msg:"escapes dirtyEntry must list at least one escaping function"
          (List.length (lines (query db ["escapes"; dirty_e])))
          1 ;
        Batch.eq_int b ~msg:"escapes cleanEntry must be empty — no ⊤ in its closure"
          (List.length (lines (query db ["escapes"; clean])))
          0 ;

        (* Dominance: a conditional static call is never MUST, and never dropped. *)
        Batch.contains b ~msg:"gatedEntry -> island is conditional, so no MUST path"
          ~haystack:(query db ["reaches"; gated; island]) "no MUST path" ;
        Batch.contains b ~msg:"gatedEntry -> direct is in the else-branch, so no MUST path either"
          ~haystack:(query db ["reaches"; gated; direct]) "no MUST path" ;
        Batch.not_contains b ~msg:"a conditional call is still recorded, so never UNREACHABLE"
          ~haystack:(query db ["unreachable"; gated; island]) "UNREACHABLE:" ;

        (* Enumerated demotion: a candidate set of one, not ⊤ — which is what
           keeps the question decidable. *)
        Db.with_db db (fun conn ->
            Batch.eq_string_opt b
              ~msg:"gatedEntry -> island must be MAY_ENUMERATED, not MAY_TOP"
              (Db.string_opt conn
                 "SELECT MAX(kind) FROM calls WHERE caller_name LIKE '%gatedEntry%' AND \
                  callee_name LIKE '%island%'")
              (Some "MAY_ENUMERATED")) ;
        Batch.contains b ~msg:"an enumerated conditional callee makes island REACHABLE"
          ~haystack:(query db ["unreachable"; gated; island]) "REACHABLE (may-reach)")
  end ;
  Lwt.return_unit

let register_cgo () =
  Test.register ~__FILE__ ~title:"callgraph-go: a cgo wrapper call is a ⊤ anchor"
    ~tags:["callgraph"; "go"; "cgo"]
  @@ fun () ->
  let cgo_enabled =
    let _, out = run_command "go" ["env"; "CGO_ENABLED"] in
    String.trim out = "1"
  in
  if not (runnable "go" ["version"]) then not_exercised "Go: the go toolchain is not runnable"
  else if not (cgo_enabled && runnable "cc" ["--version"]) then
    not_exercised "cgo: CGO_ENABLED is not 1, or there is no C toolchain"
  else begin
    let producer = build_producer () in
    let root = Temp.dir "cggo_cgo" in
    write_file (Filename.concat root "go.mod") "module cgocb\ngo 1.21\n" ;
    write_file (Filename.concat root "main.go") cgo_module ;
    let code, ndjson, err = run_command_split producer [root] in
    if code <> 0 then Test.fail "arch-callgraph-go failed on the cgo module (exit %d):\n%s" code err ;
    let kind_of_cgo_branch =
      lines ndjson
      |> List.find_map (fun l ->
             match Yojson.Safe.from_string l with
             | `Assoc f -> (
                 match
                   (List.assoc_opt "type" f, List.assoc_opt "caller_name" f,
                    List.assoc_opt "kind" f)
                 with
                 | Some (`String "call"), Some (`String caller), Some (`String kind)
                   when has_prefix ~prefix:"cgocb.cgoBranch" caller
                        || (String.length caller >= 9
                           && Filename.check_suffix caller "cgoBranch") ->
                     Some kind
                 | _ -> None)
             | _ -> None
             | exception _ -> None)
    in
    Batch.run (fun b ->
        Batch.eq_string_opt b
          ~msg:
            "a call through a cgo wrapper must be MAY_TOP: C may call back into arbitrary \
             exported Go, so UNREACHABLE cannot be claimed across it"
          kind_of_cgo_branch (Some "MAY_TOP"))
  end ;
  Lwt.return_unit
