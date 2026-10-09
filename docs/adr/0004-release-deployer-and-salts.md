# 0004. Releases use raw-salt CREATE2: versioned facet salts, versionless registry and factory salts

- **Status:** Accepted for the salt scheme and the use of CREATE2. The choice of deployer is under review:
  [#193](https://github.com/dadadave80/lattice/issues/193) (open) proposes Arachnid's proxy on every chain
  instead of CreateX first.
- **Date:** salts and CreateX from [#120](https://github.com/dadadave80/lattice/issues/120) (2026-07-09);
  the Arachnid fallback from [#189](https://github.com/dadadave80/lattice/pull/189) (2026-10-07); recorded
  2026-10-09

## Context

A release deploys the [`LatticeRegistry`](../../src/LatticeRegistry.sol), the
[`LatticeFactory`](../../src/LatticeFactory.sol) and every facet in
[`FacetInventory`](../../script/lib/FacetInventory.sol). Integrators and Lattice Studio predict these
addresses offline, a half-finished release must be finishable by anyone, and nobody may be able to put
other code at a canonical address.

## Options considered

1. **Raw-salt CREATE2.** The address depends on the deployer contract, a fixed salt and the initcode hash,
   so it is the same on every chain with that deployer and commits to the bytecode.
2. **CREATE3 with a sender-guarded salt** (CreateX). The address survives bytecode changes, but only the
   pinned sender can deploy and the chain id is folded in, so addresses differ per chain. Lattice keeps it
   for the adapter deployments in `DeployAdapters`, not for releases.
3. **Plain CREATE from a release key.** Addresses depend on a nonce and a key.

## Decision

- Salts are raw protocol strings with no deployer and no chain id:
  - every facet: `keccak256("lattice.<Name>.<version>")`, for example `keccak256("lattice.ERC20.0.1.0")`
    (`DeployRelease.facetSalt`, and `BaseDeploy._facet` with `LatticeVersion.VERSION`);
  - registry: `keccak256("lattice.LatticeRegistry")`, versionless (`REGISTRY_SALT`);
  - factory: `keccak256("lattice.LatticeFactory")`, versionless (`FACTORY_SALT`).
- The deployer is CreateX's raw-salt CREATE2 (`0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed`), which hashes
  the salt once more before use. On a chain where CreateX has no code and Arachnid's proxy
  (`0x4e59b44847b379578588920cA78FbF26c0B4956C`) has, the release uses the proxy, which uses the salt as
  given. CreateX wins wherever both exist. `DeployRelease` refuses a chain with neither.
- Every deploy is predict-then-skip, so a release run is idempotent and resumable by anyone.

## Consequences

- Every release, patches included, publishes every facet at new addresses, because the version is in the
  salt. A diamond keeps the facets it was cut with until it is upgraded. A facet edit, NatSpec included,
  therefore moves no address that would not move anyway.
- The registry and factory addresses depend only on their initcode (plus the registry's `owner` argument
  and the factory's `registry` argument) and on the chain's deployer. Any change to their bytecode moves
  them, including a NatSpec edit, because `foundry.toml` keeps solc's default metadata hash. Changes to
  them, such as those [#176](https://github.com/dadadave80/lattice/issues/176) reviews, belong before the
  first canonical broadcast; after it, the versioning policy keeps patch releases from changing them.
- A chain on Arachnid's proxy gets different addresses from a CreateX chain for the same release.
  [#193](https://github.com/dadadave80/lattice/issues/193) would make the proxy the only release deployer,
  which keeps the salts and moves every address once.
- A release reproduces only from the pinned compiler configuration at its tag. The Hedera profile changes
  the metadata hash and therefore the address.

## Confirmation

- `DeployReleaseTest`: `test_SaltDerivationGoldens` pins the salts, `test_Release_IdempotentResume` and
  `test_Release_PartialResumeRegistersPredeployedFacet` the resume path,
  `test_Release_RunsOnAnArachnidOnlyChain` and `test_Release_RevertsWithoutAnyDeterministicDeployer` the
  deployer choice.

## References

- [REGISTRY_DEPLOYMENTS.md](../../REGISTRY_DEPLOYMENTS.md), the canonical reference, including
  [why CREATE2 here](../../REGISTRY_DEPLOYMENTS.md#why-create2-here-and-create3-for-the-adapters) and
  [what changes an address](../../REGISTRY_DEPLOYMENTS.md#what-changes-an-address)
- [`DeployRelease.s.sol`](../../script/deploy/DeployRelease.s.sol),
  [`CreateXDeployer.sol`](../../script/lib/CreateXDeployer.sol)
- [README: versioning and compatibility](../../README.md#versioning-and-compatibility)
- [#120](https://github.com/dadadave80/lattice/issues/120), [#189](https://github.com/dadadave80/lattice/pull/189),
  [#193](https://github.com/dadadave80/lattice/issues/193), [#176](https://github.com/dadadave80/lattice/issues/176)
