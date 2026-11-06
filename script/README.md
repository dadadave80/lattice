# `script/` map

Deploy recipes, release and upgrade tooling, post-deploy configuration, demo drivers and the CI
guard scripts. `make help` lists every target. "None" in the last column means you run the file
directly with `forge script` (usage is in its NatSpec header) or it is only imported.

| Folder | Purpose | Entry point | Makefile target |
| --- | --- | --- | --- |
| `script/` (root) | CI guard helpers | `check-licenses.sh` and its fixture test `test-check-licenses.sh`; `check-readme-catalog.sh` and its fixture test `test-check-readme-catalog.sh`; `check-release-build.sh` and its mutation fixtures `test-check-release-build.sh`; `closing-issues.sh` and `test-closing-issues.sh`; `test-storage-layout.sh` tests the storage-layout checker on the Action's fixture project; `fork-lanes.sh` assigns each fork suite to a lane of the weekly fork job and runs a lane (with one whole-lane retry on an RPC error), and `test-fork-lanes.sh` tests it; `error-event-catalog.sh` validates native ABI/AST coverage and writes `errors.json`, with `test-error-event-catalog.sh` fixtures; `erc3643-profile.sh` binds the closed ERC-3643 initializer to canonical host/facet code and selectors, with `test-erc3643-profile.sh` mutation fixtures; `slither-db.py` normalizes `slither.db.json`; `test-coverage.sh` checks the shared native/instrumented coverage phases | `license-check`; `readme-check`; `release-build-check`; `scripts-check`; `erc3643-profile-check`; `erc3643-profile-update`; `abi-catalog`; `slither`, `slither-triage` |
| `base/` | Deploy recipes: each `Deploy<Module>.s.sol` builds its cuts (`buildCuts`) and creates and initializes the diamond in one transaction through `LatticeFactory`. Shared by deploys and tests | `BaseDeploy.s.sol` (shared primitive); `<area>/Deploy<Module>.s.sol` | `deploy-local SCRIPT=…`; `check-atomic-deploy` |
| `base/<area>/` | One subfolder per `src/` area: `access`, `accounts`, `amm`, `crosschain`, `defi`, `ens`, `governance`, `oracles`, `privacy`, `security`, `tokens`, `utils` | `Deploy<Module>.s.sol` | as `base/` |
| `base/tokens/` (permissioned token) | Closed immutable ERC-3643 suite with initial pause, owner/agent administration, the five standard registry/compliance components, and optional ERC-7674 | `DeployERC3643.s.sol` with `ERC3643Params`; no upgradeable overload | as `base/` |
| `base/tokens/` (temporary approval) | ERC-7674 token with ordinary and transaction-scoped allowances; immutable default and admin upgradeable overload | `DeployERC20TemporaryApproval.s.sol` | as `base/` |
| `base/crosschain/` (demos) | Live CCTP demo contracts, kept beside the recipes they extend | `CCTPHookDemo.s.sol`, `CCTPHookReceiptDemo.s.sol`, `CCTPUSDCDemo.s.sol` (driven by the `config/cctp-*.sh` scripts) | `deploy-cctp`, `demo-cctp-hook`, `demo-cctp-roundtrip`, `deploy-cctp-receipt`, `demo-cctp-receipt`, `demo-cctp`, `demo` |
| `base/defi/` (example) | The ENS grant M2 governed-upgrade example | `GrantExample.s.sol` (driven by `examples/governance-upgradeable-diamond/run.sh`) | `example-ens-grant-m2` |
| `config/` | One-action post-deploy configuration scripts | `EnableAurora.s.sol`, `EnableRelay.s.sol`, `RegisterEnsName.s.sol` | none |
| `config/` (closed profile) | Reviewed required/optional ERC-3643 artifact identities; only the initializer imports generated fingerprints | `erc3643-profile.json` | `erc3643-profile-check`, `erc3643-profile-update` |
| `config/` (demo drivers) | Shell loops that run the demos against a live stack | `governance-demo-loop.sh`, `cctp-usdc-demo-loop.sh`, `cctp-hook-demo.sh`, `cctp-hook-receipt-demo.sh`, `cctp-roundtrip-demo.sh`, `cctp-demo-interactive.sh` | `demo-governance`, `demo-cctp`, `deploy-cctp`, `demo-cctp-hook`, `deploy-cctp-receipt`, `demo-cctp-receipt`, `demo-cctp-roundtrip`, `demo` |
| `config/` (auth) | Runs a command with `FORGE_AUTH` built from a Foundry keystore | `keychain-auth.sh` | used by every demo target when `KEYSTORE=` is set |
| `config/hedera/` | Hedera tooling: the pinned-Foundry wrapper and the day-0 network probe ([docs/guides/hedera.md](../docs/guides/hedera.md)) | `forge-hedera.sh`, `ProbeHedera.s.sol` | none |
| `deploy/` | Canonical release and singleton deploys | `DeployRelease.s.sol` (all inventory facets/inits plus registry and factory), `DeployFactory.s.sol` (replacement factory), `DeployAdapters.s.sol`; `check-atomic-deploy.sh` | `check-atomic-deploy` |
| `recipes/` | Compiler-backed descriptive recipe catalog, ordered checked plans and native export fixtures | `GenerateRecipes.s.sol`, `type-description.jq`, `check-catalog.sh`, `test-catalog.sh`, `test-export.sh`; root wrapper `recipes.sh` | `recipes`; `scripts-check` |
| `release/` | Frozen identities, schema validation, read-only chain observations and source verification | `GenerateManifest.s.sol`, `ManifestReader.sol`, `JsonRecordWriter.sol` (bounded offline record/object serialization), `ObserveManifest.s.sol`, `validate-manifest.sh`, `source-boundary.sh`, `package-build-info.sh`, `prepare-verification.sh`, `chain-evidence.sh`, `sourcify.sh`; root wrappers `release-manifest.sh`, `release-status.sh`, `release-verify.sh`, `release-notes.sh` (compare two frozen manifests), `check-release-notes.sh` (select a canonical comparison), `test-release-notes.sh` fixtures, `check-release-manifests.sh`, `check-release-reproducibility.sh`, mutation drivers `test-release-manifest.sh`, `test-account-release-manifest.sh`, `test-release-verification.sh` and actual-linker gate `test-release-script-simulation.sh` | `release-manifest`; `release-status`; `release-verify`; `release-manifests`; `release-notes` |
| `docs/` | Documentation site build: stages forge doc output and the guides into `docs/site`, builds it with Vocs and checks its links | `build.sh`, `check-links.sh` | `doc`, `doc-serve` |
| `governance/` | Upgrade tooling for live diamonds | `UpgradeDiamond.s.sol` (CreateX deploy plus governed-cut proposal); `ProposeGovernedCut.s.sol` (OpenZeppelin Defender payload for a one-selector cut, smoke-tested in `test/unit/ProposeGovernedCutScriptTest.t.sol`) | none |
| `lib/` | Imported helpers, not run directly | `ArachnidDeployer.sol` (shared release CREATE2), `CreateXDeployer.sol` (CREATE3 and legacy raw CREATE2), `FacetInventory.sol` (release facets; drives `ExportSelectorsParityTest`), `InitInventory.sol` (stateless release inits; source parity checked), `AccountReleaseInventory.sol` (shared account blueprints and constructor-bound EntryPoint instances), `CoreCompositionMetadata.sol` (pinned upstream-only composition records), `LibraryInventory.sol` (native CREATE2-linked shared dependencies), `ReleaseVersion.sol` (deployment/observer semver parser), `RecipeSpec.sol` (documented script DTO), `RecipeInventory.sol` (canonical recipe sources), `RecipePlanLib.sol` / `TokenRecipePlans.sol` (checked cut declarations), `RecipeSpecLib.sol` (descriptive init/authority data constructors) | none |
| `upgrades/` | ERC-7201 storage-layout guard: `check-storage-layout.sh` runs the storage-safety Action's checker (`.github/actions/storage-layout/`) with Lattice's probe, baseline and optional reviewed resets file (`storage-layout.resets`) | `check-storage-layout.sh`, `StorageLayoutProbe.sol`, `storage-layout.baseline`, `storage-registry.sh`, `storage-registry.json` | `storage-check`, `storage-update` |

