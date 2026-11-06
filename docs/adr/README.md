# Architecture decision records

These records explain why Lattice is built the way it is. Each one states a decision, the options it
was weighed against, what follows from it, and the check that enforces it. The full comparison stays in
the linked issue or pull request; a record is the outcome, not a spec.

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](0001-three-file-pattern.md) | Modules are an interface, a library and a stateless facet | Accepted |
| [0002](0002-erc7201-namespaced-storage.md) | ERC-7201 storage at hard-coded `lattice.storage.<Module>` slots | Accepted |
| [0003](0003-precomputed-erc165-slots.md) | ERC-165 registration writes a precomputed map slot | Accepted |
| [0004](0004-release-deployer-and-salts.md) | Releases use raw-salt CREATE2: versioned facet salts, versionless registry and factory salts | Accepted for salts; deployer superseded by [0014](0014-arachnid-shared-release-deployer.md) |
| [0005](0005-receive-facet.md) | Bare-ETH acceptance is an opt-in facet under the zero selector | Accepted |
| [0006](0006-atomic-factory-initialization.md) | Diamonds are created and initialized atomically through `LatticeFactory` | Accepted |
| [0007](0007-registry-trust-model.md) | `LatticeRegistry` is a standalone two-tier registry | Accepted |
| [0008](0008-freeze-once-live.md) | A live module's namespace and interfaceId are frozen | Accepted |
| [0009](0009-token-extension-hook-model.md) | Token extensions replace base selectors; base libraries run no hooks | Accepted |
| [0010](0010-groth16-bn254.md) | Zero-knowledge modules standardize on Groth16 over BN254 | Accepted |
| [0011](0011-no-stateless-utility-duplicates.md) | No new copies of stateless Solady or OpenZeppelin utilities | Accepted |
| [0012](0012-storage-checker-bash-jq.md) | The storage-layout checker stays in Bash and jq | Accepted |
| [0013](0013-colocated-timelock-enforces-governor-grace.md) | A timelock in the Governor's diamond enforces the proposal grace period | Accepted |
| [0014](0014-arachnid-shared-release-deployer.md) | Shared releases use only the Arachnid deterministic-deployment proxy | Accepted |
| [0015](0015-canonical-cancun-build.md) | Canonical releases target Cancun with one pinned build configuration | Accepted |
| [0016](0016-shared-initialization-identity.md) | Shared bootstrap identity is consistent and interface claims follow routed selectors | Accepted |
| [0017](0017-hss-generation-recovery.md) | HSS job recovery invalidates generations before native deletion | Accepted locally; native sender unverified |
| [0018](0018-compiler-composition-metadata.md) | Composition facts live in raw compiler NatSpec metadata with native artifact lint | Accepted |
| [0019](0019-shared-temporary-allowances.md) | ERC-7674 allowances share the base allowance path | Accepted |
| [0020](0020-source-anchored-release-manifests.md) | Release identities freeze an existing source commit; chain observations stay separate | Accepted |
| [0021](0021-erc3643-closed-immutable-profile.md) | ERC-3643 admits one closed immutable composition | Accepted |
| [0022](0022-native-create2-release-libraries.md) | Shared external libraries use native CREATE2 linking and trusted runtime checks | Accepted |
| [0023](0023-frozen-input-source-verification.md) | Source verification submits the frozen compiler witness and requires exact bytecode matches | Accepted |
| [0024](0024-upgrade-initializer-batches.md) | Upgrade initializer batches share one replay-protected window and a stable version read | Accepted |
| [0025](0025-account-factory-release-identity.md) | Account recipes use specialized atomic factories with EntryPoint-specific release identities | Accepted |
| [0026](0026-checked-recipe-data-and-seams.md) | Recipes share checked cut plans and export descriptive composition data | Accepted |
| [0027](0027-governor-governed-cut-topology.md) | Governor validates the declared governed-cut executor topology | Accepted |
| [0028](0028-zetachain-message-recovery-options.md) | ZetaChain messages accept bounded recovery options without callbacks | Accepted |

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
