# 0003. ERC-165 registration writes a precomputed map slot

- **Status:** Accepted
- **Date:** in the first module (2026-04-25); written down as the `registerInterface` standard on
  2026-07-06; recorded 2026-10-09

## Context

A diamond answers `supportsInterface` from diamond-lib's ERC-165 storage: a
`mapping(bytes4 => bool)` in the ERC-7201 namespace `diamond.lib.storage.ERC165`, whose root is
`0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200`. Each module's init registers the
module's interfaceId in that mapping. Every init of every diamond pays for the registration, and a wrong
location is silent: the flag lands somewhere `supportsInterface` never reads.

## Options considered

1. **A precomputed file-level constant per interface and one `sstore`.**
2. **Compute `keccak256(abi.encode(interfaceId, root))` at run time.** Correct by construction, but it
   hashes on every registration.
3. **Write `supportedInterfaces[id] = true` through diamond-lib's `ERC165Storage` struct.** Readable, but
   Solidity hashes the mapping key at run time, as in option 2. diamond-lib's own `ERC165Lib` registers
   `IERC165` with a precomputed slot, as option 1 does.

## Decision

- A library declares `ERC165_MAP_<INTERFACE-NAME-UPPERCASED>_SLOT`, the value of
  `keccak256(abi.encode(bytes4(<id>), <root>))`, with the interfaceId and the full derivation in its
  `@dev` comment.
- `registerInterface()` is one `sstore(<constant>, true)` in assembly. Several interfaces mean
  `registerInterfaces()` with one `sstore` per constant.
- No runtime `keccak`, no bare hex literal inside the `sstore`, and no local copy of the ERC-165 root.
- A module with an error-only interface (interfaceId `0x00000000`) registers nothing.
- An adapter that implements a shared interface declares the same constant in its own file.

## Consequences

- Registration costs one storage write and no hashing.
- The constant is only as good as its derivation, so each one needs a test that recomputes it.
- An interface change changes its id and therefore its map slot, which makes the change visible in the
  slot test ([0008](0008-freeze-once-live.md)).
- Many older libraries still declare a local copy of the root. The standard forbids new ones; the
  [add-a-module checklist](../../CONTRIBUTING.md#adding-a-module) names `CCTPBridgeAdapterLib` as the
  model to copy.

## Confirmation

- `StorageSlotVerificationTest` recomputes every map-slot constant (`test_Erc165MapI<Module>Slot`) and
  asserts they are unique (`test_AllErc165MapSlotsAreUnique`).
- Each module's ERC-165 test (usually `test_SupportsInterface`) asks the diamond, whose read path
  recomputes the hash at run time, so a wrong constant fails it.

## References

- [AGENTS.md: `registerInterface` standard](../../AGENTS.md#registerinterface-standard-always)
- [STORAGE_REGISTRY.md](../../STORAGE_REGISTRY.md)
- [`CCTPBridgeAdapterLib.sol`](../../src/crosschain/circle/CCTPBridgeAdapterLib.sol)
