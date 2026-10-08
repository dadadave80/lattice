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
| `test/gas/` | Gas snapshots, committed under `snapshots/`. Record snapshots only here. CI fails when a run changes them; regenerate with `make snapshot`. |
| `test/composability/` | Diamond composability guard (extensions never re-export base selectors; real-diamond cut proofs). |
| `test/helpers/` | Test mixins — the blueprint helpers delegate to `script/base/` so setup never diverges from the deploy path. |
| `test/fixtures/` | ZK proving-system fixtures (groth16 / plonk / semaphore / …). |

## Naming

- One convention: `SubjectTest.t.sol` containing `contract SubjectTest`.
- Fuzz/invariant/fork/gas suffix their type where it aids discovery (`*Fuzz`, `*Invariant`, `*Fork`, `*Gas`).

## Testing approach (in priority order)

1. **Stateless fuzz** over hardcoded inputs for input-space coverage.
2. **Invariant (stateful) fuzz** for O(1) properties that must always hold (`test/invariant/`).
   `fail_on_revert = true`, so a reverting handler call fails the run: bound handler inputs to valid calls,
   skip actions the target would reject, and assert expected reverts with `vm.expectRevert`. Each suite also
   sets the inline `/// forge-config: default.invariant.fail-on-revert = true` key on its invariants (for
   invariants inherited from an abstract base, the global `[invariant] fail_on_revert = true` is what binds).
   Diamond-level suites drive recipe-built diamonds through a handler and check them against ghost state:
   `VaultDiamondInvariant` (the `DeployVaultCore` and `DeployGovernedVault` diamonds with a
   `DeployStrategyManager` diamond and live strategies) and `AccessManagerDiamondInvariant` (a
   `DeployAccessManager` diamond governing a `DeployAccessManaged` diamond, against a ghost model of Lattice's
   AccessManager semantics: OpenZeppelin v5.6.1 with the differences listed in `IAccessManager`'s `@dev`, such as
   the locked ADMIN_ROLE, the global nonce, a too-early `when` raised instead of refused, and Lattice error
   shapes), and `ERC721EnumerableInvariant` (a `DeployERC721Enumerable` diamond against a ghost set of live
   ids). They run 64 runs under `FOUNDRY_PROFILE=ci` (a contract-level
   `/// forge-config: ci.invariant.runs = 64` key, since a function-level key does not reach invariants
   inherited from a base) and the full 256 locally. `make invariant-deep` runs every invariant suite at 1,000
   runs and depth 200 (`[profile.deep.invariant]`); it is not a CI gate.
3. **Branching-tree technique (BTT)** for exhaustive, named coverage of revert paths and state-dependent
   branches. A `.tree` file lives **next to** the `.t.sol` it documents, named `<Subject><Function>.tree`.
   Each leaf maps to a named test; a `given` is a state-setup modifier, a `when` is a parameter branch, an
   `it should` is the asserted outcome. Exemplar: [`unit/TimelockControllerState.tree`](unit/TimelockControllerState.tree).

## Deployment / shared setup

Production deploy logic lives in `script/`:

