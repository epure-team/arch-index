# Research — shared index provenance for change review

`Arch_report.collect` is the established one-pass reader for report provenance.
It obtains optional schema version from `comment_db_meta`, producer-run rows
when `producer_runs` exists, and analysis coverage rows when the corresponding
table exists.  Its JSON header retains nullable fields instead of fabricating
defaults; producer rows preserve invocation digests while the recurring API
consumer already excludes those from its compatibility identity.

`arch-impact` presently exposes only `db`, a local path.  A path cannot
identify a comparable corpus or producer configuration, and does not even
survive a normal CI checkout.  PR125 supplied the *diff input* half of a
refusal-safe scope; this intake supplies the index half through the shared
reader.  The explicit future scope manifest still supplies corpus and
configuration identity, because neither tool can infer them safely from an
SQLite path.

The smallest sound API is a versioned nested object created from an
`Arch_report.collect` result.  It avoids a second SQL interpretation in
`arch-impact`, and intentionally retains empty lists/nulls as observed absence,
not as a completeness claim.
