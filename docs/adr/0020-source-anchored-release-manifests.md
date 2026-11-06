# 0020. Release identities freeze an existing source commit

- **Status:** Accepted
- **Date:** 2026-11-06; implementation decision for [#196](https://github.com/dadadave80/lattice/issues/196)
  and [#197](https://github.com/dadadave80/lattice/issues/197)

## Context

CREATE2 identities include compiler metadata and constructor arguments. The initial registry owner
changes its address and the factory's immutable registry changes its runtime codehash. Forge's
pre-broadcast simulation cannot establish an included transaction, public verification or chain
readiness. A committed manifest also cannot contain its own future Git commit hash.

## Options considered

1. **Freeze an existing source commit and observe chains separately.** Rebuild that commit's actual
   compiler inputs and inventories; a manifest-only successor may contain the resulting evidence.
2. **Rebuild historical releases from current source.** Rejected: comments, paths, metadata and build
   configuration intentionally evolve, so current bytecode cannot redefine a historical release.
3. **Publish one simulation-written deployment manifest.** Rejected: a simulation precedes broadcast
   finality and cannot prove deployment transactions or verification.
4. **Maintain a manual artifact catalog or add a schema runtime.** Rejected: the existing inventories,
   Forge, Bash, jq and cast already provide the required identities and checks.

## Decision

- Schema-v1 release identities are offline and chain independent. Local constructor execution
  supplies immutable-adjusted runtime hashes; explicit constructor arguments, CREATE2 salts,
  initcode hashes, selector commitments and the proxy initcode hash are included.
- `lattice.commit` names an existing source commit. Compiler-input witnesses contain standard-JSON
  language, sources and settings, with the actual compiler version. A manifest-only successor may
  contain the file; a release tag must preserve those build inputs. Sources and metadata freeze
  there. IPFS/CBOR metadata remains enabled.
- Goldens rebuild their own source commit under its pinned toolchain. They do not compare frozen
  releases against HEAD. Changing metadata, compiler settings or inventories creates new evidence.
- Chain status is a separate, block-pinned observation. Code presence is labelled `pre-existing`
  unless an actual transaction is supplied; it never implies source verification. Unknown
  verification remains false with a null verifier. Curation and `latest` are checked independently.
- Synthetic schema examples live under `test/fixtures`, outside consumer release paths. CI compares
  two clean current-checkout builds until actual source-anchored release goldens can be published.
- Fixture evidence is labelled `publication: fixture` with a `fixture/` tag. It is never public-chain
  support or canonical-owner evidence. Publishing a real release still requires a confirmed initial
  owner, frozen release identities and actual chain observations.

## Consequences

Historical rebuilds need Git history, initialized pinned submodules and the recorded toolchain.
Offline generation executes the complete inventory locally but needs no RPC or deployment funds.
An old release without these assets remains historical evidence with incomplete coverage; it is not
backfilled from unrelated current source. Public release manifests and ownership decisions remain
maintainer release prerequisites, not values a generator may invent.

## Confirmation

Forge identity/status tests and schema mutation fixtures check the format, constructors, CREATE2,
inventories and unknown-state rules. The manifest CI job runs on deployment-only changes and
compares two clean current builds and regenerates any published golden from its frozen source. The release asset job requires the matching
real manifest and attaches its compiler inputs alongside schemas and storage layouts.

## References

- [0014](0014-arachnid-shared-release-deployer.md), [0015](0015-canonical-cancun-build.md)
- [Release process](../../REGISTRY_DEPLOYMENTS.md), [manifest generator](../../script/release-manifest.sh)
- [#196](https://github.com/dadadave80/lattice/issues/196), [#197](https://github.com/dadadave80/lattice/issues/197)
