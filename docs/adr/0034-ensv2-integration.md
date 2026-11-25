# 0034. Separate ENSv2 resolution and issuance facets

- **Status** Proposed for acceptance with this change
- **Date** 2026-11-25

## Context

Existing Lattice callers resolve a 32-byte namehash through the ENSv1 registry and issue subnames with NameWrapper fuses. ENSv2 walks DNS labels through a hierarchy of registries. Registry roles, token IDs and resolver authorization have distinct meanings from the v1 parameters.

## Decision

Ship independent optional v2 facets, each with its own ERC-165 interface and storage namespace. Use the canonical resolver proxy for synchronous ETH reads. Resolve the canonical parent registry before issuing a child as the diamond. A new local issuer role and a separate upstream registrar grant express the two authorities. Primary-name writes continue through the ENS-supported reverse registrar.

## Alternatives and consequences

Rotating the old registry address cannot recover missing DNS labels or translate fuse rights. Client-only resolution supports gateway lookups and is appropriate for off-chain consumers, while contracts still need a synchronous path. A generic callback bridge or a custom registry adds verification and administration work beyond these two operations. Using discovery followed by canonical resolution incurs two hierarchy traversals and avoids a second DNS parser in Lattice. The v2 modules add deployment cost only to compositions that install them.

## Confirmation

Run the v2 units and fork suites, recipe/selector parity, storage checks and the existing-diamond upgrade tests. The operator guide covers the separate, owner-authorized migration procedure. [ENSv2 operator guide](../guides/ensv2.md)
