# Test layout & conventions

Structured per the **Testing** and **Deployment** sections of the Cyfrin Solidity Development Standards.

## Directory layout

| Path | Contents |
| --- | --- |
| `test/Base.t.sol` | Shared base test — `setUp` composes the system through the **same deploy code production uses** (`script/base/accounts/DeployAccount`). New system-level tests extend this instead of re-assembling facet cuts. |
| `test/unit/` | Per-facet / per-library unit tests. |
| `test/integration/` | Multi-facet / cross-module flows. |
| `test/invariant/` | Stateful (invariant) fuzz tests for core protocol properties. |
| `test/fuzz/` | Stateless fuzz tests. |
| `test/fork/` | Mainnet/testnet fork tests (RPC-gated; skip without an RPC). |
| `test/gas/` | Gas snapshots. |
| `test/composability/` | Diamond composability guard (extensions never re-export base selectors; real-diamond cut proofs). |
| `test/helpers/` | Test mixins — the blueprint helpers delegate to `script/base/` so setup never diverges from the deploy path. |
| `test/fixtures/` | ZK proving-system fixtures (groth16 / plonk / semaphore / …). |

## Naming

- One convention: `SubjectTest.t.sol` containing `contract SubjectTest`.
- Fuzz/invariant/fork/gas suffix their type where it aids discovery (`*Fuzz`, `*Invariant`, `*Fork`, `*Gas`).

## Testing approach (in priority order)

1. **Stateless fuzz** over hardcoded inputs for input-space coverage.
2. **Invariant (stateful) fuzz** for O(1) properties that must always hold (`test/invariant/`).
3. **Branching-tree technique (BTT)** for exhaustive, named coverage of revert paths and state-dependent
   branches. A `.tree` file lives **next to** the `.t.sol` it documents, named `<Subject><Function>.tree`.
   Each leaf maps to a named test; a `given` is a state-setup modifier, a `when` is a parameter branch, an
   `it should` is the asserted outcome. Exemplar: [`unit/TimelockControllerState.tree`](unit/TimelockControllerState.tree).

## Deployment / shared setup

Production deploy logic lives in `script/`:

- `script/base/` — canonical facet-set compositions, the single source of truth reused by both production
  deploys and test setup (mirrors diamond-lib's `DeployDiamond`/`DeployedDiamondState` split). `BaseDeploy.s.sol`
  is the shared primitive (`_cut`/`_cutExcept`/`_assemble`/`_assembleMulti`); the `Deploy*` recipes are
  organized into per-domain subfolders **mirroring `src/`** — `script/base/{access,accounts,amm,crosschain,defi,ens,governance,oracles,privacy,security,tokens,utils}/`.
  A recipe is a collection of facets (modified or as-is) composed to work together; e.g.
  `script/base/defi/DeployGovernedVault.s.sol` cuts `VaultCore` + `ERC20Votes` + `Governor` +
  `TimelockController` + a thin reconciliation facet.
- `script/config/` — one-action post-deploy configuration scripts (e.g. `EnableAurora`, `EnableRelay`).
- `script/deploy/`, `script/governance/`, `script/lib/`, `script/upgrades/` (storage-layout guard).

Tests must build the system through this shared code (via `Base.t.sol` or the blueprint helpers), never a
divergent test-only assembly.
