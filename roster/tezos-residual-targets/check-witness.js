#!/usr/bin/env node
'use strict';

// Independent admission helpers for alias-witness.ml output.  This module has
// no dependency on the product resolver or corpus comparison implementation.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {ComparisonInputError} = require('./comparison.js');

const hashFile = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const fail = message => { const error = new Error(message); error.code = 'ALIAS_WITNESS_INVALID'; throw error; };
const comparisonFail = message => { throw new ComparisonInputError(`alias witness: ${message}`); };
const isObject = x => x !== null && typeof x === 'object' && !Array.isArray(x);
const array = (x, at) => { if (!Array.isArray(x)) fail(`${at} must be an array`); return x; };
const string = (x, at) => { if (typeof x !== 'string' || !x) fail(`${at} must be a nonempty string`); return x; };
const location = (x, at) => {
  if (!isObject(x) || typeof x.file !== 'string' || !x.file ||
      !Number.isInteger(x.start_offset) || x.start_offset < 0 ||
      !Number.isInteger(x.end_offset) || x.end_offset < x.start_offset ||
      !Number.isInteger(x.start_line) || x.start_line < 1 ||
      !Number.isInteger(x.end_line) || x.end_line < x.start_line)
    fail(`${at} must be a complete valid source location`);
  for (const endpoint of ['start','end']) {
    const p=x[endpoint];
    if (!isObject(p) || p.file !== x.file || !Number.isInteger(p.line) || p.line < 1 ||
        !Number.isInteger(p.bol) || p.bol < 0 || !Number.isInteger(p.offset) || p.offset < p.bol ||
        !Number.isInteger(p.column) || p.column !== p.offset-p.bol)
      fail(`${at}.${endpoint} must be a complete consistent position`);
  }
  if (x.start.line !== x.start_line || x.end.line !== x.end_line ||
      x.start.offset !== x.start_offset || x.end.offset !== x.end_offset)
    fail(`${at} scalar and structured positions disagree`);
  return x;
};

function resolvedUids(occurrences, at) {
  return array(occurrences, at).flatMap((entry, index) => {
    if (!isObject(entry) || !isObject(entry.result)) fail(`${at}[${index}] malformed`);
    return ['Resolved', 'Resolved_alias'].includes(entry.result.kind)
      ? [string(entry.result.uid, `${at}[${index}].result.uid`)] : [];
  });
}

function unique(values) { return [...new Set(values)]; }

function validateRecord(record, index = 0) {
  const at = `records[${index}]`;
  if (!isObject(record) || record.schema_version !== 1) fail(`${at} schema_version must be 1`);
  string(record.cmt, `${at}.cmt`);
  for (const field of ['bindings', 'aliases', 'unsupported_alias_candidates', 'identifiers',
    'applications', 'letops', 'functions']) array(record[field], `${at}.${field}`);
  for (const [aliasIndex, alias] of record.aliases.entries()) {
    const p = `${at}.aliases[${aliasIndex}]`;
    if (!isObject(alias) || !isObject(alias.alias)) fail(`${p} malformed`);
    const aliasUid = string(alias.alias.binding_uid, `${p}.alias.binding_uid`);
    const rhsUid = string(alias.rhs_val_uid, `${p}.rhs_val_uid`);
    const bodyUids = unique(array(alias.actual_function_bodies, `${p}.actual_function_bodies`)
      .map((b, i) => string(b.binding_uid, `${p}.actual_function_bodies[${i}].binding_uid`)));
    const aliasShape = unique(resolvedUids(alias.rhs_occurrences, `${p}.rhs_occurrences`));
    const disagreements = [];
    if (alias.eligible_form !== true) disagreements.push('rhs_not_arrow');
    if (alias.one_hop_body_count !== 1 || bodyUids.length !== 1) disagreements.push('body_identity_not_unique');
    if (bodyUids.length === 1 && rhsUid !== bodyUids[0]) disagreements.push('rhs_value_uid_vs_body_uid');
    if (aliasShape.length && (aliasShape.length !== 1 || aliasShape[0] !== rhsUid))
      disagreements.push('rhs_shape_uid_vs_value_uid');
    alias._validated = {alias_uid: aliasUid, body_uid: bodyUids[0] || null, disagreements};
  }
  return record;
}

