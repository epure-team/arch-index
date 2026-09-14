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
module type OPENED = sig
  val value : int
  val run : unit -> (int, string) result
end
let module_effect n = if n < 0 then failwith "negative" else n
module Apply (X : sig val value : int end) = struct
  let value = module_effect X.value
  let run () = Error "apply"
end
module Arg = struct let value = 2 end
module Packed = struct let value = module_effect 3 let run () = Error "unpack" end
let packed = (module Packed : OPENED)
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
let parameter_partial = parameter_effect ~x:2
let parameter_full y = parameter_effect ~x:2 (Some y)
let parameter_default y = parameter_effect (Some y)
let structure_open = let open (struct
  let value = module_effect 1
  let run () = Error "structure"
end) in fun () -> if false then run () else if value > 0 then run () else Ok value
let apply_open = let open (Apply (struct let value = module_effect 2 end)) in fun () -> if value > 0 then run () else Ok value
let unpack_open = let open (val (let _ = module_effect 3 in packed) : OPENED) in fun () -> if value > 0 then run () else Ok value
let structure_call () = structure_open ()
let apply_call () = apply_open ()
let unpack_call () = unpack_open ()
module Homonym = struct let wrapped x = x + 10 end
let homonym_call () = Homonym.wrapped 1
let result_origin () = Error "origin"
let result_scope () = match result_origin () with Ok x -> x | Error _ -> 0
let dead_after_raise () = ignore (raise Exit); result_origin ()
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
const preservationProbe=moduleName=>`module C = ${moduleName}
let read p = let i=open_in_bin p in Fun.protect ~finally:(fun()->close_in_noerr i) (fun()->really_input_string i (in_channel_length i))
let prep db s = Sqlite3.prepare db s
let rows db sql columns =
 let q=prep db sql in let found=ref [] in
 while Sqlite3.step q=Sqlite3.Rc.ROW do
  found := \`List(List.init columns (fun i -> \`String(Sqlite3.column_text q i))) :: !found
 done; ignore(Sqlite3.finalize q); List.rev !found
let starts prefix value = String.length value >= String.length prefix && String.sub value 0 (String.length prefix) = prefix
let admitted (p:C.pending_call) =
 let callee,_=C.pending_display p in
 let target=match p.caller_name,p.call_site with
  | "call","native.ml:15"->Some "wrapped"
  | ("required_hole","native.ml:17"|"required_full","native.ml:18"|"over_one","native.ml:19"|"over_two","native.ml:20")->Some "required"
  | ("parameter_partial","native.ml:29"|"parameter_full","native.ml:30"|"parameter_default","native.ml:31")->Some "parameter_effect"
  | _->None in
 match target with None->None | Some name ->
  if callee=name || starts (name^".<fun:") callee then Some name else None
let residual (p:C.pending_call) =
 List.mem (p.caller_name,p.call_site)
  ["required_full","native.ml:18";"over_one","native.ml:19";"over_two","native.ml:20"]
 && match p.head with C.Head_unknown ("*TOP*",C.Callback_param)->true | _->false
let pending (p:C.pending_call) =
 let callee,callee_module=C.pending_display p in
 let admission=admitted p in
 let normalized_callee=Option.value ~default:callee admission in
 let head=match admission,p.head with
  | Some name,_->"admitted:"^name
  | None,C.Head_local n->"local:"^n | None,C.Head_enumerated n->"enumerated:"^n
  | None,C.Head_qualified(m,n)->"qualified:"^(Option.value ~default:"<null>" m)^":"^n
  | None,C.Head_unknown(n,r)->"unknown:"^n^":"^C.top_reason_to_string r in
 \`List[\`String p.caller_module;\`String p.caller_name;\`String head;\`String normalized_callee;
  (match callee_module with None->\`Null|Some s->\`String s);\`Bool p.local_module_invocation;
  \`Bool p.partial;\`Bool p.cond;\`Bool p.dead;\`String p.call_site;
  (match p.exn_scope with None->\`Null|Some n->\`Int n);
  (match p.errch_scope with None->\`Null|Some n->\`Int n);
  (match p.errch_propagates with None->\`Null|Some s->\`String s);
  (match admission,p.edge_form with Some _,_->\`Null|None,None->\`Null|None,Some s->\`String s)]
let () =
 let db=Sqlite3.db_open ":memory:" in
 (match Sqlite3.exec db (read Sys.argv.(1)) with Sqlite3.Rc.OK->()|r->failwith(Sqlite3.Rc.to_string r));
 let value_channels=List.filter (fun (c:Arch_index__Arch_errors_config.channel)->c.type_paths<>[]) Arch_index__Arch_errors_config.builtin.channels in
 let calls,_,_=C.process_cmt db ~project_root:Sys.argv.(2)
  ~source_path_of_cmt:(fun _->Some(Filename.concat Sys.argv.(2) "native.ml"))
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
  ~stmt_rebind:(prep db "INSERT OR IGNORE INTO exn_rebinds(alias_path,target_path) VALUES(?,?)")
  ~stmt_carrier:(prep db "INSERT OR IGNORE INTO channel_carriers(function_id,channel) VALUES(?,?)")
  ~value_channels Sys.argv.(3) in
 let cfg=List.filter (fun p->not(residual p)) calls |> List.map pending |> List.sort compare in
 let residual_counts=List.map(fun name->\`List[\`String name;\`Int(List.length(List.filter(fun (p:C.pending_call)->p.caller_name=name&&residual p)calls))])
  ["required_full";"over_one";"over_two"] in
 let functions=rows db "SELECT name,coalesce(signature,'<null>'),line_start,line_end,line_count,exposed,coalesce(intent,'<null>'),coalesce(comment_quality_score,'<null>'),has_pre,has_post,has_violators,has_violates,coalesce(violators_raw,'<null>'),coalesce(violates_raw,'<null>'),coalesce(tests_raw,'<null>'),coalesce(quint_raw,'<null>'),coalesce(mutation_sites,'<null>'),coalesce(deref_sites,'<null>'),coalesce(language,'<null>'),universe,coalesce(producer_run_id,'<null>') FROM functions ORDER BY name,line_start,line_end" 21 in
 let carriers=rows db "SELECT f.name,c.channel FROM channel_carriers c JOIN functions f ON f.id=c.function_id ORDER BY f.name,c.channel" 2 in
 let scopes=rows db "SELECT f.name,coalesce(p.form,'<root>'),coalesce(p.line,'<null>'),coalesce(p.col,'<null>'),s.form,s.line,s.col,s.catch_all,s.channel FROM exn_scopes s JOIN functions f ON f.id=s.function_id LEFT JOIN exn_scopes p ON p.id=s.parent_id ORDER BY f.name,s.line,s.col,s.channel" 9 in
 let catches=rows db "SELECT f.name,s.form,s.line,s.col,s.channel,c.exn_path FROM exn_scope_catches c JOIN exn_scopes s ON s.id=c.scope_id JOIN functions f ON f.id=s.function_id ORDER BY f.name,s.line,s.col,s.channel,c.exn_path" 6 in
 let origins=rows db "SELECT f.name,coalesce(s.form,'<root>'),coalesce(s.line,'<null>'),coalesce(s.col,'<null>'),o.form,coalesce(o.exn_path,'<null>'),o.escapes,o.line,o.col,o.channel,coalesce(o.operand_primitive,'<null>'),coalesce(o.operand_slot,'<null>'),coalesce(o.operand_category,'<null>'),coalesce(o.operand_repr,'<null>'),coalesce(o.operand_integer_kind,'<null>'),coalesce(o.operand_unavailable_reason,'<null>') FROM exn_origins o JOIN functions f ON f.id=o.function_id LEFT JOIN exn_scopes s ON s.id=o.scope_id ORDER BY f.name,o.line,o.col,o.channel,o.form" 16 in
 print_endline(Yojson.Basic.to_string(\`Assoc["functions",\`List functions;"cfg",\`List cfg;
  "residual_counts",\`List residual_counts;"carriers",\`List carriers;"scopes",\`List scopes;
  "catches",\`List catches;"origins",\`List origins]));
 ignore(Sqlite3.db_close db)`;

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
  for(const name of ['required_full','over_one','over_two']) {
    const calls=row(name).rich;
    assert.equal(calls.filter(c=>c.callee===target('required').body).length,1,`${name} target once`);
    assert.equal(calls.filter(c=>c.callee==='*TOP*'&&c.head==='callback_param').length,1,`${name} residual once`);
  }
  for(const name of ['alias_call','callback','local_call','nested_call','parameter_effect']) {
    assert.deepEqual(row(name).rich,row(name).legacy,`${name} unsupported rich rows unchanged`);
    assert.equal(row(name).rich_calls_digest,row(name).legacy_calls_digest,`${name} complete pending-call facts unchanged`);
    assert.deepEqual(row(name).rich_shape,row(name).legacy_shape,`${name} node/effect shape unchanged`);
  }
  assert.equal(row('parameter_partial').rich.find(c=>c.callee===target('parameter_effect').body).partial,true,
    'actual optional/refutable partial application remains partial');
  assert.deepEqual(row('parameter_partial').slots,[[1,1]],'partial application supplies only its optional slot');
  assert.deepEqual(row('parameter_full').slots,[[2,2]],'full application supplies optional and refutable slots');
  assert.deepEqual(row('parameter_default').slots,[[2,2]],
    'defaulted full application carries the compiler-materialized default expression');
  for(const name of ['parameter_full','parameter_default'])
    assert.equal(row(name).rich.find(c=>c.callee===target('parameter_effect').body).partial,false,
      `${name} actual optional/default/refutable full application is saturated`);
  for(const name of ['structure_open','apply_open','unpack_open','structure_call','apply_call','unpack_call','homonym_call','dead_after_raise']) {
    assert.deepEqual(row(name).rich,row(name).legacy,`${name} unsupported rich rows unchanged`);
    assert.deepEqual(row(name).rich_shape,row(name).legacy_shape,`${name} CFG/effect shape unchanged`);
  }
  for(const name of ['structure_open','apply_open','unpack_open'])
    assert.ok(row(name).legacy.some(call=>call.callee==='module_effect'),
      `${name} module-expression call control is non-vacuous`);
  for(const name of ['computed','structure_open','apply_open','unpack_open'])
    assert.equal(evidence.targets.some(t=>t.display===name),false,`${name} computed module open refused`);
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
  const preservation={};
  for(const [label,moduleName,object] of [
    ['predecessor','Old_cmt','old_cmt.cmx'],['current','Open_cmt','open_cmt.cmx']]) {
    const file=`preservation_${label}.ml`;
    fs.writeFileSync(path.join(temporary,file),preservationProbe(moduleName));
    opam(['ocamlfind','ocamlopt','-linkpkg','-package',packages,...includes,
      lib('arch_io/arch_io.cmxa'),lib('jsonrpc_client/jsonrpc_client.cmxa'),lib('arch_index/arch_index.cmxa'),
      object,file,'-o',`preservation_${label}`]);
    preservation[label]=JSON.parse(run(path.join(temporary,`preservation_${label}`),[
      path.join(root,'architecture-schema.sql'),temporary,path.join(temporary,'native.cmt')]));
  }
  for(const key of ['functions','cfg','carriers','scopes','origins'])
    assert.ok(preservation.current[key].length>0,`${key} preservation comparison is non-vacuous`);
  const residualCallers=['required_full','over_one','over_two'];
  assert.deepEqual(preservation.predecessor.residual_counts,residualCallers.map(name=>[name,0]),
    'predecessor has no permitted returned-call residuals');
  assert.deepEqual(preservation.current.residual_counts,residualCallers.map(name=>[name,1]),
    'current has exactly one permitted residual at each exact native overapplication site');
  const functionNames=preservation.current.functions.map(row=>row[0]);
  const lambdaName=functionNames.find(name=>name.startsWith('parameter_effect.<fun:'));
  assert.ok(lambdaName&&functionNames.includes('parameter_effect'),
    'persisted parent-to-lambda ownership and ranges are non-vacuous');
  assert.ok(preservation.current.cfg.some(row=>row[7]===true),'conditional CFG facts are non-vacuous');
  assert.ok(preservation.current.cfg.some(row=>row[8]===false),'live CFG classifications are non-vacuous');
  assert.ok(preservation.current.cfg.some(row=>row[8]===true),'dead CFG classifications are non-vacuous');
  assert.ok(preservation.current.carriers.some(row=>row[1]==='result'),'result-channel carrier facts are non-vacuous');
  assert.ok(preservation.current.scopes.some(row=>row[8]==='result'),'result-channel scope facts are non-vacuous');
  assert.ok(preservation.current.origins.some(row=>row[9]==='result'),'result-channel origin facts are non-vacuous');
  const {residual_counts:currentResiduals,...currentPreserved}=preservation.current;
  const {residual_counts:predecessorResiduals,...predecessorPreserved}=preservation.predecessor;
  assert.deepEqual(currentPreserved,predecessorPreserved,
    'complete persisted predecessor/current rich facts outside intended call-target changes');
  const consumer=fs.readFileSync(path.join(root,'lib/arch_index/call_graph_extractor.ml'),'utf8');
  fs.writeFileSync(path.join(temporary,'flat_legacy.ml'),consumer.replaceAll('Arch_index_cmt','Old_cmt'));
  fs.writeFileSync(path.join(temporary,'flat_current.ml'),consumer.replaceAll('Arch_index_cmt','Open_cmt'));
  fs.writeFileSync(path.join(temporary,'flat_probe.ml'),`let row name : Arch_index__Lsp_extractor.fn_row =
  {name; file_path="native.ml"; line_start=0; line_end=0; name_char=0; exported=true;
   signature=None; summary=None}
let names = ["wrapped";"call";"required";"required_hole";"required_full";
 "over_one";"over_two";"alias";"alias_call";"callback";"local_call";"nested";
 "nested_call";"effectful_default";"parameter_effect";"parameter_partial";
 "parameter_full";"parameter_default";"structure_open";"apply_open";"unpack_open";
 "structure_call";"apply_call";"unpack_call";"homonym_call";"result_origin";"result_scope";
 "dead_after_raise"]
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
  for(const caller of ['structure_open','apply_open','unpack_open','homonym_call'])
    assert.ok(flat.legacy.some(value=>value.startsWith(`${caller}\x1f`)),`${caller} flat control is non-vacuous`);
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
