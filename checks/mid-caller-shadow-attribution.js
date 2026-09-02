#!/usr/bin/env node
// checks/mid-caller-shadow-attribution.js — runnable directly
// (`node checks/mid-caller-shadow-attribution.js`).
//
// Ratchet check for GitHub issue #41's review-round-1 HIGH finding: an
// intra-module call lexically BETWEEN two same-level shadowed bindings must
// resolve to the EARLIER (shadowed) definition, not the later, unrelated
// one. build_local_fn_stamps (lib/arch_index/arch_index_cmt.ml) previously
// named every Head_local call target by the bare qualified name regardless
// of which stamp it belonged to; fixed by threading build_binding_names'
// per-stamp bind_name through it.
//
// This wraps tezt/tests/shadowed_definitions.ml's "same-level shadow keeps
// two rows with distinct edges" test, which contains the mid_caller
// assertion pinning this exact behavior, run via the compiled test binary
// (built by `dune build`) rather than duplicating the OCaml
// fixture-and-index machinery in JS.
//
// Exit codes: 0 = passes (fix present); 1 = assertion fired (bug present);
// >=2 = setup/environment error (never conflated with 0/1).
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");
const binary = path.join(repoRoot, "_build/default/tezt/tests/main.exe");

if (!fs.existsSync(binary)) {
  process.stderr.write(
    `mid-caller-shadow-attribution: test binary not found at ${binary} — run 'dune build' first.\n`
  );
  process.exit(2);
}

const result = spawnSync(
  binary,
  [
    "--title",
    "shadowed-definitions: same-level shadow keeps two rows with distinct edges (#41)",
  ],
  { cwd: repoRoot, encoding: "utf8" }
);

if (result.error) {
  process.stderr.write(`mid-caller-shadow-attribution: failed to run test binary: ${result.error.message}\n`);
  process.exit(2);
}

if (result.status === 0) {
  process.exit(0);
}

// tezt reports a failing test with a non-zero exit — the assertion fired,
// which is exactly what this check exists to catch when the bug is present.
process.stdout.write(result.stdout || "");
process.stderr.write(result.stderr || "");
process.exit(1);
