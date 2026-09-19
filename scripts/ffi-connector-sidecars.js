#!/usr/bin/env node
'use strict';
/* Registry-gated view of the established FFI sidecars. The underlying staged
 * readers remain evidence producers; this adapter is the only new entry point
 * and has no default registry. */
const cp = require('child_process');
const crypto = require('crypto');
const path = require('path');
const {readRegistry, RegistryError} = require('./ffi-connector-registry.js');

function starts(pathname, roots) { return roots.some(root => pathname === root || pathname.startsWith(root + '/')); }
function targetName(target) { return `${path.posix.dirname(target.dune_path)}:${target.name || ''}`; }
function run(script, root) {
  const r = cp.spawnSync(process.execPath, [path.join(__dirname, '..', script), root], {encoding:'utf8', maxBuffer:64 * 1024 * 1024});
  if (r.error || r.status !== 0) return {status:'NOT_ANALYSED', reason:'sidecar_unavailable'};
  try { return {status:'COMPUTED', value:JSON.parse(r.stdout)}; } catch (_) { return {status:'REFUSED', reason:'invalid_sidecar_output'}; }
}
function ocaml(connector, value) {
  if (!value) return {status:'NOT_ANALYSED', reason:'ocaml_c_sidecar_unavailable', records:[]};
  const records = value.records.filter(record => starts(record.external.path, connector.source_roots)).map(record => {
    const witnesses = record.witnesses.filter(w => connector.build_targets.includes(targetName(w.target)) && starts(w.artefact.path, connector.artifact_roots));
    return {...record, availability:witnesses.length === 1 ? 'RESOLVED_STRICT' : 'MAY_TOP', top_reason:witnesses.length === 1 ? null : 'registry_scope_has_no_unique_strict_witness', witnesses};
  });
  return {status:'COMPUTED', records, summary:{resolved_strict:records.filter(x=>x.availability==='RESOLVED_STRICT').length, frontiers:records.filter(x=>x.availability==='MAY_TOP').length}};
}
function rust(connector, value) {
  if (!value) return {status:'NOT_ANALYSED', reason:'rust_archive_sidecar_unavailable', endpoints:[]};
  const endpoints = value.endpoints.filter(row => starts(row.export.path, connector.source_roots)).map(row => {
    const witness = row.witness && connector.build_targets.includes(row.witness.target) && starts(row.witness.artifact, connector.artifact_roots) ? row.witness : null;
    return {...row, availability:witness ? 'RUST_ARCHIVE_ENDPOINT' : 'MAY_TOP', top_reason:witness ? null : 'registry_scope_has_no_archive_witness', witness};
  });
  return {status:'COMPUTED', endpoints, summary:{endpoints:endpoints.filter(x=>x.availability==='RUST_ARCHIVE_ENDPOINT').length, frontiers:endpoints.filter(x=>x.availability==='MAY_TOP').length}};
}
function assemble(registry, registryDigest, sidecars) {
  const connectors = registry.connectors.map(connector => {
    if (!connector.enabled) return {id:connector.id, mechanism:connector.mechanism, version:connector.version, status:'NOT_ANALYSED', reason:'connector_disabled'};
    if (connector.mechanism === 'ocaml_c_primitive') return {id:connector.id, mechanism:connector.mechanism, version:connector.version, ...ocaml(connector, sidecars.ocaml)};
    if (connector.mechanism === 'rust_c_archive_endpoint') return {id:connector.id, mechanism:connector.mechanism, version:connector.version, ...rust(connector, sidecars.rust)};
    return {id:connector.id, mechanism:connector.mechanism, version:connector.version, status:'FRONTIER', reason:'callback_receiver_set_not_proved'};
  });
  const payload = {schema_version:1, analysis:'ffi_connector_sidecars', registry_digest:registryDigest,
    scope:'registry-gated sidecar evidence only; no SQLite write, call edge, reachability verdict or MUST claim', connectors};
  return {...payload, record_digest:crypto.createHash('sha256').update(JSON.stringify(connectors)).digest('hex')};
}
function cli() {
  const args = process.argv.slice(2);
  if (args.length !== 3 || args[0] !== '--registry') { process.stderr.write('usage: ffi-connector-sidecars.js --registry REGISTRY.json CORPUS_ROOT\n'); process.exit(2); }
  try { const {registry,digest} = readRegistry(args[1]); const root=path.resolve(args[2]);
    const sidecars={ocaml:run('roster/ffi-ocaml-c-resolution/resolution.js',root).value, rust:run('roster/ffi-c-rust-callbacks/c-rust.js',root).value};
    process.stdout.write(JSON.stringify(assemble(registry,digest,sidecars),null,2)+'\n');
  } catch (e) { process.stderr.write(`ffi-connector-sidecars: ${e.message}\n`); process.exit(e instanceof RegistryError ? 2 : 2); }
}
if (require.main === module) cli();
module.exports = {assemble};
