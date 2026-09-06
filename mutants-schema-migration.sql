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
-- =============================================================================
-- IDENTITY DOCTRINE (resolved, round 4) -- THIS FILE PREVAILS.
-- =============================================================================
-- This file and bin/arch_mutants/arch_mutants.ml each held a coherent and mutually
-- exclusive theory of what identifies a mutant, and nothing anywhere said which one
-- governed. This file: identity is where the mutation is and what it replaces, "never by
-- an engine-assigned id (engine ids are not trusted for identity)", with
-- `mutant_runs.engine_mutant_id` "NOT part of any identity". The driver: the join's FIRST
-- key was the engine's own id. A reader could satisfy either and be following the project,
-- which is why the same defect survived three rounds of review -- each round fixed the
-- symptom the driver's own theory made visible, and a catalogue whose ids happened to be
-- numbered 1, 2 still had its verdicts stored against the wrong mutants.
--
-- THE RESOLUTION: THIS FILE PREVAILS, and not by seniority. An engine id is a COORDINATE,
-- not an identity -- it is handed out by one run of one engine over one catalogue, nothing
-- in the mutant determines it, and re-running the engine or reordering the catalogue gives
-- the same mutant a different number. A verdict keyed on a position is misattributed the
-- moment the position moves, silently and with no error. And when two coherent documents
-- contradict, the one asserting a PROPERTY outranks the one asserting a MECHANISM: the
-- claim here is checkable and stays true, while the driver's described how the code
-- happened to join on the day it was written.
--
-- The engine id is DEMOTED, not deleted. `engine_mutant_id` is kept, RUN-SCOPED and marked
-- as such at its column: it records what the engine called this thing in one invocation,
-- which is genuinely useful for reading an engine's output back, and no join may consult
-- it. checks/identity-doctrine-is-resolved.sh holds both halves of this.
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
    -- `<derivation>:<32-hex MD5>`. THE DERIVATION IS PART OF THE VALUE, so a consumer
    -- holding this database reads it with plain SQL and needs no access to the OCaml:
    --   'line:<hex>' -- the digest of the actual source line. This is what makes the key
    --                   survive an edit ABOVE the mutant (the line moves, the hash
    --                   follows) and refuse to conflate two different texts that landed
    --                   on the same line/column span.
    --   'site:<hex>' -- the DEGRADED derivation, used when the source cannot be read: the
    --                   digest of a synthetic site descriptor. Still stable, still
    --                   discriminating between two replacements at one span, but it will
    --                   never notice a rewrite of the line.
    -- The two are incomparable, and this column used to hold both with nothing recording
    -- which -- the same design error as an engine id in an identity field, in the very
    -- column the UNIQUE key below is built from. It was named only in a driver docstring,
    -- which is to say only to a reader of the OCaml and never to a consumer holding the
    -- database.
    -- Both derivations hash in the anchor OCCURRENCE ordinal, and that is load-bearing:
    -- the site identity distinguishes two mutants on one anchor by that ordinal, and
    -- uniqueness here runs through this column, so a hash that ignored it would
    -- re-collapse in storage the pair the identity had just told apart.
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

    -- The engine's own id for this mutant (mutaml: "<file-without-ext>:<n>"), stored with
    -- RUN-SCOPE: it names this mutant in ONE engine invocation's output and nowhere else.
    -- Kept because reading a campaign's rows back against that output is a real need; NOT
    -- part of any identity, and no join may consult it -- see the IDENTITY DOCTRINE at the
    -- head of this file for why a coordinate cannot serve as one.
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

-- =============================================================================
-- THE VERSION DECLARATION FOR THESE FOUR TABLES.
--
-- Deliberately NOT the index-wide `schema_version`, and that separation is the fix rather
-- than a preference. Both directions of the previous arrangement were measured and both
-- were inert. `lib/arch_index/arch_index_db.ml` stamps `current_schema_version = '1.13'`
-- "for the executed-mutation-campaign tables", but it is the MAIN INDEXER that writes it
-- and architecture-schema.sql creates none of the four tables above -- so 1.13 does not
-- imply they exist. And `Arch_mutant_db.open_and_migrate` created all four while writing
-- no version at all -- so a database carrying a FINISHED campaign reported whatever its
-- indexer happened to stamp (measured at 1.2, arch-load's own flat-schema version).
-- Between the two there was no value, in either direction, on which a consumer could
-- refuse.
--
-- This key means exactly "the four mutant tables exist at this version"; its ABSENCE means
-- exactly "they may not". It is written HERE, in the migration, so the hand-applied path
-- this file's own header documents (`sqlite3 <db> < mutants-schema-migration.sql`) stamps
-- it as well as the driver does. `Arch_mutant_db.mutants_schema_version` is the constant a
-- consumer compares against; the two are bumped together.
--
-- comment_db_meta is created IF NOT EXISTS with the shape BOTH schemas already give it
-- (architecture-schema.sql and arch-load's flat schema declare it identically), so this
-- stays additive on a database that has it and self-sufficient on one that does not.
-- =============================================================================

CREATE TABLE IF NOT EXISTS comment_db_meta (
    key TEXT PRIMARY KEY,
    value TEXT
);

INSERT OR REPLACE INTO comment_db_meta(key, value)
VALUES ('mutants_schema_version', '1.0');
