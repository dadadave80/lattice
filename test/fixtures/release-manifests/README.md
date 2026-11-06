# Synthetic manifest schema fixtures

These five representatives are selected from locally generated identities: registry, factory, one
facet, one initializer and the external library. They exercise schema and cross-file validation,
not an independently maintained release inventory. Current complete inventory/artifact parity is
checked by `ReleaseManifestTest` and two clean builds in CI.

`publication: fixture`, version 99.0.0, the `fixture/` tag, test owner 0x…bEEF, zero source commit/input
hash and synthetic block hash deliberately identify test data. The chain fixture's absent-code
statuses are synthetic; no chain was observed. These files are not a release, archived build proof,
canonical owner decision or public-chain support claim, and never live in consumer deployment paths.
