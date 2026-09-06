-- Migration: executed mutation campaigns (roadmap item 3.13, specs/mutation-campaign-313.md)
-- Apply with: sqlite3 <db> < mutants-schema-migration.sql
-- Safe to re-run: every statement is IF NOT EXISTS. ADDITIVE only — no existing table,
-- column, view or row is altered or removed, so an older consumer keeps reading the
-- database unchanged. Same shape as effects-schema-migration.sql, which this follows.
--
-- Deliberately NOT named `mutation_*`: `functions.mutation_sites` is already taken and
-- counts imperative state writes, which is a different fact entirely. A campaign here is
-- about mutation TESTING; a mutation_site there is about mutating memory.
--
-- What is stored and what is not:
--   * the ENGINE STATUS is stored (`mutant_runs.engine_status`, four values);
--   * the PUBLISHED VERDICT is never stored — it is derived from the status and
--     `selection_provenance` (specs/mutation-campaign-313.md FR-011). PENDING likewise:
--     it is the ABSENCE of a `mutant_runs` row in a campaign whose `completed_at` is NULL.
--     Storing either would widen a vocabulary that `bin/arch_mutants/arch_mutants.ml`'s
--     bucketing depends on being closed.
--
-- WHAT WAS DELETED, AND WHAT SHOULD HAVE BEEN. The measurement above is about the
-- REFERENCES clause, and the columns were deleted with it — the wrong half. A plain
-- `INTEGER` with no referential action works on both schemas, which is precisely the move
-- this file already makes for `mutants.function_name`, and it was confirmed by execution:
-- an identical table with a bare INTEGER column accepted both NULL and a value under
-- `PRAGMA foreign_keys = ON`, while the REFERENCES form rejected even a bound NULL. As
-- shipped without it, a campaign carried NO link of any kind back to the index run its
-- selection was derived from. `producer_run_id` is therefore restored below as a plain
-- INTEGER: populated with the latest `producer_runs.id` where the main schema has that
-- table, NULL on the flat schema, and NULL is a real answer there rather than a missing one.
--
-- `mutants.function_id` is NOT restored, and the asymmetry is deliberate: `function_name`
-- already carries that link in a form both schemas can produce, so an integer id would be a
-- second, weaker answer to a question already answered.
--
-- NO FOREIGN KEY LEAVES THESE FOUR TABLES, and that is a measurement rather than a
-- preference. `mutants.function_id REFERENCES functions(id)` and
-- `mutant_campaigns.producer_run_id REFERENCES producer_runs(id)` were both here and both
-- unpopulated. They could not be made to work: this tool reads BOTH schemas
-- (`Arch_db.Flat` and `Arch_db.Main`), and the flat schema `arch-load` writes — the one
-- every test and every check in this campaign uses — has a `functions` table with NO `id`
-- column and no `producer_runs` table at all. With `PRAGMA foreign_keys = ON`, SQLite then
-- rejects the INSERT outright ("foreign key mismatch", "no such table: main.producer_runs")
-- even when the value bound is NULL. So the choice was between a column whose declared
-- referential action can never fire on half this tool's inputs, and no column. The link a
-- reader actually needs is `mutants.function_name`, which the writer DOES populate.
--
-- What remains — campaign_id and mutant_id — points only at tables this file creates, so it
-- resolves on every schema, and `Arch_mutant_db.open_and_migrate` issues
-- `PRAGMA foreign_keys = ON` (OFF by default, per connection) so those CASCADEs genuinely
-- fire instead of being documentation.

-- =============================================================================
-- One campaign: one execution of one engine over one index.
-- Never resumed by identity — re-running always inserts a NEW row (FR-008).
-- =============================================================================

CREATE TABLE IF NOT EXISTS mutant_campaigns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    engine TEXT NOT NULL,          -- the engine command as the operator wrote it
    engine_version TEXT,           -- NULL: the engine reported no version
    -- NULLABLE ON PURPOSE. NULL means the engine declares no seed concept at all —
    -- which the report must say IN WORDS rather than rendering as an empty value, the
    -- same discipline arch-coverage applies to `no_data` (never printed as 0%).
    seed TEXT,

    -- FR-028: which artefacts ACTUALLY ran. A campaign whose engine or test runner
    -- resolved to a binary from an enclosing checkout produces a page of survivors that
    -- reads exactly like a real finding, so the reader must be able to see the paths.
    engine_path TEXT NOT NULL,
    test_runner_path TEXT NOT NULL,

    profile TEXT,                  -- the test-invocation profile that was asked for
    granularity TEXT NOT NULL
        CHECK(granularity IN ('case', 'group', 'suite')),

    -- Which index run this campaign's selection was derived from. A plain INTEGER with NO
    -- REFERENCES clause, so it resolves on the flat schema (which has no `producer_runs`
    -- table) as well as on the main one. NULL means "this database records no producer
    -- run", which is the flat schema's honest answer and not a missing value.
    producer_run_id INTEGER,

    started_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- NULL means the campaign is still open OR was interrupted. A mutant with no
    -- `mutant_runs` row inside such a campaign is PENDING, never SURVIVED (FR-014).
    completed_at TEXT
);

-- =============================================================================
-- The mutant SITE table: stable across campaigns, keyed by where the mutation is and
-- what it replaces, never by an engine-assigned id (engine ids are not trusted for
-- identity, exactly as test ids are not — C-5).
-- =============================================================================

