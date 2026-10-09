# 0007. `LatticeRegistry` is a standalone two-tier registry

- **Status:** Proposed. The design is deployed in development and tested, but
  [#176](https://github.com/dadadave80/lattice/issues/176) (open) still compares it with alternatives
  before any canonical release relies on it. This record becomes Accepted, or is superseded, when #176
  settles.
- **Date:** built for [#118](https://github.com/dadadave80/lattice/issues/118) (2026-07-08); hardening
  evidence from [#315](https://github.com/dadadave80/lattice/pull/315) (2026-10-09); recorded 2026-10-09

## Context

Every Lattice diamond can reuse one deployed copy of each facet instead of deploying its own. Something
on chain has to say which address holds the canonical code for a facet, which selectors to cut for it,
and that neither has changed. Everything that deploys through it trusts it, so its trust surface should
be as small as possible. #176 records that being non-upgradeable does not make the current design stable:
it may still change before the first major release, and the earlier "deploy-once" wording in #118 no
longer describes a stability promise.

## Options considered

#176 asks for this comparison; it is not finished.

1. **Two tiers (current).** A permissionless codehash index plus an owner-curated catalog.
2. **A curated catalog only.** Drops the permissionless index.
3. **Pinned release manifests and no on-chain catalog.** Deployers pass custom cuts; the chain verifies
   nothing.

## Decision (proposed)

[`LatticeRegistry`](../../src/LatticeRegistry.sol) is a standalone, non-upgradeable contract: no
diamond, no ERC-7201 storage, no proxy.

- **Tier A, permissionless.** `attest(deployed)` records the first address seen with a runtime codehash
  and `resolve(codehash)` returns it. No admin.
- **Tier B, curated.** `register` and `setLatest` are owner-only under a two-step ownership transfer (a
  multisig from the first mainnet release). A `(nameHash, version)` record is immutable once written.
  `latest(nameHash)` is a movable convenience pointer; security-critical consumers pin an exact version.
  A curated facet must implement ERC-8153 `exportSelectors()`; registration pins its codehash and the
  hash of its selector blob, and `getCut` re-checks both on every read.

## Consequences

- A curated record cannot be repointed, so a pinned version always yields the same cut or a drift revert.
- Tier A identifies code, not behaviour. Two instances with one codehash can export different selectors
  when the exporter reads its own storage, and `resolve` returns the first attester (finding R-3 in the
  threat model). The `ILatticeRegistry` NatSpec still describes same-codehash addresses as equivalent and
  cites #118 for the trust model; correcting it changes the registry bytecode and address
  ([0004](0004-release-deployer-and-salts.md)), so it belongs to the #176 change.
- Registration reads exports through a `staticcall`, which cannot enforce `pure`, and a hostile exporter
  can make registration or reads expensive or malformed. #315 pins each case as a `test_Finding_*` test.
- No production script resolves registry entries today: `BaseDeploy._assemble` passes custom cuts, and
  `DeployRelease` only writes the registry.

## Confirmation

- `LatticeRegistryTest`, `LatticeRegistryFuzz`, `LatticeRegistryHostileExporterTest` and the registry
  invariant suite, mapped to each invariant in the
  [threat model](../security/registry-factory-threat-model.md).

## References

- [`ILatticeRegistry.sol`](../../src/interfaces/ILatticeRegistry.sol) (the trust model as shipped)
- [Registry and factory threat model](../security/registry-factory-threat-model.md)
- [REGISTRY_DEPLOYMENTS.md](../../REGISTRY_DEPLOYMENTS.md)
- [#118](https://github.com/dadadave80/lattice/issues/118), [#176](https://github.com/dadadave80/lattice/issues/176),
  [#315](https://github.com/dadadave80/lattice/pull/315)
