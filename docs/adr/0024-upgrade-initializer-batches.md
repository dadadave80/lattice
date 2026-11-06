# 0024. Upgrade batches open one reinitializer window

- **Status:** Accepted
- **Date:** 2026-11-06; implementation decision for [#207](https://github.com/dadadave80/lattice/issues/207)

## Context

Released module inits require `InitializableLib.checkInitializing`. A live diamond has already closed
its version-1 window, so a later authorized cut needs an explicit, replay-protected window for those
steps. Tools also need the current version before building the cut.

## Decision

Release `ReinitMultiInit` with one `reinitMulti(uint64,address[],bytes[])` entrypoint. The existing
`reinitializer(version)` modifier enforces a strictly increasing uint64 and rejects nested windows.
Each step uses `DiamondLib.initializeDiamondCut` for code validation and revert-data bubbling.
Length mismatch fails atomically; the existing MultiInit zero-target terminator and empty-batch
behavior are retained. Successful empty/terminated batches still advance the version.

The helper is delegatecalled only through the diamond's existing authorized cut. It is not a facet,
does not grant roles and adds no storage namespace. Direct calls affect its own irrelevant storage.
An unsuccessful step rolls back all earlier steps, the cut and the version; uint64 maximum is terminal.

Publish the existing initialization slot and bit layout as a stable tooling read, documented in
[the storage registry](../../STORAGE_REGISTRY.md#initialization-version-read). Add no view facet or
selector to existing diamonds.

## Alternatives and consequences

Inheriting MultiInit exposes an additional unwrapped public entrypoint. Calling another shared
MultiInit at runtime adds an address/code dependency; copying its delegatecall implementation
duplicates validation. A small ordered loop over the existing DiamondLib primitive avoids both.
Empty-revert failures therefore use that primitive's `InitializeDiamondCutReverted` error.

A new view facet would require an upgrade solely to read state already available through standard
RPC. The fixed-slot read works for existing Lattice deployments and uses full-width integer decoding.
The comparison and executable validation remain in [#207](https://github.com/dadadave80/lattice/issues/207)
and its implementation PR. No gas optimization is claimed.