CREATE TABLE IF NOT EXISTS mutants (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    file_path TEXT NOT NULL,
    line INTEGER NOT NULL,
    col_start INTEGER NOT NULL,
    col_end INTEGER NOT NULL,
    replacement TEXT NOT NULL,
    -- Digest.to_hex (Digest.string <source line>) — the repository's existing idiom,
    -- see lib/arch_index/arch_index_compare.ml. It is what makes the key survive an
    -- edit ABOVE the mutant (the line moves, the hash follows) and refuse to conflate
    -- two different texts that landed on the same line/column span.
    source_hash TEXT NOT NULL,

    -- NULLABLE ON PURPOSE: a mutant the index cannot map to a function is PERSISTED,
    -- not dropped, with this column NULL. docs/mutation-testing.md already requires an
    -- unmapped survivor to be reported; dropping it one layer lower, in storage, would
    -- contradict that rule where nobody would ever see it happen.
    --
    -- A NAME and not a row id, for the reason given in the header: a `functions(id)`
    -- reference cannot resolve on the flat schema. The name is also what makes EC-4 work
    -- without any referential action — when the function is later deleted the row is
    -- retained and its name simply no longer resolves in the index, which reads as stale
    -- rather than as an error, and is the same fact a nulled-out id would have carried.
    function_name TEXT,

    created_at TEXT DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(file_path, line, col_start, col_end, replacement, source_hash)
);

CREATE INDEX IF NOT EXISTS idx_mutants_file ON mutants(file_path);
CREATE INDEX IF NOT EXISTS idx_mutants_fn   ON mutants(function_name);

-- =============================================================================
-- One row per (campaign, mutant) ACTUALLY ATTEMPTED. A mutant the campaign never
-- reached has no row here at all — that absence is what PENDING means.
-- =============================================================================

CREATE TABLE IF NOT EXISTS mutant_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    campaign_id INTEGER NOT NULL REFERENCES mutant_campaigns(id) ON DELETE CASCADE,
    mutant_id INTEGER NOT NULL REFERENCES mutants(id) ON DELETE CASCADE,

    -- The engine's own id for this mutant (mutaml: "<file-without-ext>:<n>"). Kept for
    -- traceability back into the engine's output; NOT part of any identity.
    engine_mutant_id TEXT,

    -- Closed to four values, and the OCaml consumer matches on it TOTALLY. A fifth
    -- value added here without updating that match is dropped with no error at all —
    -- no crash, no log, only a smaller answer (measured precedents: top_reason
    -- 'ambiguous_unit' at 1.9, exn_origins.form 'inferred_bind' at 1.8).
    engine_status TEXT NOT NULL
        CHECK(engine_status IN ('KILLED', 'SURVIVED', 'TIMEOUT', 'ERROR')),

    -- FR-010. A STORED column, not a derived condition: no report, view or JSON output
    -- may expose `engine_status` without it (FR-013), because a bounded SURVIVED read
    -- without its provenance is a false accusation against a test that never ran.
    --   'proved_superset' — the test cone holds no ⊤ edge AND the index carries a
    --                       soundness contract, so the executed set is provably a
    --                       superset of everything that reaches the mutant.
    --   'top_bounded'     — a ⊤ edge inside the test cone: the selection MAY have
    --                       missed a covering test.
    --   'no_contract'     — the index carries no soundness contract at all, which is a
    --                       different fact from a contract whose cone escapes (EC-5).
    selection_provenance TEXT NOT NULL
        CHECK(selection_provenance IN ('proved_superset', 'top_bounded', 'no_contract')),

    -- Both sizes, separately: the executed set is a SUPERSET of the intended one
    -- whenever the profile's granularity is coarser than one case, and the cost of
    -- that over-selection has to be visible rather than inferred.
    intended_tests INTEGER NOT NULL,
    executed_tests INTEGER NOT NULL,
    executed_superset INTEGER NOT NULL DEFAULT 0
        CHECK(executed_superset IN (0, 1)),

    recorded_at TEXT DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(campaign_id, mutant_id)
);

CREATE INDEX IF NOT EXISTS idx_mutant_runs_campaign ON mutant_runs(campaign_id);
CREATE INDEX IF NOT EXISTS idx_mutant_runs_mutant   ON mutant_runs(mutant_id);
CREATE INDEX IF NOT EXISTS idx_mutant_runs_status   ON mutant_runs(engine_status);

-- =============================================================================
-- Per-test attribution — written ONLY when attribution is genuinely known.
-- FR-007: attribution is NEVER inferred from an executed set of size > 1. A mutant
-- killed while eleven tests ran tells you the suite catches it, not which test did.
-- That is why this is a separate table from mutant_runs and not a column on it: a row
-- here is a positive claim about one test, and most runs cannot make one (C-6).
-- =============================================================================

CREATE TABLE IF NOT EXISTS mutant_kills (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    campaign_id INTEGER NOT NULL REFERENCES mutant_campaigns(id) ON DELETE CASCADE,
    mutant_id INTEGER NOT NULL REFERENCES mutants(id) ON DELETE CASCADE,

    -- The resolved test NAME, not a position: alcotest's group-plus-index addressing is
    -- an invocation detail re-resolved from the profile every campaign, so it cannot be
    -- part of identity across campaigns.
    test_name TEXT NOT NULL,

    -- How the attribution came to be known. Closed vocabulary for the same reason as
    -- selection_provenance: a third way of knowing must be a deliberate addition.
    attribution TEXT NOT NULL
        CHECK(attribution IN ('singleton_executed_set', 'engine_named')),

    recorded_at TEXT DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(campaign_id, mutant_id, test_name)
);

CREATE INDEX IF NOT EXISTS idx_mutant_kills_campaign ON mutant_kills(campaign_id);
CREATE INDEX IF NOT EXISTS idx_mutant_kills_test     ON mutant_kills(test_name);
