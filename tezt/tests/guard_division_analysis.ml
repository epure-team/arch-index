open Arch_tezt

let arch_guard () = locate ~env_var:"ARCH_GUARD" "bin/arch_guard/arch_guard.exe"

let domain_probe () =
  locate ~env_var:"ARCH_GUARD_DOMAIN_PROBE" "tezt/fixtures/arch_guard/domain_probe.exe"

let register () =
  Test.register ~__FILE__ ~title:"arch-guard: authentic CMT inventory drives classification"
    ~tags:["arch_guard"; "inventory"]
  @@ fun () ->
  let root = Temp.dir "arch_guard_red" in
  let source = Filename.concat (repo_root ()) "tezt/fixtures/arch_guard/inventory.ml" in
  let local = Filename.concat root "inventory.ml" in
  write_file local (read_file source) ;
  let code, compiled = run_command ~cwd:root "ocamlc" ["-bin-annot"; "-c"; "inventory.ml"] in
  if code <> 0 then Test.fail "fixture compilation failed (setup error):\n%s" compiled ;
  let cmt = Filename.concat root "inventory.cmt" in
  let code, stdout, stderr =
    run_command_split (arch_guard ()) ["--cmt"; cmt; "--format"; "json"]
  in
  if code <> 0 then Test.fail "arch_guard failed (setup error):\n%s" stderr ;
  let json = Yojson.Safe.from_string stdout in
  let total = Yojson.Safe.Util.(json |> member "census" |> member "total_sites" |> to_int) in
  if total <> 12 then Test.fail "expected twelve authentic division sites, got %d in %s" total stdout ;
  let sites = Yojson.Safe.Util.(json |> member "sites" |> to_list) in
  let unsupported =
    List.filter (fun site -> Yojson.Safe.Util.(site |> member "status" |> to_string) = "UNSUPPORTED") sites
  in
  if List.length unsupported <> 5 then
    Test.fail "partial, loop, try, int64, and effect ancestry must all remain UNSUPPORTED: %s" stdout ;
  let census name = Yojson.Safe.Util.(json |> member "census" |> member name |> to_int) in
  let expected = [("nonzero", 3); ("zero", 1); ("may_zero", 2); ("unreachable", 1); ("unsupported", 5)] in
  List.iter
    (fun (name, want) ->
      let got = census name in
      if got <> want then Test.fail "semantic census %s: expected %d, got %d in %s" name want got stdout)
    expected ;
  Lwt.return_unit

let register_domain () =
  Test.register ~__FILE__ ~title:"arch-guard: constant-zero-v1 exact singleton transfer"
    ~tags:["arch_guard"; "domain"]
  @@ fun () ->
  let request =
    {|{"id":"add","width":8,"op":"add","args":[{"kind":"const","value":"2"},{"kind":"const","value":"3"}]}
|}
  in
  let code, output = run_command ~stdin:request (domain_probe ()) [] in
  if code <> 0 then Test.fail "domain probe setup failed:\n%s" output ;
  let response = Yojson.Safe.from_string output in
  let open Yojson.Safe.Util in
  let kind = response |> member "result" |> member "kind" |> to_string in
  let value = response |> member "result" |> member "value" |> to_string_option in
  if kind <> "const" || value <> Some "5" then
    Test.fail "expected exact Const 5, got %s" output ;
  let restriction =
    {|{"id":"restrict","width":8,"op":"restrict_ne_zero","args":[{"kind":"const","value":"2"}]}
|}
  in
  let code, output = run_command ~stdin:restriction (domain_probe ()) [] in
  if code <> 0 then Test.fail "domain restriction probe setup failed:\n%s" output ;
  let response = Yojson.Safe.from_string output in
  let kind = response |> member "result" |> member "kind" |> to_string in
  let value = response |> member "result" |> member "value" |> to_string_option in
  if kind <> "const" || value <> Some "2" then
    Test.fail "restriction must be reductive and preserve Const 2, got %s" output ;
  Lwt.return_unit

let register_checkers () =
  let checker = Filename.concat (repo_root ()) "scripts/check-arch-guard.js" in
  List.iter
    (fun (mode, expected) ->
      Test.register ~__FILE__ ~title:("arch-guard independent checker: " ^ mode)
        ~tags:["arch_guard"; "independent_checker"] @@ fun () ->
      let code, stdout, stderr = run_command_split "node" [checker; mode] in
      if code <> expected then
        Test.fail "checker %s: expected exit %d, got %d (1=assertion, >=2=execution)\n%s\n%s"
          mode expected code stdout stderr ;
      Lwt.return_unit)
    [("inventory", 0); ("numeric", 0); ("domain", 0); ("inputs", 0);
     ("report", 0); ("owned", 0); ("--assertion-control", 1); ("--execution-control", 2)]
