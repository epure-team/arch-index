# SARIF 2.1.0 JSON Schema (vendored)

`sarif-schema-2.1.0.json` is fetched verbatim from the OASIS SARIF specification repository:

    https://raw.githubusercontent.com/oasis-tcs/sarif-spec/main/sarif-2.1/schema/sarif-schema-2.1.0.json

Fetched 2026-09-05 (112 768 bytes). It declares itself
`"$schema": "http://json-schema.org/draft-04/schema#"` — the schema is JSON Schema **draft-04**,
which is the load-bearing constraint on `tezt/tests/sarif_out.ml`'s validator choice (see that
file's header comment).

Vendored rather than fetched at test time: a test that needs the network is a test that fails for
the wrong reason. The OASIS TC's SARIF specification artifacts (including this schema) are
published for unrestricted reuse; redistributing this file alongside the tool that emits SARIF
against it is exactly the intended use.

Do not hand-edit this file. To refresh it, re-fetch the URL above and update the date and byte
count here.
