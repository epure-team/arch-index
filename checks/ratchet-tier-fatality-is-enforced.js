#!/usr/bin/env node
// checks/ratchet-tier-fatality-is-enforced.js — runnable directly: `node <path> [root]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS. checks/run-ratchet.js's own header states the rule for the `ratchet` tier
// in so many words: "Self-contained: each builds whatever fixture it needs. There is no
// configuration in which one of these legitimately cannot run, so >=2 here is a broken check
// and is FATAL." The code that was supposed to implement that read:
//
//   } else if (code === 3 || !t.fatalUnrun) {
//
// `t.fatalUnrun` is true for the ratchet tier, so for THAT tier the whole condition collapsed
// to `code === 3` — and when it was true, the branch treated the check as merely "REFUSED (3)",
// non-fatal, exactly like the population-dependent campaign tier. A self-contained check in
// checks/ could exit 3 and the runner would report it as an unrun-but-harmless refusal instead
// of the HARNESS ERROR the header promises, and if nothing else in the run failed, `run-ratchet`
// printed PASS and exited 0. Any self-contained check can be permanently neutralised this way —
// change one `process.exit(1)` (or any other non-0/1 outcome the fatality rule is supposed to
// cover) to `process.exit(3)` and the ratchet stops ratcheting while still going green.
//
// WHAT IS ASSERTED, and why two codes and not one. The bug this check exists to catch was found
// via code 3, because 3 is also legitimately non-fatal in the OTHER tier — that is exactly what
// let the wrong condition look plausible. A fix that only special-cases 3 back to fatal (instead
// of restoring "any code besides 0 or 1, in the fatal tier, is fatal") would still pass a
// narrower version of this same regression for some other code the header's rule also covers.
// So this drives the fixture with code 3 AND a second, unrelated non-zero/non-one code, and
// requires BOTH to be treated as fatal by the ratchet tier.
//
// HOW: a self-contained temp fixture, not the real checks/ or scripts/ directories — the whole
// point is to control the tested check's exit code, and the real ratchet must never be made to
// fail on command to prove this. run-ratchet.js takes `[root]` for exactly this reason (see
// checks/ratchet-is-wired-into-ci.js's use of the same knob).

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const root = process.argv[2] || path.resolve(__dirname, '..');
const runnerAbs = path.join(root, 'checks', 'run-ratchet.js');

if (!fs.existsSync(runnerAbs)) {
  console.error(`ratchet-tier-fatality: ${runnerAbs} does not exist. Nothing was checked.`);
  process.exit(2);
}

const mkFixture = (exitCode) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ratchet-fatality-'));
  fs.mkdirSync(path.join(dir, 'checks'));
  fs.mkdirSync(path.join(dir, 'scripts'));
  // The subject: a self-contained check that always exits `exitCode`. It needs no fixture of
  // its own, so under the stated rule >=2 from it can only mean the runner refused to treat it
  // as fatal, never a real setup failure.
  fs.writeFileSync(
    path.join(dir, 'checks', 'always-exits.sh'),
    `#!/usr/bin/env bash\nexit ${exitCode}\n`,
    { mode: 0o755 }
  );
  // Keep the campaign tier non-empty and green so the only thing under test is the ratchet
  // tier's fatality handling, not the empty-tier guard.
  fs.writeFileSync(path.join(dir, 'scripts', 'check-noop.sh'), '#!/usr/bin/env bash\nexit 0\n', {
    mode: 0o755,
  });
  return dir;
};

const rmFixture = (dir) => {
  try {
    fs.rmSync(dir, { recursive: true, force: true });
  } catch {
    /* best-effort cleanup */
  }
};

const runAgainst = (fixtureRoot) =>
  spawnSync(process.execPath, [runnerAbs, fixtureRoot], { encoding: 'utf8' });

const failures = [];
// Code 3 is the code that revealed the bug (it collides with the campaign tier's legitimate
// "REFUSED" outcome); 5 is an arbitrary second code the same header rule covers and that the
// old condition never special-cased, so a fix narrowed to "code 3" specifically would still
// fail this one.
for (const exitCode of [3, 5]) {
  const dir = mkFixture(exitCode);
  let r;
  try {
    r = runAgainst(dir);
  } finally {
    rmFixture(dir);
  }
  if (r.error) {
    console.error(`ratchet-tier-fatality: could not run run-ratchet.js: ${r.error.message}`);
    process.exit(2);
  }
  const out = `${r.stdout || ''}${r.stderr || ''}`;
  if (r.status === 0) {
    failures.push(
      `exit code ${exitCode} from a self-contained checks/ entry made run-ratchet.js report ` +
        `PASS (exit 0). The header says >=2 from the ratchet tier is FATAL; it was not.`
    );
  } else if (!/HARNESS ERROR/.test(out)) {
    failures.push(
      `exit code ${exitCode} from a self-contained checks/ entry did not produce a "HARNESS ` +
        `ERROR" verdict in run-ratchet's own output (overall exit was ${r.status}). Fatal ` +
        `treatment is not just "non-zero" — it is the HARNESS ERROR classification.`
    );
  }
}

if (failures.length) {
  console.error('ratchet-tier-fatality: the ratchet tier\'s stated fatality rule is not enforced:');
  for (const f of failures) console.error(`  - ${f}`);
  process.exit(1);
}

console.log(
  'ratchet-tier-fatality: a self-contained check exiting 3 or 5 is correctly fatal ' +
    '(HARNESS ERROR) in the ratchet tier.'
);
process.exit(0);
