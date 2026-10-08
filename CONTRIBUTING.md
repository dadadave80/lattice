# Contributing to Lattice

Lattice is an open-source public good. Contributions are welcome: new modules, bug fixes, tests and
documentation.

This file is the human summary. [AGENTS.md](AGENTS.md) is the canonical project guide, and where the two
differ, AGENTS.md wins. [SECURITY.md](SECURITY.md) covers vulnerability reports: never file them as public
issues.

## Getting started

```sh
git clone https://github.com/dadadave80/lattice.git
cd lattice
make install   # git submodule update --init --recursive (diamond-lib, forge-std, ...)
make build
make test
```

`make help` lists every target. [test/README.md](test/README.md) explains the test layout, naming and the
recipe-built test setup.

## Branches, commits and pull requests

- **Base every PR on `dev`.** GitHub's default branch is `main`, which is the release branch. Only release
  promotions target it. See [AGENTS.md: Git workflow](AGENTS.md#git-workflow-and-authorization).
- **Branch names** are descriptive and conventional: `feat/...`, `fix/...`, `docs/...`, `test/...`,
  `ci/...`.
- **Commit subjects and the PR title use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).**
  Release Please builds the changelog from these types (see
  [release-please-config.json](release-please-config.json)): `feat`, `fix`, `perf`, `refactor` and `docs`
  are listed; `test`, `build`, `ci` and `chore` are hidden. A subject in any other form is left out of the
  changelog. Add a scope where it helps (`fix(crosschain): ...`).
- **Breaking changes** use `!` after the type or scope and a `BREAKING CHANGE:` footer saying what
  integrators must change: `fix(vaults)!: ...`. A changed interfaceId, ABI or storage layout counts.
- **Sign your commits.** The branch rulesets require signed commits, so an unverified commit cannot land.
- Keep each PR to one concern, and say in the description what changed, why, and how you validated it.
  The [PR template](.github/pull_request_template.md) has the sections and the steps most often missed.
- **Name each completed issue on its own `Closes #N` line in the PR body**, and use `Refs #N` for
  partial work.

## Architecture in brief