- `script/base/` — canonical facet-set compositions, the single source of truth reused by both production
  deploys and test setup (mirrors diamond-lib's `DeployDiamond`/`DeployedDiamondState` split). `BaseDeploy.s.sol`
  is the shared primitive (`_cut`/`_cutExcept`/`_assemble`/`_assembleMulti`; `_assemble*` create and initialize
  each proxy in one transaction through `LatticeFactory`); the `Deploy*` recipes are
  organized into per-domain subfolders **mirroring `src/`** — `script/base/{access,accounts,amm,crosschain,defi,ens,governance,oracles,privacy,security,tokens,utils}/`.
  A recipe is a collection of facets (modified or as-is) composed to work together; e.g.
  `script/base/defi/DeployGovernedVault.s.sol` cuts `VaultCore` + `ERC20Votes` + `Governor` +
  `TimelockController` + a thin reconciliation facet.
- `script/config/` — one-action post-deploy configuration scripts (e.g. `EnableAurora`, `EnableRelay`), the
  demo-driver shell loops, the `keychain-auth.sh` keystore helper and the `hedera/` tooling.
- `script/deploy/`, `script/governance/`, `script/lib/`, `script/upgrades/` (storage-layout guard).

[`script/README.md`](../script/README.md) maps every `script/` folder to its entry points and Makefile targets.

Tests must build the system through this shared code (via `Base.t.sol` or the blueprint helpers), never a
divergent test-only assembly.

## Mutation testing (local pilot)

`make mutation` runs a [Gambit](https://github.com/Certora/gambit) mutation pilot (#245) on three
libraries: `ERC4626Lib`, `StrategyManagerLib` and `AccessManagerLib`. It is a local check only. It is not
in `make ci` or any workflow, and Gambit is not a repo dependency, so install it yourself
(`cargo install --git https://github.com/Certora/gambit`).

How it works (`script/mutation-test.sh`, config in `test/mutation/gambit.conf.json`):

1. Gambit writes every mutant of the three files to `gambit_out/` (gitignored), compiling each one with the
   pinned solc (`SOLC=` overrides). Paths in the config are relative to the config's own directory. The
   mutants are reused while the config, the sources and solc are unchanged.
2. Each library gets its own scratch copy of the repo (outside the tree, deleted on exit), so `src/` in
   your checkout is never modified. Forge runs inside the copy, so the `forge inspect` FFI in
   `test/helpers/GetSelectors.sol` reads the copy's build.
3. A baseline run of the library's test set must pass first. Then each mutant is copied over the source
   and the test set runs with `--fail-fast` under `FOUNDRY_PROFILE=ci`, fork suites excluded, with a fixed
   fuzz seed. A failing test kills the mutant. A mutant that passes every test survives. A mutant that does
   not compile is stillborn and is left out of the score. The test sets are the unit, fuzz, integration
   and invariant suites that reach each library through a recipe diamond (`match_set()` in the script).
4. The score per file and the survivor list go to `gambit_out/run/report.md`, and each mutant's forge log
   to `gambit_out/run/logs/<id>.log`.

`MUTANTS="12 45"` re-runs only those ids into `gambit_out/rerun/`, which is how you check that new tests
kill the survivors. `TARGETS=AccessManagerLib` limits the run to one library, and `KEEP=1` keeps the scratch
copies. A full run takes about an hour on a 12-core laptop. Recompiling the dependents of the mutated
library takes most of the roughly 35 seconds each `ERC4626Lib` or `StrategyManagerLib` mutant costs.

Gambit mutates Solidity expressions, not Yul. The `assembly` blocks (the 512-bit half of `mulDiv`, the
storage getters, `registerInterface`'s `sstore`) are not mutated, so the scores say nothing about them.
`MulDivDifferentialFuzz` covers `mulDiv`.

### Pilot results (2026-10-08)

All mutants were run, with no sampling and no functions excluded. No mutant was stillborn. The "after"
column re-runs only the first run's survivors against the new tests. Adding tests cannot revive a killed
mutant, so after = first-run kills + newly killed.

| File | Mutants | Killed before | Score before | Killed after | Score after | Equivalent | Score excluding equivalents |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `AccessManagerLib` | 287 | 230 | 80.1% | 271 | 94.4% | 16 | 100% |
| `ERC4626Lib` | 253 | 240 | 94.9% | 248 | 98.0% | 5 | 100% |
| `StrategyManagerLib` | 245 | 217 | 88.6% | 243 | 99.2% | 2 | 100% |

The tests that kill the real gaps are in `test/unit/AccessManagerTest.t.sol`, `test/unit/ERC4626Test.t.sol`
and `test/unit/StrategyManagerTest.t.sol`, under a "#245: mutation pilot regressions" heading. Each runs
against the module's recipe diamond.

Equivalent mutants (ids from the run above; `gambit_out/mutants.log` maps an id to its edit):

| Id | Location | Mutant | Why no test can kill it |
| ---: | --- | --- | --- |
| 1 | `ERC4626Lib` `__ERC4626_init` | drop `checkInitializing` | Every init that calls it (`ERC4626Init`, `VaultCoreInit`, `GovernedVaultInit`, `GovernedVaultENSInit`) calls `__ERC20_init` first, which runs the same guard. |
| 25 | `ERC4626Lib` `maxWithdraw` | `!ok` → `false` | With an unreadable NAV, `_tryNav` returns `nav = 0`. The value of a balance is then `shares * 1 / (supply + 10**offset)`, which floors to 0. |
| 90, 94 | `ERC4626Lib` `_nav`, `_tryNav` | `data.length < 32` → `32 < data.length` | They differ only when a successful `totalAssets()` returns other than exactly 32 bytes. Neither shipped `totalAssets()` facet (`ERC4626`, `VaultCore`) does that. |
| 93 | `ERC4626Lib` `_tryNav` | failure check → `false` | `ok` is still the call's own result, and every caller drops `nav` when `ok` is false. The mutant differs only when a failed read carries under 32 bytes of revert data: it then reverts instead of returning `(false, 0)`. On a plain vault `totalAssets()` cannot fail, and `VaultCore` fails with `VaultCoreStrategyNavUnavailable(address)`, which is 36 bytes. |
| 254 | `StrategyManagerLib` `__StrategyManager_init` | drop `checkInitializing` | Its only caller, `StrategyManagerInit`, calls `__AccessControl_init` first, which runs the same guard. |
| 324 | `StrategyManagerLib` `_removeStrategy` | `arrIdx != lastIdx` → `true` | Removing the last element then swaps it with itself, and its index entry is deleted straight after. |
| 524 | `AccessManagerLib` `canCall` | `roleId == PUBLIC_ROLE` → `false` | `hasRole(PUBLIC_ROLE, …)` returns `(true, 0)`, which leads to the same `(true, 0)`. |
| 565–568 | `AccessManagerLib` `setGrantDelay` | drop or alter the zeroing of `pendingGrantDelay` / `grantDelayEffectAt` | Both fields are overwritten a few lines later in the same call. |
| 606–609 | `AccessManagerLib` `setTargetAdminDelay` | the same for `pendingAdminDelay` / `adminDelayEffectAt` | The same reason. |
| 729 | `AccessManagerLib` `_canCallExtended` | `data.length < 4` → `false` | With under 4 bytes of calldata, `execute` and `schedule` both revert on the same `data[0:4]` slice either way. |
| 764, 765 | `AccessManagerLib` `_writeSchedule` | drop or alter the clearing of an expired `readyAt` | The slot is overwritten with the new `readyAt` a few lines later. |

Two observations from the triage:

- `AccessManagerLib` never wrote `Delay.pendingValue` or `Delay.effectAt`, so re-granting a member with a
  lower execution delay took effect at once, and the run counted 687 and 688 (the pending-delay branch of
  `_effectiveDelay`) as equivalent. #287 ports OpenZeppelin's `withUpdate(newDelay, 0)`: a decrease now
  waits out the difference, and the "#287" tests in `test/unit/AccessManagerTest.t.sol` kill both mutants
  (see below). #287 also dropped `_grantRoleInternal`'s `emitEvent` flag, so the equivalent mutants 696 and
  710 (`emitEvent` → `true`) no longer exist. That leaves 12 of the run's 16 `AccessManagerLib` equivalents.
- `execute` and `schedule` with under 4 bytes of calldata to a target other than the manager revert with a
  calldata-slice error, not `AccessManagerUnauthorizedAccount`.

Mutant ids are positions in `gambit_out/mutants.log`, so they move whenever a target file changes, and
`MUTANTS=` ids are only valid against the mutants generated from the current sources. Find a mutant again by
its line and edit. The #287 check:

| Source | Pending-branch mutants (never / reversed comparison) | Result |
| --- | --- | --- |
| dev before #287 (ERC4626Lib already shrunk by the `mulDiv` consolidation) | 558, 559 | both survive |
| #287 | 535, 536 | both killed |

On the #287 source, all 76 mutants in the changed functions (`getAccess`, `setGrantDelay`,
`setTargetAdminDelay`, `_effectiveDelay`, `_updateEffectAt`, `_grantRoleInternal`) were run. 68 are killed.
The 8 survivors are the setter-zeroing equivalents listed above.

The pilot stays out of CI, as decided for #245. The kill rates above are the input for revisiting that.
