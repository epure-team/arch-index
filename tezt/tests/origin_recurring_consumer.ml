open Arch_tezt

let register () =
  let checker = Filename.concat (repo_root ()) "checks/origin-recurring-consumer.js" in
  let run ?control mode =
    let prefix = match control with None -> "" | Some c -> "ORIGIN_CONSUMER_CHECK_CONTROL=" ^ c ^ " " in
    Sys.command (Printf.sprintf "%snode %s %s" prefix (Filename.quote checker) (Filename.quote mode))
  in
  List.iter
    (fun mode ->
      Test.register ~__FILE__ ~title:("origin recurring consumer: " ^ mode)
        ~tags:["origin"; "consumer"; mode] @@ fun () ->
      let code = run mode in
      if code <> 0 then Test.fail "origin checker %s exited %d (0=pass, 1=assertion, >=2=execution)" mode code ;
      Lwt.return_unit)
    ["authentic"; "failures"; "package"] ;
  List.iter
    (fun (control, expected) ->
      Test.register ~__FILE__ ~title:("origin recurring consumer checker exit: " ^ control)
        ~tags:["origin"; "consumer"; "exit_mapping"] @@ fun () ->
      let code = run ~control "authentic" in
      if code <> expected then Test.fail "origin checker control %s exited %d, expected %d" control code expected ;
      Lwt.return_unit)
    [("assert", 1); ("execution", 2)]
