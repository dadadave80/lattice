# 0009. Token extensions replace base selectors; base libraries run no hooks

- **Status:** Accepted for 0.5.0 (decision D25, option (a), on
  [#234](https://github.com/dadadave80/lattice/issues/234))
- **Date:** [#311](https://github.com/dadadave80/lattice/pull/311) (2026-10-08); recorded 2026-10-09

## Context

OpenZeppelin composes token extensions through `virtual _update` overrides, so Pausable, Votes,
Enumerable and the rest all see every balance movement. Lattice libraries are internal and not
`virtual` ([0001](0001-three-file-pattern.md)), so an extension cannot hook the base library's
movement. It has to replace the standard's public movement selectors with its own versions. Two such
extensions on one diamond claim the same selectors, and a facet that moves balances through the base
library directly skips them both.

## Options considered

1. **(a) One movement-replacing extension per diamond.** Declare each standard's family mutually
   exclusive and pin that with tests. Cheapest; rules out pairs such as Enumerable with Votes.
2. **(b) A hook in each base library.** `_update` calls whichever extensions an init enabled, for example
   through a flag appended to the base namespace. Every path then runs the hooks, at the cost of an SLOAD
   per movement on every token and base libraries that import their extensions.
3. **(c) Combined facets for each pair.** Their number grows combinatorially.

## Decision

- `ERC20Lib._update`, `ERC721Lib._update` and `ERC1155Lib._update` move balances and emit the standard
  events (ERC-721 also checks authorization and clears the token approval); none of them runs an
  extension hook.
- An extension that must see or gate every transfer replaces all of its standard's movement selectors,
  and its recipe cuts it with `Replace` or excludes the base copies with `_cutExcept`.
- Any two extensions of one family are mutually exclusive, and every direct mover (a facet that calls the
  base library's `_mint`, `_burn` or `_update`) is mutually exclusive with every movement-replacing
  extension of its standard.
- A diamond that needs two behaviours on one path gets one combined facet that applies both, as
  `GovernedVault` does for ERC-20 balances and votes.
- Option (b) is revisited only with ERC-3643 ([#172](https://github.com/dadadave80/lattice/issues/172)).
  It would append to the released `ERC20Storage`.

## Consequences

- No token pays a per-movement hook read.
- `Add`ing a second family member reverts at the cut, but `Replace` silently routes the selectors to the
  later facet and drops the earlier facet's logic. A direct mover shares no selector with the family, so
  its cut succeeds with no signal. Both are integrator hazards the guide and NatSpec spell out.
- Every new movement-replacing extension (ERC-721 Consecutive next) must replace the full selector set,
  join its standard's family test, and pin its exclusions in `CompositionHazardsTest`.

## Confirmation

- `CompositionHazardsTest` pins the model, for example `test_MovementReplacingFamilyClaimsTheTransferPair`,
  `test_PausableAddedToVotesRevertsAtCut`, `test_PausableReplacingVotesDesyncsVotes`,
  `test_BurnableNextToVotesDesyncsVotes` and the ERC-721 and ERC-1155 equivalents.
- `SelectorCompatibilityTest` checks every selector that two release facets share against its hand
  classification; the movement selectors carry a D25 note in the generated
  [matrix](../guides/selector-compatibility.md#matrix).

## References

- [Token extension hook model](../guides/selector-compatibility.md#token-extension-hook-model), which
  has the per-standard tables of movement-replacing extensions, direct movers and exclusions
- [`ERC20Lib.sol`](../../src/tokens/ERC20/libraries/ERC20Lib.sol)
- [#234](https://github.com/dadadave80/lattice/issues/234), [#311](https://github.com/dadadave80/lattice/pull/311),
  [#172](https://github.com/dadadave80/lattice/issues/172)
