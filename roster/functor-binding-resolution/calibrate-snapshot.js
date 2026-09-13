// Bounded read-only attribution of the uncommitted product snapshot.
// Does not change constants, create commits, or use incremental build corpora.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const cp = require('node:child_process');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../..');
const label = process.argv[2];
if(label && !/^[a-z0-9-]+$/.test(label)) throw Error('invalid run label');
const out = path.join(__dirname, 'calibration', label || '');
fs.mkdirSync(out, {recursive:true});
// A failed rerun must never leave an older success available as current evidence.
fs.writeFileSync(path.join(out,'evidence.json'),JSON.stringify({verdict:'RUNNING'})+'\n');
function run(bin,args,cwd=root) {
  const r=cp.spawnSync(bin,args,{cwd,encoding:'utf8',maxBuffer:64*1024*1024});
  if(r.status!==0) throw new Error(`${bin} ${args.join(' ')}: ${r.status}\n${r.stdout}\n${r.stderr}`);
  return r.stdout;
}
const sha = x => crypto.createHash('sha256').update(x).digest('hex');
const base = run('git',['rev-parse','HEAD']).trim();
const productPaths = args => run('git',args).trim().split('\n')
  .filter(x=>x && !/^(briefs|roster|skills-meta|docs)\//.test(x)).sort();
const tracked = productPaths(['diff','--name-only','HEAD']);
const untracked = productPaths(['ls-files','--others','--exclude-standard']);
const added = ['lib/arch_index/arch_index_bindings.ml','lib/arch_index/arch_index_bindings.mli',
  'lib/arch_tools/arch_functor_bindings.ml','lib/arch_tools/arch_functor_bindings.mli',
  'lib/arch_tools/arch_functor_catalogue.mli','tezt/tests/functor_bindings.ml'];
const files=[...new Set([...tracked,...added])].sort();
for(const f of files) if(path.isAbsolute(f)||f.split('/').includes('..')) throw Error('unsafe snapshot path');
const manifest=files.map(file=>({file,sha256:sha(fs.readFileSync(path.join(root,file)))}));
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'arch-index-binding-calibration-'));
const trees=[path.join(temporary,'base'),path.join(temporary,'candidate')];
const made=[];
const evidence={base,snapshot:manifest,snapshot_sha256:sha(JSON.stringify(manifest)),cells:{},temporary};
function query(db,sql) { return JSON.parse(run('sqlite3',['-json',db,sql])||'[]'); }
try {
  for(const tree of trees) {run('git',['worktree','add','--detach',tree,base]);made.push(tree);}
  for(const file of files) {
    const target=path.join(trees[1],file);fs.mkdirSync(path.dirname(target),{recursive:true});
    fs.copyFileSync(path.join(root,file),target);
  }
  for(const [i,tree] of trees.entries()) {
    console.log(`building fresh ${i===0?'base':'candidate'}: ${tree}`);
    const log=run('opam',['exec','--switch=/home/mathias/dev/arch-index','--','dune','build','--root','.'],tree);
    fs.writeFileSync(path.join(out,`build-${i}.log`),log);
  }
  for(const [scope,relative] of [['ceiling','_build/default'],['origin','_build/default/lib/arch_index']]) {
    for(const [label,engine,corpus] of [['A',0,0],['B',1,0],['C',0,1],['D',1,1]]) {
      const db=path.join(temporary,`${scope}-${label}.db`);
      const exe=path.join(trees[engine],'_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe');
      console.log(`indexing ${scope}/${label}`);
      const log=run(exe,['--build-dir',path.join(trees[corpus],relative),'--db-path',db,
        '--schema-path',path.join(trees[engine],'architecture-schema.sql')],trees[corpus]);
      fs.writeFileSync(path.join(out,`${scope}-${label}.log`),log);
      const totals=query(db,`SELECT (SELECT count(*) FROM modules) modules,
        (SELECT count(*) FROM functions) functions,(SELECT count(*) FROM calls) calls,
        (SELECT count(*) FROM exn_origins) origins,
        (SELECT count(*) FROM calls WHERE kind='MUST' AND callee_id IS NULL AND callee_name NOT LIKE 'Stdlib.%') must_null`)[0];
      const groups=query(db,'SELECT channel,form,escapes,count(*) count FROM exn_origins GROUP BY channel,form,escapes ORDER BY channel,form,escapes');
      const modules=query(db,'SELECT path FROM modules ORDER BY path').map(x=>x.path);
      const callRows=query(db,'SELECT caller_id,callee_id,callee_name,call_site,kind,top_reason,top_anchor,edge_form,count(*) n FROM calls GROUP BY caller_id,callee_id,callee_name,call_site,kind,top_reason,top_anchor,edge_form ORDER BY caller_id,callee_id,callee_name,call_site,kind,top_reason,top_anchor,edge_form');
      evidence.cells[`${scope}-${label}`]={totals,groups,modules,calls_sha256:sha(JSON.stringify(callRows))};
    }
  }
  for(const scope of ['ceiling','origin']) for(const [a,b] of [['A','B'],['C','D']]) {
    if(JSON.stringify(evidence.cells[`${scope}-${a}`])!==JSON.stringify(evidence.cells[`${scope}-${b}`]))
      throw Error(`behavior delta detected: ${scope}/${a}-${b}`);
  }
  for(const entry of manifest) if(sha(fs.readFileSync(path.join(root,entry.file)))!==entry.sha256)
    throw Error(`active source changed during measurement: ${entry.file}`);
  if(JSON.stringify(tracked)!==JSON.stringify(productPaths(['diff','--name-only','HEAD']))
    || JSON.stringify(untracked)!==JSON.stringify(productPaths(['ls-files','--others','--exclude-standard'])))
    throw Error('active product file inventory changed during measurement');
  evidence.verdict='SOURCE_ONLY';
  fs.writeFileSync(path.join(out,'evidence.json'),JSON.stringify(evidence,null,2)+'\n');
  console.log(JSON.stringify({verdict:evidence.verdict,snapshot:evidence.snapshot_sha256,
    cells:Object.fromEntries(Object.entries(evidence.cells).map(([k,v])=>[k,v.totals]))},null,2));
} finally {
  // Exact paths derive only from this invocation's mkdtemp and successful adds.
  for(const tree of made.reverse()) run('git',['worktree','remove','--force',tree]);
  if(path.dirname(temporary)!==os.tmpdir()||!path.basename(temporary).startsWith('arch-index-binding-calibration-'))
    throw Error('unsafe cleanup root');
  fs.rmSync(temporary,{recursive:true});
  console.log(`removed owned calibration copies and build artifacts: ${temporary}`);
}
