# 0007. `LatticeRegistry` is a standalone two-tier registry

- **Status:** Accepted. The comparison and current-toolchain evidence are tracked in
  [#176](https://github.com/dadadave80/lattice/issues/176). This selects the architecture; it is not an
  audit or a production-readiness assertion.
- **Date:** built for [#118](https://github.com/dadadave80/lattice/issues/118) (2026-07-08); hardening
  evidence from [#315](https://github.com/dadadave80/lattice/pull/315) (2026-10-09); recorded 2026-10-09;
  decision confirmed with Cancun cold/warm measurements on 2026-11-06

## Context

Every Lattice diamond can reuse one deployed copy of each facet instead of deploying its own. Something
on chain has to say which address holds the canonical code for a facet, which selectors to cut for it,
and that neither has changed. Everything that deploys through it trusts it, so its trust surface should
be as small as possible. #176 records that being non-upgradeable does not make the current design stable:
it may still change before the first major release, and the earlier "deploy-once" wording in #118 no
longer describes a stability promise.

## Options considered

1. **Two tiers (current).** A permissionless codehash index plus an owner-curated catalog.
2. **A curated catalog only.** Drops the permissionless index.
3. **Pinned release manifests and no on-chain catalog.** Deployers pass custom cuts; the chain verifies
   nothing.

The comparison also evaluates stored selector arrays/blobs, caller-supplied selector proofs, fixed
blueprint factories, recipe-committed addresses, per-call registries, proxies/clones and sorted-input
validation. The issue and its implementation PR hold the decision matrices; their underlying comparison
documents remain outside this repository.

## Decision

[`LatticeRegistry`](../../src/LatticeRegistry.sol) is a standalone, non-upgradeable contract: no
diamond, no ERC-7201 storage, no proxy.

- **Tier A, permissionless.** `attest(deployed)` records the first address seen with a runtime codehash
  and `resolve(codehash)` returns it. No admin.
- **Tier B, curated.** `register` and `setLatest` are owner-only under a two-step ownership transfer (a
  multisig from the first mainnet release). A `(nameHash, version)` record is immutable once written.
  `latest(nameHash)` is a movable convenience pointer; security-critical consumers pin an exact version.
  A curated facet must implement ERC-8153 `exportSelectors()`; registration pins its codehash and the
  hash of its selector blob, and `getCut` re-checks both on every read.
- **Selector source.** Retain bounded live exports, as selected by the maintainer on 2026-10-09. Code
  blobs avoid exporter availability risk but add registration and cold-read cost. Their small warm-read
  saving requires hundreds of reads to amortize setup in the measured workloads. Curated pure exporters
  do not justify adding data-contract deployment and changing the registry for that workload.
- **Factory.** Keep the standalone factory with its immutable registry, dynamic entries and custom cuts.
  Fixed blueprints remain appropriate for account products rather than every arbitrary recipe.
- **Address and reuse.** Keep sender/salt prediction, `deploy` for prechecked scripts and `deployStrict`
  for user interfaces. The event commits to the materialized recipe; the address does not. Strict calls
  reject occupied addresses and unpinned `latest` entries.
- **Validation.** Keep duplicate/loupe checks. The measured pairwise registration scan is acceptable for
  current exports; requiring sorted exports would change every export for a one-time saving. Generated
  recipes can put the loupe first without removing validation.

## Consequences

- A curated record cannot be repointed, so a pinned version always yields the same cut or a drift revert.
- Tier A identifies code, not behaviour. Two instances with one codehash can export different selectors
  when the exporter reads its own storage, and `resolve` returns the first attester (finding R-3 in the
  threat model). The `ILatticeRegistry` NatSpec lists the assumptions under which same-codehash
  addresses are equivalent and says `resolve` is not a selector source (#321).
- Registration reads exports through a `staticcall`, which cannot enforce `pure`, and a hostile exporter
  could make registration or reads expensive or malformed. Since #321 every exporter call gets at most
  100,000 gas and 8,192 bytes of return, and a malformed return is `NotERC8153` at `register` and
  `SelectorDrift` on a read.
- No production script resolves registry entries today: `BaseDeploy._assemble` passes custom cuts, and
  `DeployRelease` only writes the registry.
- A material change to these implementations requires fresh standalone deployments and updated consumer
  references. Non-upgradeability does not freeze the pre-major project design or make existing development
  addresses canonical. Upgradeable shared trust roots add an administrator and lifetime dispatch costs
  without a demonstrated need here.

## Confirmation

- `LatticeRegistryTest`, `LatticeRegistryFuzz`, `LatticeRegistryHostileExporterTest` and the registry
  invariant suite, mapped to each invariant in the
  [threat model](../security/registry-factory-threat-model.md).
- `LatticeCoreGasTest` measures cold/warm reads, fresh deployments with distinct salts and idempotent
  reuse. `LatticeCoreDesignBenchTest` compares complete read paths, registration resource bounds, duplicate
  validation and loupe ordering under the shared toolchain. No production optimization is introduced by
  the evidence update.

## References

- [`ILatticeRegistry.sol`](../../src/interfaces/ILatticeRegistry.sol) (the trust model as shipped)
- [Registry and factory threat model](../security/registry-factory-threat-model.md)
- [REGISTRY_DEPLOYMENTS.md](../../REGISTRY_DEPLOYMENTS.md)
- [#118](https://github.com/dadadave80/lattice/issues/118), [#176](https://github.com/dadadave80/lattice/issues/176),
  [#315](https://github.com/dadadave80/lattice/pull/315)
