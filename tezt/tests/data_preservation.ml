open Arch_tezt

let register () =
  List.iter (fun name ->
    Test.register ~__FILE__ ~title:("data preservation: " ^ name)
      ~tags:["effects"; "cmt"; "data_preservation"]
    @@ fun () ->
    let checker = Filename.concat (repo_root ())
        ("roster/ocaml-data-preservation/check-" ^ name ^ ".js") in
    let code, stdout, stderr = run_command_split "node" [checker] in
    if code <> 0 then
      Test.fail "data preservation %s exit %d (1=assertion, 2=setup)\n%s\n%s"
        name code stdout stderr ;
    Lwt.return_unit)
    ["effects"; "cmt-copies"]
