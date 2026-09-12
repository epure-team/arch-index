open Arch_tezt

let register () =
  let script = Filename.concat (repo_root ()) "checks/actionable-review-reports.js" in
  let run ?control mode =
    let control =
      match control with
      | None -> ""
      | Some value -> "ACTIONABLE_REVIEW_REPORTS_CONTROL=" ^ Filename.quote value ^ " "
    in
    Printf.sprintf
      "%sARCH_REPORT=%s ARCH_RULES=%s ARCH_INDEX=%s ARCH_SCHEMA=%s node %s %s"
      control
      (Filename.quote (arch_report ()))
      (Filename.quote (arch_rules ()))
      (Filename.quote (callgraph_ocaml ()))
      (Filename.quote (schema ()))
      (Filename.quote script) (Filename.quote mode)
  in
  List.iter
    (fun mode ->
      Test.register ~__FILE__ ~title:("actionable report standalone check: " ^ mode)
        ~tags:["report"; "standalone_check"; mode]
      @@ fun () ->
      let command = run mode in
      let code = Sys.command command in
      if code <> 0 then
        Test.fail "standalone checker %s exited %d (0=pass, 1=assertion, >=2=execution)"
          mode code ;
      Lwt.return_unit)
    ["rules"; "ordering"; "operands"; "compatibility"] ;
  List.iter
    (fun (control, expected) ->
      Test.register ~__FILE__
        ~title:("actionable report checker exit mapping: " ^ control)
        ~tags:["report"; "standalone_check"; "exit_mapping"]
      @@ fun () ->
      let code = Sys.command (run ~control "rules") in
      if code <> expected then
        Test.fail "checker control %s exited %d, expected %d" control code expected ;
      Lwt.return_unit)
    [ ("assert", 1); ("execution", 2) ]