Moving a file breaks README permalinks and the `@lattice-script/` imports in `test/`, so update both
in the same change.

Canonical builders resolve inventory facets with `BaseDeploy._facet(name)` and stateless initializers
with `_init(name)`. When the Arachnid proxy is installed, these reuse or deploy the exact release
identities for the current `LatticeVersion`; a proxy-free local test falls back to CREATE. Account
initializers additionally bind their EntryPoint through `AccountReleaseInventory`. The recipe guard
suites check every cut and recursively inspect nested `MultiInit` calls against these identities before
assembling each diamond. Their separate local fallback tests exercise the proxy-free path.
`base/tokens/TokenDeployBase.s.sol` shares the three typed base-token builders internally with their
extensions. Recipe helpers are never deployed during broadcast: they contain script-only cheatcodes
and can exceed the EIP-170 limit. The atomic deployment gate broadcasts both authority variants of
an ERC-20, ERC-721 and ERC-1155 extension to check this path.

For module initialization during a later authorized upgrade, `InitInventory` releases
[`ReinitMultiInit`](../src/utils/ReinitMultiInit.sol). Use its address as the cut's `_init` with
`reinitMulti(version, inits, calldatas)`; the [composition guide](../docs/guides/compose-your-own-diamond.md#initialize-modules-during-an-upgrade)
shows the version read and ordered payload.

## Error and event catalog

`make abi-catalog` builds the canonical source artifacts from scratch and writes `out/errors.json`.
CI checks the same catalog, and tagged releases attach it alongside the storage registry. Set
`ABI_CATALOG_OUTPUT=/absolute/path/errors.json` to keep the output outside Forge's cleaned artifact
directory, as the release workflow does.

The schema has three collections:

| Key | Contents |
| --- | --- |
| `errors` | Four-byte selector → canonical signature and declaration source paths |
| `events` | Full signature hash → canonical signature and definitions, including indexed/anonymous encoding |
| `assembly` | Custom-error selector, revert source file and byte position (`byte-offset:length`) |

For example, `.errors["0xd7e6bcf8"]` describes `NotInitializing()` and its declarations. Anonymous
events retain their signature hash as a catalog key, although they emit no signature topic. Repeated
declarations of the same signature share a key; different event encodings remain separate definitions.

The checker reads native compiler ASTs and ABIs for every `src/` and `lib/diamond-lib/src/` declaration.
It rejects missing source artifacts, declarations absent from all ABIs, distinct signatures with the same
selector, and assembly error selectors missing from the catalog. AST type resolution binds complete
signatures, including tuple/array parameters; mixed compiler node IDs require another clean build.
The supported local assembly convention is adjacent literal `mstore(0, selector)` / `revert(28, 4)`.
Known return-data bubbling, empty reverts and Solidity's built-in `Panic(uint256)` are separate accepted
shapes; every other assembly revert fails until the checker is extended.
`script/test-error-event-catalog.sh` covers these guards with positive and negative fixtures.

## Recipe data and checked composition

Run `make recipes` with the pinned toolchain to write `out/recipes.json`. The command uses the canonical
CI profile and no RPC or broadcast. It collects all canonical recipe classes in inventory order through
bounded native Forge executions, validates every record against compiler ABIs, then atomically replaces
the output. A failed record or validation leaves an existing catalog intact. Source commit and dirty-tree
state are captured before generated outputs. CI runs the same export and retains a `recipe-catalog`
artifact; its format job also runs the isolated exporter/catalog regression fixtures. Demos and abstract
helpers have explicit dispositions; they are not silently treated as canonical deploy profiles.

[`RecipeSpec.sol`](lib/RecipeSpec.sol) documents the machine data: ordered facet cuts and selector
selection, active seam participants/allowed final owners/reasons, proxy and builder-output kinds,
complete nested initializer trees, parameter names/types/units/examples/rules, assigned authorities and
public deployment contexts. Account constructor EntryPoints are separate from runtime owner/salt inputs;
`accountProfiles` records the six canonical EntryPoint-specific release bindings. ERC3643 has one builder
ABI and two explicit temporary-approval profiles. Policy-only bundle initialization is not full module
configuration; compiler composition metadata retains those internal phases.

Small integers (including enum values and ordinary parent indices) are native JSON numbers; large
integers, including the root-parent uint256 sentinel, are **decimal JSON strings**.
Addresses, bytes32, dynamic bytes and strings retain their ABI types through native named serialization
and an exact ABI-byte roundtrip. Use a lossless JSON parser and preserve integer strings or use
arbitrary-precision arithmetic when consuming the output; do not assume every integer can safely pass
through a JavaScript number. Binding strings are source descriptions, never executable expressions. Examples are illustrative inputs or named templates,
not verified target-chain configuration.

Every exclusion, partial export omission or replacement cites a declared seam. Builders check the whole
plan before resolving shared implementations, then validate ordered selector ownership. The typed test
suites compare actual cuts and initializer trees with the data and inspect assembled proxy routes; a
separate fixed selector-owner oracle detects correlated mistakes in plans and allowed-owner declarations.
The checked builder rejects ERC1363 together with ERC20Pausable, ERC20Votes or GovernedVault under
ADR0009. Arbitrary authorized diamond cuts can bypass this script policy. External assets/providers,
EntryPoints, verifiers/circuits and existing-state migration requirements remain caller obligations.

## Coverage prerequisites and native checks

`make coverage` first validates the pinned canonical build and persists its complete compiler artifacts,
including test fixtures and scripts. Metadata, initializer ABI and serializer tests read those artifacts
while coverage executes without optimization.

The exact bytecode-sensitive ERC3643 fixture suites and three mixed-suite hash/size methods run natively
before instrumentation. The same anchored selectors exclude only those tests from the instrumented phase;
independent ERC3643 registry/component suites and the other token recipes retain measured coverage.
Production fingerprint and EIP-170 assertions remain enabled, and a native failure stops the command.
Native test results are separate validation, not coverage hits. The report retains every `src/` entry,
including unmeasured closed-profile lines, with the existing test/script source filter unchanged.

Scheduled uses this same entrypoint with `ARGS='--md --report lcov'`. Every phase suppresses gas snapshot
writes; the ordinary test and CI targets continue to run all native tests. `script/test-coverage.sh`
checks the phase order, exact filter complement, report flags and fail-closed behavior with fake Forge.
