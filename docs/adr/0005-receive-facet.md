# 0005. Bare-ETH acceptance is an opt-in facet under the zero selector

- **Status:** Accepted
- **Date:** the facet from [#155](https://github.com/dadadave80/lattice/pull/155) (2026-07-20); opt-in per
  recipe from [#295](https://github.com/dadadave80/lattice/pull/295) (2026-10-08); recorded 2026-10-09

## Context

diamond-lib v0.3.0 made its `Diamond` base abstract and dropped its `receive()`. Some diamonds must take
plain ETH sends (accounts, timelocks, an HTS treasury, a swap executor's native payouts); most never
should, and ETH sent to a diamond that cannot move it is lost. A diamond's fallback looks up `msg.sig`,
which reads as `0x00000000` for empty calldata.

## Options considered

1. **A `Receive` facet cut under `bytes4(0)`.** Only diamonds that cut it accept bare sends.
2. **`receive()` on the `Lattice` proxy.** Every diamond would accept bare ETH, including the ones that
   cannot spend it.
3. **A payable fallback that accepts anything unrouted.** It would also swallow calls to selectors that
   were never cut.

## Decision

- [`Lattice`](../../src/Lattice.sol) declares no `receive()`, so a diamond without the facet rejects bare
  ETH.
- [`Receive`](../../src/Receive.sol) is a stateless facet whose `receive()` accepts ETH and whose ERC-8153
  export is the single zero selector `0x00000000`. It has no init, no interface and no ERC-165
  registration, since `receive()` has no selector.
- A recipe cuts `Receive` only when its diamond must accept plain native sends. Forwarding `msg.value`
  through a payable function never needs it.

## Consequences

- Only empty calldata reaches `receive()`. Calldata of one to four zero bytes routes to the facet but
  matches no function and reverts.
- Routing costs a cold selector lookup and a `delegatecall` (about 4,700 gas), so Solidity's `.transfer()`
  and `.send()`, with their 2,300-gas stipend, cannot pay a Lattice diamond. Senders use
  `call{value: ...}("")`.
- `Receive` is the one facet whose export differs from its `forge inspect` method identifiers, and the
  parity test carries that exception.
- The `Lattice` NatSpec still says every recipe cuts `Receive`. That has been false since #295; the fix
  waits for a change that may move the `LatticeFactory` address, whose initcode embeds `Lattice`
  ([0004](0004-release-deployer-and-salts.md)).

## Confirmation

- `ReceiveTest`: `test_BareSendAcceptedWithReceiveFacet`, `test_BareSendRejectedWithoutReceiveFacet`,
  `test_ExplicitZeroSelectorCalldataRejected`, `test_ShortNonEmptyCalldataRejected`.
- `ExportSelectorsParityTest` requires the export to be exactly `0x00000000`.

## References

- [`Receive.sol`](../../src/Receive.sol), [`Lattice.sol`](../../src/Lattice.sol)
- [Compose your own diamond](../guides/compose-your-own-diamond.md)
- [#155](https://github.com/dadadave80/lattice/pull/155), [#295](https://github.com/dadadave80/lattice/pull/295)
