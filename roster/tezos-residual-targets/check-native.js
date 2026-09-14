#!/usr/bin/env node
'use strict';
// Native CMT/API RED control.  It compiles its own fixture and asks the exact
// checkout collector for rich pending rows; no corpus or prebuilt product DB.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '../..');
const source = `module Owned = struct
  let base ?(a=0) ~b x = a + b + x
  let alias = base
end
let applied () = Owned.alias ~b:2 1
let partial () = Owned.alias ~b:2
module Callback = struct let base x = x let alias = base end
let callback xs = List.map Callback.alias xs
module Inline = struct include struct let body x = x let alias = body end end
let inline_include x = Inline.alias x
let point_free = Owned.alias
module Ops = struct
  let bind o f = match o with None -> None | Some x -> f x
  let ( let* ) = bind
end
let letop x = let open Ops in let* v = x in Some (v + 1)
module Hidden = struct
  let f ~a ~b = if b > 0 then (fun c -> a + b + c) else (fun c -> c)
  let alias = f
  let optional ?(a=0) ~b = if b > 0 then (fun c -> a + b + c) else (fun c -> c)
  let opt_alias = optional
  type hidden = int -> int
  let tri (a : int) (b : int) : hidden = fun c -> a + b + c
  let tri_alias = tri
end
let required_hole () = Hidden.alias ~b:1 2
let required_full () = Hidden.alias ~a:3 ~b:1 2
let optional_hole () = Hidden.opt_alias ~b:1
let optional_full () = Hidden.opt_alias ~a:3 ~b:1 2
let hidden_partial () = Hidden.tri_alias 1 2
`;
const probe = `module C = Arch_index__Arch_index_cmt
open Typedtree
let () =
  let info = Cmt_format.read_cmt Sys.argv.(1) in
  let s = match info.cmt_annots with Implementation s -> s | _ -> failwith "implementation" in
  let fns = C.build_local_fn_stamps s in
  let targets = C.build_local_module_targets ~local_fn_stamps:fns s in
  let rows = ref [] in
  List.iter (fun (it:structure_item) -> match it.str_desc with
  | Tstr_value (_,vbs) -> List.iter (fun (vb:value_binding) -> match vb.vb_pat.pat_desc with
    | Tpat_var (id,_,_) ->
      List.iter (fun enabled ->
      let local_module_targets = if enabled then Some targets else None in
      let calls,_,_,_ = C.collect_calls_from_expr ~local_fn_stamps:fns ?local_module_targets
        ~src_path:"native.ml" ~caller_module:"native.ml" ~caller_name:(Ident.name id) vb.vb_expr in
      let render (p:C.pending_call) = let n,_ = C.pending_display p in
        let h = match p.head with C.Head_enumerated _ -> "enumerated" | C.Head_unknown (_,r) -> C.top_reason_to_string r | _ -> "other" in
        \`Assoc ["callee",\`String n;"head",\`String h;"partial",\`Bool p.partial;"form",match p.edge_form with None -> \`Null | Some x -> \`String x] in
      rows := \`Assoc ["caller",\`String (Ident.name id);"context",\`Bool enabled;"calls",\`List (List.map render calls)] :: !rows
      ) [false;true]
    | _ -> ()) vbs | _ -> ()) s.str_items;
  let bodies = Hashtbl.fold (fun _ (name,arity) acc -> (name,\`Int arity)::acc) fns [] in
  print_endline (Yojson.Basic.to_string (\`Assoc ["rows",\`List !rows;"bodies",\`Assoc bodies]))`;
