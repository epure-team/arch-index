-- Architecture Index Schema
-- This database provides a queryable index of the codebase for gardening purposes.
-- Location: docs/architecture.db

PRAGMA foreign_keys = ON;

-- Roadmap 1.3: the honest-absence guarantee. One row per (language, analysis)
-- pair a coverage run could have attempted for a TARGET project, so a query
-- over a language/analysis no adapter covers returns a row saying so, never
-- silence (arch-coverage-matrix is the writer; see
-- lib/arch_index/coverage_matrix.ml). `language` is NULL for a cross-language
-- analysis (`decisions`, test-line `coverage`) that is not scoped to one
-- language. Snapshot semantics: arch-coverage-matrix deletes and re-inserts
-- every row on each run — this describes the CURRENT run, not history.
CREATE TABLE IF NOT EXISTS analysis_coverage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    language TEXT,
    analysis TEXT NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('covered', 'not_analysed', 'failed', 'partial')),
    detail TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_analysis_coverage_status ON analysis_coverage(status);
CREATE INDEX IF NOT EXISTS idx_analysis_coverage_language ON analysis_coverage(language);

-- Roadmap 1.2 (ADR 002): one row per producer invocation that wrote into this
-- database. `functions.producer_run_id` / `calls.producer_run_id` point back
-- here so a row's provenance is a join, not five denormalised text columns
-- repeated per row — at Octez scale (1.4M+ calls) the latter is a ~200 MB
-- mistake for data that never varies within one run.
CREATE TABLE IF NOT EXISTS producer_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    -- This table is written ONLY by the main-schema (CMT) writer — e.g.
    -- 'arch_index_cmt'. The two flat-schema writers (runner.ml's LSP path,
    -- bin/arch_load's NDJSON loader) never insert here; their provenance
    -- lives in comment_db_meta instead (see docs/schema.md's Provenance
    -- section for why).
    producer TEXT NOT NULL,
    producer_version TEXT,                  -- tool version string; NULL if unknown
    -- An MD5 identity fingerprint (Stdlib Digest, not SHA-256 — this compares
    -- invocations, it is not a security boundary) over (producer,
    -- producer_version, argv), so two reports of the same invocation can be
    -- compared without re-running. Does not hash project content (a full
    -- tree walk) — narrower than a full content-addressed digest, documented
    -- as a deliberate simplification, not silently dropped: a future item
    -- that needs content-sensitivity extends this digest rather than
    -- replacing the column.
    invocation_digest TEXT,
    -- ADR 002 soundness classes. Mirrors function_effects.soundness's
    -- vocabulary (sound/candidate/manual) under different names — the
    -- mapping is sound_with_top<-sound, heuristic<-candidate,
    -- asserted<-manual — recorded here as a comment, not applied to existing
    -- function_effects rows, so a later consolidation of the two columns is
    -- mechanical rather than a guess.
    soundness_class TEXT NOT NULL DEFAULT 'heuristic'
        CHECK(soundness_class IN ('sound_with_top', 'heuristic', 'asserted')),
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Modules (source files)
CREATE TABLE IF NOT EXISTS modules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    path TEXT UNIQUE NOT NULL,              -- 'src/installer.ml'
    lines INTEGER NOT NULL DEFAULT 0,       -- line count
    intent TEXT,                            -- human-written purpose description
    last_analyzed TEXT,                     -- ISO 8601 timestamp
    has_mli BOOLEAN DEFAULT 0,              -- whether .mli exists
    quint_module_raw TEXT DEFAULT NULL,     -- body of {quint-module} comment section (Quint preamble)
    -- Roadmap 1.1: which producer/language emitted this module — from
    -- Language_registry.detect_language_roots's (language, root) pairs, matched
    -- by longest root prefix. NULL on a pre-1.1 index (never guessed backward).
    language TEXT DEFAULT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_modules_lines ON modules(lines DESC);
CREATE INDEX IF NOT EXISTS idx_modules_no_intent ON modules(intent) WHERE intent IS NULL;
CREATE INDEX IF NOT EXISTS idx_modules_language ON modules(language);

-- Functions
CREATE TABLE IF NOT EXISTS functions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    module_id INTEGER NOT NULL REFERENCES modules(id) ON DELETE CASCADE,
    name TEXT NOT NULL,                     -- 'install_node'
    signature TEXT,                         -- '?quiet:bool -> node_request -> (unit, R.msg) result'
    line_start INTEGER,
    line_end INTEGER,
    line_count INTEGER GENERATED ALWAYS AS (line_end - line_start + 1) STORED,
    exposed BOOLEAN DEFAULT 0,              -- appears in .mli
    intent TEXT,                            -- human-written purpose description
    -- Comment quality fields (Epic A)
    comment_quality_score INTEGER DEFAULT NULL,  -- 0-100 composite score
    has_pre BOOLEAN DEFAULT 0,             -- {pre} section present
    has_post BOOLEAN DEFAULT 0,            -- {post} section present
    has_violators BOOLEAN DEFAULT 0,       -- {violators} section present
    has_violates BOOLEAN DEFAULT 0,        -- {violates} section present
    violators_raw TEXT DEFAULT NULL,       -- JSON: [{"name":"...","reason":"..."}]
    violates_raw TEXT DEFAULT NULL,        -- JSON: [{"name":"...","reason":"..."}]
    tests_raw TEXT DEFAULT NULL,           -- JSON: [{"file":"test/...","case":"..."}]
    quint_raw TEXT DEFAULT NULL,           -- body of {quint} comment section (raw Quint action fragment)
    -- Mutability metrics (R8): diagnostic complexity signals, NOT a gate.
    -- mutation_sites counts writes (:=, incr/decr, record field <-, array/bytes
    -- set, container mutation); deref_sites counts ref reads (!). Writes are
    -- what makes a function hard to reason about; reads are the symptom. NULL
    -- on backends that do not compute them.
    mutation_sites INTEGER DEFAULT NULL,
    deref_sites INTEGER DEFAULT NULL,
    -- Roadmap 1.1 (SPEC-sound-callgraph.md FR-001: "node identity carries a
    -- language tag + internal/external universe flag"). [language] is
    -- inherited from this function's own [modules.language] at insert time —
    -- NULL on a pre-1.1 index, never guessed. [universe] is 'internal' for
    -- every row a producer actually emitted (which is every row in THIS
    -- table); 'external' is reserved for the synthesized `ext:` leaves
    -- Arch_graph.load creates from a NULL callee_id, which are not functions
    -- rows at all today (deferred to a later item) — so 'internal' is the
    -- only value this table's own rows can carry right now, and the CHECK
    -- constraint documents the eventual full domain rather than one this
    -- table will ever violate on its own.
    language TEXT DEFAULT NULL,
    universe TEXT NOT NULL DEFAULT 'internal' CHECK(universe IN ('internal', 'external')),
    -- Roadmap 1.2 (ADR 002): which producer_runs row emitted this row. NULL on
    -- a pre-1.2 index, never guessed backward (same discipline as language).
    producer_run_id INTEGER REFERENCES producer_runs(id) ON DELETE SET NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(module_id, name)
);

-- Violation graph view: surfaces broken violator cross-references (Epic A)
CREATE VIEW IF NOT EXISTS v_violation_graph AS
SELECT
    f.id AS function_id,
    f.name AS function_name,
    m.path AS module_path,
    json_extract(v.value, '$.name') AS referenced_name,
    json_extract(v.value, '$.reason') AS reason,
    CASE WHEN EXISTS (
        SELECT 1 FROM functions f2
        WHERE f2.name = json_extract(v.value, '$.name')
    ) THEN 'resolved' ELSE 'broken' END AS link_status
FROM functions f
JOIN modules m ON f.module_id = m.id
JOIN json_each(f.violators_raw) v
WHERE f.violators_raw IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_functions_module ON functions(module_id);
CREATE INDEX IF NOT EXISTS idx_functions_exposed ON functions(exposed);
CREATE INDEX IF NOT EXISTS idx_functions_language ON functions(language);
CREATE INDEX IF NOT EXISTS idx_functions_universe ON functions(universe);
CREATE INDEX IF NOT EXISTS idx_functions_no_intent ON functions(intent) WHERE intent IS NULL;
CREATE INDEX IF NOT EXISTS idx_functions_large ON functions(line_count DESC);
CREATE INDEX IF NOT EXISTS idx_functions_mutation ON functions(mutation_sites DESC)
  WHERE mutation_sites IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_functions_producer_run ON functions(producer_run_id);

-- Mutability density (R8). Advisory only: a threshold on this is gameable by
-- hiding writes behind a helper, so surface it for sorting and review, never as
-- a CI gate.
CREATE VIEW IF NOT EXISTS v_mutation_heavy AS
SELECT
    m.path            AS module_path,
    f.name            AS function_name,
    f.mutation_sites,
    f.deref_sites,
    f.line_count,
    CASE WHEN f.line_count > 0
         THEN ROUND(f.mutation_sites * 1000.0 / f.line_count, 1) END AS mutations_per_kloc
FROM functions f
JOIN modules m ON m.id = f.module_id
WHERE f.mutation_sites IS NOT NULL AND f.mutation_sites > 0
ORDER BY f.mutation_sites DESC;

-- Call relationships (which functions call which)
-- callee_id is NULL for external/unresolved calls (stdlib, dependencies)
-- callee_name is always populated for searchability
--
-- EDGE-KIND CONTRACT (PR-A): a ⊤-marking backend MUST also populate `kind` and set
-- comment_db_meta('callgraph_contract','v1'). kind ∈ {MUST (uniquely-resolved static call),
-- MAY_ENUMERATED (dynamic call bounded to a candidate set), MAY_TOP (unresolvable/dynamic/reflective/
-- FFI — could-call-anything, NEVER dropped)}. `reaches` uses MUST only (under-approx); `unreachable`
-- uses the full graph + ⊤ rule (over-approx) and REFUSES if the contract flag is absent. Legacy DBs
-- without `kind` are treated as all-MUST for `reaches` and refused for `unreachable`.
CREATE TABLE IF NOT EXISTS calls (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    caller_id INTEGER NOT NULL REFERENCES functions(id) ON DELETE CASCADE,
    callee_id INTEGER REFERENCES functions(id) ON DELETE CASCADE,
    callee_name TEXT NOT NULL,              -- function name (for unresolved: Module.func)
    call_site TEXT,                         -- file:line location
    kind TEXT,                              -- edge-kind contract: MUST | MAY_ENUMERATED | MAY_TOP (NULL on legacy = MUST)
    -- Roadmap 1.2 (ADR 002): which producer_runs row emitted this edge.
    producer_run_id INTEGER REFERENCES producer_runs(id) ON DELETE SET NULL,
    -- Roadmap 1.4: the ⊤-anchor taxonomy. Both NULL unless kind='MAY_TOP' —
    -- meaningless for a resolved or bounded-candidate edge. top_reason is
    -- the AGNOSTIC vocabulary every producer maps its own local causes onto
    -- (docs/edge-kind-contract.md); an out-of-vocabulary value is rejected by
    -- the loader like an invalid kind is today. top_anchor is a location
    -- string for the expression that lost the target — not always
    -- call_site (a callback's anchor is its own parameter binding, not the
    -- call that invokes it), though every producer shipped today uses
    -- call_site (file:line — no column; the OCaml producer's own call sites
    -- carry none today) as an initial approximation; see
    -- docs/edge-kind-contract.md.
    top_reason TEXT
        CHECK(top_reason IS NULL OR top_reason IN (
            'callback_param', 'module_param', 'dropped_node',
            'reflection', 'ffi', 'dynamic_load', 'dispatch_unbounded',
            'trait_object', 'fn_pointer', 'extern'
        ))
        -- FIX (review, MEDIUM): the vocabulary CHECK alone let a non-MAY_TOP
        -- row carry a top_reason, which is meaningless (a resolved or
        -- bounded-candidate edge is not unknowable, so no reason applies).
        CHECK(top_reason IS NULL OR kind = 'MAY_TOP'),
    top_anchor TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_calls_caller ON calls(caller_id);
CREATE INDEX IF NOT EXISTS idx_calls_callee ON calls(callee_id);
CREATE INDEX IF NOT EXISTS idx_calls_callee_name ON calls(callee_name);
CREATE INDEX IF NOT EXISTS idx_calls_producer_run ON calls(producer_run_id);
CREATE INDEX IF NOT EXISTS idx_calls_top_reason ON calls(top_reason);

-- Backend/contract metadata (key/value). A ⊤-marking backend sets
-- callgraph_contract='v1' here once every calls.kind is populated (see EDGE-KIND
-- CONTRACT above); arch-query's `unreachable`/`escapes` REFUSE without it.
CREATE TABLE IF NOT EXISTS comment_db_meta (
    key TEXT PRIMARY KEY,
    value TEXT
);

-- Module dependencies (open, include, alias, local_open)
CREATE TABLE IF NOT EXISTS module_deps (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_module INTEGER NOT NULL REFERENCES modules(id) ON DELETE CASCADE,
    target_module INTEGER REFERENCES modules(id) ON DELETE CASCADE,  -- NULL if external
    target_path TEXT NOT NULL,               -- Module path string (e.g., "Stdlib.List")
    dep_kind TEXT NOT NULL CHECK(dep_kind IN ('open', 'include', 'alias', 'local_open')),
    alias_name TEXT,                         -- For alias: the local name (e.g., "L" for "module L = List")
    line_number INTEGER,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_module_deps_source ON module_deps(source_module);
CREATE INDEX IF NOT EXISTS idx_module_deps_target ON module_deps(target_module);
CREATE INDEX IF NOT EXISTS idx_module_deps_kind ON module_deps(dep_kind);

-- Type usage (which functions use which types)
CREATE TABLE IF NOT EXISTS type_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    function_id INTEGER NOT NULL REFERENCES functions(id) ON DELETE CASCADE,
    type_id INTEGER REFERENCES types(id) ON DELETE CASCADE,  -- NULL if external type
    type_name TEXT NOT NULL,                 -- For external types or display
    usage_role TEXT NOT NULL CHECK(usage_role IN ('param', 'return', 'local', 'field_access', 'constructor')),
    position INTEGER,                        -- Parameter position (for params)
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_type_usage_function ON type_usage(function_id);
CREATE INDEX IF NOT EXISTS idx_type_usage_type ON type_usage(type_id);
CREATE INDEX IF NOT EXISTS idx_type_usage_role ON type_usage(usage_role);

-- Unsafe parameters (type safety tracking)
CREATE TABLE IF NOT EXISTS unsafe_params (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    function_id INTEGER NOT NULL REFERENCES functions(id) ON DELETE CASCADE,
    param_name TEXT NOT NULL,               -- 'instance'
    current_type TEXT NOT NULL,             -- 'string'
    target_type TEXT,                       -- 'Instance_name.t'
    fixed BOOLEAN DEFAULT 0,
    fixed_at TEXT,
    github_issue INTEGER,                   -- tracking issue number
    UNIQUE(function_id, param_name)
);

CREATE INDEX IF NOT EXISTS idx_unsafe_unfixed ON unsafe_params(fixed) WHERE fixed = 0;

-- Decision / condition analysis (study §5). One row per boolean decision site,
-- one per atomic condition. Verdicts carry their PROVENANCE: a finding that says
-- "dead" without a reason is unusable by a reviewer and dangerous when applied
-- by an agent (§6.7). Written by a decision-analysis producer; absent on
-- backends that do not run one.
CREATE TABLE IF NOT EXISTS decisions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    function_id INTEGER REFERENCES functions(id) ON DELETE CASCADE,
                                            -- NULL when no function range contains
                                            -- the site: recorded, never dropped
    file_path TEXT NOT NULL,
    line INTEGER NOT NULL,
    col INTEGER,
    form TEXT NOT NULL,                     -- if | match | while | when | assert | boolexpr
    arity INTEGER NOT NULL,                 -- number of atomic conditions
    verdict TEXT NOT NULL,                  -- OK | CONSTANT_TRUE | CONSTANT_FALSE
                                            --  | DEAD_SUBTERM | IDENTICAL_ARMS
                                            --  | IMPLIED_TRUE | IMPLIED_FALSE
                                            --  | UNREACHABLE_PATH | HIGH_ARITY
    decided_by TEXT NOT NULL,               -- enumeration | smt | budget_exhausted | no_solver
    evidence TEXT,                          -- removable atoms, or the settling guards
    snippet TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_decisions_fn ON decisions(function_id);
CREATE INDEX IF NOT EXISTS idx_decisions_verdict ON decisions(verdict);

-- One row per atomic condition of a decision that carried a verdict.
--
-- NOT POPULATED BY ANY PRODUCER IN THIS TREE. decision-lint records the decision and its arity;
-- it does not yet emit the per-condition independence verdicts this table is shaped for. It is
-- listed here as the intended shape, and `decision-lint --db` DELETEs it on every run so that
-- rows from some future or out-of-tree producer cannot survive a reload and be read as current
-- — but a consumer must treat an empty `conditions` as "not computed", never as "no condition
-- carried a verdict".
CREATE TABLE IF NOT EXISTS conditions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    decision_id INTEGER NOT NULL REFERENCES decisions(id) ON DELETE CASCADE,
    ordinal INTEGER NOT NULL,               -- short-circuit evaluation order
    text TEXT NOT NULL,                     -- the condition as written
    merge_rung INTEGER,                     -- 0..4: which canonicalisation rung merged it
    verdict TEXT NOT NULL                   -- INDEPENDENT | REMOVABLE | UNKNOWN
);

CREATE INDEX IF NOT EXISTS idx_conditions_decision ON conditions(decision_id);

-- Decisions carrying an actionable verdict. Advisory: report and review, never
-- a CI gate in this form (ratcheting is a separate, later decision).
CREATE VIEW IF NOT EXISTS v_useless_branches AS
SELECT
    d.file_path,
    d.line,
    f.name AS function_name,
    d.form,
    d.verdict,
    d.decided_by,
    d.evidence,
    d.snippet
FROM decisions d
LEFT JOIN functions f ON f.id = d.function_id
WHERE d.verdict NOT IN ('OK', 'HIGH_ARITY')
ORDER BY d.file_path, d.line;

-- Statically dead call sites (R2). A call recorded in a basic block that is
-- UNREACHABLE from its function's CFG entry can never execute — code after an
-- unconditional `raise`, an arm the walker proved unenterable, and so on.
-- Under-approximate: unmodelled constructs stay reachable, so this table
-- under-reports and never over-claims. Reported, never a gate.
CREATE TABLE IF NOT EXISTS dead_code_sites (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    function_id INTEGER NOT NULL REFERENCES functions(id) ON DELETE CASCADE,
    call_site TEXT,                         -- file:line of the unreachable call
    callee_name TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_dead_sites_fn ON dead_code_sites(function_id);

CREATE VIEW IF NOT EXISTS v_dead_code AS
SELECT
    m.path        AS module_path,
    f.name        AS function_name,
    d.call_site,
    d.callee_name
FROM dead_code_sites d
JOIN functions f ON f.id = d.function_id
JOIN modules m ON m.id = f.module_id
ORDER BY m.path, f.name, d.call_site;

-- Exception-identity may-raise sets (specs/exn-raise-sets.md). Written by the
-- CMT producer only; a DB without comment_db_meta('exn_contract','v1') is
-- NOT_ANALYSED for the raises / raisers-of / exn-stats queries — never an
-- empty set read as "raises nothing".
--
-- exn_scopes: one row per `try` body / `match … with exception` scrutinee in a
-- function node (lambda nodes included), with the enclosing scope of the same
-- node as parent. catch_all = some unguarded, non-re-raising catch-all arm.
-- channel: specs/error-channels.md — which channel this scope belongs to.
-- The producer emits only 'exception' rows as of schema 1.3 (slices 0-1);
-- the column exists so a later producer can widen without another migration.
CREATE TABLE IF NOT EXISTS exn_scopes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    function_id INTEGER NOT NULL REFERENCES functions(id) ON DELETE CASCADE,
    parent_id INTEGER REFERENCES exn_scopes(id) ON DELETE CASCADE,
    form TEXT NOT NULL CHECK(form IN ('try','match_exception')),
    line INTEGER NOT NULL,
    col INTEGER NOT NULL,
    catch_all BOOLEAN NOT NULL DEFAULT 0,
    channel TEXT NOT NULL DEFAULT 'exception'
);
-- Canonical constructor paths caught by a scope's closing arms.
CREATE TABLE IF NOT EXISTS exn_scope_catches (
    scope_id INTEGER NOT NULL REFERENCES exn_scopes(id) ON DELETE CASCADE,
    exn_path TEXT NOT NULL
);
-- exn_origins: a raise-head application, an assert, or a Partial match.
-- exn_path NULL = unknown value (⊤) for 'unknown', informational for 'reraise'.
-- scope_id = innermost enclosing scope of the same node ('reraise': the scope
-- whose arm bound the re-raised variable). escapes = not closed by the chain.
-- channel: see exn_scopes.channel above — same schema-1.3 note applies.
CREATE TABLE IF NOT EXISTS exn_origins (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    function_id INTEGER NOT NULL REFERENCES functions(id) ON DELETE CASCADE,
    scope_id INTEGER REFERENCES exn_scopes(id) ON DELETE SET NULL,
    form TEXT NOT NULL CHECK(form IN ('raise','reraise','unknown','failwith','invalid_arg','assert','partial_match','compare','division','index','inferred_bind')),
    exn_path TEXT,
    escapes BOOLEAN NOT NULL DEFAULT 1,
    line INTEGER NOT NULL,
    col INTEGER NOT NULL,
    channel TEXT NOT NULL DEFAULT 'exception'
);
-- The innermost scope enclosing a call site, PER CHANNEL (absent = no scope).
-- This table carries no channel column of its own — the scope it points at
-- already does (specs/error-channels.md Clarifications: "Schema"), so a
-- consumer that wants one channel's scope joins exn_scopes and filters there.
--
-- PRIMARY KEY (call_id, scope_id), not (call_id): one call site can be covered
-- by an exception-channel scope AND a value-channel scope at the same time (a
-- carrier call inside a `try`, whose result is then matched on). With the
-- single-column key only ONE of the two could be stored: the walker encoded
-- the second id space in the SIGN of the integer and then DROPPED the
-- value-channel scope whenever an exception scope also covered the call — an
-- over-approximation, so never unsound, but a permanent precision ceiling and
-- a second id space living inside one column. Both are gone.
CREATE TABLE IF NOT EXISTS call_exn_scopes (
    call_id INTEGER NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
    scope_id INTEGER NOT NULL REFERENCES exn_scopes(id) ON DELETE CASCADE,
    PRIMARY KEY (call_id, scope_id)
);
-- `exception Alias = Target`: queries canonicalise alias_path to target_path.
CREATE TABLE IF NOT EXISTS exn_rebinds (
    alias_path TEXT NOT NULL PRIMARY KEY,
    target_path TEXT NOT NULL
);
-- exn_edges: per-call-site value-channel classification (propagates / a bind's
-- bound-or-continuation argument / sink / transform / convert —
-- specs/error-channels.md Clarifications: "Schema"). Additive, unused as of
-- schema 1.3: the producer emits every fact through exn_origins/exn_scopes/
-- call_exn_scopes on the 'exception' channel only (FR-029's byte-identical
-- requirement); value channels (result/option/...) start writing rows here in
-- a later slice.
--
-- RESERVED VOCABULARY (review round 1): of the six roles the CHECK admits,
-- only 'propagates' is ever written (arch_index.ml's single insert_exn_edge
-- call site) and only 'propagates' is ever read (arch_exn.ml's role filter).
-- 'bind_arg', 'sink', 'transform_add', 'transform_replace' and 'convert' have
-- NO consumer: a row carrying one is stored and then ignored by every query.
-- A transform's added identity is an exn_origins row on the target channel; a
-- 'replace' transform and a sink are expressed as the ABSENCE of a
-- propagating edge; a converter is a from-channel exn_scopes row plus a
-- to-channel exn_origins row. See docs/error-channels-porting.md §1. The list
-- is left wide rather than narrowed to ('propagates') so a later slice can
-- give one of them a consumer without a schema version bump; do not read it
-- as a menu for a new producer.
CREATE TABLE IF NOT EXISTS exn_edges (
    call_id INTEGER NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
    channel TEXT NOT NULL,
    role TEXT NOT NULL CHECK(role IN ('propagates','bind_arg','sink','transform_add','transform_replace','convert')),
    PRIMARY KEY (call_id, channel, role)
);
-- channel_carriers: which (function, channel) pairs the producer determined
-- to be a c-carrier by the specs/error-channels.md Clarifications rule (its
-- return type, after stripping leading arrows, matches the channel's carrier
-- type). A node absent here for channel c answers NOT_A_CARRIER(c) at query
-- time even when it has zero origins/edges on c (an always-Ok carrier is
-- still BOUNDED: {}, not NOT_A_CARRIER — the two are not the same fact).
-- Written starting with the value-channel spine slice (slice 2); additive
-- under schema 1.3, no separate migration file.
CREATE TABLE IF NOT EXISTS channel_carriers (
    function_id INTEGER NOT NULL REFERENCES functions(id) ON DELETE CASCADE,
    channel TEXT NOT NULL,
    PRIMARY KEY (function_id, channel)
);
CREATE INDEX IF NOT EXISTS idx_exn_scopes_fn ON exn_scopes(function_id);
CREATE INDEX IF NOT EXISTS idx_exn_origins_fn ON exn_origins(function_id);
CREATE INDEX IF NOT EXISTS idx_exn_scope_catches_scope ON exn_scope_catches(scope_id);
CREATE INDEX IF NOT EXISTS idx_exn_edges_channel ON exn_edges(channel);
CREATE INDEX IF NOT EXISTS idx_channel_carriers_channel ON channel_carriers(channel);

-- Test coverage tracking
CREATE TABLE IF NOT EXISTS coverage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    function_id INTEGER NOT NULL REFERENCES functions(id) ON DELETE CASCADE,
    covered_lines INTEGER NOT NULL DEFAULT 0,
    total_lines INTEGER NOT NULL DEFAULT 0,
    percentage REAL GENERATED ALWAYS AS (
        CASE WHEN total_lines > 0 THEN (covered_lines * 100.0 / total_lines) ELSE 0 END
    ) STORED,
    recorded_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(function_id, recorded_at)
);

CREATE INDEX IF NOT EXISTS idx_coverage_low ON coverage(percentage) WHERE percentage < 50;

-- Gardening tasks (links to GitHub issues)
CREATE TABLE IF NOT EXISTS gardening_tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    github_issue INTEGER UNIQUE,            -- GitHub issue number
    category TEXT NOT NULL,                 -- 'split-file', 'type-safety', 'coverage', etc.
    title TEXT,
    target_module_id INTEGER REFERENCES modules(id) ON DELETE SET NULL,
    target_function_id INTEGER REFERENCES functions(id) ON DELETE SET NULL,
    status TEXT DEFAULT 'open',             -- 'open', 'in_progress', 'done'
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    completed_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_tasks_status ON gardening_tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_category ON gardening_tasks(category);

-- Gardening log (history of completed work)
CREATE TABLE IF NOT EXISTS gardening_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    contributor TEXT,
    category TEXT NOT NULL,
    description TEXT NOT NULL,
    pr_number INTEGER,
    issue_number INTEGER,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Types (record, variant, abstract, alias)
CREATE TABLE IF NOT EXISTS types (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    module_id INTEGER NOT NULL REFERENCES modules(id) ON DELETE CASCADE,
    name TEXT NOT NULL,                     -- 'node_request'
    kind TEXT NOT NULL,                     -- 'record', 'variant', 'abstract', 'alias', 'open'
    line_start INTEGER,
    line_end INTEGER,
    exposed BOOLEAN DEFAULT 0,              -- appears in .mli
    manifest TEXT,                          -- for aliases: the type it aliases
    intent TEXT,                            -- human-written purpose description
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(module_id, name)
);

CREATE INDEX IF NOT EXISTS idx_types_module ON types(module_id);
CREATE INDEX IF NOT EXISTS idx_types_kind ON types(kind);
CREATE INDEX IF NOT EXISTS idx_types_exposed ON types(exposed);

-- Record fields
CREATE TABLE IF NOT EXISTS type_fields (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type_id INTEGER NOT NULL REFERENCES types(id) ON DELETE CASCADE,
    field_name TEXT NOT NULL,               -- 'instance'
    field_type TEXT NOT NULL,               -- 'string'
    position INTEGER NOT NULL DEFAULT 0,    -- order within the record
    UNIQUE(type_id, field_name)
);

CREATE INDEX IF NOT EXISTS idx_type_fields_type ON type_fields(type_id);
CREATE INDEX IF NOT EXISTS idx_type_fields_name ON type_fields(field_name);
CREATE INDEX IF NOT EXISTS idx_type_fields_ftype ON type_fields(field_type);

-- Variant constructors
CREATE TABLE IF NOT EXISTS type_constructors (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type_id INTEGER NOT NULL REFERENCES types(id) ON DELETE CASCADE,
    constructor_name TEXT NOT NULL,          -- 'Genesis'
    position INTEGER NOT NULL DEFAULT 0,    -- order within the variant
    arg_types TEXT,                         -- comma-separated: 'string, int' or NULL for constant
    UNIQUE(type_id, constructor_name)
);

CREATE INDEX IF NOT EXISTS idx_type_constructors_type ON type_constructors(type_id);
CREATE INDEX IF NOT EXISTS idx_type_constructors_name ON type_constructors(constructor_name);

-- =============================================================================
-- Useful Views
-- =============================================================================

-- Large files needing attention
CREATE VIEW IF NOT EXISTS v_large_files AS
SELECT path, lines, intent, has_mli
FROM modules
WHERE lines > 500
ORDER BY lines DESC;

-- Large functions needing attention
CREATE VIEW IF NOT EXISTS v_large_functions AS
SELECT m.path, f.name, f.line_count, f.intent, f.exposed
FROM functions f
JOIN modules m ON f.module_id = m.id
WHERE f.line_count > 50
ORDER BY f.line_count DESC;

-- Functions without documentation
CREATE VIEW IF NOT EXISTS v_undocumented AS
SELECT m.path, f.name, f.signature, f.exposed
FROM functions f
JOIN modules m ON f.module_id = m.id
WHERE f.intent IS NULL AND f.exposed = 1
ORDER BY m.path, f.name;

-- Unsafe parameters to fix
CREATE VIEW IF NOT EXISTS v_unsafe_params AS
SELECT m.path, f.name, u.param_name, u.current_type, u.target_type, u.github_issue
FROM unsafe_params u
JOIN functions f ON u.function_id = f.id
JOIN modules m ON f.module_id = m.id
WHERE u.fixed = 0
ORDER BY m.path, f.name;

-- Low coverage functions
CREATE VIEW IF NOT EXISTS v_low_coverage AS
SELECT m.path, f.name, c.percentage, c.covered_lines, c.total_lines
FROM coverage c
JOIN functions f ON c.function_id = f.id
JOIN modules m ON f.module_id = m.id
WHERE c.percentage < 50
ORDER BY c.percentage ASC;

-- Most called functions (potential refactoring targets)
CREATE VIEW IF NOT EXISTS v_most_called AS
SELECT m.path, f.name, COUNT(c.id) as caller_count
FROM functions f
JOIN modules m ON f.module_id = m.id
LEFT JOIN calls c ON f.id = c.callee_id
GROUP BY f.id
HAVING caller_count > 5
ORDER BY caller_count DESC;

-- Functions that call a given function (callers)
CREATE VIEW IF NOT EXISTS v_callers AS
SELECT
    c.callee_name,
    cf.name as caller_name,
    cm.path as caller_path,
    c.call_site
FROM calls c
JOIN functions cf ON c.caller_id = cf.id
JOIN modules cm ON cf.module_id = cm.id
ORDER BY c.callee_name, cm.path;

-- Functions called by a given function (callees)
CREATE VIEW IF NOT EXISTS v_callees AS
SELECT
    cf.name as caller_name,
    cm.path as caller_path,
    c.callee_name,
    COALESCE(tm.path, 'external') as callee_path,
    c.call_site
FROM calls c
JOIN functions cf ON c.caller_id = cf.id
JOIN modules cm ON cf.module_id = cm.id
LEFT JOIN functions tf ON c.callee_id = tf.id
LEFT JOIN modules tm ON tf.module_id = tm.id
ORDER BY cm.path, cf.name;

-- Open gardening tasks by category. Not `status = 'open'`: a task moved to 'in_progress' is
-- neither 'open' nor yet 'done', and a NULL status (no NOT NULL constraint, only a DEFAULT)
-- reads as the documented default rather than vanishing — same fix as arch-query's `gardening
-- open` command, applied here too so the two readings of "open tasks" cannot diverge (#34).
CREATE VIEW IF NOT EXISTS v_open_tasks AS
SELECT category, COUNT(*) as count, GROUP_CONCAT(github_issue) as issues
FROM gardening_tasks
WHERE COALESCE(status, 'open') <> 'done'
GROUP BY category
ORDER BY count DESC;

-- Types by field: find types containing a specific field name
CREATE VIEW IF NOT EXISTS v_type_fields AS
SELECT m.path, t.name as type_name, t.kind, tf.field_name, tf.field_type
FROM type_fields tf
JOIN types t ON tf.type_id = t.id
JOIN modules m ON t.module_id = m.id
ORDER BY m.path, t.name, tf.position;

-- Types by field type: find all types that contain a field of a given type
CREATE VIEW IF NOT EXISTS v_types_with_field_type AS
SELECT m.path, t.name as type_name, tf.field_name, tf.field_type
FROM type_fields tf
JOIN types t ON tf.type_id = t.id
JOIN modules m ON t.module_id = m.id
ORDER BY tf.field_type, m.path, t.name;

-- Variant constructors overview
CREATE VIEW IF NOT EXISTS v_variant_constructors AS
SELECT m.path, t.name as type_name, tc.constructor_name, tc.arg_types
FROM type_constructors tc
JOIN types t ON tc.type_id = t.id
JOIN modules m ON t.module_id = m.id
ORDER BY m.path, t.name, tc.position;

-- Module dependencies overview
CREATE VIEW IF NOT EXISTS v_module_deps AS
SELECT
    sm.path as source_path,
    d.target_path,
    d.dep_kind,
    d.alias_name,
    d.line_number,
    CASE WHEN d.target_module IS NOT NULL THEN 'resolved' ELSE 'external' END as status
FROM module_deps d
JOIN modules sm ON d.source_module = sm.id
ORDER BY sm.path, d.line_number;

-- Modules with most dependencies (potential refactoring targets)
CREATE VIEW IF NOT EXISTS v_high_deps AS
SELECT m.path, COUNT(*) as dep_count
FROM modules m
JOIN module_deps d ON m.id = d.source_module
GROUP BY m.id
HAVING dep_count > 10
ORDER BY dep_count DESC;

-- Types used by a function (param and return types)
CREATE VIEW IF NOT EXISTS v_types_used_by AS
SELECT
    fm.path as function_path,
    f.name as function_name,
    tu.type_name,
    tu.usage_role,
    tu.position,
    CASE WHEN tu.type_id IS NOT NULL THEN 'resolved' ELSE 'external' END as status,
    COALESCE(tm.path, 'external') as type_module_path
FROM type_usage tu
JOIN functions f ON tu.function_id = f.id
JOIN modules fm ON f.module_id = fm.id
LEFT JOIN types t ON tu.type_id = t.id
LEFT JOIN modules tm ON t.module_id = tm.id
ORDER BY fm.path, f.name, tu.usage_role, tu.position;

-- Functions using a type (which functions accept/return a given type)
CREATE VIEW IF NOT EXISTS v_functions_using AS
SELECT
    tu.type_name,
    tu.usage_role,
    fm.path as function_path,
    f.name as function_name,
    f.signature,
    CASE WHEN tu.type_id IS NOT NULL THEN 'resolved' ELSE 'external' END as status
FROM type_usage tu
JOIN functions f ON tu.function_id = f.id
JOIN modules fm ON f.module_id = fm.id
ORDER BY tu.type_name, tu.usage_role, fm.path, f.name;

-- Types most commonly used as parameters (API surface analysis)
CREATE VIEW IF NOT EXISTS v_common_param_types AS
SELECT
    type_name,
    COUNT(*) as usage_count,
    COUNT(DISTINCT function_id) as function_count
FROM type_usage
WHERE usage_role = 'param'
GROUP BY type_name
HAVING usage_count > 3
ORDER BY usage_count DESC;

-- Types most commonly returned (output type analysis)
CREATE VIEW IF NOT EXISTS v_common_return_types AS
SELECT
    type_name,
    COUNT(*) as usage_count,
    COUNT(DISTINCT function_id) as function_count
FROM type_usage
WHERE usage_role = 'return'
GROUP BY type_name
HAVING usage_count > 3
ORDER BY usage_count DESC;

-- =============================================================================
-- Sample Queries (for reference)
-- =============================================================================

-- Find all functions that take a raw string 'instance' parameter:
-- SELECT * FROM v_unsafe_params WHERE param_name = 'instance';

-- Find functions called by many others (coupling hotspots):
-- SELECT * FROM v_most_called LIMIT 10;

-- Get gardening progress stats:
-- SELECT category,
--        SUM(CASE WHEN status = 'done' THEN 1 ELSE 0 END) as done,
--        SUM(CASE WHEN status = 'open' THEN 1 ELSE 0 END) as open
-- FROM gardening_tasks GROUP BY category;

-- Find modules without any function documentation:
-- SELECT m.path, COUNT(f.id) as func_count, SUM(CASE WHEN f.intent IS NULL THEN 1 ELSE 0 END) as undoc
-- FROM modules m
-- JOIN functions f ON f.module_id = m.id
-- GROUP BY m.id
-- HAVING undoc = func_count;

-- Find types that have both a string field and an int field:
-- SELECT DISTINCT t.name, m.path FROM types t
-- JOIN type_fields tf1 ON t.id = tf1.type_id AND tf1.field_type = 'string'
-- JOIN type_fields tf2 ON t.id = tf2.type_id AND tf2.field_type = 'int'
-- JOIN modules m ON t.module_id = m.id;

-- Find all types containing a field named 'instance':
-- SELECT * FROM v_type_fields WHERE field_name = 'instance';

-- Find all record types with a field of type 'connection_mode':
-- SELECT * FROM v_types_with_field_type WHERE field_type LIKE '%connection_mode%';

-- Find types that aggregate string, int, and some page type:
-- SELECT t.name, m.path, GROUP_CONCAT(tf.field_name || ':' || tf.field_type, ', ') as fields
-- FROM types t
-- JOIN modules m ON t.module_id = m.id
-- JOIN type_fields tf ON t.id = tf.type_id
-- WHERE t.id IN (SELECT type_id FROM type_fields WHERE field_type = 'string')
--   AND t.id IN (SELECT type_id FROM type_fields WHERE field_type = 'int')
--   AND t.id IN (SELECT type_id FROM type_fields WHERE field_type LIKE '%page%')
-- GROUP BY t.id;

-- Find all functions that accept a 'story' type as parameter:
-- SELECT * FROM v_functions_using WHERE type_name LIKE '%story%' AND usage_role = 'param';

-- Find all functions that return a Result type:
-- SELECT * FROM v_functions_using WHERE type_name LIKE '%result%' AND usage_role = 'return';

-- Find what types a specific function uses:
-- SELECT * FROM v_types_used_by WHERE function_name = 'my_function';

-- Find functions that use both 'story' and 'epic' types:
-- SELECT f.name, m.path FROM functions f
-- JOIN modules m ON f.module_id = m.id
-- WHERE f.id IN (SELECT function_id FROM type_usage WHERE type_name LIKE '%story%')
--   AND f.id IN (SELECT function_id FROM type_usage WHERE type_name LIKE '%epic%');