function deriveEvidence(records, options = {}) {
  array(records, 'records').forEach(validateRecord);
  const evidence = [];
  records.forEach((record, cmtIndex) => {
    record.identifiers.forEach((occurrence, occurrenceIndex) => {
      const valueUid = occurrence.val_uid;
      const shapeUids = unique(resolvedUids(occurrence.occurrences,
        `records[${cmtIndex}].identifiers[${occurrenceIndex}].occurrences`));
      const aliases = record.aliases.filter(a => a.alias.binding_uid === valueUid || shapeUids.includes(a.alias.binding_uid));
      if (!aliases.length) return;
      for (const alias of aliases) {
        const disagreements = [...alias._validated.disagreements];
        if (valueUid !== alias.alias.binding_uid) disagreements.push('occurrence_value_uid_vs_alias_uid');
        if (shapeUids.length && (shapeUids.length !== 1 || shapeUids[0] !== alias.alias.binding_uid))
          disagreements.push('occurrence_shape_uid_vs_alias_uid');
        evidence.push({
          cmt_index: cmtIndex, occurrence_index: occurrenceIndex,
          occurrence_loc: occurrence.loc, occurrence_name_loc: occurrence.name_loc,
          occurrence_path: occurrence.path, occurrence_longident: occurrence.longident,
          alias_uid: alias.alias.binding_uid, alias_binding_loc: alias.alias.binding_loc,
          alias_rhs_loc: alias.alias.rhs_loc, body_uid: alias._validated.body_uid,
          body_binding_loc: alias.actual_function_bodies[0]?.binding_loc || null,
          body_loc: alias.actual_function_bodies[0]?.body_loc || null,
          eligible: disagreements.length === 0, disagreements
        });
      }
    });
  });
  const cmtFiles = records.map(r => r.cmt);
  return {
    schema_version: 1,
    purpose: 'independent occurrence-to-one-hop-alias-to-body compiler evidence; not reviewed proof',
    actual_probe: options.probeFile ? {path: path.resolve(options.probeFile), sha256: hashFile(options.probeFile)} : null,
    source_evidence: records.map((r, i) => ({cmt_index:i, cmt:r.cmt,
      cmt_sha256: fs.existsSync(r.cmt) ? hashFile(r.cmt) : null,
      source:r.source, source_digest:r.source_digest, builddir:r.builddir})),
    records, evidence
  };
}

function validateDerived(document) {
  if (!isObject(document) || document.schema_version !== 1) fail('derived schema_version must be 1');
  array(document.records, 'records').forEach(validateRecord);
  for (const [index, item] of array(document.evidence, 'evidence').entries()) {
    if (!isObject(item) || !Number.isInteger(item.cmt_index) || !Number.isInteger(item.occurrence_index))
      fail(`evidence[${index}] malformed indices`);
    if (item.eligible !== (array(item.disagreements, `evidence[${index}].disagreements`).length === 0))
      fail(`evidence[${index}] eligibility contradicts disagreements`);
    for (const field of ['occurrence_loc','alias_binding_loc','alias_rhs_loc'])
      if (!isObject(item[field])) fail(`evidence[${index}].${field} missing`);
  }
  return document;
}

