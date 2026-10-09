# 0008. A live module's namespace and interfaceId are frozen

- **Status:** Accepted
- **Date:** stated as the 0.x versioning policy in [#273](https://github.com/dadadave80/lattice/pull/273)
  and in AGENTS.md by [#274](https://github.com/dadadave80/lattice/pull/274) (both 2026-10-08); recorded
  2026-10-09

## Context

Lattice is pre-1.0 and may break its ABI and storage layouts when that improves correctness, which
fresh deployments absorb. A diamond already running a module cannot absorb it: a reordered or retyped
field silently corrupts its state, and a changed interfaceId breaks every integrator that checks
`supportsInterface`. Modules are live in places Lattice does not control, such as downstream projects
that pin a Lattice tag or submodule, so "released by Lattice" is too narrow a test.

## Options considered

1. **Freeze once live anywhere.** Live means a release deployment, a Lattice demo, or a known downstream
   deployment, on any network.
2. **Freeze at 1.0.** Leaves running testnet and downstream diamonds exposed to breaking upgrades until
   then.
3. **Freeze at release tag.** Ignores demos and downstream deployments of untagged code, and freezes
   modules nobody has deployed.

## Decision

Once a module is live on any network:

- its ERC-7201 namespace is frozen, and its storage struct may only grow by appending fields at the end;
- its interfaceId is frozen, so its selector set stays as it is;
- a new selector goes in a separate interface with its own ERC-165 registration and map slot
  ([0003](0003-precomputed-erc165-slots.md));
- new state goes in a new namespace or in fields appended to the struct.

Before a module is live, its layout and interface may change freely for a fresh deployment: mark the
change `!` with a `BREAKING CHANGE:` footer, say that a fresh deployment is required, and regenerate the
storage baseline. A patch release never changes a storage layout, a selector set or interfaceId, or the
`LatticeRegistry`/`LatticeFactory` bytecode.

## Consequences

- A fix to a live module can grow its surface but never reshape it. `IStrategyManagerRecovery` exists so
  that `IStrategyManager` keeps `0xcce4011b`, and `IVaultCoreRecovery` so that `IVaultCore` keeps
  `0xa86d8962`; the vault-side latch lives in a new namespace, `lattice.storage.VaultCoreRecovery`, and
  the strategy manager's latch is a field appended to `StrategyManagerStorage`.
- A diamond keeps the facets it was cut with. A fix reaches it only through a `diamondCut`, so any new
  state must start valid from the zero value its existing storage holds.
- Deciding whether a module is live needs knowledge of downstream deployments, which no check has.

## Confirmation

- `make storage-check` compares every annotated struct with the committed baseline. With
  `--baseline-ref` (CI passes the pull request's base) it also requires each struct to be an append-only
  extension of the layout at that commit. A reviewed fresh-deployment exception must be listed in
  `script/upgrades/storage-layout.resets`.
- No check freezes interfaceIds. An id change does change the interface's ERC-165 map slot, so
  `StorageSlotVerificationTest` and the module's ERC-165 test fail until the constant is re-pinned, which
  puts the change in front of a reviewer.

## References

- [README: versioning and compatibility](../../README.md#versioning-and-compatibility)
- [AGENTS.md: development stage](../../AGENTS.md#development-stage-and-design-decisions) and
  [Solidity architecture and storage](../../AGENTS.md#solidity-architecture-and-storage)
- [Storage-safety Action](../../.github/actions/storage-layout/README.md)
- [`IStrategyManagerRecovery.sol`](../../src/interfaces/defi/IStrategyManagerRecovery.sol),
  [`IVaultCoreRecovery.sol`](../../src/interfaces/defi/IVaultCoreRecovery.sol)
