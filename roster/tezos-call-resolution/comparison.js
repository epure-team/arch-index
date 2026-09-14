'use strict';
const crypto=require('node:crypto'),fs=require('node:fs');
const {DatabaseSync}=require('node:sqlite');
const CANONICAL_FIELDS=['caller_path','caller','call_site','target_path','target','callee_name','kind','edge_form','top_reason','top_anchor'];
const POSITION_FIELDS=['caller_line_start','caller_line_end','target_line_start','target_line_end'];
class ComparisonInputError extends Error {}
function canonicalRow(row) {
  const out={};
  for(const field of CANONICAL_FIELDS) {
    if(!(field in row)) throw new ComparisonInputError(`row lacks ${field}`);
    if(row[field]===undefined) throw new ComparisonInputError(`row has undefined ${field}`);
    out[field]=row[field];
  }
  if(typeof out.caller_path!=='string'||!out.caller_path||typeof out.caller!=='string'||!out.caller||typeof out.callee_name!=='string'||!out.callee_name)
    throw new ComparisonInputError('caller and callee identities must be strings');
  if((out.target_path===null)!==(out.target===null)) throw new ComparisonInputError('partial target identity');
  if(out.target!==null&&(typeof out.target!=='string'||!out.target||typeof out.target_path!=='string'||!out.target_path)) throw new ComparisonInputError('invalid target identity');
  if(out.call_site!==null&&typeof out.call_site!=='string') throw new ComparisonInputError('invalid call_site');
  if(!['MUST','MAY_ENUMERATED','MAY_TOP'].includes(out.kind)) throw new ComparisonInputError('invalid kind');
  if(out.edge_form!==null&&!['value_alias','module_alias'].includes(out.edge_form)) throw new ComparisonInputError('invalid edge_form');
  if(out.top_reason!==null&&typeof out.top_reason!=='string') throw new ComparisonInputError('invalid top_reason');
  if(out.top_anchor!==null&&typeof out.top_anchor!=='string') throw new ComparisonInputError('invalid top_anchor');
  return out;
}
const stringifyRow=row=>JSON.stringify(canonicalRow(row));
const canonicalStrings=rows=>rows.map(stringifyRow).sort();
// The durable canonical snapshot is one compact JSON array followed by the
// conventional final newline (the pinned baseline uses this exact encoding).
const digestStrings=strings=>crypto.createHash('sha256').update(JSON.stringify(strings)+'\n').digest('hex');
function requireDatabaseShape(db,expectedArtifactSuffixes) {
  const required={modules:['id','path'],functions:['id','module_id','name','line_start','line_end'],calls:['id','caller_id','callee_id','callee_name','call_site','kind','edge_form','top_reason','top_anchor']};
  for(const [table,columns] of Object.entries(required)) {
    const found=new Set(db.prepare(`PRAGMA table_info(${table})`).all().map(row=>row.name));
    if(!found.size) throw new ComparisonInputError(`missing table: ${table}`);
    for(const column of columns) if(!found.has(column)) throw new ComparisonInputError(`missing column: ${table}.${column}`);
  }
  const quick=db.prepare('PRAGMA quick_check').get();
  if(!quick||Object.values(quick)[0]!=='ok') throw new ComparisonInputError('SQLite quick_check failed');
  if(db.prepare('PRAGMA foreign_key_check').all().length) throw new ComparisonInputError('foreign-key violations');
  const missingCaller=db.prepare('SELECT count(*) n FROM calls c LEFT JOIN functions f ON f.id=c.caller_id WHERE f.id IS NULL').get().n;
  const missingTarget=db.prepare('SELECT count(*) n FROM calls c LEFT JOIN functions f ON f.id=c.callee_id WHERE c.callee_id IS NOT NULL AND f.id IS NULL').get().n;
  if(missingCaller||missingTarget) throw new ComparisonInputError('missing caller or target row');
  for(const table of ['functor_catalogue_runs','functor_catalogue_inputs','functor_binding_inputs'])
    if(!db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?").get(table)) throw new ComparisonInputError(`missing table: ${table}`);
  const runs=db.prepare('SELECT selected_inputs FROM functor_catalogue_runs').all();
  if(runs.length!==1||Number(runs[0].selected_inputs)!==410) throw new ComparisonInputError('catalogue run does not declare exactly 410 selected inputs');
  for(const table of ['functor_catalogue_inputs','functor_binding_inputs']) {
    const outcomes=db.prepare(`SELECT outcome,count(*) n FROM ${table} GROUP BY outcome`).all();
    if(outcomes.length!==1||outcomes[0].outcome!=='collected'||Number(outcomes[0].n)!==410)
      throw new ComparisonInputError(`${table} is incomplete`);
  }
  const joined=Number(db.prepare(`SELECT count(*) n FROM functor_catalogue_inputs c
    JOIN functor_binding_inputs b ON b.producer_run_id=c.producer_run_id AND b.artifact=c.artifact
    JOIN modules m ON m.id=c.module_id WHERE c.outcome='collected' AND b.outcome='collected'`).get().n);
  if(joined!==410) throw new ComparisonInputError('catalogue/binding/module completion join is not exactly 410');
  if(expectedArtifactSuffixes) {
    const actual=db.prepare('SELECT artifact FROM functor_catalogue_inputs').all().map(row=>{
      const parts=row.artifact.split(/[\\/]/);return parts.slice(-2).join('/');
    }).sort();
    const expected=[...expectedArtifactSuffixes].sort();
    if(JSON.stringify(actual)!==JSON.stringify(expected)) throw new ComparisonInputError('catalogue artifact set differs from the exact manifest destination set');
  }
}
function snapshotDatabase(dbPath,options={}) {
  if(!fs.existsSync(dbPath)||!fs.statSync(dbPath).isFile()) throw new ComparisonInputError(`missing database: ${dbPath}`);
  const db=new DatabaseSync(dbPath,{readOnly:true});
  try {
    requireDatabaseShape(db,options.expectedArtifactSuffixes);
    const positioned=db.prepare(`SELECT cm.path caller_path,cf.name caller,c.call_site,
      tm.path target_path,tf.name target,c.callee_name,c.kind,c.edge_form,c.top_reason,c.top_anchor,
      cf.line_start caller_line_start,cf.line_end caller_line_end,
      tf.line_start target_line_start,tf.line_end target_line_end
      FROM calls c JOIN functions cf ON cf.id=c.caller_id JOIN modules cm ON cm.id=cf.module_id
      LEFT JOIN functions tf ON tf.id=c.callee_id LEFT JOIN modules tm ON tm.id=tf.module_id`).all();
    const total=Number(db.prepare('SELECT count(*) n FROM calls').get().n);
    if(positioned.length!==total) throw new ComparisonInputError('incomplete call collection');
    const rows=positioned.map(canonicalRow),strings=canonicalStrings(rows);
    return {rows,positioned_rows:positioned,canonical_strings:strings,digest:digestStrings(strings),row_count:rows.length};
  } finally { db.close(); }
}
function counted(rows) {
  const map=new Map();
  for(const row of rows) { const key=stringifyRow(row),item=map.get(key)||{row:canonicalRow(row),count:0};item.count++;map.set(key,item); }
  return map;
}
function subtract(oldRows,newRows) {
  const oldMap=counted(oldRows),newMap=counted(newRows),removed=[],added=[];
  for(const [key,item] of oldMap) for(let n=item.count-(newMap.get(key)?.count||0);n>0;n--) removed.push(item.row);
  for(const [key,item] of newMap) for(let n=item.count-(oldMap.get(key)?.count||0);n>0;n--) added.push(item.row);
  return {removed,added};
}
const siteKey=r=>JSON.stringify([r.caller_path,r.caller,r.call_site,r.callee_name]);
const relationKey=r=>JSON.stringify([r.caller_path,r.caller,r.call_site,r.target_path,r.target]);
const sliceOf=r=>r.caller_path.startsWith('irmin/')?'irmin':r.caller_path.startsWith('src/proto_alpha/')?'protocol':'other';
const relationSet=rows=>new Set(rows.filter(r=>r.edge_form!=='value_alias'&&r.target!==null).map(relationKey));
function compareSnapshots(oldSnapshot,newSnapshot,options={}) {
  if(!oldSnapshot||!newSnapshot||!Array.isArray(oldSnapshot.rows)||!Array.isArray(newSnapshot.rows)) throw new ComparisonInputError('snapshots require row arrays');
  const oldRows=oldSnapshot.rows.map(canonicalRow),newRows=newSnapshot.rows.map(canonicalRow);
  const {removed,added}=subtract(oldRows,newRows),errors=[],transitions=[],residuals=[];
  const unmatchedBefore=counted(removed),unmatchedAfter=counted(added);
  const sameSite=(a,b)=>a.caller_path===b.caller_path&&a.caller===b.caller&&a.call_site===b.call_site;
  const pairKey=w=>`${stringifyRow(w.before)}\n${stringifyRow(w.after)}`;
  const available=(map,row)=>(map.get(stringifyRow(row))?.count||0)>0;
  const consume=(map,row)=>{map.get(stringifyRow(row)).count--;};
  const residualCapacity=new Map();

  // A reviewed pair consumes one actual removed and one actual added fact.
  // No Cartesian join, guessed spelling match, or set-based witness reuse:
  // duplicate occurrences require duplicate exact witnesses. The runner
  // separately checks snapshot digests, positions and review/source evidence.
  for(const witness of options.approvedTransitions||[]) {
    const before=canonicalRow(witness.before),after=canonicalRow(witness.after);
    const permitted=sameSite(before,after)&&before.target===null
      &&before.kind==='MAY_TOP'&&before.top_reason==='module_param'
      &&after.target!==null&&after.target_path===before.caller_path
      &&after.kind==='MAY_ENUMERATED'&&after.top_reason===null&&after.top_anchor===null
      &&after.edge_form===before.edge_form;
    if(!permitted||!available(unmatchedBefore,before)||!available(unmatchedAfter,after)) {
      errors.push(`forbidden, unused or overused transition witness ${siteKey(before)}`);
      continue;
    }
    consume(unmatchedBefore,before);consume(unmatchedAfter,after);
    transitions.push({slice:sliceOf(before),before,after,witness_approved:true});
    const key=pairKey(witness);
    residualCapacity.set(key,(residualCapacity.get(key)||0)+1);
  }
  for(const witness of options.approvedResiduals||[]) {
    const after=canonicalRow(witness.after),head=witness.head;
    const beforeHead=canonicalRow(head.before),afterHead=canonicalRow(head.after);
    const key=pairKey(head);
    const permitted=Number.isInteger(witness.arity)&&witness.arity>0
      &&Number.isInteger(witness.arguments)&&witness.arguments>witness.arity
      &&sameSite(after,afterHead)&&sameSite(beforeHead,afterHead)
      &&after.kind==='MAY_TOP'&&after.top_reason==='callback_param'
      &&after.target===null&&after.callee_name==='*TOP*'&&after.edge_form===null
      &&after.top_anchor===after.call_site&&afterHead.edge_form===null
      &&(residualCapacity.get(key)||0)>0&&available(unmatchedAfter,after);
    if(!permitted) {errors.push(`forbidden or overused return residual witness ${siteKey(after)}`);continue;}
    consume(unmatchedAfter,after);residualCapacity.set(key,residualCapacity.get(key)-1);
    residuals.push({after,head:{before:beforeHead,after:afterHead},arity:witness.arity,arguments:witness.arguments});
  }
  for(const [label,map] of [['removed',unmatchedBefore],['added',unmatchedAfter]]) {
    for(const {row,count} of map.values()) if(count>0)
      errors.push(`unaccounted ${label} fact x${count} ${siteKey(row)}`);
  }
  const oldRelations=relationSet(oldRows),newRelations=relationSet(newRows);
  const losses=[...oldRelations].filter(key=>!newRelations.has(key)),gains=[...newRelations].filter(key=>!oldRelations.has(key));
  if(losses.length) errors.push(`existing relation losses: ${losses.length}`);
  if(added.some(row=>row.kind==='MUST')) errors.push('new MUST row');
  const transitionGains=new Set(transitions.filter(t=>t.after.edge_form!=='value_alias')
    .map(t=>relationKey(t.after)).filter(key=>!oldRelations.has(key)));
  if(gains.length!==transitionGains.size||gains.some(gain=>!transitionGains.has(gain)))
    errors.push(`primary relation gains (${gains.length}) do not match transition relation set (${transitionGains.size})`);
  const slices={irmin:{relation_gains:0},protocol:{relation_gains:0},other:{relation_gains:0}};
  const gainKeys=new Set(gains);
  for(const row of newRows) if(gainKeys.delete(relationKey(row))) slices[sliceOf(row)].relation_gains++;
  return {ok:!errors.length,errors,neutral:!removed.length&&!added.length,
    summary:{old_rows:oldRows.length,new_rows:newRows.length,removed_rows:removed.length,added_rows:added.length,relation_losses:losses.length,relation_gains:gains.length},
    slices,changes:{removed,added,transitions,residuals,relation_losses:losses,relation_gains:gains}};
}
module.exports={CANONICAL_FIELDS,POSITION_FIELDS,ComparisonInputError,canonicalStrings,digestStrings,snapshotDatabase,compareSnapshots};