// Locator schema (all zero-based):
//   {bucket:'applications'|'identifiers', index:N}
//   {bucket:'letops', index:N, operator_index:N}
// Each invocation gets its own locator.  Callers must consume locators as a
// multiset; this function never treats one native record as multiple calls.
function validateOneHopUnchecked(record, locator) {
  validateRecord(record);
  if (!isObject(locator) || !Number.isInteger(locator.index) || locator.index < 0)
    comparisonFail('locator requires a nonnegative integer index');
  let occurrence, supplied = null, occurrenceLoc, nameLoc, pathName, shapeEntries;
  let consumerContext = null;
  if (locator.bucket === 'applications' || locator.bucket === 'identifiers') {
    occurrence = record[locator.bucket][locator.index];
    if (!isObject(occurrence)) comparisonFail('locator is out of range');
    supplied = locator.bucket === 'applications' ? occurrence.supplied_some : null;
    if (locator.bucket === 'identifiers' && (!Array.isArray(occurrence.callback_contexts) ||
        occurrence.callback_contexts.length === 0))
      comparisonFail('identifier locator is not a callback occurrence');
    if (locator.bucket === 'identifiers') {
      occurrence.callback_contexts.forEach((context, i) => {
        location(context.application_loc, `callback context[${i}] application`);
        if (!Number.isInteger(context.argument_slot) || context.argument_slot < 0)
          comparisonFail(`callback context[${i}] has invalid argument slot`);
      });
      consumerContext = {kind:'callback', contexts:occurrence.callback_contexts};
    } else consumerContext = {kind:'application', application_loc:occurrence.application_loc};
    if (locator.bucket === 'applications' && (!Number.isInteger(occurrence.supplied_some) ||
        occurrence.supplied_some < 0 || !Number.isInteger(occurrence.slots) ||
        occurrence.slots < occurrence.supplied_some || !Array.isArray(occurrence.arguments) ||
        occurrence.arguments.length !== occurrence.slots ||
        occurrence.arguments.filter(a => a && a.supplied === true).length !== occurrence.supplied_some))
      comparisonFail('application supplied/slot metadata is inconsistent');
    occurrenceLoc = locator.bucket === 'applications' ? occurrence.application_loc : occurrence.loc;
    nameLoc = occurrence.name_loc;
    pathName = occurrence.path;
    shapeEntries = occurrence.occurrences;
  } else if (locator.bucket === 'letops') {
    const letop = record.letops[locator.index];
    if (!isObject(letop) || !Number.isInteger(locator.operator_index) || locator.operator_index < 0)
      comparisonFail('letop locator requires operator_index');
    occurrence = letop.operators[locator.operator_index];
    if (!isObject(occurrence)) comparisonFail('letop operator locator is out of range');
    occurrenceLoc = occurrence.bop_loc; nameLoc = occurrence.name_loc; pathName = occurrence.path;
    shapeEntries = occurrence.located_longident_candidates;
    consumerContext = {kind:'letop_operator', role:occurrence.role, bop_loc:occurrence.bop_loc};
  } else comparisonFail('unknown locator bucket');
  location(occurrenceLoc, 'occurrence location');
  location(nameLoc, 'occurrence name location');
  if (typeof pathName !== 'string' || !pathName.includes('.'))
    comparisonFail('occurrence path is not qualified');
  const valueUid = occurrence.val_uid;
  const shapeUids = unique(resolvedUids(shapeEntries, 'occurrence shape entries'));
  if (shapeUids.length > 1) comparisonFail('occurrence has competing shape resolutions');
  const uidDiffers = shapeUids.length === 1 && shapeUids[0] !== valueUid;
  if (uidDiffers) {
    const resolvedEntries = shapeEntries.filter(x => x && x.result &&
      ['Resolved','Resolved_alias'].includes(x.result.kind));
    if (resolvedEntries.length !== 1 || resolvedEntries[0].result.kind !== 'Resolved')
      comparisonFail('signature/implementation UID layering requires one plain Resolved shape endpoint');
    if (!Array.isArray(occurrence.val_uid_bindings) || occurrence.val_uid_bindings.length !== 0)
      comparisonFail('signature value UID unexpectedly has a concrete binding');
    const declarations = occurrence.val_uid_declarations;
    if (!Array.isArray(declarations) || declarations.length !== 1)
      comparisonFail('signature value UID requires exactly one same-CMT declaration');
    const declaration = declarations[0], leaf = pathName.split('.').at(-1);
    if (declaration.kind !== 'Value' || declaration.uid !== valueUid ||
        declaration.name !== leaf || declaration.is_arrow !== true)
      comparisonFail('value UID is not the matching arrow-typed signature declaration');
    location(declaration.loc, 'signature declaration location');
  }
  const endpointUid = uidDiffers ? shapeUids[0] : valueUid;
  const aliases = record.aliases.filter(a => a.alias.binding_uid === endpointUid);
  if (aliases.length !== 1) comparisonFail(`occurrence maps to ${aliases.length} alias declarations`);
  const alias = aliases[0];
  if (alias.rhs_kind !== 'local_pident' || alias.eligible_form !== true)
    comparisonFail('alias RHS is not one bare arrow-typed local Pident');
  if (alias.one_hop_body_count !== 1 || alias.actual_function_bodies.length !== 1)
    comparisonFail('alias does not map to exactly one actual function body');
  const body = alias.actual_function_bodies[0];
  if (!Number.isInteger(body.syntactic_arity) || body.syntactic_arity <= 0 || body.rhs_is_function !== true)
    comparisonFail('target is not an actual positive-arity syntactic function body');
  if (alias.rhs_val_uid !== body.binding_uid)
    comparisonFail('alias RHS value UID disagrees with body binding UID');
  if (!isObject(alias.rhs_ident) || alias.rhs_ident.unique_name !== body.ident.unique_name)
    comparisonFail('alias RHS Ident disagrees with body Ident');
  const rhsShapeUids = unique(resolvedUids(alias.rhs_occurrences, 'alias RHS occurrences'));
  if (rhsShapeUids.length > 1) comparisonFail('alias RHS has competing shape resolutions');
  if (rhsShapeUids.length === 1 && rhsShapeUids[0] !== body.binding_uid)
    comparisonFail('alias RHS shape UID disagrees with body binding UID');
  if (alias.target_ident_bindings.length !== 1 ||
      alias.target_ident_bindings[0].ident.unique_name !== body.ident.unique_name)
    comparisonFail('Pident declaration identity is absent or ambiguous');
  const aliasMembers = record.bindings.filter(b => b.binding_uid === alias.alias.binding_uid &&
    b.ident.unique_name === alias.alias.ident.unique_name);
  const bodyMembers = record.bindings.filter(b => b.binding_uid === body.binding_uid &&
    b.ident.unique_name === body.ident.unique_name);
  if (aliasMembers.length !== 1 || bodyMembers.length !== 1)
    comparisonFail('alias/body declaration is absent or ambiguous in the same-CMT binding table');
  for (const [name, value] of [['alias binding',alias.alias.binding_loc],['alias RHS',alias.alias.rhs_loc],
    ['body binding',body.binding_loc],['body',body.body_loc]]) location(value, `${name} location`);
  return {
    locator: {...locator}, cmt: record.cmt, source: record.source,
    occurrence_path: pathName, occurrence_loc: occurrenceLoc, occurrence_name_loc: nameLoc,
    alias_uid: alias.alias.binding_uid, alias_binding_loc: alias.alias.binding_loc,
    alias_rhs_loc: alias.alias.rhs_loc, body_uid: body.binding_uid,
    body_binding_loc: body.binding_loc, body_loc: body.body_loc,
    syntactic_arity: body.syntactic_arity, supplied_some: supplied,
    consumer_context: consumerContext
  };
}

function validateOneHop(record, locator) {
  try { return validateOneHopUnchecked(record, locator); }
  catch (error) {
    if (error instanceof ComparisonInputError) throw error;
    comparisonFail(error && error.message ? error.message : String(error));
  }
}

module.exports = { deriveEvidence, validateDerived, validateOneHop, validateRecord, resolvedUids };

if (require.main === module) {
  try {
    const input = process.argv[2];
    if (!input || process.argv.length > 4) fail('usage: check-witness.js PROBE.json [PROBE-BINARY-SOURCE]');
    const raw = JSON.parse(fs.readFileSync(input, 'utf8'));
    const output = deriveEvidence(raw, {probeFile: process.argv[3]});
    validateDerived(output);
    process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
  } catch (error) {
    process.stderr.write(`ALIAS_WITNESS_SETUP: ${error.message}\n`);
    process.exitCode = 2;
  }
}
