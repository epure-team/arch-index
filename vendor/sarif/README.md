# SARIF 2.1.0 JSON Schema (vendored)

`sarif-schema-2.1.0.json` is fetched verbatim from the OASIS SARIF specification repository:

    https://raw.githubusercontent.com/oasis-tcs/sarif-spec/main/sarif-2.1/schema/sarif-schema-2.1.0.json

Fetched 2026-09-05 (112 768 bytes). It declares itself
`"$schema": "http://json-schema.org/draft-04/schema#"` — the schema is JSON Schema **draft-04**,
which is the load-bearing constraint on `tezt/tests/sarif_out.ml`'s validator choice (see that
file's header comment).

Vendored rather than fetched at test time: a test that needs the network is a test that fails for
the wrong reason.

## Provenance and license

This file is not released under an OSI open-source license; it is a specification artifact of the
OASIS SARIF Technical Committee, governed by OASIS's own IPR framework rather than a project
LICENSE file. Per the sarif-spec repository's own
[LICENSE.md](https://github.com/oasis-tcs/sarif-spec/blob/master/LICENSE.md): content in that
repository is produced under the OASIS TC Process and OASIS IPR Policy, with the SARIF TC
operating in **RF on RAND Terms Mode** (royalty-free on reasonable-and-non-discriminatory terms)
for TC-member contributions, and the **OASIS Feedback License** for non-member contributions. The
repository states its content is "intended to be part of the SARIF TC's permanent record of
activity, visible and freely available for all to use, subject to applicable OASIS policies" —
which is the basis for vendoring this schema alongside a tool that emits SARIF against it, rather
than a claim of public-domain or MIT-equivalent rights. Consult the linked LICENSE.md and OASIS's
own IPR Policy/TC Process/Bylaws for the authoritative terms; this note is a citation, not a
substitute for them.

Do not hand-edit this file. To refresh it, re-fetch the URL above and update the date and byte
count here.
