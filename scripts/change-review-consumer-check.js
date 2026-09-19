#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {runConsumer} = require('./change-review-consumer.js');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'change-review-consumer-'));
const put = (n, x) => { const p = path.join(root, n); fs.writeFileSync(p, `${JSON.stringify(x)}\n`); return p; };
const impact = ({line = 6, exportName = 'entry', frontier = 'reflector', digest = 'run-a'} = {}) => ({
  computed:true, contract_ok:true, sound_reachability:true,
  resolved_cone:'possible_bounded', resolved_edge_kinds:['MUST','MAY_ENUMERATED'],
  impact_input:{version:1,mode:'diff',range:'HEAD~1..HEAD',changed_files:[{path:'src/app.ml',lines:[line]}]},
  index_provenance:{version:1,schema_version:'1.16',producers:[{producer:'arch-index',producer_version:'1',soundness_class:'sound_with_top',invocation_digest:digest}],analysis_coverage:[{language:'ocaml',analysis:'callgraph',status:'covered',detail:null}]},
  files_unmatched:[],files_file_granular:[],decision_analysis_available:true,
  touched:[{file:'src/app.ml',name:'helper',exported:false,how:'line'}],affected_exported:[exportName],tests_reaching:['test_helper'],top_frontier:[{function:frontier,escapes:1}],findings:{computed:true,decisions:[{file:'src/app.ml',line:line,form:'if'}]}
});
const scope = put('scope.json', {version:1,corpus:'fixture@1',configuration:'impact'});
const base = runConsumer({impact:put('base.json',impact()),scope,out:path.join(root,'base')});
assert.equal(base.exit,0,'first package succeeds');
const current = runConsumer({impact:put('current.json',impact({digest:'path-changed'})),scope,baseline:path.join(root,'base','run.json'),out:path.join(root,'current')});
assert.equal(current.exit,0,'digest-only drift stays provenance');
const delta = JSON.parse(fs.readFileSync(path.join(root,'current','delta.json')));
assert.deepEqual(delta.surfaces.touched.unchanged,[{identity:'src/app.ml:helper'}]);
assert.deepEqual(delta.surfaces.frontier.unchanged,[{identity:'reflector:1'}]);
const scopeDrift = runConsumer({impact:put('scope-drift.json',impact()),scope:put('scope2.json',{version:1,corpus:'fixture@2',configuration:'impact'}),baseline:path.join(root,'base','run.json'),out:path.join(root,'scope-drift')});
assert.equal(scopeDrift.exit,2,'scope drift refuses');
assert.equal(fs.existsSync(path.join(root,'scope-drift','delta.json')),false,'refusal writes no delta');
const diffDrift = runConsumer({impact:put('diff-drift.json',impact({line:7})),scope,baseline:path.join(root,'base','run.json'),out:path.join(root,'diff-drift')});
assert.equal(diffDrift.exit,2,'changed-line scope drift refuses');
const topDrift = runConsumer({impact:put('top-drift.json',impact({frontier:'other'})),scope,baseline:path.join(root,'base','run.json'),out:path.join(root,'top-drift')});
assert.equal(topDrift.exit,0,'observed TOP frontier rows are descriptive deltas');
fs.rmSync(root,{recursive:true,force:true});
process.stdout.write('change-review-consumer checks: PASS\n');
