#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '../..');
let temporary;

const source = `module M = struct let tick x = x + 1 end
let wrapped = let open M in fun x -> tick x
let call x = wrapped x
let required = let open M in fun ~a ~b -> if b > 0 then (fun c -> tick (a+b+c)) else (fun c -> c)
let required_hole () = required ~b:1 2
let required_full () = required ~a:3 ~b:1 2
let over_one () = required ~a:3 ~b:1 2
let over_two () = required ~a:4 ~b:2 3
let alias = wrapped
let alias_call x = alias x
let callback xs = List.map wrapped xs
let local_call x = let local = let open M in fun y -> tick y in local x
let nested = let open M in (let open M in fun x -> tick x)
let nested_call x = nested x
let effectful_default () = 7
let parameter_effect = let open M in fun ?(x=effectful_default ()) (Some y) -> tick (x+y)
let parameter_partial = parameter_effect
let parameter_full y = parameter_effect (Some y)
module F (X:sig val x:int end) = struct
  let computed = let open (struct let y = X.x end) in fun z -> y + z
  let computed_call z = computed z
end
`;

function run(command,args,options={}) {
  const r=cp.spawnSync(command,args,{cwd:temporary,encoding:'utf8',timeout:120000,maxBuffer:64*1024*1024,...options});
  if(r.error||r.signal||r.status!==0) throw new Error(`${command} setup failed (${r.status}): ${r.error||r.signal||r.stderr}`);
  return r.stdout;
}
function opam(args) { return fs.existsSync(path.join(root,'_opam')) ? run('opam',['exec',`--switch=${root}`,'--',...args]) : run(args[0],args.slice(1)); }
function replaceOnce(source,needle,replacement,label) {
  assert.equal(source.split(needle).length-1,1,`${label} instrumentation point is unique`);
  return source.replace(needle,replacement);
}