let temporary;
function run(command,args,options={}) { const r=cp.spawnSync(command,args,{cwd:temporary,encoding:'utf8',timeout:120000,maxBuffer:16*1024*1024,...options}); if(r.error||r.signal||r.status!==0) throw new Error(`${command} setup failed (${r.status}): ${r.error||r.signal||r.stderr}`); return r.stdout; }
function compiler(args) { return fs.existsSync(path.join(root,'_opam')) ? run('opam',['exec',`--switch=${root}`,'--',...args]) : run(args[0],args.slice(1)); }
try {
 const args=process.argv.slice(2);
 if(args.length>1||(args.length===1&&args[0]!=='--probe-only')) throw new Error('usage: check-native.js [--probe-only]');
 temporary=fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-local-value-'));
 fs.writeFileSync(path.join(temporary,'native.ml'),source); fs.writeFileSync(path.join(temporary,'probe.ml'),probe);
 compiler(['ocamlc','-w','-16','-bin-annot','-c','native.ml']);
 const lib=n=>path.join(root,'_build/default/lib',n);
 compiler(['ocamlfind','ocamlopt','-linkpkg','-package','compiler-libs.common,sqlite3,ppxlib,eio,eio.unix,yojson,otoml,digestif.c,ppx_inline_test.runtime-lib,ppx_assert.runtime-lib','-I',lib('arch_index/.arch_index.objs/byte'),'-I',lib('arch_io/.arch_io.objs/byte'),'-I',lib('jsonrpc_client/.jsonrpc_client.objs/byte'),lib('arch_io/arch_io.cmxa'),lib('jsonrpc_client/jsonrpc_client.cmxa'),lib('arch_index/arch_index.cmxa'),'probe.ml','-o','probe']);
 const evidence=JSON.parse(run(path.join(temporary,'probe'),[path.join(temporary,'native.cmt')]));
 const rows=evidence.rows;
 const calls=(name,enabled)=>{const rs=rows.filter(x=>x.caller===name&&x.context===enabled);assert.equal(rs.length,1,`native caller ${name}/${enabled}`);return rs[0].calls};
 assert.equal(evidence.bodies['Hidden.tri'],3,'syntactic body arity survives hidden return alias');
 assert.equal(evidence.bodies['Hidden.f'],2);
 assert.equal(evidence.bodies['Hidden.optional'],2);
 assert.ok(!Object.keys(evidence.bodies).some(n=>/alias$|point_free$/.test(n)),'body table excludes aliases');
 for(const enabled of [false,true]) {
  for (const [caller,target,unresolved,partial] of [['applied','Owned.base','Owned.alias',false],['partial','Owned.base','Owned.alias',true],['callback','Callback.base','Callback.alias',false],['inline_include','Inline.body','Inline.alias',false],['letop','Ops.bind','Ops.let*',false]]) {
   const callee=enabled?target:unresolved;
   assert.deepEqual(calls(caller,enabled).filter(x=>x.callee===callee),[{callee,head:enabled?'enumerated':'module_param',partial,form:null}],`${caller} one-hop body target/${enabled}`);
  }
  assert.deepEqual(calls('point_free',enabled).filter(x=>x.callee==='Owned.alias'),[{callee:'Owned.alias',head:'module_param',partial:false,form:'value_alias'}],'point-free remains historical');
  for(const [caller,target,unresolved,partial,residuals] of [
   ['required_hole','Hidden.f','Hidden.alias',true,0],
   ['required_full','Hidden.f','Hidden.alias',false,1],
   ['optional_hole','Hidden.optional','Hidden.opt_alias',true,0],
   ['optional_full','Hidden.optional','Hidden.opt_alias',false,1],
   ['hidden_partial','Hidden.tri','Hidden.tri_alias',enabled,0],
  ]) {
   const callee=enabled?target:unresolved, actual=calls(caller,enabled);
   assert.deepEqual(actual.filter(x=>x.callee===callee),[{callee,head:enabled?'enumerated':'module_param',partial,form:null}],`${caller} exact pending metadata/${enabled}`);
   const returns=actual.filter(x=>x.callee==='*TOP*');
   assert.equal(returns.length,enabled?residuals:0,`${caller} exact return residual count/${enabled}`);
   assert.ok(returns.every(x=>x.head==='callback_param'&&x.partial===false&&x.form===null));
   assert.equal(actual.length,1+returns.length,`${caller} has no unaccounted native calls`);
  }
 }
 console.log('PASS native local value aliases: both contexts, body-only table, exact partial/residual metadata');
 if(args.length===0) {
  const exe=path.join(root,'_build/default/tezt/tests/main.exe');
  const localSwitch=fs.existsSync(path.join(root,'_opam'));
  const command=localSwitch?'opam':exe;
  const testArgs=[...(localSwitch?['exec',`--switch=${root}`,'--',exe]:[]),'--file','tezt/tests/local_value_targets.ml','--keep-going'];
  const result=cp.spawnSync(command,testArgs,{cwd:root,encoding:'utf8',timeout:120000,maxBuffer:16*1024*1024});
  const output=(result.stdout||'')+(result.stderr||'');
  if(result.error||result.signal) throw new Error(`native Tezt setup: ${result.error||result.signal}`);
  if(result.status!==0) {
   if(result.status===1&&output.includes('LOCAL_VALUE_ASSERTION:')&&!output.includes('LOCAL_VALUE_SETUP:')) assert.fail(output);
   throw new Error(`native Tezt setup exit ${result.status}: ${output}`);
  }
  for(const title of ['local value aliases: qualified invocation reaches the one-hop body','local value aliases: rejection and flat attribution use the actual body','local value aliases: native pending metadata','local value aliases: forced CMT flat attribution'])
   assert.ok(output.split('\n').some(line=>line.includes('[SUCCESS]')&&line.includes(title)),`missing actual Tezt success: ${title}`);
  console.log(output);
 }
} catch (error) { console.error(`${error instanceof assert.AssertionError?'ASSERTION':'SETUP'}: ${error.message}`); process.exitCode=error instanceof assert.AssertionError?1:2; }
finally { if(temporary) { try { fs.rmSync(temporary,{recursive:true}); } catch(error) { console.error(`SETUP: cleanup: ${error.message}`);process.exitCode=2; } } }
