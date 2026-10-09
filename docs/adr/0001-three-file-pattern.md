# 0001. Modules are an interface, a library and a stateless facet

- **Status:** Accepted
- **Date:** in force since the first module, AccessControl ([#1](https://github.com/dadadave80/lattice/pull/1),
  2026-04-25); recorded 2026-10-09

## Context

An EIP-2535 diamond `delegatecall`s its facets, so a facet runs against the diamond's storage, never its
own. Lattice ships modules that integrators cut together in one diamond, and several pieces of code need
the same module logic: the module's own facet, combined facets that do two things on one path (for
example [`GovernedVault`](../../src/defi/GovernedVault.sol)), and the init contracts that seed state
during `initialize`.

## Options considered

1. **Interface, library, facet.** The ABI lives in the interface, all logic and storage access in an
   internal library, and the facet only forwards.
2. **Logic in the facet.** Another facet or an init could reach the logic only through an external call
   or by inheriting the whole facet.
3. **One shared AppStorage struct.** Every module would add fields to one struct, so independently
   written modules would share and reorder one layout.

## Decision

Every module with state or an ABI has three files:

- `src/interfaces/<area>/I<Module>.sol`: functions, custom errors and events.
- `src/<area>/libraries/<Module>Lib.sol`: all logic as `internal` functions, the module's ERC-7201
  storage ([0002](0002-erc7201-namespaced-storage.md)), `registerInterface()`
  ([0003](0003-precomputed-erc165-slots.md)) and `__<Module>_init`.
- `src/<area>/<Module>.sol`: a stateless facet of `virtual` one-line forwards to the library, plus the
  ERC-8153 `exportSelectors()` list of its cuttable selectors.

Pure helpers with no storage, facet or interface live in `src/utils/libraries/` and skip the split. A few
contracts are standalone where the standard or deployment model needs it (`LatticeRegistry`,
`LatticeFactory`, `AccountFactory`, the `*Standalone` variants).

## Consequences

- Internal library calls compile into the calling facet, so a combined facet or an init reuses a module's
  logic with no external call and no shared deployment.
- Facets hold no state, so one deployed facet serves every diamond, which is what the release
  ([0004](0004-release-deployer-and-salts.md)) and the registry ([0007](0007-registry-trust-model.md))
  rely on.
- A module is three files plus its registration in the release inventory, the slot test, the storage
  probe and the module catalog, which the
  [add-a-module checklist](../../CONTRIBUTING.md#adding-a-module) lists.
- Libraries are not `virtual`, so behaviour cannot be changed by overriding a hook. Extensions that must
  see every token movement replace selectors instead ([0009](0009-token-extension-hook-model.md)).

## Confirmation

- `ExportSelectorsParityTest` checks that every facet in
  [`FacetInventory`](../../script/lib/FacetInventory.sol) exports exactly its `forge inspect`
  method identifiers, without `exportSelectors()` itself.
- `make storage-check` guards every namespaced storage struct. No check proves a facet stateless; review
  does.
- `make readme-check` requires every `src/` contract in the README module catalog.

## References

- [README: three-layer facet pattern](../../README.md#architecture-three-layer-facet-pattern)
- [AGENTS.md: Solidity architecture and storage](../../AGENTS.md#solidity-architecture-and-storage)
- [#85](https://github.com/dadadave80/lattice/pull/85) (domain-mirrored interface folders)
