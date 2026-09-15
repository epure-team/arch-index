#!/usr/bin/env node
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),cp=require('node:child_process');
const {probeRecords}=require('./run-probe.js');
const baseline=require('./baseline.js');
let verificationState,binaryPins;
const root=path.resolve(__dirname,'../..');let temporary;
const source=`module S = Stdlib
module M = struct end
module Exported_shape = struct
  type record_shape = { mutable value : int }
  type variant_shape = Variant of int
end
include Exported_shape
exception Local
exception Alias = Local
type local_token = Token of int
let typed (x : local_token) : local_token = x
let alias_call n = S.abs n
let caught n = try if n < 0 then raise Local else n with Local -> 0
type ('a,'r) cont = ('a -> 'r) -> 'r
let side_effect n = if n < 0 then failwith "negative" else n
let result_origin () = Error "origin"
let basic n = let rec aux = let open M in fun x -> if x=0 then 0 else aux (x-1) in aux n
let effects r n = let rec aux = let open M in fun x -> if x=0 then !r else (r := !r + 1; aux (x-1)) in aux n
let annotated n = let rec aux = let open M in (fun x -> if x=0 then 0 else aux (x-1) : int -> int) in aux n
let pattern_annotated n = let rec aux : int -> int = fun x -> if x=0 then 0 else aux (x-1) in aux n
let nested n = let rec aux = let open M in fun x -> let invoke y = if y=0 then 0 else aux (y-1) in invoke x in aux n
let default_self n = let rec aux = let open M in fun ?(seed=if n=0 then 0 else aux ~seed:0 0) x -> if x=0 then seed else aux ~seed (x-1) in aux n
let optional n = let rec aux = let open M in fun ?bonus x y -> if x=0 then y else aux ?bonus (x-1) y in aux n 1
let refutable n = let rec aux = let open M in fun (Some x) -> if x=0 then 0 else aux (Some(x-1)) in aux (Some n)
let partial n = let rec aux = let open M in fun x y -> if x=0 then y else let d=aux (x-1) in d y in aux n 1
let labelled n = let rec aux = let open M in fun ~a x ~b y -> if x=0 then a+b+y else let f=aux ~b (x-1) in f ~a y in aux ~a:0 n ~b:1 2
let overapplied n = let rec aux = let open M in fun x -> if x=0 then fun y->y else fun y->aux (x-1) y in aux n 1
let alias_hidden n = let rec aux : type r. int -> int -> (int,r) cont = let open M in fun n v k -> if n=0 then k v else aux (n-1) v k in aux n 1 (fun x -> x)
let mutual n = let rec left x=if x=0 then 0 else right(x-1) and right x=if x=0 then 0 else left(x-1) in left n
let nonrecursive n = let aux x=x+1 in aux n
let shadowed n = let rec aux = let open M in fun x -> let aux y=y+1 in aux x in aux n
let wrapped n = let rec aux = if n<0 then fun x->x else fun x->x+1 in aux n
let rhs_escape n = let rec aux = let open M in fun x -> let saved=aux in ignore saved; if x=0 then 0 else aux(x-1) in aux n
let stacked n = let rec outer = let open M in fun x -> let rec inner y = if y=0 then 0 else outer(y-1) in inner x in outer n
let structural_nonfunction = let rec aux = let open M in fun x -> if x=0 then 0 else aux(x-1) in aux 2
let channel n = let rec aux = let open M in fun x -> if x=0 then result_origin() else let handled = match aux(x-1) with Ok y->y|Error _->0 in Ok handled in match aux n with Ok y->y|Error _->0
let caught_recursive n = let rec aux = let open M in fun x -> try if x=0 then raise Local else aux(x-1) with Local->0 in aux n
let direct_control n = let rec aux x = if x=0 then 0 else aux(x-1) in aux n
let nested_open n = let rec aux = let open M in let open M in fun x -> if x=0 then 0 else aux(x-1) in aux n
let dead n = let rec aux = let open M in fun x -> if x=0 then 0 else aux(x-1) in ignore(raise Exit); aux n
let collision n =
  let first =
# 100 "native.ml"
fun x -> x in
  let rec aux = let open M in
# 100 "native.ml"
fun x -> if x=0 then 0 else aux(x-1) in
  first (aux n)
`;
function run(cmd,args,opt={}){const r=cp.spawnSync(cmd,args,{cwd:temporary,encoding:'utf8',timeout:120000,maxBuffer:128*1024*1024,...opt});if(r.error||r.signal||r.status!==0)throw Error(`${cmd} setup ${r.status}: ${r.error||r.signal||r.stderr}`);return r.stdout;}
function opam(args){return fs.existsSync(path.join(root,'_opam'))?run('opam',['exec',`--switch=${root}`,'--',...args]):run(args[0],args.slice(1));}
function stripInline(text,label){const xs=text.match(/let%test[\s\S]*?\n\n/g)||[];assert.equal(xs.length,3,`${label} inline-test premise`);const out=text.replace(/let%test[\s\S]*?\n\n/g,'');assert.equal(/let%/.test(out),false);return out;}
const counted=rows=>{const m=new Map();for(const row of rows){const k=JSON.stringify(row),v=m.get(k)||{row,count:0};v.count++;m.set(k,v);}return m;};
function subtract(a,b){const bm=counted(b),out=[];for(const {row,count} of counted(a).values())for(let n=count-(bm.get(JSON.stringify(row))?.count||0);n>0;n--)out.push(row);return out;}
function validatePending(oldRows,newRows,eligible){
 const removed=subtract(oldRows,newRows),added=subtract(newRows,oldRows),used=new Set(),usedAdded=new Set(),usedResidual=new Set(),acceptedHeads=new Map();
 const exactContext=(a,b)=>[0,1,5,7,8,9,10,11,12].every(i=>a[i]===b[i]);
 for(const before of removed){
  let match=-1;
  for(let j=0;j<added.length&&match<0;j++){const after=added[j];if(usedAdded.has(j)||!exactContext(before,after))continue;
   for(let i=0;i<eligible.length;i++){if(used.has(i))continue;const app=eligible[i],scope=app.matching_recursive_scope,rootOwner=scope?.actual_root;
    const site=`${app.application_loc.start.file}:${app.application_loc.start.line}`,binder=scope?.binder?.name,expectedPartial=app.result_arrow||app.supplied_some<app.root_syntactic_arity;
    if(before[1]!==app.caller?.name||before[9]!==site||before[2]!==`unknown:${binder}:callback_param`||before[3]!==binder||before[4]!==null||before[13]!==null)continue;
    if(after[2]!==`enumerated:${rootOwner?.name}`||after[3]!==rootOwner?.name||after[4]!==null||after[6]!==expectedPartial||after[13]!==null)continue;
    match=j;used.add(i);acceptedHeads.set(i,after);break;
   }
  }
  assert.notEqual(match,-1,`unapproved removed pending row ${JSON.stringify(before)}`);usedAdded.add(match);
 }
 for(let j=0;j<added.length;j++){if(usedAdded.has(j))continue;const after=added[j];
  let accepted=false;
  for(let i=0;i<eligible.length&&!accepted;i++){if(usedResidual.has(i)||!used.has(i))continue;const app=eligible[i],head=acceptedHeads.get(i),site=`${app.application_loc.start.file}:${app.application_loc.start.line}`;
   if(app.supplied_some<=app.root_syntactic_arity||after[1]!==app.caller?.name||after[9]!==site)continue;
   if(![0,1,7,8,9,10].every(k=>after[k]===head[k]))continue;
   if(after[2]==='unknown:*TOP*:callback_param'&&after[3]==='*TOP*'&&after[4]===null&&after[5]===false&&after[6]===false&&after[11]===null&&after[12]===null&&after[13]===null){usedResidual.add(i);usedAdded.add(j);accepted=true;}
  }
  assert.ok(accepted,`unapproved added pending row ${JSON.stringify(after)}`);
 }
 return {removed:removed.length,added:added.length,approved_heads:used.size,approved_residuals:usedResidual.size};
}
try{
 verificationState=baseline.state();
 binaryPins=Object.fromEntries([baseline.CURRENT_PRODUCER,baseline.CURRENT_SCHEMA,path.join(root,'_build/default/lib/arch_index/arch_index_cmt.pp.ml')].map(file=>[file,baseline.fileSha256(file)]));
 temporary=fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-recursive-open-native-'));fs.writeFileSync(path.join(temporary,'native.ml'),source);
 opam(['ocamlc','-w','-8-26-39','-bin-annot','-c','native.ml']);fs.mkdirSync(path.join(temporary,'_build/default'),{recursive:true});fs.copyFileSync(path.join(temporary,'native.cmt'),path.join(temporary,'_build/default/native.cmt'));
 const records=probeRecords([path.join(temporary,'native.cmt')]),record=records[0];assert.equal(record?.schema_version,'recursive-open-witness-v1','recursive native probe record');
 const eligible=record.all_application_occurrences.filter(x=>x.classification==='native_self_head_requires_storage_confirmation');assert.ok(eligible.length>=10,'native eligible set is non-vacuous');
 const labelled=eligible.find(app=>app.caller?.name.startsWith('labelled.<fun:'));
 assert.ok(labelled,'authentic labelled partial self-head');assert.equal(labelled.root_syntactic_arity,4);assert.equal(labelled.supplied_some,2);
 assert.ok(labelled.arguments.some(arg=>!arg.supplied)&&labelled.arguments.some(arg=>arg.supplied),'genuine interleaved missing and supplied argument slots');
 assert.ok(eligible.some(x=>x.caller?.name.includes('default_self')&&x.matching_recursive_scope?.actual_root),'self-call inside optional default has native owner/root');
 assert.ok(eligible.some(x=>x.caller?.name.includes('stacked')&&x.head.ident.name==='outer'),'nested local recursion reaches active outer binder');
 assert.ok(eligible.some(x=>x.matching_recursive_scope?.actual_root?.name.startsWith('structural_nonfunction.<fun:')),'structural non-function RHS contains eligible local recursion');
 const collision=eligible.find(x=>x.matching_recursive_scope?.actual_root?.name.startsWith('collision.<fun:'));assert.ok(collision,'collision recursive occurrence');
 const collisionRoot=collision.matching_recursive_scope.actual_root,collisionPeer=record.native_function_owners.find(o=>o.allocation_base===collisionRoot.allocation_base&&o.native_owner_index!==collisionRoot.native_owner_index);
 assert.equal(collisionRoot.allocation_ordinal,2,'recursive root observes actual second collision ordinal');assert.equal(collisionPeer?.allocation_ordinal,1,'same-position physical peer owns first ordinal');
 assert.equal(collision.matching_recursive_scope.root_observation_count,1,'collision retains one exact physical recursive root');assert.notEqual(collisionPeer.native_owner_index,collisionRoot.native_owner_index,'same-position bodies remain physically distinct owners');
 const overapplication=eligible.find(x=>x.supplied_some>x.root_syntactic_arity);assert.ok(overapplication,'native overapplication control occurrence');
 const overSite=`${overapplication.application_loc.start.file}:${overapplication.application_loc.start.line}`,overBinder=overapplication.matching_recursive_scope.binder.name,overRoot=overapplication.matching_recursive_scope.actual_root.name;
 const beforeControl=['Native',overapplication.caller.name,`unknown:${overBinder}:callback_param`,overBinder,null,false,false,true,false,overSite,'exn-control','result','result',null];
 const headControl=['Native',overapplication.caller.name,`enumerated:${overRoot}`,overRoot,null,false,overapplication.result_arrow||overapplication.supplied_some<overapplication.root_syntactic_arity,true,false,overSite,'exn-control','result','result',null];
 const residualControl=['Native',overapplication.caller.name,'unknown:*TOP*:callback_param','*TOP*',null,false,false,true,false,overSite,'exn-control',null,null,null];
 assert.deepEqual(validatePending([beforeControl],[headControl,residualControl],[overapplication]),{removed:1,added:2,approved_heads:1,approved_residuals:1},'counted native head and residual control');
 const driftedResidual=residualControl.slice();driftedResidual[10]='different-exn-scope';assert.throws(()=>validatePending([beforeControl],[headControl,driftedResidual],[overapplication]),/unapproved added pending row/,'residual context drift is refused');
 const lib=n=>path.join(root,'_build/default/lib',n),packages='compiler-libs.common,sqlite3,ppxlib,eio,eio.unix,yojson,otoml,digestif.c,ppx_inline_test.runtime-lib,ppx_assert.runtime-lib';
 const inc=['-I',lib('arch_index/.arch_index.objs/byte'),'-I',lib('arch_io/.arch_io.objs/byte'),'-I',lib('jsonrpc_client/.jsonrpc_client.objs/byte')];
 fs.copyFileSync(path.join(root,'_build/default/lib/arch_index/arch_index_cmt.pp.ml'),path.join(temporary,'current_cmt.ml'));
 const old=cp.spawnSync('git',['show','4a952441fcd7648d20e68b5c6348de1b3fe85522:lib/arch_index/arch_index_cmt.ml'],{cwd:root,encoding:'utf8',maxBuffer:64*1024*1024});if(old.status!==0)throw Error(`predecessor source: ${old.stderr}`);fs.writeFileSync(path.join(temporary,'old_cmt.ml'),stripInline(old.stdout,'predecessor'));
 for(const file of ['current_cmt.ml','old_cmt.ml'])opam(['ocamlfind','ocamlopt','-package',packages,...inc,'-open','Arch_index__','-c',file]);
 const preserved={};for(const [label,moduleName,obj] of [['old','Old_cmt','old_cmt.cmx'],['current','Current_cmt','current_cmt.cmx']]){
  const probe=fs.readFileSync(path.join(root,'roster/tezos-recursive-typed-bodies/native-preservation-probe.ml'),'utf8').replace('Native_collector',moduleName),file=`preserve_${label}.ml`;fs.writeFileSync(path.join(temporary,file),probe);
  opam(['ocamlfind','ocamlopt','-linkpkg','-package',packages,...inc,lib('arch_io/arch_io.cmxa'),lib('jsonrpc_client/jsonrpc_client.cmxa'),lib('arch_index/arch_index.cmxa'),obj,file,'-o',`preserve_${label}`]);
  preserved[label]=JSON.parse(run(path.join(temporary,`preserve_${label}`),[path.join(root,'architecture-schema.sql'),temporary,path.join(temporary,'native.cmt')]));
 }
 for(const k of ['pending','functions','carriers','scopes','catches','origins'])assert.ok(preserved.current[k].length>0,`${k} non-vacuous`);
 const requiredPreservationArray=(snapshot,label,key)=>{
  assert.ok(Array.isArray(snapshot[key]),`${label} ${key} preservation array present`);
  assert.ok(snapshot[key].length>0,`${label} ${key} preservation set non-vacuous`);
  return snapshot[key];
 };
 for(const [label,snapshot] of Object.entries(preserved)){
  const modules=requiredPreservationArray(snapshot,label,'modules');
  const deps=requiredPreservationArray(snapshot,label,'deps');
  const rebinds=requiredPreservationArray(snapshot,label,'rebinds');
  const typeUsages=requiredPreservationArray(snapshot,label,'type_usages');
  const types=requiredPreservationArray(snapshot,label,'types');
  const fields=requiredPreservationArray(snapshot,label,'fields');
  const constructors=requiredPreservationArray(snapshot,label,'constructors');
  const catches=requiredPreservationArray(snapshot,label,'catches');
  assert.ok(modules.every(row=>Array.isArray(row)&&row.length===6),'module preservation rows retain semantic fields');
  assert.ok(deps.every(row=>Array.isArray(row)&&row.length===5),'dependency preservation rows retain semantic fields');
  assert.ok(deps.some(row=>Array.isArray(row)&&row[2]==='alias'),'module-alias dependency is preserved');
  assert.ok(deps.some(row=>Array.isArray(row)&&row[2]==='include'),'include dependency is preserved');
  assert.ok(rebinds.every(row=>Array.isArray(row)&&row.length===2),'exception rebind facts are complete');
  assert.ok(typeUsages.every(row=>Array.isArray(row)&&row.length===5),'type-usage facts retain owner and position');
  assert.ok(types.every(row=>Array.isArray(row)&&row.length===8),'type preservation rows retain semantic fields');
  assert.ok(fields.every(row=>Array.isArray(row)&&row.length===5),'field preservation rows retain semantic fields');
  assert.ok(constructors.every(row=>Array.isArray(row)&&row.length===5),'constructor preservation rows retain semantic fields');
  assert.ok(catches.every(row=>Array.isArray(row)&&row.length===6),`${label} exception catch facts are complete`);
  assert.ok(snapshot.functions.some(row=>Array.isArray(row)&&Number(row[16])>0),`${label} mutation effects non-vacuous`);
  assert.ok(snapshot.functions.some(row=>Array.isArray(row)&&Number(row[17])>0),`${label} dereference effects non-vacuous`);
  assert.ok(snapshot.pending.some(row=>Array.isArray(row)&&row[13]==='module_alias'),`${label} module_alias reexport edge preserved`);
 }
 assert.ok(preserved.current.pending.some(r=>r[7]===true),'conditional pending fact');assert.ok(preserved.current.pending.some(r=>r[8]===true),'dead pending fact');
 assert.ok(preserved.current.carriers.some(r=>r[1]==='result'),'configured result carrier');assert.ok(preserved.current.scopes.some(r=>r[8]==='result'),'result scope');assert.ok(preserved.current.origins.some(r=>r[9]==='result'),'result origin');
 const selectedPending=preserved.current.pending.filter(row=>eligible.some(app=>row[1]===app.caller?.name&&row[9]===`${app.application_loc.start.file}:${app.application_loc.start.line}`));
 assert.ok(selectedPending.some(row=>row[1].startsWith('caught_recursive.')&&row[10]!==null),'selected self-head has real exception scope');
 assert.ok(selectedPending.some(row=>row[1].startsWith('channel.')&&row[11]!==null),'selected self-head has real channel scope');
 const effectCall=eligible.find(app=>app.caller?.name.startsWith('effects.<fun:'));
 assert.ok(effectCall,'selected recursive effect call exists');
 const effectParent=record.native_function_owners.find(owner=>owner.native_owner_index===effectCall.matching_recursive_scope.actual_root.parent_owner_index);
 assert.equal(effectParent?.name,'effects','effect context is the selected root native parent');
 // The predecessor stores effect counts on the structural owner, not on its
 // promoted lambda. Require that exact native ancestor, not an unrelated row.
 assert.ok(preserved.current.functions.some(row=>row[0]===effectParent.name
   &&Number(row[2])===effectParent.loc.start.line&&Number(row[3])===effectParent.loc.end.line
   &&Number(row[16])>0&&Number(row[17])>0),'selected recursive parent context has nonzero mutation/dereference effects');
 const {admissions:currentAdmissions,pending:currentPending,...currentPreserved}=preserved.current,{admissions:oldAdmissions,pending:oldPending,...oldPreserved}=preserved.old;
 assert.deepEqual(currentPreserved,oldPreserved,'complete stored rich preservation before admitted target assertion');
 validatePending(oldPending,currentPending,eligible);
 const consumer=fs.readFileSync(path.join(root,'lib/arch_index/call_graph_extractor.ml'),'utf8');fs.writeFileSync(path.join(temporary,'flat_old.ml'),consumer.replaceAll('Arch_index_cmt','Old_cmt'));fs.writeFileSync(path.join(temporary,'flat_current.ml'),consumer.replaceAll('Arch_index_cmt','Current_cmt'));
 const names=['typed','alias_call','caught','basic','effects','annotated','pattern_annotated','nested','default_self','optional','refutable','partial','labelled','overapplied','alias_hidden','mutual','nonrecursive','shadowed','wrapped','rhs_escape','stacked','structural_nonfunction','channel','caught_recursive','direct_control','nested_open','dead','collision'];
 const ocamlNames='['+names.map(n=>`"${n}"`).join(';')+']';
 fs.writeFileSync(path.join(temporary,'flat_probe.ml'),`let row name : Arch_index__Lsp_extractor.fn_row={name;file_path="native.ml";line_start=0;line_end=0;name_char=0;exported=true;signature=None;summary=None}\nlet render (c:Flat_old.call_row)=String.concat "\\031" [c.caller_name;c.caller_file;c.callee_name;Option.value ~default:"<null>" c.callee_file;c.call_site;Option.value ~default:"<null>" c.edge_form]\nlet render2 (c:Flat_current.call_row)=String.concat "\\031" [c.caller_name;c.caller_file;c.callee_name;Option.value ~default:"<null>" c.callee_file;c.call_site;Option.value ~default:"<null>" c.edge_form]\nlet ()=let rs=List.map row ${ocamlNames} in let a=Flat_old.extract_calls_from_cmts ~project_dir:Sys.argv.(1) rs|>List.map render|>List.sort compare and b=Flat_current.extract_calls_from_cmts ~project_dir:Sys.argv.(1) rs|>List.map render2|>List.sort compare in print_endline(Yojson.Basic.to_string(\`List[\`List(List.map(fun x->\`String x)a);\`List(List.map(fun x->\`String x)b)]))`);
 for(const f of ['flat_old.ml','flat_current.ml'])opam(['ocamlfind','ocamlopt','-package',packages,...inc,'-open','Arch_index__','-c',f]);opam(['ocamlfind','ocamlopt','-linkpkg','-package',packages,...inc,lib('arch_io/arch_io.cmxa'),lib('jsonrpc_client/jsonrpc_client.cmxa'),lib('arch_index/arch_index.cmxa'),'old_cmt.cmx','current_cmt.cmx','flat_old.cmx','flat_current.cmx','flat_probe.ml','-o','flat_probe']);
 const flat=JSON.parse(run(path.join(temporary,'flat_probe'),[temporary]));assert.ok(flat[0].length>0,'flat multiset non-vacuous');assert.deepEqual(flat[1],flat[0],'duplicate-sensitive flat preservation');
 const basic=eligible.find(x=>x.caller?.name.startsWith('basic.<fun:')&&x.head?.ident?.name==='aux');assert.ok(basic,'authentic basic recursive occurrence');const expected=basic.matching_recursive_scope.actual_root;
 const body=expected.name;
 const candidates=currentAdmissions.filter(r=>r[0]===basic.caller.name&&r[1]===`${basic.application_loc.start.file}:${basic.application_loc.start.line}`);
 assert.ok(candidates.some(r=>r[2]===body&&r[3]==='enumerated'),'RECURSIVE_OPEN_ASSERTION: authentic singleton recursive self-head reaches independently observed body '+body);
 const exe=path.join(root,'_build/default/tezt/tests/main.exe'),local=fs.existsSync(path.join(root,'_opam'));
 const tezt=cp.spawnSync(local?'opam':exe,[...(local?['exec',`--switch=${root}`,'--',exe]:[]),'--no-color','--file','tezt/tests/recursive_open_body_targets.ml','--keep-going'],{cwd:root,encoding:'utf8',timeout:120000,maxBuffer:64*1024*1024});
 const teztOutput=(tezt.stdout||'')+(tezt.stderr||'');if(tezt.error||tezt.signal)throw Error(`native Tezt setup: ${tezt.error||tezt.signal}`);if(tezt.status!==0){if(tezt.status===1&&teztOutput.includes('RECURSIVE_OPEN_ASSERTION:')&&!teztOutput.includes('RECURSIVE_OPEN_SETUP:'))assert.fail(teztOutput);throw Error(`native Tezt setup ${tezt.status}: ${teztOutput}`);}
 for(const title of ['recursive open bodies: exact self-heads and conservative boundaries','recursive open bodies: rejected root becomes dropped-node TOP'])assert.ok(teztOutput.split('\n').some(line=>line.includes('[SUCCESS]')&&line.includes(title)),`missing Tezt success: ${title}`);
 console.log('PASS recursive open native: authentic targets and complete rich/flat preservation');
}catch(e){const semantic=e instanceof assert.AssertionError;console.error(`${semantic?'ASSERTION':'SETUP'}: ${e.message}`);process.exitCode=semantic?1:2;}finally{
 if(temporary)fs.rmSync(temporary,{recursive:true,force:true});
 try{
  if(verificationState)baseline.assertStateUnchanged(verificationState,baseline.state());
  if(binaryPins)for(const [file,digest] of Object.entries(binaryPins))if(baseline.fileSha256(file)!==digest)throw Error(`verification binary changed: ${file}`);
 }catch(e){console.error(`SETUP: ${e.message}`);process.exitCode=2;}
}
