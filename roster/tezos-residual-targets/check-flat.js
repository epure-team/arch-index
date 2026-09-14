#!/usr/bin/env node
'use strict';

// Forced CMT fallback test.  We compile an exact temporary copy of the
// implementation so this checker can call its intentionally-private fallback
// without widening the product interface.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');

const root = path.resolve(__dirname, '../..');
let temporary;

function run(command, args, options = {}) {
  const result = cp.spawnSync(command, args, {cwd:temporary, encoding:'utf8',
    timeout:120000, maxBuffer:64*1024*1024, ...options});
  if (result.error || result.signal || result.status !== 0)
    throw new Error(`${command} setup failed (${result.status}): ${result.error || result.signal || result.stderr}`);
  return result.stdout;
}

function opam(args) {
  return fs.existsSync(path.join(root,'_opam'))
    ? run('opam', ['exec', `--switch=${root}`, '--', ...args])
    : run(args[0], args.slice(1));
}

try {
  if (process.argv.length !== 2) throw new Error('usage: check-flat.js');
  temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-index-flat-alias-'));
  const build = path.join(temporary, '_build/default');
  fs.mkdirSync(build, {recursive:true});
  const fixture = name => `module Owned = struct
  let base x = x + 1
  let alias = base
end
let run () = Owned.alias ${name === 'a' ? 1 : 2}
let root_body x = x
module Bridge = struct let alias = root_body end
let point_free = root_body
let root_run () = Bridge.alias 3
`;
  fs.writeFileSync(path.join(temporary, 'a.ml'), fixture('a'));
  fs.writeFileSync(path.join(temporary, 'b.ml'), fixture('b'));
  fs.copyFileSync(path.join(root, 'lib/arch_index/call_graph_extractor.ml'),
    path.join(temporary, 'call_graph_extractor.ml'));
  fs.writeFileSync(path.join(temporary, 'probe.ml'), `
let row name file_path : Arch_index__Lsp_extractor.fn_row =
  {name; file_path; line_start=0; line_end=0; name_char=0; exported=true;
   signature=None; summary=None}
let () =
  let project_dir = Sys.argv.(1) in
  let rows = [row "run" "a.ml"; row "run" "b.ml"; row "Owned.base" "a.ml";
              row "root_body" "a.ml"] in
  let calls = Call_graph_extractor.extract_calls_from_cmts ~project_dir rows in
  let json (c : Call_graph_extractor.call_row) = \`Assoc [
    "caller",\`String c.caller_name; "caller_file",\`String c.caller_file;
    "callee",\`String c.callee_name;
    "callee_file",(match c.callee_file with None->\`Null|Some x->\`String x);
    "call_site",\`String c.call_site;
    "edge_form",(match c.edge_form with None->\`Null|Some x->\`String x)] in
  print_endline (Yojson.Basic.to_string (\`List (List.map json calls)))
`);
  for (const name of ['a','b'])
    opam(['ocamlc','-w','-16','-bin-annot','-c','-o',path.join(build,`${name}.cmo`),`${name}.ml`]);
  const lib = name => path.join(root, '_build/default/lib', name);
  const packages = 'compiler-libs.common,sqlite3,ppxlib,eio,eio.unix,yojson,otoml,digestif.c,ppx_inline_test.runtime-lib,ppx_assert.runtime-lib';
  const includes = ['-I',lib('arch_index/.arch_index.objs/byte'),'-I',lib('arch_io/.arch_io.objs/byte'),
    '-I',lib('jsonrpc_client/.jsonrpc_client.objs/byte')];
  opam(['ocamlfind','ocamlopt','-package',packages,...includes,'-open','Arch_index__','-c','call_graph_extractor.ml']);
  opam(['ocamlfind','ocamlopt','-linkpkg','-package',packages,...includes,
    lib('arch_io/arch_io.cmxa'),lib('jsonrpc_client/jsonrpc_client.cmxa'),lib('arch_index/arch_index.cmxa'),
    'call_graph_extractor.cmx','probe.ml','-o','probe']);
  const rows = JSON.parse(run(path.join(temporary,'probe'), [temporary]));
  const actual = rows.filter(row => row.callee === 'Owned.base');
  assert.equal(actual.length, 2, 'both real CMT alias calls must be observed exactly once');
  const positive = actual.filter(row => row.caller === 'run' && row.caller_file === 'a.ml');
  const negative = actual.filter(row => row.caller === 'run' && row.caller_file === 'b.ml');
  assert.equal(positive.length, 1, 'same-file function-row positive is nonvacuous');
  assert.equal(positive[0].callee_file, 'a.ml', 'same-file body receives its file');
  assert.equal(negative.length, 1, 'missing-local-target negative is nonvacuous');
  assert.equal(negative[0].callee_file, null,
    'foreign same-name function row must not attribute the local body');
  assert.ok(actual.every(row => row.edge_form === null), 'invocation form remains ordinary');
  const pointFree = rows.filter(row => row.caller === 'point_free');
  assert.equal(pointFree.length, 2, 'both legacy point-free edges remain');
  assert.ok(pointFree.every(row => row.callee === 'root_body' &&
    row.callee_file === 'a.ml' && row.edge_form === 'value_alias'),
    'alias invocation ownership must not change legacy point-free file attribution');
  const rootCalls = rows.filter(row => row.caller === 'root_run');
  assert.equal(rootCalls.length, 2);
  assert.equal(rootCalls.find(row => row.caller_file === 'a.ml').callee_file, 'a.ml');
  assert.equal(rootCalls.find(row => row.caller_file === 'b.ml').callee_file, null);
  assert.equal(rows.length, 6, 'flat fallback invents no nested caller coverage');
  console.log('PASS flat CMT alias attribution (same-file positive, foreign-homonym refusal)');
} catch (error) {
  const assertion = error instanceof assert.AssertionError;
  process.stderr.write(`${assertion ? 'FLAT_ALIAS_ASSERTION' : 'FLAT_ALIAS_SETUP'}: ${error.message}\n`);
  process.exitCode = assertion ? 1 : 2;
} finally {
  if (temporary) fs.rmSync(temporary, {recursive:true, force:true});
}