Modules follow a three-layer pattern. The full rules are in
[AGENTS.md: Solidity architecture and storage](AGENTS.md#solidity-architecture-and-storage).

1. **Interface** (`src/interfaces/<area>/I<Module>.sol`): ABI, errors and events.
2. **Library** (`src/<area>/libraries/<Module>Lib.sol`): all logic, storage through one ERC-7201 namespace,
   `registerInterface()` and `__<Module>_init`.
3. **Facet** (`src/<area>/<Module>.sol`): thin and stateless. It forwards to the library and exports its
   selectors (ERC-8153 `exportSelectors()`).

Storage policy, as AGENTS.md states it:

- State lives in the diamond, never in a facet. Every module gets a unique, precomputed ERC-7201 namespace
  and ERC-165 map slot, recorded in [STORAGE_REGISTRY.md](STORAGE_REGISTRY.md).
- An upgrade that keeps existing state needs a compatible layout (normally append-only) or a designed and
  tested migration. Reordering, removing or retyping a field must never silently corrupt a live instance.
- Before the first major release, a necessary layout change is allowed for a fresh deployment. Say that a
  fresh deployment is required, update the baseline and the consumers, and do not present the change as
  safe for an existing deployment.
- A namespace or interfaceId is frozen once it is live on any network, including a downstream project's
  deployment. From then on a layout change is append-only or a tested migration, as
  [AGENTS.md](AGENTS.md#solidity-architecture-and-storage) states.

`make storage-check` compares every `@custom:storage-location erc7201:` struct in `src/` against the
committed baseline. The struct list is derived from those annotations, so a new struct is checked
automatically. It must also be imported into
[script/upgrades/StorageLayoutProbe.sol](script/upgrades/StorageLayoutProbe.sol), or the check fails.
After an intended layout change, run `make storage-update` and review the baseline diff.

Two conventions have exact forms in AGENTS.md: the
[external-source attribution line](AGENTS.md#external-source-attribution-always) and the
[`registerInterface` standard](AGENTS.md#registerinterface-standard-always).

## Before you open a PR

Run `make ci`. It runs CI's Solidity gates, in CI's order:

| Target | Gate |
| --- | --- |
| `make fmt-check` | `forge fmt --check` |
| `make sizes` | EIP-170 size limit under `FOUNDRY_PROFILE=ci` |
| `make via-ir` | IR-pipeline build |
| `make storage-check` | ERC-7201 storage-layout baseline |
| `make test-ci` | full test suite under `FOUNDRY_PROFILE=ci` |
| `make snapshot-check` | gas snapshots in `snapshots/` match the committed files (`make snapshot` regenerates them) |

CI also runs checks that `make ci` leaves out:

- a size gate under via-ir (`make via-ir` only compiles);
- Slither (`make slither`), which fails on any High result that is not suppressed or triaged. Confirm a
  new one is a false positive first. Suppress a statement-level result with
  `// slither-disable-next-line <detector> <reason>` directly above the flagged line: a triaged id embeds
  that line's numbers, so it would resurface whenever the file shifts. Triage function-level results, and
  results in files that must stay byte-exact, with `make slither-triage`, then give each new
  `slither.db.json` entry a one-line `reason`;
- Anvil deploy checks: `make test-grant-runner`, `make example-ens-grant-m2 LOCAL=1` and
  `make check-atomic-deploy`. The last one fails if any file in `script/` calls `new Lattice` or a
  separate `initialize`. To run them, start `make anvil` in one shell, then run them in another.

Fork suites (`test/fork/`) need RPC URLs and skip their lanes cleanly without them. They pin historical
blocks, so use archive endpoints (see `.env.example`); the `Scheduled` workflow runs them weekly against
archive secrets. Say in the PR which lanes you ran. Behavior changes need regression tests through a real
diamond built from the module's recipe.

Optional, local only: `make mutation` runs the [Gambit](https://github.com/Certora/gambit) mutation pilot
on `ERC4626Lib`, `StrategyManagerLib` and `AccessManagerLib` and reports which mutants the tests miss. It
needs `gambit` on your `PATH`, is not part of `make ci` or any workflow, and takes about an hour on a
laptop. See [test/README.md](test/README.md#mutation-testing-local-pilot) for how it works and the pilot
results.

## Adding a module

Work through this list in order. The example is EmergencyStop (`security` area). Several of these steps
fail silently when missed, so do every one.

**Source**

- [ ] **Interface** `src/interfaces/<area>/I<Module>.sol`: functions, errors, events. Example:
      `src/interfaces/security/IEmergencyStop.sol`.
- [ ] **Library** `src/<area>/libraries/<Module>Lib.sol` with:
  - the storage-slot constant (`EMERGENCY_STOP_STORAGE_SLOT`) for namespace `lattice.storage.<Module>`.
    `cast index-erc7201 lattice.storage.<Module>` prints the value;
  - the struct with `/// @custom:storage-location erc7201:lattice.storage.<Module>` on the line directly
    above `struct <Module>Storage {`. The storage guard pairs the two lines;
  - `ERC165_MAP_I<MODULE>_SLOT` with its `@dev` derivation, `registerInterface()`, and
    `__<Module>_init()`, in the form the [`registerInterface` standard](AGENTS.md#registerinterface-standard-always)
    shows. Skip all three for a module with no storage to seed and an error-only interface
    (interfaceId `0x00000000`).

  Do not copy `EMERGENCY_STOP_ERC165_STORAGE_LOCATION` from the example: it is an unused local copy of
  the ERC-165 storage root, which the standard forbids. `CCTPBridgeAdapterLib` shows the correct form.

  A module with no state (for example `HederaPrngAdapter`) has no slot constant or struct. It skips the
  storage-slot test, the probe import and `make storage-update`, but still needs the ERC-165 map slot, its
  slot test and a registry row.
- [ ] **Facet** `src/<area>/<Module>.sol`: one-line forwards to the library, plus `exportSelectors()`
      returning the packed selectors from `forge inspect <Module> methodIdentifiers`, in that order, without
      `exportSelectors()` itself (`0x0ef22643`). Add `@custom:lattice-version` set to the release that
      first ships the facet, and `@custom:lattice-source` set to `Lattice original` or, for ported code,
      the upstream and its version (`OpenZeppelin v5.6.1`).
      [#200](https://github.com/dadadave80/lattice/issues/200) may replace the version tag.
- [ ] **NatSpec**: `@author` on each new file, plus the
      [attribution line](AGENTS.md#external-source-attribution-always) if the code is ported or adapted.
- [ ] **Init**: compose `__<Module>_init` in the recipe's local `<Module>RecipeInit` (EmergencyStop does).
      Add a standalone `src/<area>/<Module>Init.sol` only when other recipes need it (for example
      `ChainlinkAdapterInit`).

**Registration**

- [ ] **Release inventory** `script/lib/FacetInventory.sol`: add the name and the `"<file>:<Name>"` path
      at the same index, then raise the count everywhere it appears (`string[N]` twice, `new string[](N)`
      twice, the loop bound and the `@notice`). Update the count that `test/unit/DeployReleaseTest.t.sol`
      pins (`"inventory count drifted"`) to match. An entry here is what ships the facet and puts it under
      the parity gate. Prove it: `make test MATCH=ExportSelectorsParityTest` and
      `make test MATCH=DeployReleaseTest`.
- [ ] **Slot test** `test/unit/StorageSlotVerificationTest.t.sol`: import both constants, add
      `test_<Module>StorageSlot` and `test_Erc165MapI<Module>Slot`, append both constants to
      `_allStorageSlots()` and `_allErc165MapSlots()`, and raise those arrays' sizes. A failing assertion
      prints the expected value, which is also how to check a new map-slot constant. Prove it:
      `make test MATCH=StorageSlotVerificationTest`.
- [ ] **Storage guard** `script/upgrades/StorageLayoutProbe.sol`: import `<Module>Storage` and declare it as
      a state variable. Then `make storage-update`, check the baseline diff only adds your section, and
      `make storage-check`.
- [ ] **Registry** [STORAGE_REGISTRY.md](STORAGE_REGISTRY.md): add the module's row (namespace, storage
      slot, interface, interfaceId, ERC-165 map slot).

**Recipe and tests**

- [ ] **Recipe** `script/base/<area>/Deploy<Module>.s.sol`: `buildCuts(...)` returns the cuts and init, and
      `run(...)` deploys with `_assemble`. Never `new Lattice` or a separate `initialize` call in `script/`.
      Example: `script/base/security/DeployEmergencyStop.s.sol`. Prove it: `make anvil` in one shell,
      then `make check-atomic-deploy`.
- [ ] **Test base** `test/base/<Module>TestBase.sol` builds the diamond from `buildCuts`. Put test-only
      facets in `test/helpers/`.
- [ ] **Unit tests** `test/unit/<Module>Test.t.sol`, including an ERC-165 registration test through the
      diamond (`test_ERC165RegisteredIEmergencyStop`; most modules call it `test_SupportsInterface`). Prove
      it: `make test MATCH=<Module>Test`.
- [ ] **Recipe guard**: add `test_Upgradeable_<Module>` to the matching
      `test/composability/RecipeUpgradeability<Group>Test.t.sol`. Nothing enforces one guard per recipe, so
      only this list catches a missing one.
- [ ] **Docs**: add the module to the README Modules table, backticked (`make readme-check` fails without
      it), and the `src/` layout comment.
- [ ] **Gates**: `make fmt` (it also sorts imports), then `make ci`.
