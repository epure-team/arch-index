#!/usr/bin/env node
'use strict';
const fs=require('node:fs'),os=require('node:os'),path=require('node:path'),crypto=require('node:crypto'),cp=require('node:child_process');
const {ComparisonInputError,snapshotDatabase,compareSnapshots}=require('./comparison.js');
const root=path.resolve(__dirname,'../..');
const tezos='/home/mathias/dev/tezos/tezos';
const manifest=path.join(root,'roster/functor-instance-resolution/tezos-irmin-candidate/manifest-410.tsv');
const activeTask=path.join(root,'briefs/ACTIVE_TASK');
const activeManifest=path.join(root,'briefs/tezos-call-resolution-manifest.txt');
const producer=path.join(root,'_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe');
const schema=path.join(root,'architecture-schema.sql');
const EXPECTED={digest:'4ce3270de370cc9db7b449531610c0dfaa7eb45647ce4dd68601fa417933fecd',rows:45018,
  manifest:'9e38880a52f855c58081b1a171af5879058cbaa2697aaa5694827cbd16f8ecd1',
  baselineProducer:'2a630da61bbad791a6475b6f5d099e41f55054fd7a090115aba394401d527f99',
  tezosRevision:'1727d7e192f2374edda7ad7adceef6f4ec51f71a',checkout:'ea8e5b4269985e779020a92a5054bc0678f5edb6'};
