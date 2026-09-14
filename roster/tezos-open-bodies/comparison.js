'use strict';
// Preserve the delivered canonical schema, not its permission for module_param
// transitions. This attempt admits only independently witnessed direct calls.
const previous = require('../tezos-call-resolution/comparison.js');
const {canonicalStrings,ComparisonInputError} = previous;
const key = row => canonicalStrings([row])[0];
const canonical = row => JSON.parse(key(row));
const site = row => JSON.stringify([row.caller_path,row.caller,row.call_site]);
const relation = row => JSON.stringify([row.caller_path,row.caller,row.call_site,row.target_path,row.target]);
const slice = row => row.caller_path.startsWith('irmin/') ? 'irmin'
  : row.caller_path.startsWith('src/proto_alpha/') ? 'protocol' : 'other';
function counted(rows) {
  const result=new Map();
  for(const row of rows) {
    const k=key(row),item=result.get(k)||{row:canonical(row),count:0};
    item.count++; result.set(k,item);
  }
  return result;
}
function subtract(a,b) {
  const other=counted(b),result=[];
  for(const item of counted(a).values())
    for(let n=item.count-(other.get(key(item.row))?.count||0);n>0;n--) result.push(item.row);
  return result;
}
const relationSet=rows=>new Set(rows.filter(r=>r.target!==null&&r.edge_form!=='value_alias').map(relation));
function compareSnapshots(oldSnapshot,newSnapshot,options={}) {
  if(!Array.isArray(oldSnapshot?.rows)||!Array.isArray(newSnapshot?.rows))
    throw new ComparisonInputError('snapshots require row arrays');
  const oldRows=oldSnapshot.rows.map(canonical),newRows=newSnapshot.rows.map(canonical);
  const removed=subtract(oldRows,newRows),added=subtract(newRows,oldRows);
  const beforeLeft=counted(removed),afterLeft=counted(added);
  const errors=[],transitions=[],residuals=[],returnCapacity=new Map();
  const available=(map,row)=>(map.get(key(row))?.count||0)>0;
  const consume=(map,row)=>map.get(key(row)).count--;
  const pairKey=p=>key(p.before)+'\n'+key(p.after);
  for(const pair of options.approvedTransitions||[]) {
    const before=canonical(pair.before),after=canonical(pair.after);
    const permitted=site(before)===site(after)&&typeof before.call_site==='string'
      &&before.target===null&&before.kind==='MAY_TOP'&&before.top_reason==='callback_param'
      &&before.top_anchor===before.call_site&&before.edge_form===null
      &&after.target!==null&&after.target_path===before.caller_path
      &&after.callee_name===after.target&&after.kind==='MAY_ENUMERATED'
      &&after.top_reason===null&&after.top_anchor===null&&after.edge_form===null;
    if(!permitted||!available(beforeLeft,before)||!available(afterLeft,after)) {
      errors.push(`forbidden, unused or overused open-body transition ${site(before)}`);continue;
    }
    consume(beforeLeft,before);consume(afterLeft,after);
    transitions.push({slice:slice(before),before,after,witness_approved:true});
    const k=pairKey(pair);returnCapacity.set(k,(returnCapacity.get(k)||0)+1);
  }
  for(const witness of options.approvedResiduals||[]) {
    const after=canonical(witness.after),head={before:canonical(witness.head.before),after:canonical(witness.head.after)};
    const k=pairKey(head);
    const permitted=Number.isInteger(witness.arity)&&witness.arity>0
      &&Number.isInteger(witness.arguments)&&witness.arguments>witness.arity
      &&site(after)===site(head.after)&&after.target===null
      &&after.kind==='MAY_TOP'&&after.callee_name==='*TOP*'
      &&after.top_reason==='callback_param'&&after.top_anchor===after.call_site
      &&after.edge_form===null&&(returnCapacity.get(k)||0)>0&&available(afterLeft,after);
    if(!permitted){errors.push(`forbidden or overused returned-call residual ${site(after)}`);continue;}
    consume(afterLeft,after);returnCapacity.set(k,returnCapacity.get(k)-1);
    residuals.push({after,head,arity:witness.arity,arguments:witness.arguments});
  }
  for(const [label,map] of [['removed',beforeLeft],['added',afterLeft]])
    for(const {row,count} of map.values())if(count>0)
      errors.push(`unaccounted ${label} fact x${count} ${site(row)}`);
  const oldRelations=relationSet(oldRows),newRelations=relationSet(newRows);
  const losses=[...oldRelations].filter(k=>!newRelations.has(k));
  const gains=[...newRelations].filter(k=>!oldRelations.has(k));
  if(losses.length)errors.push(`existing relation losses: ${losses.length}`);
  if(added.some(r=>r.kind==='MUST'))errors.push('new MUST row');
  if([...removed,...added].some(r=>r.edge_form!==null))errors.push('changed reexport fact');
  const approvedGains=new Set(transitions.map(t=>relation(t.after)).filter(k=>!oldRelations.has(k)));
  if(gains.length!==approvedGains.size||gains.some(k=>!approvedGains.has(k)))
    errors.push('primary gains do not match witnessed relation set');
  const slices={irmin:{relation_gains:0},protocol:{relation_gains:0},other:{relation_gains:0}};
  const remaining=new Set(gains);
  for(const row of newRows)if(remaining.delete(relation(row)))slices[slice(row)].relation_gains++;
  return {ok:errors.length===0,errors,neutral:removed.length===0&&added.length===0,
    summary:{old_rows:oldRows.length,new_rows:newRows.length,removed_rows:removed.length,
      added_rows:added.length,relation_losses:losses.length,relation_gains:gains.length},
    slices,changes:{removed,added,transitions,residuals,relation_losses:losses,relation_gains:gains}};
}
module.exports={...previous,compareSnapshots};
