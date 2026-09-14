#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const {compareSnapshots} = require('./comparison.js');
const before = {caller_path:'src/proto_alpha/sample.ml',caller:'run',
  call_site:'src/proto_alpha/sample.ml:7',target_path:null,target:null,
  callee_name:'wrapped',kind:'MAY_TOP',edge_form:null,top_reason:'callback_param',
  top_anchor:'src/proto_alpha/sample.ml:7'};
const after = {...before,target_path:before.caller_path,target:'wrapped.<fun:3:1>',
  callee_name:'wrapped.<fun:3:1>',kind:'MAY_ENUMERATED',top_reason:null,top_anchor:null};
const residual = {...before,callee_name:'*TOP*'};
function compare(a,b,transitions=[],residuals=[]) {
  return compareSnapshots({rows:a},{rows:b},{approvedTransitions:transitions,approvedResiduals:residuals});
}
function run() {
  const pair={before,after};
  const positive=compare([before],[after],[pair]);
  assert.equal(positive.ok,true,'independently approved callback invocation is admissible');
  assert.equal(positive.summary.relation_gains,1);
  assert.equal(positive.slices.protocol.relation_gains,1);
  assert.equal(positive.summary.relation_losses,0);
  assert.equal(compare([before],[before]).neutral,true);
  assert.equal(compare([before],[after]).ok,false,'no implicit transition permission');
  assert.equal(compare([before],[after],[pair,pair]).ok,false,'overused pair');
  assert.equal(compare([before,before],[after,after],[pair]).ok,false,'duplicate needs exact capacity');
  assert.equal(compare([before,before],[after,after],[pair,pair]).ok,true);
  for (const change of [{kind:'MUST'},{target_path:'foreign.ml'},
    {callee_name:'wrong'},{top_anchor:'invented'},{top_reason:'callback_param'},
    {edge_form:'value_alias'},{caller:'other'},{call_site:'sample.ml:8'}]) {
    const altered={...after,...change};
    assert.equal(compare([before],[altered],[{before,after:altered}]).ok,false,
      `refuse altered target ${JSON.stringify(change)}`);
  }
  for (const change of [{top_reason:'module_param'},{top_anchor:null},
    {edge_form:'value_alias'},{target:after.target,target_path:after.target_path}]) {
    const altered={...before,...change};
    assert.equal(compare([altered],[after],[{before:altered,after}]).ok,false,
      `refuse altered predecessor ${JSON.stringify(change)}`);
  }
  const returned={after:residual,head:pair,arity:1,arguments:2};
  assert.equal(compare([before],[after,residual],[pair],[returned]).ok,true);
  assert.equal(compare([before],[after,residual],[pair]).ok,false,'unwitnessed residual');
  assert.equal(compare([before],[after,residual,residual],[pair],[returned,returned]).ok,false,
    'one return residual capacity per head occurrence');
  assert.equal(compare([before],[after,residual],[pair],[{...returned,arguments:1}]).ok,false);
  const oldResolved={...after,caller:'retained'};
  assert.equal(compare([before,oldResolved],[after],[pair]).ok,false,'old resolved relation loss');
  const alias={...oldResolved,edge_form:'value_alias'};
  assert.equal(compare([before,alias],[after],[pair]).ok,false,'old point-free row loss');
  return 'PASS open-body comparison: exact transitions, duplicates, residual capacity and refusals';
}
if(require.main===module) {
  try {if(process.argv.length!==2)throw Error('usage: check-comparison.js');console.log(run());}
  catch(e){console.error(e.stack||e);process.exitCode=e instanceof assert.AssertionError?1:2;}
}
module.exports={run};
