# 0018. Keep composition facts in compiler-emitted NatSpec

- **Status:** Accepted
- **Date:** 2026-11-06, decided and recorded for [#200](https://github.com/dadadave80/lattice/issues/200)

## Context

Facet dependencies, selector owners, initializer order and parameter units lived in prose and downstream
catalog overlays. Redundant `lattice-version` tags had drifted from the actual release version. Lattice
needs inspectable code facts without introducing a parser dependency or a runtime composition engine.

## Options considered

1. **Raw compiler metadata plus native Forge lint.** solc preserves contract and function custom tags;
   source and compiled artifacts remain the authority, with an explicit overlay for unmodified upstream code.
2. **Foundry's normalized metadata.** It retains method tags but drops contract custom tags, so cannot carry
   the facet catalog reliably.
3. **A source/AST parser or a separate complete JSON catalog.** A parser adds maintenance and dependency
   costs; a second full catalog repeats facts and can drift. Neither is needed for this metadata gate.
4. **Bump every source version tag each release.** This duplicates the manifest and rotates module codehashes
   for a semantic-version edit. Keep the release version in LatticeVersion and manifests instead.

## Decision

First-party release facets use contract NatSpec for requires/family/owns/touches/init/seam. Released
initializers declare contract kind and method-specific initializes/after/same-call/sequence/registration/
parameter facts. Multi-entrypoint initializers describe each method separately. The vocabulary and exact
record framing are in [CONTRIBUTING](../../CONTRIBUTING.md#composition-metadata).

Consumers decode `artifact.rawMetadata` as JSON, then read `output.devdoc` and `output.devdoc.methods`.
There is no `contracts` wrapper. solc joins repeated tags without adding separators; record tags therefore
end in semicolons. Empty sets explicitly say `none;`. A bare registration marker is present with an empty
string and must be the last tag in its comment block; otherwise solc consumes the next custom tag as its value. The compiler fixture pins all these observations under the shared solc toolchain.

Hard dependencies follow actual public routes or checked guards. Internal library calls and shared-state
reads do not imply that their public facets must be cut. Conventional management surfaces and configuration
ordering are labeled as such. Touches describes first-party writes reachable from exported facet entrypoints, including transitive
writes; initializer-only writes are represented by their own module/sequence records; the shared reentrancy lock and upstream Ownable slots have explicit non-ERC-7201 names.

The four diamond-lib core facets and MultiInit remain unmodified. A five-entry
[provenance overlay](../../script/lib/CoreCompositionMetadata.sol) records their actual behavior at the
pinned upstream commit. MultiInit's sequence is caller-defined, not a claimed fixed bundle. No future
first-party inventory entry is exempted. `lattice-version` source tags are removed; LatticeVersion and
release manifests remain the version authority.

## Consequences

The gate has no new runtime or parser dependency and adds no on-chain selector, storage field, gas path or
composition solver. Native syntax/reference checks catch drift cheaply; semantic completeness still needs
source review and existing composition tests. Declared write sets do not constrain arbitrary external
callbacks or delegatecalls, and family/seam records are not a complete proof of safe hook composition.

NatSpec changes rotate compiler metadata hashes, hence codehashes and CREATE2 addresses, even when executable
opcodes and bytecode lengths are identical. Removing Registry/Factory version tags and correcting the
Registry's obsolete CreateX claim also changes their development deployment identities. New release
manifests must be generated; old addresses are not advertised as the new bytecode. This is a feature release.

## Confirmation

[`CompositionMetadataTest`](../../test/unit/CompositionMetadataTest.t.sol) checks every inventory entry,
compiled tag retention/folding, mandatory fields, dangling references, exported ownership/seam signatures,
namespace names and parameter coverage/units. Missing and dangling mutation fixtures must be rejected.
Existing selector parity, storage, release-manifest and composition-hazard gates continue to apply.

## References

- [#200](https://github.com/dadadave80/lattice/issues/200)
- [ADR0009: token extension hooks](0009-token-extension-hook-model.md)
- [ADR0014: Arachnid deployment](0014-arachnid-shared-release-deployer.md)
- [ADR0016: shared initialization identity](0016-shared-initialization-identity.md)
