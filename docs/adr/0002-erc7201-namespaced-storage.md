# 0002. ERC-7201 storage at hard-coded `lattice.storage.<Module>` slots

- **Status:** Accepted
- **Date:** hard-coded ERC-7201 slots since the first module (2026-04-25); the `lattice.storage.` prefix in
  use from 2026-05-29, with the remaining `openzeppelin.storage.` namespaces renamed by 2026-06-14;
  recorded 2026-10-09

## Context

Every module cut into a diamond writes to the diamond's one storage space. Modules are written
independently and combined by integrators, so each needs a location no other module can reach, that
tools can find, and that costs as little as possible to address on every call.

## Options considered

1. **ERC-7201 namespaces with the slot precomputed as a constant.** The slot is a literal; solc's
   `@custom:storage-location` annotation names the namespace for tooling.
2. **The same namespaces, slot computed at run time** (`keccak256` of the namespace in every accessor).
   Same layout, but every storage access pays for the hash.
3. **EIP-2535 AppStorage**, one struct at slot 0 shared by all facets. Modules written apart would have to
   agree on one layout.

## Decision

- Each module owns one namespace, `lattice.storage.<Module>`, and one struct annotated
  `/// @custom:storage-location erc7201:lattice.storage.<Module>`.
- The library declares the slot as a file-level constant, `<MODULE>_STORAGE_SLOT`, with the derivation
  `keccak256(abi.encode(uint256(keccak256("lattice.storage.<Module>")) - 1)) & ~bytes32(uint256(0xff))` in
  its `@dev` comment. `cast index-erc7201 lattice.storage.<Module>` prints the value.
- The library reaches the struct through one accessor that assigns the constant with `$.slot := ...` in
  assembly. No accessor computes its slot at run time.
- New state for a live module goes in a new namespace or at the end of the struct
  ([0008](0008-freeze-once-live.md)).

## Consequences

- Addressing storage costs no hashing.
- A wrong constant would silently write to another location, so every constant needs an independent
  check (below).
- Solc emits no storage layout for a struct reached only through an assembly slot cast, so layout tooling
  needs a probe contract ([0012](0012-storage-checker-bash-jq.md)).
- All 96 namespaces in `src/` today use the `lattice.storage.` prefix and are distinct.

## Confirmation

- `StorageSlotVerificationTest` re-derives every slot constant from its namespace and asserts all slots
  are unique (`test_AllErc7201SlotsAreUnique`).
- `make storage-check` pairs each annotation with its struct and fails when the declaring file does not
  contain the namespace's derived slot as a literal.
- [STORAGE_REGISTRY.md](../../STORAGE_REGISTRY.md) lists every namespace and slot.

## References

- [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201)
- [`ERC20Lib.sol`](../../src/tokens/ERC20/libraries/ERC20Lib.sol) (an example of the constant, the struct
  and the accessor)
- [AGENTS.md: Solidity architecture and storage](../../AGENTS.md#solidity-architecture-and-storage)
