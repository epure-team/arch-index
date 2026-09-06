#!/usr/bin/env node
// checks/campaign-checks-receive-their-required-argument.js — runnable directly:
// `node <path> [root]`.
//
// Exit convention: 0 = passes · 1 = assertion fired · >=2 = error/setup failure.
//
// WHY THIS EXISTS. checks/run-ratchet.js ran every campaign-tier check with NO ARGUMENTS.
// Measured against the real tree (HEAD 0851761): of five non-PASS campaign entries, three
// (scripts/check-qa-convergence.js, scripts/check-review-convergence.js,
// scripts/check-scope-diff.sh) do not name a missing precondition at all — they print their own
// `usage:` line, because they were never given the path they document as required, even though
// the artefact each one wants is present in the tree (briefs/<ACTIVE_TASK>-review.json,
// briefs/ACTIVE_TASK itself). A runner that calls every check the same way regardless of what
// that check declares it needs is not "running the campaign tier" — it is running the subset of
// the campaign tier that happens to accept zero arguments, and reporting the rest as UNRUN
// instead of as "never actually invoked correctly". scripts/check-scope-diff.sh in particular
// was, once given its manifest, the one that would have surfaced a real, already-fixed-once
// scope violation (.github/workflows/ci.yml) — see the round-1 NO-GO history on
// briefs/mutation-campaign-313-manifest.txt. A gate that never passes a check its argument
// cannot tell a real green from "never ran for real".
//
// WHAT IS ASSERTED. Each check's own `Usage:` comment is the source of truth for what it
// needs — not a guess: check-review-convergence.js wants `<review.json path>`,
// check-qa-convergence.js wants `<qa-state.json path>`, check-scope-diff.sh wants
// `<manifest-path>`. The repository's own documented convention for those paths (see
// .claude/commands/roster-review.md, roster-qa.md, roster-implement.md) is
// `briefs/<task>-{review.json,qa-state.json,manifest.txt}` where `<task>` is the content of
// briefs/ACTIVE_TASK. This check drives a throwaway fixture — never the real checks/ or
// scripts/ trees, so it cannot be fooled by (or accidentally trip) the real campaign — with
// stand-in scripts under those three exact names, and asserts run-ratchet.js actually invoked
// each one with a non-empty, task-derived argument rather than none.
//
// The trap named in the brief: a check whose own scope is narrower than what it claims is the
// same defect this file exists to catch, one level up. This only asserts that AN argument
// reached each script — not a fixed literal — precisely so a future rename of the convention
// doesn't require touching this file, but "received nothing" always fails it.

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const root = process.argv[2] || path.resolve(__dirname, '..');
const runnerAbs = path.join(root, 'checks', 'run-ratchet.js');

if (!fs.existsSync(runnerAbs)) {
  console.error(`campaign-checks-receive-their-required-argument: ${runnerAbs} does not exist.`);
  process.exit(2);
}

const TASK = 'demo-task';

// The three campaign scripts whose Usage: comment names a required path argument, and the
// marker file each stand-in writes recording exactly what argv it received.
const NAMED = ['check-review-convergence.js', 'check-qa-convergence.js', 'check-scope-diff.sh'];

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'campaign-argv-'));
const rmFixture = () => {
  try {
    fs.rmSync(dir, { recursive: true, force: true });
  } catch {
    /* best-effort cleanup */
  }
};

let failures = [];
try {
  fs.mkdirSync(path.join(dir, 'checks'));
  fs.mkdirSync(path.join(dir, 'scripts'));
  fs.mkdirSync(path.join(dir, 'briefs'));

  // Keep the ratchet tier non-empty and green: not what this check is about.
  fs.writeFileSync(path.join(dir, 'checks', 'noop.sh'), '#!/usr/bin/env bash\nexit 0\n', {
    mode: 0o755,
  });

  fs.writeFileSync(path.join(dir, 'briefs', 'ACTIVE_TASK'), `${TASK}\n`);
  fs.writeFileSync(path.join(dir, 'briefs', `${TASK}-review.json`), '{}\n');
  fs.writeFileSync(path.join(dir, 'briefs', `${TASK}-qa-state.json`), '{}\n');
  fs.writeFileSync(path.join(dir, 'briefs', `${TASK}-manifest.txt`), 'base=0\n---\n');

  const markerFor = (name) => path.join(dir, `${name}.argv`);

  // Stand-ins: record argv, then exit 0 unconditionally. They must NOT reimplement the real
  // scripts — the point is only to observe what run-ratchet.js decided to pass.
  fs.writeFileSync(
    path.join(dir, 'scripts', 'check-review-convergence.js'),
    `#!/usr/bin/env node\nrequire('fs').writeFileSync(${JSON.stringify(
      markerFor('check-review-convergence.js')
    )}, JSON.stringify(process.argv.slice(2)));\nprocess.exit(0);\n`,
    { mode: 0o755 }
  );
  fs.writeFileSync(
    path.join(dir, 'scripts', 'check-qa-convergence.js'),
    `#!/usr/bin/env node\nrequire('fs').writeFileSync(${JSON.stringify(
      markerFor('check-qa-convergence.js')
    )}, JSON.stringify(process.argv.slice(2)));\nprocess.exit(0);\n`,
    { mode: 0o755 }
  );
  fs.writeFileSync(
    path.join(dir, 'scripts', 'check-scope-diff.sh'),
    `#!/usr/bin/env bash\nprintf '%s' "$1" > ${JSON.stringify(markerFor('check-scope-diff.sh'))}\nexit 0\n`,
    { mode: 0o755 }
  );

  const r = spawnSync(process.execPath, [runnerAbs, dir], { encoding: 'utf8' });
  if (r.error) {
    console.error(`campaign-checks-receive-their-required-argument: could not run run-ratchet.js: ${r.error.message}`);
    process.exit(2);
  }

  for (const name of NAMED) {
    const marker = markerFor(name);
    if (!fs.existsSync(marker)) {
      failures.push(`${name} was not even invoked by run-ratchet.js against the fixture.`);
      continue;
    }
    const raw = fs.readFileSync(marker, 'utf8');
    const argv = name.endsWith('.sh') ? (raw ? [raw] : []) : JSON.parse(raw || '[]');
    if (argv.length === 0 || !argv[0]) {
      failures.push(
        `${name} was invoked with no argument. Its own Usage: comment requires a path, and ` +
          `briefs/${TASK}-* exists in the fixture for exactly this purpose.`
      );
    } else if (!argv[0].includes(TASK)) {
      failures.push(
        `${name} was invoked with argument ${JSON.stringify(argv[0])}, which does not name the ` +
          `active task (${TASK}) at all — not derived from briefs/ACTIVE_TASK.`
      );
    }
  }
} finally {
  rmFixture();
}

if (failures.length) {
  console.error('campaign-checks-receive-their-required-argument: run-ratchet.js is not passing');
  console.error('required arguments to the checks that declare they need one:');
  for (const f of failures) console.error(`  - ${f}`);
  process.exit(1);
}

console.log(
  'campaign-checks-receive-their-required-argument: check-review-convergence.js, ' +
    'check-qa-convergence.js and check-scope-diff.sh each received a task-derived argument.'
);
process.exit(0);
