# Round 1 compiler-global state observation

Architect-owned client, compiled and run against the public library at product2b8b7bf.
Observed compile0/run0; stdout `before_marker=true after_marker=false`.
The client's success means the undesirable mutation was reproduced, not a regression test PASS.
No third-party input or vulnerability investigation.

```ocaml
let () =
  let marker = Sys.argv.(1) in
  let cmt = Sys.argv.(2) in
  Load_path.init ~auto_include:Load_path.no_auto_include
    ~visible:[marker; Config.standard_library] ~hidden:[];
  Envaux.reset_cache ();
  let before = Load_path.get_paths () in
  ignore (Arch_guard.render_json [cmt]);
  let after = Load_path.get_paths () in
  Printf.printf "before_marker=%b after_marker=%b\n"
    (List.mem marker before.visible) (List.mem marker after.visible);
  if not (List.mem marker before.visible) || List.mem marker after.visible then exit 1
```

Architect self scratch: /tmp/architect-self-ldoEzc (self.db and self-stats.txt).
Indexer used --build-dir=_build/default/lib/arch_index, --schema-path=architecture-schema.sql;
self golden diff0 (23/828/5223), rules --on-vacuous fail0, impact --diff main..HEAD --repo .0.
Architect origin output: /tmp/architect-origin-bZdqcw/evidence; producer0 and validator0.
Reviewer scratch: /tmp/guard-review-r1.Fpew97; exact commands in review-r1-reviewer.md.
Root retained observations before removing these owned disposable databases and client builds.
