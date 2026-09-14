#!/usr/bin/env node
'use strict';
// Self-contained authentic CMT/collector ratchet. No corpus inputs or worktree.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const source = `module M = struct
  let f ~a ~b = if b > 0 then (fun c -> a + b + c) else (fun c -> c)
  let optional ?(a=0) ~b = if b > 0 then (fun c -> a + b + c) else (fun c -> c)
end
let partial () = M.f ~b:1 2
let full () = M.f ~a:3 ~b:1 2
let optional_partial () = M.optional ~b:1
let optional_full () = M.optional ~a:3 ~b:1 2
`;
const probe = `module C = Arch_index__Arch_index_cmt
open Typedtree
let () =
  let info = Cmt_format.read_cmt Sys.argv.(1) in
  let s = match info.cmt_annots with Implementation s -> s
    | _ -> failwith "implementation required" in
  let local_fn_stamps = C.build_local_fn_stamps s in
  let targets = C.build_local_module_targets ~local_fn_stamps s in
  let rows = ref [] in
  List.iter (fun (it:structure_item) -> match it.str_desc with
    | Tstr_value (_,vbs) -> List.iter (fun (vb:value_binding) ->
      match vb.vb_pat.pat_desc with
      | Tpat_var (id,_,_) ->
        let caller = Ident.name id in
        let applications = ref [] in
        let it = {Tast_iterator.default_iterator with expr=(fun self e ->
          (match e.exp_desc with
          | Texp_apply ({exp_desc=Texp_ident (p,_,_);_},args) ->
            applications := (Path.name p,List.length args,
              List.length (List.filter_map snd args)) :: !applications
          | _ -> ()); Tast_iterator.default_iterator.expr self e)} in
        it.expr it vb.vb_expr;
        List.iter (fun enabled ->
          let local_module_targets = if enabled then Some targets else None in
          let calls,_,_,_ = C.collect_calls_from_expr ?local_module_targets
            ~local_fn_stamps ~src_path:"label.ml" ~caller_module:"label.ml"
            ~caller_name:caller vb.vb_expr in
          let call (p:C.pending_call) =
            let display,_ = C.pending_display p in
            let head = match p.head with
              | C.Head_unknown (_,r) -> C.top_reason_to_string r
              | C.Head_enumerated _ -> "enumerated" | _ -> "other" in
            \`Assoc ["callee",\`String display; "head",\`String head;
              "partial",\`Bool p.partial] in
          rows := \`Assoc ["caller",\`String caller; "context",\`Bool enabled;
            "applications",\`List (List.map (fun (p,slots,supplied) ->
              \`Assoc ["path",\`String p;"slots",\`Int slots;"supplied",\`Int supplied]) !applications);
            "calls",\`List (List.map call calls)] :: !rows
        ) [false;true]
      | _ -> ()) vbs
    | _ -> ()) s.str_items;
  let arities = Hashtbl.fold (fun _ (name,arity) acc ->
    if name="M.f" || name="M.optional" then (name,\`Int arity)::acc else acc)
    local_fn_stamps [] in
  print_endline (Yojson.Basic.to_string (\`Assoc ["arities",\`Assoc arities;
    "rows",\`List !rows]))
`;

let temporary;
function run(command, args, options = {}) {
  const result = cp.spawnSync(command, args, {cwd:temporary, encoding:'utf8',
    timeout:120000, maxBuffer:16*1024*1024, ...options});
  if (result.error || result.signal || result.status !== 0)
    throw new Error(`${command} setup failed (${result.status}): ${result.error || result.signal || result.stderr}`);
  return result.stdout;
}
function compiler(args, options) {
  return fs.existsSync(path.join(root,'_opam'))
    ? run('opam',['exec',`--switch=${root}`,'--',...args],options)
    : run(args[0],args.slice(1),options);
}
try {
  temporary = fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-labeled-arity-'));
  fs.writeFileSync(path.join(temporary,'label.ml'),source);
  fs.writeFileSync(path.join(temporary,'probe.ml'),probe);
  compiler(['ocamlc','-w','-16','-bin-annot','-c','label.ml']);
  // Link the exact checkout, including its private collector interface. The
  // installed public package intentionally does not expose that interface.
  const lib = name => path.join(root,'_build/default/lib',name);
  compiler(['ocamlfind','ocamlopt','-linkpkg','-package',
    'compiler-libs.common,sqlite3,ppxlib,eio,eio.unix,yojson,otoml,digestif.c,ppx_inline_test.runtime-lib,ppx_assert.runtime-lib',
    '-I',lib('arch_index/.arch_index.objs/byte'),
    '-I',lib('arch_io/.arch_io.objs/byte'),
    '-I',lib('jsonrpc_client/.jsonrpc_client.objs/byte'),
    lib('arch_io/arch_io.cmxa'),lib('jsonrpc_client/jsonrpc_client.cmxa'),
    lib('arch_index/arch_index.cmxa'),'probe.ml','-o','probe']);
  const evidence = JSON.parse(run(path.join(temporary,'probe'),[path.join(temporary,'label.cmt')]));
  assert.deepEqual(evidence.arities, {'M.f':2,'M.optional':2}, 'native syntactic body arities');
  assert.equal(evidence.rows.length,8,'all four callers in both contexts');
  const row = (caller,context) => {
    const matches=evidence.rows.filter(r=>r.caller===caller&&r.context===context);
    assert.equal(matches.length,1,`unique ${caller}/${context}`); return matches[0];
  };
  const cases = [
    ['partial','M.f',true,3,2,0], ['full','M.f',false,3,3,1],
    ['optional_partial','M.optional',true,2,1,0],
    ['optional_full','M.optional',false,3,3,1],
  ];
  // Establish every native fixture premise before the deliberately failing
  // residual assertion, so a broken optional control cannot hide behind RED.
  for (const [caller,target,partial,slots,supplied] of cases) {
    for (const enabled of [false,true]) {
      const r=row(caller,enabled);
      assert.deepEqual(r.applications,[{path:target,slots,supplied}],`native supplied-slot premise ${caller}`);
      assert.deepEqual(r.calls.filter(c=>c.callee===target),
        [{callee:target,head:enabled?'enumerated':'module_param',partial}],`pending head premise ${caller}/${enabled}`);
    }
  }
  console.log('PREMISES: four native callers, supplied slots and partial head metadata verified');
  for (const [caller,target,partial,slots,supplied,residuals] of cases) {
    for (const enabled of [false,true]) {
      const r=row(caller,enabled);
      assert.deepEqual(r.applications,[{path:target,slots,supplied}],`native supplied-slot premise ${caller}`);
      const heads=r.calls.filter(c=>c.callee===target);
      assert.deepEqual(heads,[{callee:target,head:enabled?'enumerated':'module_param',partial}],`exact pending head ${caller}/${enabled}`);
      const returns=r.calls.filter(c=>c.callee==='*TOP*');
      assert.equal(returns.length,enabled?residuals:0,`omitted label is not a supplied argument: ${caller}/${enabled}`);
      assert.ok(returns.every(c=>c.head==='callback_param'&&c.partial===false),'residual metadata');
      assert.equal(r.calls.length,1+returns.length,`no unaccounted call ${caller}/${enabled}`);
    }
  }
  console.log('PASS labeled arity: four native callers, both contexts, exact head/residual metadata');
} catch (error) {
  console.error(`${error instanceof assert.AssertionError?'ASSERTION':'SETUP'}: ${error.message}`);
  process.exitCode=error instanceof assert.AssertionError?1:2;
} finally {
  if (temporary) fs.rmSync(temporary,{recursive:true});
}
