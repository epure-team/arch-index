open Cmdliner

let run cmts format =
  try
    match format with
    | "json" -> print_string (Arch_guard.render_json cmts)
    | "text" -> print_string (Arch_guard.render_text cmts)
    | _ -> prerr_endline "arch-guard: --format must be text or json" ; exit 2
  with Arch_guard.Error message -> prerr_endline ("arch-guard: " ^ message) ; exit 2

let cmts =
  Arg.(value & opt_all string [] & info ["cmt"] ~docv:"FILE" ~doc:"Analyze this CMT artifact.")

let format =
  Arg.(value & opt string "text" & info ["format"] ~docv:"FORMAT" ~doc:"Output text or json.")

let cmd =
  let info = Cmd.info "arch_guard" ~version:"0.1.0" ~doc:"Experimental OCaml divisor analysis" in
  Cmd.v info Term.(const run $ cmts $ format)

let () =
  let code = Cmd.eval ~term_err:2 cmd in
  exit (if code = 0 then 0 else 2)
