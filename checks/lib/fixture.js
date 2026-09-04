// checks/lib/fixture.js — shared harness for the qualified-unit-resolution checks.
//
// Exit-code convention (roster ratchet, A-6), honoured by every check that uses this:
//   0    the property holds (pass)
//   1    the assertion fired — the defect is still present
//   >=2  setup failure (toolchain missing, build broke) — NOT a verdict on the code
//
// Everything is assembled at runtime: no fixture is committed, so a check is
// self-contained and cannot drift from what it claims to build.

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

// checks/lib/ -> checks/ -> repo root. This is a real source path, never a
// _build mirror, so it needs no marker-file search: the trap that cost the
// coverage-matrix task two fix rounds was deriving the root from an
// executable's own location, which lands inside _build/default.
const REPO_ROOT = path.resolve(__dirname, "..", "..");

const SETUP_FAILURE = 2;

function setupFail(msg, err) {
  process.stderr.write(`SETUP FAILURE: ${msg}\n`);
  if (err && err.message) process.stderr.write(`${err.message}\n`);
  process.exit(SETUP_FAILURE);
}

function run(cmd, args, opts = {}) {
  return execFileSync(cmd, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    ...opts,
  });
}

/** The producer binary, built from THIS tree. Absent => setup failure, not a fail. */
function producerPath() {
  const p = path.join(
    REPO_ROOT,
    "_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe"
  );
  if (!fs.existsSync(p)) {
    setupFail(
      `producer not built at ${p}\n` +
        `build it first:  dune build --root . bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe`
    );
  }
  return p;
}

function schemaPath() {
  const p = path.join(REPO_ROOT, "architecture-schema.sql");
  if (!fs.existsSync(p)) setupFail(`schema not found at ${p}`);
  return p;
}

/**
 * Write `files` (relative path -> contents) into a fresh temp dir, build it with
 * dune, index it with the producer, and return the sqlite db path.
 *
 * `dune` is invoked with `--root .` deliberately and non-negotiably: dune
 * searches UPWARD for its project root, and these checks run under a temp dir
 * (often /tmp) where unrelated stray dune-project files make a bare `dune build`
 * silently root itself somewhere else and behave nonsensically. That effect was
 * misdiagnosed as flaky CI for an entire task before it was understood.
 */
function buildAndIndex(name, files) {
  let dir;
  try {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), `archidx-check-${name}-`));
  } catch (e) {
    setupFail("cannot create temp dir", e);
  }

  for (const [rel, contents] of Object.entries(files)) {
    const full = path.join(dir, rel);
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, contents);
  }

  try {
    // @check builds .cmt/.cmti for executables too, which `dune build` alone
    // does not always produce — the producer reads those, so without it the
    // fixture indexes as empty and the check would "pass" vacuously.
    run("dune", ["build", "--root", ".", "@check"], { cwd: dir });
  } catch (e) {
    setupFail(`dune build failed in fixture ${name}\n${e.stdout || ""}\n${e.stderr || ""}`);
  }

  const db = path.join(dir, "index.db");
  try {
    run(producerPath(), [
      `--build-dir=${path.join(dir, "_build/default")}`,
      `--db-path=${db}`,
      `--schema-path=${schemaPath()}`,
    ]);
  } catch (e) {
    setupFail(`producer failed on fixture ${name}\n${e.stdout || ""}\n${e.stderr || ""}`);
  }

  if (!fs.existsSync(db)) setupFail(`producer produced no database for fixture ${name}`);
  return { dir, db };
}

/** One SQL query -> array of row strings (sqlite3 default pipe separator). */
function query(db, sql) {
  try {
    return run("sqlite3", [db, sql]).trim().split("\n").filter((l) => l.length > 0);
  } catch (e) {
    setupFail(`sqlite3 query failed:\n${sql}`, e);
  }
}

/**
 * Report and exit. `ok` true -> 0, false -> 1. Never throws past here, so a
 * check can never exit 1 for a reason other than its own assertion.
 */
function verdict(ok, { pass, fail }) {
  if (ok) {
    process.stdout.write(`PASS: ${pass}\n`);
    process.exit(0);
  }
  process.stdout.write(`FAIL: ${fail}\n`);
  process.exit(1);
}

module.exports = { REPO_ROOT, buildAndIndex, query, verdict, setupFail };
