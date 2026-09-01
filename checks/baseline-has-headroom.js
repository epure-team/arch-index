#!/usr/bin/env node
'use strict';

/*
 * Ratchet — no-must-null-regression.js's baseline must carry real headroom.
 *
 * Guards a HIGH review finding from round 1 of wire-checks-into-ci
 * (briefs/wire-checks-into-ci-review.json): BASELINE was set to exactly the
 * measured value (zero headroom), so the gate would fire on the very next
 * unrelated call site that failed to resolve — a count the implementer's own
 * analysis showed tracks ordinary repo growth, not resolver regressions.
 *
 * This check does not re-measure anything; it only asserts the source file
 * encodes CLEAN_MEASURED and a strictly positive HEADROOM, and that
 * BASELINE = CLEAN_MEASURED + HEADROOM. Proven red against commit d735da8,
 * where the file had a single bare `const BASELINE = 2024;` with no
 * CLEAN_MEASURED/HEADROOM split at all.
 *
 * Exit: 0 pass, 1 assertion fired (bug present), >=2 setup/error.
 */

const fs = require('fs');
const path = require('path');

const TARGET = path.join(__dirname, 'no-must-null-regression.js');

function setupFail(msg) {
  console.error('SETUP FAILURE: ' + msg);
  process.exit(2);
}

if (!fs.existsSync(TARGET)) setupFail('missing ' + TARGET);
const src = fs.readFileSync(TARGET, 'utf8');

const cleanMatch = src.match(/const\s+CLEAN_MEASURED\s*=\s*(\d+)\s*;/);
const headroomMatch = src.match(/const\s+HEADROOM\s*=\s*(\d+)\s*;/);
const baselineMatch = src.match(
  /const\s+BASELINE\s*=\s*CLEAN_MEASURED\s*\+\s*HEADROOM\s*;/
);

const failures = [];
if (!cleanMatch) failures.push('no `const CLEAN_MEASURED = <n>;` found');
if (!headroomMatch) failures.push('no `const HEADROOM = <n>;` found');
if (!baselineMatch) failures.push('BASELINE is not defined as CLEAN_MEASURED + HEADROOM');
if (headroomMatch && parseInt(headroomMatch[1], 10) <= 0) {
  failures.push('HEADROOM is not strictly positive: ' + headroomMatch[1]);
}

if (failures.length > 0) {
  for (const f of failures) console.error('ASSERTION FAILED: ' + f);
  process.exit(1);
}

console.log(
  'OK baseline-has-headroom: CLEAN_MEASURED=' +
    cleanMatch[1] +
    ' HEADROOM=' +
    headroomMatch[1]
);
process.exit(0);
