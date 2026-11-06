# 0025. Account recipes use specialized factories with constructor-bound release identities

- **Status:** Accepted
- **Date:** 2026-11-06; implementation comparison for [#209](https://github.com/dadadave80/lattice/issues/209)

## Context

The two account recipes assembled plain Lattice through LatticeFactory. Their facets initialized,
but plain Lattice has neither AccountDiamond's ERC-7579 handler dispatch nor ModularAccount6900's
ERC-6900 execution-module dispatch. The existing specialized account factories already create the
correct proxy and initialize it atomically. Their fixed blueprint and initializer are constructor
arguments; each initializer fixes its trusted EntryPoint in immutable code.

## Options considered

1. **Use the existing specialized factories and release their constructor-bound identities.** Chosen:
   preserves atomic initialization, fallback semantics and the existing owner/salt counterfactual address formula.
2. **Deploy a specialized proxy directly from each script.** Separate broadcast deployment and
   initialization expose an initialization window; adding another atomic helper duplicates the factories.
3. **Teach LatticeFactory every proxy kind.** Changes standalone core bytecode and expands its trust
   surface without a demonstrated advantage over the existing account factories.
4. **One mutable factory for every EntryPoint and blueprint.** Adds configuration authority and complicates
   which state a counterfactual address commits to. The current constructor-fixed model is sufficient.

## Decision

- Both account recipes call their matching specialized factory's `createAccount`. Reusing owner and
  salt intentionally returns the existing account, following the factory's existing idempotent semantics.
- `AccountReleaseInventory` is the script-only source for both canonical facet-name blueprints and
  EntryPoint instance names. The release, recipes and manifest generator use that definition.
- Release each proxy kind against the repository's pinned v0.7/v0.8/v0.9 EntryPoints, with v0.9 the
  default. Each pair has an initializer whose constructor encodes the EntryPoint and a factory whose
  constructor encodes the complete ordered released cuts plus that initializer address.
- Use Arachnid with `keccak256("lattice.<identity-name>.<version>")` salts. Initcode hashes bind all
  constructor arguments. Initializers receive Tier-A attestations, without curated facet registrations.
  Factories remain manifest-only, following LatticeFactory: runtime codehash does not commit to their
  stored blueprint, so a permissionless resolver result cannot identify the canonical factory instance.
- Keep constructor-bound account initializers outside stateless InitInventory. Custom EntryPoints
  remain an explicit noncanonical profile. Local execution without Arachnid may CREATE the supporting
  contracts, while still creating accounts through the correct specialized factory.
- Include every pair as ordinary `contracts[]` entries with full artifact, constructor arguments,
  initcode/runtime hashes, address and salt. Supplementary `accounts[]` bindings record EntryPoint,
  proxy kind/hash and blueprint hash. Frozen source regeneration remains the complete identity check.

## Consequences

There are twelve additional canonical shared contract identities. Factory construction stores each
blueprint, adding release transactions and storage cost; the deployed factory execution path is unchanged.
The initializer's runtime depends on EntryPoint, and the factory's runtime depends on its immutable
initializer and proxy hash. Identical init runtime at another version may resolve to the first Tier-A
attester; consumers pin the versioned manifest address for identity. Correcting AccountFactory's source
documentation also rotates its compiler metadata/hash and derived addresses, without changing its
executable logic. No Registry, LatticeFactory, interface or persistent layout change is required.

Existing plain-Lattice accounts retain their original fallback behavior; changing a deployment script
does not upgrade them. A pinned EntryPoint is not proof of compatible code, bundler availability or native
EIP-7702 support on a target chain. Module and EntryPoint trust assumptions still apply.

## Confirmation

Tests call the real script run entrypoints, install a 7579 fallback handler through validated execution,
and exercise 6900 external-module dispatch. Release tests cover all pairs' constructor immutables,
predictions, routing, initializer attestation, nonowner completion, resumability and local/custom profiles.
A regression constructs usable eight/nine-facet factories with identical runtime hashes and distinct
blueprints, then proves permissionless attestation of the alternate factory cannot change release selection. Manifest
tests compare trusted proxy artifacts and exact constructors; native fixtures reject missing/dangling
bindings and valid-ABI constructor conflicts. Filtered release simulation, source reproducibility and
local Anvil atomic-deployment checks exercise the real tooling path.

## References

- [Issue #209](https://github.com/dadadave80/lattice/issues/209)
- [Account release inventory](../../script/lib/AccountReleaseInventory.sol)
- [Account factories](../../src/accounts/erc7579/AccountFactory.sol), [6900 factory](../../src/accounts/erc6900/AccountFactory6900.sol)
- [Release and account deployment reference](../../REGISTRY_DEPLOYMENTS.md#account-releases)
- [Atomic initialization](0006-atomic-factory-initialization.md), [Arachnid policy](0014-arachnid-shared-release-deployer.md)
