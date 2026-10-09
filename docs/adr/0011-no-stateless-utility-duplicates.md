# 0011. No new copies of stateless Solady or OpenZeppelin utilities

- **Status:** Accepted
- **Date:** a standing maintainer rule with no PR of its own; recorded 2026-10-09

## Context

Solady and OpenZeppelin Contracts publish audited, MIT-licensed stateless libraries (ECDSA, signature
checking, `Math`, `SafeCast`, `Strings`, `Base64`, `EnumerableSet`, `MerkleProof`, `LibClone`,
`SafeTransferLib` and so on) that any Foundry project can `forge install`. Lattice's value is diamond
modules: an interface, a library with ERC-7201 storage, and a stateless facet
([0001](0001-three-file-pattern.md)) that compose in one diamond. A pure helper gains nothing from that
pattern, and a re-implementation is unaudited code to maintain.

## Options considered

1. **Build modules only.** Point integrators to Solady or OpenZeppelin for stateless helpers.
2. **Ship a utility layer as well.** Duplicates audited code with no diamond-specific benefit and adds
   review surface.

## Decision

- Lattice does not add a stateless utility library (no storage, no facet, no init) whose audited
  equivalent exists in Solady or OpenZeppelin. It builds what needs the diamond pattern: modules with
  their own storage, facets, initializers, or integration with Lattice's access and init libraries.
- The ports already in `src/utils/libraries/` (ECDSA, Math, SafeCast, Strings, EnumerableSet,
  ShortStrings, SignatureChecker, Checkpoints, Base64 and others) predate this rule. They stay because
  modules use them, each credits its upstream, and they are not a precedent for new ones.
- Wrapping audited upstream code in a facet is not duplication. The generic ZK verifiers and the
  Semaphore module are the model ([0010](0010-groth16-bn254.md)).

## Consequences

- Lattice depends on neither Solady nor OpenZeppelin; its submodules are forge-std and diamond-lib. A
  module that needs a primitive Lattice does not have raises a dependency question, and a new dependency
  needs the maintainer's approval (AGENTS.md).
- Existing copies shrink rather than grow: [#296](https://github.com/dadadave80/lattice/pull/296) reduced
  three `mulDiv` copies to the one in `math/Math.sol`, with a differential fuzz suite confirming identical
  results.

## Confirmation

None automated. Reviewers apply the rule, and the
[attribution rule](../../AGENTS.md#external-source-attribution-always) makes every port name its upstream,
which shows when a new file duplicates one.

## References

- [README: utility libraries](../../README.md#modules)
- [#296](https://github.com/dadadave80/lattice/pull/296)
