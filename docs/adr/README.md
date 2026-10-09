# Architecture decision records

These records explain why Lattice is built the way it is. Each one states a decision, the options it
was weighed against, what follows from it, and the check that enforces it. The full comparison stays in
the linked issue or pull request; a record is the outcome, not a spec.

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](0001-three-file-pattern.md) | Modules are an interface, a library and a stateless facet | Accepted |
| [0002](0002-erc7201-namespaced-storage.md) | ERC-7201 storage at hard-coded `lattice.storage.<Module>` slots | Accepted |
| [0003](0003-precomputed-erc165-slots.md) | ERC-165 registration writes a precomputed map slot | Accepted |
| [0004](0004-release-deployer-and-salts.md) | Releases use raw-salt CREATE2: versioned facet salts, versionless registry and factory salts | Accepted; deployer under review in [#193](https://github.com/dadadave80/lattice/issues/193) |
| [0005](0005-receive-facet.md) | Bare-ETH acceptance is an opt-in facet under the zero selector | Accepted |
| [0006](0006-atomic-factory-initialization.md) | Diamonds are created and initialized atomically through `LatticeFactory` | Accepted |
| [0007](0007-registry-trust-model.md) | `LatticeRegistry` is a standalone two-tier registry | Proposed until [#176](https://github.com/dadadave80/lattice/issues/176) settles |
| [0008](0008-freeze-once-live.md) | A live module's namespace and interfaceId are frozen | Accepted |
| [0009](0009-token-extension-hook-model.md) | Token extensions replace base selectors; base libraries run no hooks | Accepted |
| [0010](0010-groth16-bn254.md) | Zero-knowledge modules standardize on Groth16 over BN254 | Accepted |
| [0011](0011-no-stateless-utility-duplicates.md) | No new copies of stateless Solady or OpenZeppelin utilities | Accepted |
| [0012](0012-storage-checker-bash-jq.md) | The storage-layout checker stays in Bash and jq | Accepted |
| [0013](0013-colocated-timelock-enforces-governor-grace.md) | A timelock in the Governor's diamond enforces the proposal grace period | Accepted |

## When to write one

Write an ADR when a change settles a material architecture decision, the kind
[AGENTS.md](../../AGENTS.md#development-stage-and-design-decisions) asks to compare with credible
alternatives. Record the outcome here and keep the comparison itself in the issue or pull request.

A record is never rewritten to reverse its decision. A new ADR replaces it, and the old record's status
becomes `Superseded by NNNN`. Corrections that keep the decision, such as a fixed link or a status that
follows a linked issue, are edited in place.

## Template

Copy this into `NNNN-short-title.md`, using the next free number, then add the record to the table above
and to the `Design decisions` sidebar group in [`docs/site/vocs.config.ts`](../site/vocs.config.ts).

```markdown
# NNNN. Decision as a short sentence

- **Status:** Proposed | Accepted | Superseded by NNNN
- **Date:** when it was decided (and the PR or issue that decided it); when it was recorded

## Context

The problem and the constraints, with links to the code.

## Options considered

1. **The chosen option.** One line.
2. **An alternative.** One line on why it lost.

## Decision

What Lattice does, stated so a reviewer can check a change against it.

## Consequences

What follows, good and bad, including what it costs and what it rules out.

## Confirmation

The test, gate or review step that enforces the decision, or "none" with the reason.

## References

Issues, pull requests and files.
```
