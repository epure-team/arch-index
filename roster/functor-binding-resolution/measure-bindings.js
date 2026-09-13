// Bounded architectural metadata measurement; no Tezos source/build changes.
// A temporary symlink selection under _build preserves CMT source-root mapping.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'../..');
const tezos='/home/mathias/dev/tezos/tezos';
const manifest=path.join(root,'roster/functor-instance-resolution/tezos-irmin-candidate/manifest-410.tsv');
const hash=x=>crypto.createHash('sha256').update(x).digest('hex');
const selected=fs.readFileSync(manifest,'utf8').split('\n').filter(x=>x&&!x.startsWith('#')).map(x=>x.split('\t'));
if(selected.length!==410) throw Error('manifest does not contain410 inputs');
for(const [slice,digest,file] of selected) {
  if(!/^[a-z0-9-]+$/.test(slice)||hash(fs.readFileSync(file))!==digest) throw Error(`invalid manifest input: ${file}`);
}
function command(bin,args,cwd=root) {
  const r=cp.spawnSync(bin,args,{cwd,encoding:'utf8',maxBuffer:64*1024*1024});
  if(r.status!==0) throw Error(`${bin} exit${r.status}\n${r.stdout}\n${r.stderr}`);
  return r.stdout;
}
const before=command('git',['status','--porcelain'],tezos);
const revision=command('git',['rev-parse','HEAD'],tezos).trim();
const corpus=fs.mkdtempSync(path.join(tezos,'_build/arch-index-bindings-probe-'));
const exe=path.join(root,'_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe');
const query=path.join(root,'_build/default/bin/arch_query/arch_query.exe');
const db=path.join(corpus,'probe.db');
const out=path.join(__dirname,'tezos-irmin-bindings');
fs.mkdirSync(out,{recursive:true});
try {
  for(const [slice,,file] of selected) {
    fs.mkdirSync(path.join(corpus,slice),{recursive:true});
    fs.symlinkSync(file,path.join(corpus,slice,path.basename(file)));
  }
  const log=command(exe,['--build-dir',corpus,'--db-path',db,'--schema-path',path.join(root,'architecture-schema.sql')],tezos);
  fs.writeFileSync(path.join(out,'producer.log'),log);
  const sql=s=>JSON.parse(command('sqlite3',['-json',db,s])||'[]');
  const q=cp.spawnSync(query,[db,'functor-bindings','0'],{cwd:root,env:{...process.env,ARCH_QUERY_FORMAT:'json'},encoding:'utf8'});
  const report={revision,dirty_entries:before.trim().split('\n').filter(Boolean).length,
    manifest_sha256:hash(fs.readFileSync(manifest)),selected:410,
    producer_sha256:hash(fs.readFileSync(exe)),query_sha256:hash(fs.readFileSync(query)),
    query:{exit:q.status,stdout:q.stdout,stderr:q.stderr},
    inputs:sql('SELECT outcome,count(*) count FROM functor_binding_inputs GROUP BY outcome'),
    catalogue:sql('SELECT count(*) applications FROM functor_applications'),
    results:sql('SELECT status,reason,count(*) count FROM functor_bindings GROUP BY status,reason'),
    formals:sql("SELECT formal_position,count(*) count FROM functor_bindings WHERE status='matched' GROUP BY formal_position ORDER BY formal_position"),
    slices:sql("SELECT CASE WHEN i.source LIKE 'irmin/%' THEN 'irmin' WHEN i.source LIKE 'src/proto_alpha/%' THEN 'protocol' ELSE 'other' END slice,b.status,b.reason,count(*) count FROM functor_bindings b JOIN functor_catalogue_inputs i USING(producer_run_id,artifact) GROUP BY slice,b.status,b.reason ORDER BY slice,b.status,b.reason"),
    graph:sql('SELECT kind,count(*) count FROM calls GROUP BY kind'),
    declarations:sql('SELECT count(*) count FROM functor_declarations')};
  if(command('git',['status','--porcelain'],tezos)!==before) throw Error('Tezos worktree status changed during measurement');
  for(const [,digest,file] of selected) if(hash(fs.readFileSync(file))!==digest) throw Error('CMT changed during measurement');
  fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
} finally {
  if(path.dirname(corpus)!==path.join(tezos,'_build')||!path.basename(corpus).startsWith('arch-index-bindings-probe-')) throw Error('unsafe cleanup root');
  fs.rmSync(corpus,{recursive:true});
  console.log(`removed exact temporary symlink corpus and database: ${corpus}`);
}
