# `script/` map

Deploy recipes, release and upgrade tooling, post-deploy configuration, demo drivers and the CI
guard scripts. `make help` lists every target. "None" in the last column means you run the file
directly with `forge script` (usage is in its NatSpec header) or it is only imported.

| Folder | Purpose | Entry point | Makefile target |
| --- | --- | --- | --- |
| `script/` (root) | CI guard helpers | `check-licenses.sh` and its fixture test `test-check-licenses.sh`; `check-readme-catalog.sh` and its fixture test `test-check-readme-catalog.sh`; `check-release-build.sh` and its mutation fixtures `test-check-release-build.sh`; `closing-issues.sh` and `test-closing-issues.sh`; `test-storage-layout.sh` tests the storage-layout checker on the Action's fixture project; `fork-lanes.sh` assigns each fork suite to a lane of the weekly fork job and runs a lane (with one whole-lane retry on an RPC error), and `test-fork-lanes.sh` tests it; `error-event-catalog.sh` validates native ABI/AST coverage and writes `errors.json`, with `test-error-event-catalog.sh` fixtures; `slither-db.py` normalizes `slither.db.json` | `license-check`; `readme-check`; `release-build-check`; `scripts-check`; `abi-catalog`; `slither`, `slither-triage` |
| `base/` | Deploy recipes: each `Deploy<Module>.s.sol` builds its cuts (`buildCuts`) and creates and initializes the diamond in one transaction through `LatticeFactory`. Shared by deploys and tests | `BaseDeploy.s.sol` (shared primitive); `<area>/Deploy<Module>.s.sol` | `deploy-local SCRIPT=…`; `check-atomic-deploy` |
| `base/<area>/` | One subfolder per `src/` area: `access`, `accounts`, `amm`, `crosschain`, `defi`, `ens`, `governance`, `oracles`, `privacy`, `security`, `tokens`, `utils` | `Deploy<Module>.s.sol` | as `base/` |
| `base/tokens/` (temporary approval) | ERC-7674 token with ordinary and transaction-scoped allowances; immutable default and admin upgradeable overload | `DeployERC20TemporaryApproval.s.sol` | as `base/` |
| `base/crosschain/` (demos) | Live CCTP demo contracts, kept beside the recipes they extend | `CCTPHookDemo.s.sol`, `CCTPHookReceiptDemo.s.sol`, `CCTPUSDCDemo.s.sol` (driven by the `config/cctp-*.sh` scripts) | `deploy-cctp`, `demo-cctp-hook`, `demo-cctp-roundtrip`, `deploy-cctp-receipt`, `demo-cctp-receipt`, `demo-cctp`, `demo` |
| `base/defi/` (example) | The ENS grant M2 governed-upgrade example | `GrantExample.s.sol` (driven by `examples/governance-upgradeable-diamond/run.sh`) | `example-ens-grant-m2` |
| `config/` | One-action post-deploy configuration scripts | `EnableAurora.s.sol`, `EnableRelay.s.sol`, `RegisterEnsName.s.sol` | none |
| `config/` (demo drivers) | Shell loops that run the demos against a live stack | `governance-demo-loop.sh`, `cctp-usdc-demo-loop.sh`, `cctp-hook-demo.sh`, `cctp-hook-receipt-demo.sh`, `cctp-roundtrip-demo.sh`, `cctp-demo-interactive.sh` | `demo-governance`, `demo-cctp`, `deploy-cctp`, `demo-cctp-hook`, `deploy-cctp-receipt`, `demo-cctp-receipt`, `demo-cctp-roundtrip`, `demo` |
| `config/` (auth) | Runs a command with `FORGE_AUTH` built from a Foundry keystore | `keychain-auth.sh` | used by every demo target when `KEYSTORE=` is set |
| `config/hedera/` | Hedera tooling: the pinned-Foundry wrapper and the day-0 network probe ([docs/guides/hedera.md](../docs/guides/hedera.md)) | `forge-hedera.sh`, `ProbeHedera.s.sol` | none |
| `deploy/` | Canonical release and singleton deploys | `DeployRelease.s.sol` (all inventory facets/inits plus registry and factory), `DeployFactory.s.sol` (replacement factory), `DeployAdapters.s.sol`; `check-atomic-deploy.sh` | `check-atomic-deploy` |
| `release/` | Frozen identities, schema validation, read-only chain observations and source verification | `GenerateManifest.s.sol`, `ManifestReader.sol`, `ObserveManifest.s.sol`, `validate-manifest.sh`, `source-boundary.sh`, `package-build-info.sh`, `prepare-verification.sh`, `chain-evidence.sh`, `sourcify.sh`; root wrappers `release-manifest.sh`, `release-status.sh`, `release-verify.sh`, `check-release-manifests.sh`, `check-release-reproducibility.sh`, mutation drivers `test-release-manifest.sh`, `test-release-verification.sh` and actual-linker gate `test-release-script-simulation.sh` | `release-manifest`; `release-status`; `release-verify`; `release-manifests` |
| `docs/` | Documentation site build: stages forge doc output and the guides into `docs/site`, builds it with Vocs and checks its links | `build.sh`, `check-links.sh` | `doc`, `doc-serve` |
| `governance/` | Upgrade tooling for live diamonds | `UpgradeDiamond.s.sol` (CreateX deploy plus governed-cut proposal); `ProposeGovernedCut.s.sol` (OpenZeppelin Defender payload for a one-selector cut, smoke-tested in `test/unit/ProposeGovernedCutScriptTest.t.sol`) | none |
| `lib/` | Imported helpers, not run directly | `ArachnidDeployer.sol` (shared release CREATE2), `CreateXDeployer.sol` (CREATE3 and legacy raw CREATE2), `FacetInventory.sol` (release facets; drives `ExportSelectorsParityTest`), `InitInventory.sol` (stateless release inits; source parity checked), `CoreCompositionMetadata.sol` (pinned upstream-only composition records), `LibraryInventory.sol` (native CREATE2-linked shared dependencies), `ReleaseVersion.sol` (deployment/observer semver parser) | none |
| `upgrades/` | ERC-7201 storage-layout guard: `check-storage-layout.sh` runs the storage-safety Action's checker (`.github/actions/storage-layout/`) with Lattice's probe, baseline and optional reviewed resets file (`storage-layout.resets`) | `check-storage-layout.sh`, `StorageLayoutProbe.sol`, `storage-layout.baseline`, `storage-registry.sh`, `storage-registry.json` | `storage-check`, `storage-update` |

Moving a file breaks README permalinks and the `@lattice-script/` imports in `test/`, so update both
in the same change.

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
