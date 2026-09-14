#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const cp = require('node:child_process');

const root = path.resolve(__dirname, '../..');
const probeSource = path.join(__dirname, 'alias-witness.ml');
const maxBuffer = 256 * 1024 * 1024;

function setupError(message) {
  const error = new Error(message);
  error.code = 'ALIAS_PROBE_SETUP';
  return error;
}

function checked(command, args, options = {}) {
  const result = cp.spawnSync(command, args, {encoding:'utf8', maxBuffer, ...options});
  if (result.error) throw setupError(`${command}: ${result.error.message}`);
  if (result.status !== 0) {
    const detail = (result.stderr || result.stdout || '').trim();
    throw setupError(`${command} exited ${result.status}${detail ? `: ${detail}` : ''}`);
  }
  return result.stdout;
}

function validateInputs(cmtFiles) {
  if (!Array.isArray(cmtFiles) || cmtFiles.length === 0)
    throw setupError('probeRecords requires a nonempty CMT path array');
  return cmtFiles.map((file, index) => {
    if (typeof file !== 'string' || !path.isAbsolute(file) || path.extname(file) !== '.cmt')
      throw setupError(`CMT input ${index} must be an absolute .cmt path`);
    let stat;
    try { stat = fs.statSync(file); } catch (error) { throw setupError(`CMT input ${index}: ${error.message}`); }
    if (!stat.isFile()) throw setupError(`CMT input ${index} is not a regular file`);
    return file;
  });
}

function probeRecords(cmtFiles) {
  const inputs = validateInputs(cmtFiles);
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'arch-index-alias-probe-'));
  try {
    const copiedSource = path.join(temp, 'alias_witness.ml');
    const binary = path.join(temp, 'alias-witness');
    fs.copyFileSync(probeSource, copiedSource);
    const compile = ['ocamlfind', 'ocamlopt', '-package', 'compiler-libs.common', '-linkpkg',
      '-o', binary, 'alias_witness.ml'];
    if (fs.existsSync(path.join(root,'_opam')))
      checked('opam', ['exec', `--switch=${root}`, '--', ...compile], {cwd:temp});
    else checked(compile[0], compile.slice(1), {cwd:temp});
    const output = checked(binary, inputs, {cwd:temp});
    let records;
    try { records = JSON.parse(output); }
    catch (error) { throw setupError(`native probe emitted malformed JSON: ${error.message}`); }
    if (!Array.isArray(records) || records.length !== inputs.length)
      throw setupError(`native probe returned ${Array.isArray(records) ? records.length : 'non-array'} records for ${inputs.length} inputs`);
    records.forEach((record, index) => {
      if (!record || record.schema_version !== 1 || record.cmt !== inputs[index])
        throw setupError(`native probe record ${index} does not preserve input identity/order`);
    });
    return records;
  } finally {
    fs.rmSync(temp, {recursive:true, force:true});
  }
}

module.exports = {probeRecords};

if (require.main === module) {
  try {
    process.stdout.write(`${JSON.stringify(probeRecords(process.argv.slice(2)), null, 2)}\n`);
  } catch (error) {
    process.stderr.write(`ALIAS_PROBE_SETUP: ${error.message}\n`);
    process.exitCode = 2;
  }
}
