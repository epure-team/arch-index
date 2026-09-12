(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Runner failures are diagnostics, not verbose progress narration. *)

open Arch_tezt

let go_project =
  [("go.mod", "module stub\n\ngo 1.21\n"); ("main.go", "package main\n\nfunc main() {}\n")]

let count_occurrences ~needle haystack =
  let needle_len = String.length needle in
  let rec loop count from =
    match String.index_from_opt haystack from needle.[0] with
    | None -> count
    | Some at ->
        if at + needle_len <= String.length haystack
           && String.sub haystack at needle_len = needle
        then loop (count + 1) (at + needle_len)
        else loop count (at + 1)
  in
  if needle = "" then 0 else loop 0 0

let run ~path ~timeout_s ?(verbose = false) project =
  let args =
    [
      "--project";
      project;
      "--language";
      "go";
      "--output";
      temp_db "runner_diagnostic";
    ]
    @ if verbose then ["--verbose"] else []
  in
  run_command_split
    ~env:[("PATH", path); ("EPURE_ARCH_INDEX_TIMEOUT_S", timeout_s)]
    (arch_index_cli ())
    args

let check_quiet_failure b ~label ~needle ~reason stderr =
  Batch.check b
    ~msg:(Printf.sprintf "%s was silent on stderr:\n%s" label stderr)
    (contains ~needle stderr) ;
  Batch.check b
    ~msg:(Printf.sprintf "%s dropped its reason from stderr:\n%s" label stderr)
    (contains ~needle:reason stderr) ;
  Batch.check b
    ~msg:(Printf.sprintf "%s leaked verbose progress narration:\n%s" label stderr)
    (not (contains ~needle:"extracting symbols" stderr))

let register_lookup_failure () =
  Test.register ~__FILE__
    ~title:"runner diagnostics: missing LSP is reported without --verbose"
    ~tags:["lsp"; "diagnostics"; "runner"]
  @@ fun () ->
  with_project ~name:"runner_lookup" ~files:go_project @@ fun project ->
  let code, stdout, stderr = run ~path:"" ~timeout_s:"2" project in
  let _, verbose_stdout, verbose_stderr =
    run ~path:"" ~timeout_s:"2" ~verbose:true project
  in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"lookup failure keeps the current success exit code" code 0 ;
      Batch.eq_string b ~msg:"quiet lookup failure writes no stdout" stdout "" ;
      check_quiet_failure b ~label:"LSP lookup failure"
        ~needle:"LSP lookup failed" ~reason:"gopls" stderr ;
      Batch.eq_int b
        ~msg:"--verbose must not duplicate the lookup diagnostic"
        (count_occurrences ~needle:"LSP lookup failed" verbose_stderr)
        1 ;
      Batch.check b
        ~msg:"--verbose no longer emits progress narration"
        (contains ~needle:"arch_index_lsp: language=go" verbose_stdout)) ;
  Lwt.return_unit

let register_start_failure () =
  Test.register ~__FILE__
    ~title:"runner diagnostics: LSP start failure is reported without --verbose"
    ~tags:["lsp"; "diagnostics"; "runner"]
  @@ fun () ->
  with_project ~name:"runner_start" ~files:go_project @@ fun project ->
  let dir = Temp.dir "runner_start_server" in
  write_exec
    (Filename.concat dir "gopls")
    {|#!/bin/sh
BODY='{"jsonrpc":"2.0","id":1,"error":{"code":-32002,"message":"STARTUP_SENTINEL"}}'
printf 'Content-Length: %s\r\n\r\n%s' "${#BODY}" "$BODY"
|} ;
  let code, stdout, stderr = run ~path:dir ~timeout_s:"2" project in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"start failure keeps the current success exit code" code 0 ;
      Batch.eq_string b ~msg:"quiet start failure writes no stdout" stdout "" ;
      check_quiet_failure b ~label:"LSP start failure"
        ~needle:"LSP start failed" ~reason:"STARTUP_SENTINEL" stderr) ;
  Lwt.return_unit

let register_timeout () =
  Test.register ~__FILE__
    ~title:"runner diagnostics: timeout and partial results are reported without --verbose"
    ~tags:["lsp"; "diagnostics"; "runner"]
  @@ fun () ->
  with_project ~name:"runner_timeout" ~files:go_project @@ fun project ->
  let dir = Temp.dir "runner_timeout_server" in
  write_exec (Filename.concat dir "gopls") "#!/bin/sh\nexec /bin/sleep 10\n" ;
  let code, stdout, stderr = run ~path:dir ~timeout_s:"1" project in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"timeout keeps the current success exit code" code 0 ;
      Batch.eq_string b ~msg:"quiet timeout writes no stdout" stdout "" ;
      check_quiet_failure b ~label:"LSP timeout"
        ~needle:"timeout after 1s" ~reason:"using partial results" stderr) ;
  Lwt.return_unit

let register_unexpected_exception () =
  Test.register ~__FILE__
    ~title:"runner diagnostics: unexpected spawn error is reported without --verbose"
    ~tags:["lsp"; "diagnostics"; "runner"]
  @@ fun () ->
  with_project ~name:"runner_exception" ~files:go_project @@ fun project ->
  let dir = Temp.dir "runner_nonexec_server" in
  let server = Filename.concat dir "gopls" in
  write_file server "not executable\n" ;
  let code, stdout, stderr = run ~path:dir ~timeout_s:"2" project in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"unexpected error keeps the current success exit code" code 0 ;
      Batch.eq_string b ~msg:"quiet unexpected error writes no stdout" stdout "" ;
      check_quiet_failure b ~label:"unexpected LSP error"
        ~needle:"unexpected error" ~reason:"Permission denied" stderr) ;
  Lwt.return_unit

let register () =
  register_lookup_failure () ;
  register_start_failure () ;
  register_timeout () ;
  register_unexpected_exception ()
