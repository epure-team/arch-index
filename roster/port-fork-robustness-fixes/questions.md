# Research Questions

_Deliberate deviation from the skill template, which mandates
`# Research Questions — <task-slug>`: this slug names the intent the file exists to hide.
The researcher is blind by design; the title must not brief them._

_Generated: 2026-08-25_
_DO NOT include the task description in this file or share it with the researcher._

1. Where are the language-server-driven extraction entry points defined, and what does the abstract client type expose in its interface versus its implementation (constructors, request/response functions, shutdown)?

2. Which modules are re-exported in the library's public `.mli`/top-level interface, and which internal modules are reachable only from inside the library or from test targets?

3. How does the existing tezt-based test suite bootstrap fixtures for the compiler-artifact producer (fixture projects, temp dirs, guards on environment variables, tags), and what shared helpers exist for spawning subprocesses or building fixture projects?

4. Where in the extraction path are per-document errors from the server handled versus propagated, and what value does a run return when its overall timeout fires mid-extraction?

5. Where is the conversion from filesystem paths to URIs implemented, and how does a language identifier select the set of files scanned (extension tables, registry lookups, defaults for unknown languages)?

6. How are Eio timeouts, switches, and cancellation used in this producer, and are there existing patterns in the repo for injecting a clock or fake time in tests?

7. What does the configuration module expose (env-var-backed knobs, defaults, override points), and which parts of the extraction pipeline read from it?

8. [ecosystem] How do existing projects test LSP clients without a real language server — what in-process/mock server harnesses, transport abstractions, or recorded-session fixtures are commonly used, and how do LSP test suites simulate per-request errors and timeouts?