const sha=data=>crypto.createHash('sha256').update(data).digest('hex');
const fileSha=file=>sha(fs.readFileSync(file));
function run(bin,args,cwd) {
  const result=cp.spawnSync(bin,args,{cwd,encoding:'utf8',maxBuffer:64*1024*1024});
  if(result.error) throw new ComparisonInputError(`${bin}: ${result.error.message}`);
  if(result.status!==0) throw new ComparisonInputError(`${bin} exited ${result.status}\n${result.stdout}\n${result.stderr}`);
  return result.stdout;
}
function parseArgs(argv) {
  let baseline=null,self=false,witness=null;
  for(let i=0;i<argv.length;i++) {
    if(argv[i]==='--self') self=true;
    else if(argv[i]==='--baseline'&&i+1<argv.length) baseline=path.resolve(argv[++i]);
    else if(argv[i]==='--witness'&&i+1<argv.length) witness=path.resolve(argv[++i]);
    else throw new ComparisonInputError(`usage: verify.js --baseline DB [--self | --witness FILE]`);
  }
  if(!baseline) throw new ComparisonInputError('missing --baseline');
  if(self&&witness) throw new ComparisonInputError('--witness is only valid for a candidate comparison');
  return {baseline,self,witness};
}
function loadProvenance(baseline,{expected=EXPECTED}={}) {
  const file=path.join(path.dirname(baseline),'provenance.json');
  if(!fs.existsSync(file)) throw new ComparisonInputError('baseline lacks sibling provenance.json');
  let value;try{value=JSON.parse(fs.readFileSync(file,'utf8'));}catch(error){throw new ComparisonInputError(`invalid provenance: ${error.message}`);}
  if(path.resolve(value.db||'')!==baseline) throw new ComparisonInputError('provenance does not bind the requested database path');
  if(value.manifest_sha256!==expected.manifest||value.producer_sha256!==expected.baselineProducer
    ||value.revision!==expected.tezosRevision||value.checkout!==expected.checkout||value.selected!==410
    ||value.source_status_unchanged!==true||value.input_hashes_unchanged!==true)
    throw new ComparisonInputError('baseline provenance does not match the pinned producer/corpus/source record');
  return {file,value,sha256:fileSha(file)};
}
function readManifest({manifestFile=manifest,expected=EXPECTED}={}) {
  const content=fs.readFileSync(manifestFile);
  if(sha(content)!==expected.manifest) throw new ComparisonInputError('fixed410 manifest digest mismatch');
  const entries=content.toString('utf8').split('\n').filter(line=>line&&!line.startsWith('#')).map(line=>line.split('\t'));
  if(entries.length!==410||entries.some(parts=>parts.length!==3)) throw new ComparisonInputError('fixed410 manifest is incomplete or malformed');
  const seen=new Set();
  for(const [slice,digest,file] of entries) {
    if(!/^[a-z0-9-]+$/.test(slice)||!/^\/.*\.cmt$/.test(file)||!fs.existsSync(file)||fileSha(file)!==digest)
      throw new ComparisonInputError(`fixed410 input mismatch: ${file}`);
    const destination=`${slice}/${path.basename(file)}`;
    if(seen.has(destination)) throw new ComparisonInputError(`selection collision: ${destination}`);
    seen.add(destination);
  }
  return {content,entries};
}
function sourceState() {
  return {arch_status:run('git',['status','--porcelain=v1','--untracked-files=all'],root),
    tezos_status:run('git',['status','--porcelain=v1','--untracked-files=all'],tezos),
    tezos_revision:run('git',['rev-parse','HEAD'],tezos).trim(),active_task:fs.existsSync(activeTask)?fs.readFileSync(activeTask):Buffer.alloc(0),
    active_manifest:fs.readFileSync(activeManifest)};
}
function assertSourceState(before,after) {
  for(const key of Object.keys(before)) if(!Buffer.from(before[key]).equals(Buffer.from(after[key]))) throw new ComparisonInputError(`source state changed during verification: ${key}`);
}
function changedGroups(result,oldSnapshot,newSnapshot) {
  const keys=new Set([...result.changes.removed,...result.changes.added].map(r=>JSON.stringify([r.caller_path,r.caller,r.call_site,r.callee_name])));
  // Index each snapshot once. Refiltering every snapshot for every changed
  // group made the first real candidate spend minutes formatting its report.
  const index=snapshot=>{
    const groups=new Map();
    for(const row of snapshot.positioned_rows) {
      const key=JSON.stringify([row.caller_path,row.caller,row.call_site,row.callee_name]);
      if(!keys.has(key)) continue;
      if(!groups.has(key)) groups.set(key,[]);
      groups.get(key).push(row);
    }
    return groups;
  };
  const before=index(oldSnapshot),after=index(newSnapshot);
  return [...keys].sort().map(key=>({key:JSON.parse(key),old:before.get(key)||[],new:after.get(key)||[]}));
}
function loadWitness(file,baseline,candidate) {
  if(!file) return {transitions:[],residuals:[],sha256:null};
  let value,raw;try{raw=fs.readFileSync(file);value=JSON.parse(raw);}catch(error){throw new ComparisonInputError(`invalid witness file: ${error.message}`);}
  if(value.baseline_digest!==baseline.digest||value.candidate_digest!==candidate.digest||!Array.isArray(value.transitions))
    throw new ComparisonInputError('witness file is not bound to these exact snapshots');
  const positionKey=row=>JSON.stringify({caller_path:row.caller_path,caller:row.caller,call_site:row.call_site,
    target_path:row.target_path,target:row.target,callee_name:row.callee_name,kind:row.kind,edge_form:row.edge_form,
    top_reason:row.top_reason,top_anchor:row.top_anchor,caller_line_start:row.caller_line_start,caller_line_end:row.caller_line_end,
    target_line_start:row.target_line_start,target_line_end:row.target_line_end});
  const beforePositions=new Set(baseline.positioned_rows.map(positionKey));
  const afterPositions=new Set(candidate.positioned_rows.map(positionKey));
  const exact=(positions,wanted)=>positions.has(positionKey(wanted));
  const review=(item,index)=>{
    if(!item||['reviewed_by','reviewed_at','source_evidence'].some(key=>typeof item[key]!=='string'||!item[key].trim()))
      throw new ComparisonInputError(`witness ${index} lacks review/source evidence`);
  };
  const transitions=value.transitions.map((item,index)=>{
    review(item,index);
    if(!item.before||!item.after) throw new ComparisonInputError(`witness ${index} lacks paired facts`);
    if(!exact(beforePositions,item.before)||!exact(afterPositions,item.after))
      throw new ComparisonInputError(`witness ${index} does not contain exact facts and positions from both snapshots`);
    return {before:item.before,after:item.after};
  });
  if(value.residuals!==undefined&&!Array.isArray(value.residuals)) throw new ComparisonInputError('witness residuals must be an array');
  const residuals=(value.residuals||[]).map((item,index)=>{
    review(item,`residual ${index}`);
    if(!item.after||!item.head?.before||!item.head?.after
      ||!exact(afterPositions,item.after)
      ||!exact(beforePositions,item.head.before)
      ||!exact(afterPositions,item.head.after))
      throw new ComparisonInputError(`residual ${index} lacks exact positioned head/return facts`);
    return {after:item.after,head:item.head,arity:item.arity,arguments:item.arguments};
  });
  return {transitions,residuals,sha256:sha(raw)};
}
function main() {
  const args=parseArgs(process.argv.slice(2));
  // Implementation deactivates its slot before downstream review/QA. A foreign
  // active task is still refused; the pinned task manifest remains mandatory.
  if(fs.existsSync(activeTask)&&fs.readFileSync(activeTask,'utf8').trim()!=='tezos-call-resolution') throw new ComparisonInputError('a different task is active');
  const activeText=fs.readFileSync(activeManifest,'utf8');
  for(const required of ['roster/tezos-call-resolution/','improvement/','lib/arch_index/call_graph_extractor.ml'])
    if(!activeText.includes(required)) throw new ComparisonInputError(`active scope manifest lacks ${required}`);
  const provenance=loadProvenance(args.baseline),manifestBefore=readManifest(),stateBefore=sourceState();
  const producerBefore=fileSha(producer),schemaBefore=fileSha(schema);
  if(stateBefore.tezos_revision!==EXPECTED.tezosRevision) throw new ComparisonInputError('Tezos revision differs from pinned provenance');
  const expectedArtifactSuffixes=manifestBefore.entries.map(([slice,,file])=>`${slice}/${path.basename(file)}`);
  const baseline=snapshotDatabase(args.baseline,{expectedArtifactSuffixes});
  if(baseline.row_count!==EXPECTED.rows||baseline.digest!==EXPECTED.digest) throw new ComparisonInputError(`baseline canonical mismatch: ${baseline.row_count}/${baseline.digest}`);
  const outputRoot=path.join(root,'improvement/2026-09-14-tezos-resolution');
  fs.mkdirSync(outputRoot,{recursive:true});
  const label=`${new Date().toISOString().replace(/[:.]/g,'-')}-${args.self?'self':'candidate'}-${process.pid}`;
  const output=path.join(outputRoot,label);fs.mkdirSync(output);
  let temporary=null,candidate=baseline,producerLog='self comparison: producer not invoked\n';
  try {
    if(!args.self) {
      if(!fs.existsSync(producer)||!fs.statSync(producer).isFile()) throw new ComparisonInputError('current producer is missing');
      temporary=fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-resolution-'));
      const selection=path.join(temporary,'selection'),db=path.join(temporary,'candidate.db');fs.mkdirSync(selection);
      for(const [slice,,file] of manifestBefore.entries) { const dir=path.join(selection,slice);fs.mkdirSync(dir,{recursive:true});fs.symlinkSync(file,path.join(dir,path.basename(file))); }
      const result=cp.spawnSync(producer,['--build-dir',selection,'--db-path',db,'--schema-path',schema],{cwd:tezos,encoding:'utf8',maxBuffer:64*1024*1024});
      producerLog=`stdout:\n${result.stdout||''}\nstderr:\n${result.stderr||''}`;
      fs.writeFileSync(path.join(output,'producer.log'),producerLog);
      if(result.error||result.status!==0) throw new ComparisonInputError(`producer failed: ${result.error?.message||result.status}`);
      candidate=snapshotDatabase(db,{expectedArtifactSuffixes});
    } else fs.writeFileSync(path.join(output,'producer.log'),producerLog);
    const witness=loadWitness(args.witness,baseline,candidate);
    const result=compareSnapshots(baseline,candidate,{approvedTransitions:witness.transitions,approvedResiduals:witness.residuals});
    const manifestAfter=readManifest(),stateAfter=sourceState();
    if(!manifestBefore.content.equals(manifestAfter.content)) throw new ComparisonInputError('manifest content changed during verification');
    for(const [,digest,file] of manifestAfter.entries) if(fileSha(file)!==digest) throw new ComparisonInputError(`input changed after producer: ${file}`);
    assertSourceState(stateBefore,stateAfter);
    if(fileSha(producer)!==producerBefore||fileSha(schema)!==schemaBefore) throw new ComparisonInputError('producer or schema changed during verification');
    const runProvenance={mode:args.self?'self':'candidate',created_at:new Date().toISOString(),baseline_db:args.baseline,
      baseline_digest:baseline.digest,baseline_provenance_sha256:provenance.sha256,manifest_sha256:EXPECTED.manifest,
      selected:410,tezos_revision:stateBefore.tezos_revision,tezos_status_sha256:sha(stateBefore.tezos_status),
      arch_checkout:run('git',['rev-parse','HEAD'],root).trim(),arch_status_sha256:sha(stateBefore.arch_status),
      active_manifest_sha256:sha(stateBefore.active_manifest),producer_sha256:producerBefore,schema_sha256:schemaBefore,
      reviewed_witness_file:args.witness,reviewed_witness_sha256:witness.sha256,
      candidate_digest:candidate.digest,candidate_rows:candidate.row_count,source_status_unchanged:true,input_hashes_unchanged:true};
    fs.writeFileSync(path.join(output,'provenance.json'),JSON.stringify(runProvenance,null,2)+'\n');
    fs.writeFileSync(path.join(output,'changes.json'),JSON.stringify({...result.changes,changed_groups:changedGroups(result,baseline,candidate)},null,2)+'\n');
    const report={verdict:result.ok?'PASS':'REFUSE',classification:args.self?'self':result.neutral?'neutral_replay':'candidate',retention_authorized:false,
      note:result.neutral?'zero changes verify repeatability but are not a product gain':'positive changes require semantic source review and all downstream gates',
      errors:result.errors,summary:result.summary,slices:result.slices,baseline_digest:baseline.digest,candidate_digest:candidate.digest,output};
    fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2)+'\n');
    // Full errors remain durable in report.json; a changed corpus can have
    // thousands of pending witnesses, so stdout is a bounded summary.
    process.stdout.write(`${JSON.stringify({...report,errors:report.errors.slice(0,5),error_count:report.errors.length},null,2)}\n`);
    if(!result.ok) process.exitCode=1;
  } finally {
    if(temporary) {
      if(path.dirname(temporary)!==os.tmpdir()||!path.basename(temporary).startsWith('arch-index-resolution-')) throw new ComparisonInputError('unsafe temporary cleanup path');
      fs.rmSync(temporary,{recursive:true});
    }
  }
}
if(require.main===module) try { main(); } catch(error) {
  process.stderr.write(`SETUP FAILED: ${error.stack||error}\n`);
  process.exitCode=error instanceof ComparisonInputError?2:3;
}
module.exports={EXPECTED,loadProvenance,readManifest,loadWitness};