try {
  const args=process.argv.slice(2);
  if(args.length>1||(args.length===1&&!['--mutate-disable-open','--probe-only'].includes(args[0])))
    throw new Error('usage: check-native.js [--probe-only|--mutate-disable-open]');
  temporary=fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-open-body-'));
  fs.writeFileSync(path.join(temporary,'native.ml'),source);
  fs.copyFileSync(path.join(root,'_build/default/lib/arch_index/arch_index_cmt.pp.ml'),path.join(temporary,'open_cmt.ml'));
  fs.copyFileSync(path.join(root,'roster/tezos-open-bodies/native-check-probe.ml'),path.join(temporary,'probe.ml'));
  if(args[0]==='--mutate-disable-open') {
    const probePath=path.join(temporary,'probe.ml');
    fs.writeFileSync(probePath,fs.readFileSync(probePath,'utf8').replace(
      'C.collect_calls_from_expr_with_open_bodies ~open_body_targets:targets',
      'C.collect_calls_from_expr_with_open_bodies'));
  }
  opam(['ocamlc','-w','-16-33','-bin-annot','-c','native.ml']);
  fs.mkdirSync(path.join(temporary,'_build/default'),{recursive:true});
  fs.copyFileSync(path.join(temporary,'native.cmt'),path.join(temporary,'_build/default/native.cmt'));
  const lib=n=>path.join(root,'_build/default/lib',n);
  const packages='compiler-libs.common,sqlite3,ppxlib,eio,eio.unix,yojson,otoml,digestif.c,ppx_inline_test.runtime-lib,ppx_assert.runtime-lib';
  const includes=['-I',lib('arch_index/.arch_index.objs/byte'),'-I',lib('arch_io/.arch_io.objs/byte'),'-I',lib('jsonrpc_client/.jsonrpc_client.objs/byte')];
  opam(['ocamlfind','ocamlopt','-package',packages,...includes,'-open','Arch_index__','-c','open_cmt.ml']);
  opam(['ocamlfind','ocamlopt','-linkpkg','-package',packages,...includes,
    lib('arch_io/arch_io.cmxa'),lib('jsonrpc_client/jsonrpc_client.cmxa'),lib('arch_index/arch_index.cmxa'),
    'open_cmt.cmx','probe.ml','-o','probe']);
  const evidence=JSON.parse(run(path.join(temporary,'probe'),[path.join(temporary,'native.cmt')]));
  const row=name=>{const xs=evidence.rows.filter(x=>x.caller===name);assert.equal(xs.length,1,`unique ${name}`);return xs[0];};
  const target=name=>{const xs=evidence.targets.filter(x=>x.display===name);assert.equal(xs.length,1,`unique target ${name}`);return xs[0];};
  for(const [name,arity] of [['wrapped',1],['required',2]]) {
    const t=target(name); assert.equal(t.arity,arity); assert.equal(t.matches,1); assert.equal(t.expected,true);
    assert.match(t.body,new RegExp(`^${name.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')}\\.<fun:`));
  }
  assert.deepEqual(evidence.identity_control,{canonical_matches:1,physical_expected:false},
    'same canonical root marker cannot substitute a different physical literal');
  assert.deepEqual(evidence.multiple_control,{canonical_matches:2,physical_expected:true},
    'duplicate observation is represented and cannot satisfy unique correspondence');
  assert.equal(evidence.targets.some(t=>['alias','nested','local'].includes(t.display)),false,'unsupported shapes excluded');
  assert.deepEqual(row('call').rich.filter(c=>c.callee===target('wrapped').body),
    [{callee:target('wrapped').body,head:'enumerated',partial:false,form:evidence.rows.find(x=>x.caller==='call').rich.find(c=>c.callee===target('wrapped').body).form}]);
  assert.match(row('call').rich.find(c=>c.callee===target('wrapped').body).form,/^__open_body:/,'new occurrence carries private provenance');
  assert.deepEqual(row('required_hole').slots,[[3,2]],'required hole has three slots but two supplied expressions');
  assert.deepEqual(row('required_full').slots,[[3,3]],'required full supplies every slot');
  assert.equal(row('required_hole').rich.find(c=>c.callee===target('required').body).partial,true);
  assert.equal(row('required_full').rich.find(c=>c.callee===target('required').body).partial,false);
  for(const name of ['over_one','over_two']) {
    const calls=row(name).rich;
    assert.equal(calls.filter(c=>c.callee===target('required').body).length,1,`${name} target once`);
    assert.equal(calls.filter(c=>c.callee==='*TOP*'&&c.head==='callback_param').length,1,`${name} residual once`);
  }
  for(const name of ['alias_call','callback','local_call','nested_call','parameter_effect','parameter_partial']) {
    assert.deepEqual(row(name).rich,row(name).legacy,`${name} unsupported rich rows unchanged`);
    assert.equal(row(name).rich_calls_digest,row(name).legacy_calls_digest,`${name} complete pending-call facts unchanged`);
    assert.deepEqual(row(name).rich_shape,row(name).legacy_shape,`${name} node/effect shape unchanged`);
  }
  assert.equal(evidence.targets.some(t=>t.display==='computed'),false,'computed module open refused');
  const oldResult=cp.spawnSync('git',['show','e8d072e:lib/arch_index/arch_index_cmt.ml'],
    {cwd:root,encoding:'utf8',timeout:120000,maxBuffer:64*1024*1024});
  if(oldResult.error||oldResult.signal||oldResult.status!==0)
    throw new Error(`old collector setup failed (${oldResult.status}): ${oldResult.error||oldResult.signal||oldResult.stderr}`);
  const inlineTests=oldResult.stdout.match(/let%test[\s\S]*?\n\n/g)||[];
  assert.equal(inlineTests.length,3,'predecessor has exactly three removable inline tests');
  const oldSource=oldResult.stdout.replace(/let%test[\s\S]*?\n\n/g,'');
  assert.equal(/let%/.test(oldSource),false,'predecessor temp copy has no unprocessed inline-test extension');
  fs.writeFileSync(path.join(temporary,'old_cmt.ml'),oldSource);
  opam(['ocamlfind','ocamlopt','-package',packages,...includes,'-open','Arch_index__','-c','old_cmt.ml']);
  const consumer=fs.readFileSync(path.join(root,'lib/arch_index/call_graph_extractor.ml'),'utf8');
  fs.writeFileSync(path.join(temporary,'flat_legacy.ml'),consumer.replaceAll('Arch_index_cmt','Old_cmt'));
  fs.writeFileSync(path.join(temporary,'flat_current.ml'),consumer.replaceAll('Arch_index_cmt','Open_cmt'));
  fs.writeFileSync(path.join(temporary,'flat_probe.ml'),`let row name : Arch_index__Lsp_extractor.fn_row =
  {name; file_path="native.ml"; line_start=0; line_end=0; name_char=0; exported=true;
   signature=None; summary=None}
let names = ["wrapped";"call";"required";"required_hole";"required_full";
 "over_one";"over_two";"alias";"alias_call";"callback";"local_call";"nested";
 "nested_call";"effectful_default";"parameter_effect";"parameter_partial";
 "parameter_full"]
let render_legacy (c:Flat_legacy.call_row) = String.concat "\\031" [c.caller_name;c.caller_file;
 c.callee_name;Option.value ~default:"<null>" c.callee_file;c.call_site;
 Option.value ~default:"<null>" c.edge_form]
let render_current (c:Flat_current.call_row) = String.concat "\\031" [c.caller_name;c.caller_file;
 c.callee_name;Option.value ~default:"<null>" c.callee_file;c.call_site;
 Option.value ~default:"<null>" c.edge_form]
let () =
 let rows=List.map row names in
 let a=Flat_legacy.extract_calls_from_cmts ~project_dir:Sys.argv.(1) rows |> List.map render_legacy |> List.sort String.compare in
 let b=Flat_current.extract_calls_from_cmts ~project_dir:Sys.argv.(1) rows |> List.map render_current |> List.sort String.compare in
 print_endline (Yojson.Basic.to_string (\`Assoc ["legacy",\`List(List.map (fun x->\`String x) a);"disabled",\`List(List.map(fun x->\`String x)b)]))`);
  opam(['ocamlfind','ocamlopt','-package',packages,...includes,'-open','Arch_index__','-c','flat_legacy.ml']);
  opam(['ocamlfind','ocamlopt','-package',packages,...includes,'-open','Arch_index__','-c','flat_current.ml']);
  opam(['ocamlfind','ocamlopt','-linkpkg','-package',packages,...includes,
    lib('arch_io/arch_io.cmxa'),lib('jsonrpc_client/jsonrpc_client.cmxa'),lib('arch_index/arch_index.cmxa'),
    'old_cmt.cmx','open_cmt.cmx','flat_legacy.cmx','flat_current.cmx','flat_probe.ml','-o','flat_probe']);
  const flat=JSON.parse(run(path.join(temporary,'flat_probe'),[temporary]));
  assert.ok(flat.legacy.length>0,'forced flat multiset is non-vacuous');
  assert.deepEqual(flat.disabled,flat.legacy,'complete duplicate-sensitive predecessor/current public flat call_row multiset');
  const processProbe = moduleName => `module C = ${moduleName}
let read p = let i=open_in_bin p in Fun.protect ~finally:(fun()->close_in_noerr i) (fun()->really_input_string i (in_channel_length i))
let prep db s = Sqlite3.prepare db s
let () =
 let db=Sqlite3.db_open ":memory:" in
 (match Sqlite3.exec db (read Sys.argv.(1)) with Sqlite3.Rc.OK->() | r->failwith(Sqlite3.Rc.to_string r));
 let calls,_,_=C.process_cmt db ~project_root:Sys.argv.(2)
  ~source_path_of_cmt:(fun _->Some (Filename.concat Sys.argv.(2) "native.ml"))
  ~count_code_lines:(fun _->1) ~exposed_tbl:(Hashtbl.create 0) ~doc_tbl:(Hashtbl.create 0)
  ~module_quint_tbl:(Hashtbl.create 0)
  ~stmt_mod:(prep db "INSERT INTO modules(path,lines,last_analyzed,has_mli,quint_module_raw,language) VALUES(?,?,?,?,?,?)")
  ~stmt_fn:(prep db "INSERT OR REPLACE INTO functions(module_id,name,signature,line_start,line_end,exposed,intent,comment_quality_score,has_pre,has_post,has_violators,has_violates,violators_raw,violates_raw,tests_raw,quint_raw,mutation_sites,deref_sites,language,producer_run_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
  ~stmt_ty:(prep db "INSERT OR REPLACE INTO types(module_id,name,kind,line_start,line_end,exposed,manifest,intent) VALUES(?,?,?,?,?,?,?,?)")
  ~stmt_fld:(prep db "INSERT INTO type_fields(type_id,field_name,field_type,position) VALUES(?,?,?,?)")
  ~stmt_ctor:(prep db "INSERT INTO type_constructors(type_id,constructor_name,position,arg_types) VALUES(?,?,?,?)")
  ~stmt_scope:(prep db "INSERT INTO exn_scopes(function_id,parent_id,form,line,col,catch_all,channel) VALUES(?,?,?,?,?,?,?)")
  ~stmt_catch:(prep db "INSERT INTO exn_scope_catches(scope_id,exn_path) VALUES(?,?)")
  ~stmt_origin:(prep db "INSERT INTO exn_origins(function_id,scope_id,form,exn_path,escapes,line,col,channel,operand_primitive,operand_slot,operand_category,operand_repr,operand_integer_kind,operand_unavailable_reason) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
  ~stmt_rebind:(prep db "INSERT OR IGNORE INTO exn_rebinds(alias_path,target_path) VALUES(?,?)") Sys.argv.(3) in
 let rows=List.filter (fun (p:C.pending_call)->p.caller_name="call") calls |> List.map (fun p->
  let n,_=C.pending_display p in let h=match p.head with C.Head_unknown(_,r)->C.top_reason_to_string r|C.Head_enumerated _->"enumerated"|_->"other" in
  \`Assoc["callee",\`String n;"head",\`String h;"form",match p.edge_form with None->\`Null|Some x->\`String x]) in
 let q=Sqlite3.prepare db "SELECT name FROM functions WHERE name LIKE 'wrapped.<fun:%'" in
 let bodies=ref [] in while Sqlite3.step q=Sqlite3.Rc.ROW do bodies:=Sqlite3.column_text q 0::!bodies done; ignore(Sqlite3.finalize q);
 let dropped=List.filter (fun name->C.is_dropped_node ~module_path:"native.ml" ~name) !bodies |> List.length in
 print_endline(Yojson.Basic.to_string(\`Assoc["calls",\`List rows;"bodies",\`List(List.map(fun x->\`String x)!bodies);"dropped",\`Int dropped])); ignore(Sqlite3.db_close db)`;
  const currentRaw=fs.readFileSync(path.join(root,'lib/arch_index/arch_index_cmt.ml'),'utf8');
  const currentInline=currentRaw.match(/let%test[\s\S]*?\n\n/g)||[];
  assert.equal(currentInline.length,3,'current source has exactly three removable inline tests');
  const pp=currentRaw.replace(/let%test[\s\S]*?\n\n/g,'');
  assert.equal(/let%/.test(pp),false,'instrumented current copy has no residual inline-test extension');
  for(const [kind,needle,replacement,moduleName] of [
    ['physical','expected_body = body;','expected_body = {body with exp_loc = {body.exp_loc with loc_ghost = true}};','Mismatch_cmt'],
    ['multiple','target.matching_bodies <- target.matching_bodies + 1 ;','target.matching_bodies <- target.matching_bodies + 2 ;','Multiple_cmt']]) {
    const file=kind==='physical'?'mismatch_cmt.ml':'multiple_cmt.ml';
    fs.writeFileSync(path.join(temporary,file),replaceOnce(pp,needle,replacement,kind));
    fs.writeFileSync(path.join(temporary,`${kind}_process.ml`),processProbe(moduleName));
    opam(['ocamlfind','ocamlopt','-package',packages,...includes,'-open','Arch_index__','-c',file]);
    opam(['ocamlfind','ocamlopt','-linkpkg','-package',packages,...includes,
      lib('arch_io/arch_io.cmxa'),lib('jsonrpc_client/jsonrpc_client.cmxa'),lib('arch_index/arch_index.cmxa'),
      file.replace('.ml','.cmx'),`${kind}_process.ml`,'-o',`${kind}_process`]);
    const rows=JSON.parse(run(path.join(temporary,`${kind}_process`),[
      path.join(root,'architecture-schema.sql'),temporary,path.join(temporary,'native.cmt')]));
    assert.equal(rows.bodies.length,1,`${kind} exact wrapped body was really stored`);
    assert.match(rows.bodies[0],/^wrapped\.<fun:/,`${kind} stored canonical root body`);
    assert.equal(rows.dropped,0,`${kind} stored body is not in dropped-node registry`);
    assert.deepEqual(rows.calls,[{callee:'wrapped',head:'callback_param',form:null}],`${kind} actual process_cmt finalization refuses enumeration`);
  }
  if(args.length===0) {
    const exe=path.join(root,'_build/default/tezt/tests/main.exe');
    const local=fs.existsSync(path.join(root,'_opam'));
    const command=local?'opam':exe;
    const testArgs=[...(local?['exec',`--switch=${root}`,'--',exe]:[]),'--no-color','--file','tezt/tests/open_body_targets.ml','--keep-going'];
    const result=cp.spawnSync(command,testArgs,{cwd:root,encoding:'utf8',timeout:120000,maxBuffer:64*1024*1024});
    const output=(result.stdout||'')+(result.stderr||'');
    if(result.error||result.signal) throw new Error(`native Tezt setup: ${result.error||result.signal}`);
    if(result.status!==0) {
      if(result.status===1&&output.includes('OPEN_BODY_ASSERTION:')&&!output.includes('OPEN_BODY_SETUP:')) assert.fail(output);
      throw new Error(`native Tezt setup exit ${result.status}: ${output}`);
    }
    for(const title of [
      'open-wrapped structural bodies: exact rich invocation targets and boundaries',
      'open-wrapped structural bodies: rejected actual body stays dropped_node TOP',
      'open-wrapped structural bodies: rejected parent makes its body unavailable',
      'open-wrapped structural bodies: flat collector remains legacy-compatible'])
      assert.ok(output.split('\n').some(line=>line.includes('[SUCCESS]')&&line.includes(title)),`missing actual Tezt success: ${title}`);
  }
  console.log(`PASS native open bodies: exact identity, slots/partial/residuals, refusal, exact rich/flat facts${args.length===0?' and Tezt controls':''}`);
} catch(error) {
  console.error(`${error instanceof assert.AssertionError?'ASSERTION':'SETUP'}: ${error.message}`);
  process.exitCode=error instanceof assert.AssertionError?1:2;
} finally { if(temporary) fs.rmSync(temporary,{recursive:true,force:true}); }
