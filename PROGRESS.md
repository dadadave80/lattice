# Grant progress

Single index of milestone-completion evidence, per grant. Every code claim links a commit-SHA
permalink; every deployment claim links a source-verified contract or transaction a reviewer can
confirm directly on the explorer.

# ENS Public Goods Builder Grant

## Milestone 1 — Reference deployment ✅

A self-governed, ENS-named ERC-4626 vault diamond deployed to Sepolia with verified source,
which then executed a full governance lifecycle against itself.

| Evidence | Link |
|---|---|
| Deploy script (commit permalink) | [`script/base/defi/DeployGovernedVaultENS.s.sol`](https://github.com/dadadave80/lattice/blob/d1af01a91199e7f13de1600bd8af194850c2a3be/script/base/defi/DeployGovernedVaultENS.s.sol) |
| Verified diamond (Sepolia) | [`0x7a498c34A8Dc3B6502889C21218Da0F8696b7bb6`](https://sepolia.etherscan.io/address/0x7a498c34a8dc3b6502889c21218da0f8696b7bb6#code) — all 14 facets verified (next row) |
| Verified facets (Etherscan) | [ERC165Facet](https://sepolia.etherscan.io/address/0xddd97e17031bfb32c3428f13a44eb0449bf4ac62#code) · [AccessControl](https://sepolia.etherscan.io/address/0xf45d5e8bc4ad61059434983edab44963ccd0570d#code) · [TimelockController](https://sepolia.etherscan.io/address/0x894507f901ffe88fb9ff7ebe8edaecb2b959da10#code) · [ERC20](https://sepolia.etherscan.io/address/0x58e1f0d2ad3d94011c765adf0508dd588e3a7397#code) · [ERC4626](https://sepolia.etherscan.io/address/0xcc2b1ff44ac9bd105448c3346c571f8cc6ad1c04#code) · [VaultCore](https://sepolia.etherscan.io/address/0xecf68bd66e8457ceeee826bb5ab8040d36d2056f#code) · [Votes](https://sepolia.etherscan.io/address/0x3e698cce280af053bf6bf3f61edfe4f75e2d77fe#code) · [ERC20Votes](https://sepolia.etherscan.io/address/0x6db23df1319b12b2f8f36e78ccc409a6acbab56d#code) · [Governor](https://sepolia.etherscan.io/address/0x50c36f0eaeec1e3fa6d5f4212067aaa9c9e0b938#code) · [GovernedVault](https://sepolia.etherscan.io/address/0x27bcd5beff0594ff3abf4f27eeeb176f5f6d442b#code) · [DiamondLoupeFacet](https://sepolia.etherscan.io/address/0x983c1f18254af7f0c998a6f24699f17c5d1d2ab1#code) · [EmergencyStop](https://sepolia.etherscan.io/address/0xce342fdcade10e9571b8e249faa1f043cd0dd7e5#code) · [GovernedDiamondCut](https://sepolia.etherscan.io/address/0xc4eb702847dac1f636cee9c06dc125f132f49183#code) · [ENSReverseClaimer](https://sepolia.etherscan.io/address/0x91dfa8a2ee39ba605cb1633e46c8598d1649cc38#code) · (init: [GovernedVaultENSInit](https://sepolia.etherscan.io/address/0x58147df75c453c269ade1b18270505c1b5dc91d0#code)) |
| Underlying asset | [`TestnetAsset`](https://sepolia.etherscan.io/address/0x9383f665dff7529f6c28e732ec4136d332fa43c9#code) (open faucet: `mint(address,uint256)`) |
| Primary ENS name (forward + reverse) | [`milestone1vault.lattice.studio.eth`](https://sepolia.app.ens.domains/milestone1vault.lattice.studio.eth) |
| Governance lifecycle executed on-chain | [`ProposalExecuted` tx `0xfba2c5…df64`](https://sepolia.etherscan.io/tx/0xfba2c57a3063883b43edb905fabcbe508c3ff9d3f0447d2d58fa2739c832df64) — proposal froze the loupe/cut selectors and reasserted the ENS name via the diamond's own Governor + TimelockController |
| Deploy broadcast log | [`broadcast/DeployGovernedVaultENS.s.sol/11155111/run-latest.json`](broadcast/DeployGovernedVaultENS.s.sol/11155111/run-latest.json) |
| Governance-demo broadcast log | [`broadcast/DeployGovernedVaultENS.s.sol/11155111/governanceDemo-latest.json`](broadcast/DeployGovernedVaultENS.s.sol/11155111/governanceDemo-latest.json) |
| ENS registration broadcast log | [`broadcast/RegisterEnsName.s.sol/11155111/register-latest.json`](broadcast/RegisterEnsName.s.sol/11155111/register-latest.json) |
| One-command reproduce | [README live deployments section](README.md#live-deployments-and-demos) |
| Community files | [`LICENSE`](LICENSE) · [`SECURITY.md`](SECURITY.md) · [`CONTRIBUTING.md`](CONTRIBUTING.md) |

This deployment predates the one-transaction `LatticeFactory` rule: it created and initialized the diamond
in two transactions. Every `script/base/**` recipe now deploys through the factory.

Tag: `grant-m1` — created on `main` when this evidence is promoted from `dev`.

## Milestone 2 — Worked integration example + composition guide ✅

A runnable governance-upgradeable Diamond example and a "Compose your own Diamond" guide, exercised in CI on
Anvil and reproduced live on Sepolia, where the example vault upgraded itself through its own Governor +
TimelockController.

| Evidence | Link |
|---|---|
| Composition guide | [`docs/guides/compose-your-own-diamond.md`](https://github.com/dadadave80/lattice/blob/grant-m2/docs/guides/compose-your-own-diamond.md) |
| Runnable example (one `make` command, local Anvil or any EVM RPC) | [`examples/governance-upgradeable-diamond/`](https://github.com/dadadave80/lattice/tree/grant-m2/examples/governance-upgradeable-diamond) |
| Canonical test: namespace check → atomic init → propose → vote → timelock → `diamondCut`, state preserved | [`test/unit/GovernedVaultUpgradeTest.t.sol`](https://github.com/dadadave80/lattice/blob/grant-m2/test/unit/GovernedVaultUpgradeTest.t.sol) |
| Green CI running the example end to end on Anvil | [CI run 37650708789](https://github.com/dadadave80/lattice/actions/runs/37650708789) on the tagged commit [`4e95664`](https://github.com/dadadave80/lattice/commit/4e956649aebb8cebf7d3d73fd4c472ab3ecbea2b); originally [run 34620029310](https://github.com/dadadave80/lattice/actions/runs/34620029310) on [`25db4d7`](https://github.com/dadadave80/lattice/commit/25db4d7c49489dba6b9787703e85b4bf5a59ba1c) (identical tree; see the note below) |
| Live Sepolia vault (all 20 contracts verified on Etherscan and Sourcify) | [`0x942592e135FFfF39d993F43B735aF34605E829d5`](https://sepolia.etherscan.io/address/0x942592e135FFfF39d993F43B735aF34605E829d5#code) |
| Governed upgrade executed on-chain | [`ProposalExecuted` tx `0xbe354e…0c08`](https://sepolia.etherscan.io/tx/0xbe354e29b26c4e95ac54db7b6c3ca66fc72752dd25fb7f7460b8c0be90630c08) — `grantVersion()` returns 2 through the proxy; deposited assets and shares unchanged |
| Source of the live run (commit permalink) | [`script/base/defi/GrantExample.s.sol` @ `0e1560b`](https://github.com/dadadave80/lattice/blob/0e1560bca65abc937050b166eccbfb1d254831d3/script/base/defi/GrantExample.s.sol) (the deployed contracts are verified on Sourcify against this tree) |
| Deploy broadcast log | [`broadcast/GrantExample.s.sol/11155111/run-latest.json`](broadcast/GrantExample.s.sol/11155111/run-latest.json) |
| Every recipe deploys and initializes in one transaction | [#182](https://github.com/dadadave80/lattice/pull/182); `make check-atomic-deploy` runs in CI |
| Full governance flow on-chain (all status 1) | [mint](https://sepolia.etherscan.io/tx/0x4c219786640b3f6238b4a949239d8f40dcf5679037044da016913a898f91be2b) → [approve](https://sepolia.etherscan.io/tx/0xa270467b13d273d3156699103fe536e42a060e12c19f03f02c644e7d905dccba) → [deposit](https://sepolia.etherscan.io/tx/0xc1cb951f8bc763cff449d5ade1278d69daf686d4683ce3f4dc40fdb87f1096af) → [delegate](https://sepolia.etherscan.io/tx/0xaf6b4ce89d1711c24db68324ff23d1bd28677287c9656fc3167b46a189886621) → [propose](https://sepolia.etherscan.io/tx/0xb7e518aee9c8de4b8af28fdf6f93e825bc17451841ebc5c55f7a17624496fa2f) → [castVote](https://sepolia.etherscan.io/tx/0xc3af69dc314d96adc10416bf62b725110d0277a8bbad4a189b5402698be91762) → [queue](https://sepolia.etherscan.io/tx/0xd343dbc4cae33e35bc9f5ac3d4b8c6b10f4a5bb39c95d38cf7b45270ff7a10da) → [execute](https://sepolia.etherscan.io/tx/0xbe354e29b26c4e95ac54db7b6c3ca66fc72752dd25fb7f7460b8c0be90630c08) |

Tag: [`grant-m2`](https://github.com/dadadave80/lattice/releases/tag/grant-m2), commit `4e95664`, on `main`; the repository links above resolve at the tag.

**Commit history note.** `dev` and `main` were rewritten after the milestone was delivered, which re-created the
tag on a new commit with the same tree. Commits cited in earlier copies of this page still resolve on GitHub but
are no longer on a branch. Each has a tree-identical commit on `main`:

| Cited earlier | Now on `main` | Tree |
|---|---|---|
| `9ccdcaf` (head of CI run 34620029310) | [`25db4d7`](https://github.com/dadadave80/lattice/commit/25db4d7c49489dba6b9787703e85b4bf5a59ba1c) | `9fb66c2` |
| `d5a89e6` (source of the live run) | [`0e1560b`](https://github.com/dadadave80/lattice/commit/0e1560bca65abc937050b166eccbfb1d254831d3) | `c5bcc9e` |
| `94b7d93` (tag commit; [CI run 34623283525](https://github.com/dadadave80/lattice/actions/runs/34623283525)) | [`4e95664`](https://github.com/dadadave80/lattice/commit/4e956649aebb8cebf7d3d73fd4c472ab3ecbea2b) | `beba22a` |

**Demo scope and known issues.** The live vault is a testnet demo:
- **Governance can be taken over.** The deployer holds every vote, but the demo asset's `mint` is open to
  anyone, and governance delays are minutes (voting delay 60 s, voting period 600 s, timelock 300 s; quorum 4).
  Anyone could mint, delegate and outvote the deployer.
- **Issues found after delivery.** They don't change the M2 flow:
  - [#214](https://github.com/dadadave80/lattice/issues/214): ERC-4626 shares are priced on the idle balance.
    This is latent here, because the vault has no strategy manager.
  - [#222](https://github.com/dadadave80/lattice/issues/222): an ERC20Votes ERC-165 constant writes to slot
    `keccak256(0)`. The write is present in this vault's storage.
  - [#255](https://github.com/dadadave80/lattice/issues/255): `supportsInterface(0x01ffc9a7)` returns false.

## Milestone 3 — Docs site + reusable storage-safety Action

Delivered in release [`v0.5.0`](https://github.com/dadadave80/lattice/releases/tag/v0.5.0). The site and the Action are built and tested in this repository, the docs deploy to GitHub Pages from `main`, and the Action is released and proven in an external repository.

| Evidence | Status |
|---|---|
| Docs site source: the guides plus the API reference `forge doc` generates, built with Vocs under `/lattice` | [`docs/site/`](docs/site/vocs.config.ts) · [`script/docs/build.sh`](script/docs/build.sh) (`make doc`) |
| Docs build and link check in CI on every relevant pull request | [`.github/workflows/docs.yml`](.github/workflows/docs.yml) (pull requests build only; `main` builds and deploys to GitHub Pages) |
| Public docs URL | [`https://dadadave80.github.io/lattice/`](https://dadadave80.github.io/lattice/), first deployed by [run 37938597222](https://github.com/dadadave80/lattice/actions/runs/37938597222) from `main` at [`2134a6e`](https://github.com/dadadave80/lattice/commit/2134a6e67bec3c1422675fbd3cf6c20b230516bf) |
| Storage-safety Action: composite Action on the Bash+jq checker Lattice's own CI runs | [`.github/actions/storage-layout/`](.github/actions/storage-layout/README.md) |
| Action regression cases (43) on a fixture consumer project, and a CI self-test calling the Action | [`script/test-storage-layout.sh`](script/test-storage-layout.sh) · `storage-action` job in [`test.yml`](.github/workflows/test.yml) |
| Lattice CI checks every pull request append-only against its base through the same Action | `storage-layout` job in [`test.yml`](.github/workflows/test.yml) |
| Versioned Action release (tag and commit) | [`storage-layout-v1.0.0`](https://github.com/dadadave80/lattice/releases/tag/storage-layout-v1.0.0) → [`828e0a8`](https://github.com/dadadave80/lattice/commit/828e0a88d2eff10cfea786ab2dc7854cdf26785c) |
| External demo repository calling the released Action | [`lattice-storage-guard-demo`](https://github.com/dadadave80/lattice-storage-guard-demo) pins `.github/actions/storage-layout@828e0a8…` ([workflow](https://github.com/dadadave80/lattice-storage-guard-demo/blob/main/.github/workflows/storage.yml)) |
| Demo runs: red on an incompatible change, green on its fix, green on a safe append | reorder [red](https://github.com/dadadave80/lattice-storage-guard-demo/actions/runs/37923527240) → fix [green](https://github.com/dadadave80/lattice-storage-guard-demo/actions/runs/37923624481) ([#1](https://github.com/dadadave80/lattice-storage-guard-demo/pull/1)) · safe append [green](https://github.com/dadadave80/lattice-storage-guard-demo/actions/runs/37923536837) ([#2](https://github.com/dadadave80/lattice-storage-guard-demo/pull/2)) |

Tag: [`grant-m3`](https://github.com/dadadave80/lattice/releases/tag/grant-m3), commit [`cca133b`](https://github.com/dadadave80/lattice/commit/cca133b07abda7fdde4468798d1dce3e36ea7849) (the v0.5.0 release), on `main`.

# Circle Arc Grant (2026 Cohort 2 — application evidence)

Groundwork delivered **before** application: the `CCTPBridgeAdapter` (Circle CCTP v2, including
`depositForBurnWithHook`/`relayMessageWithHook` hooks) proven with live USDC on Arc testnet as the
source chain, in both a plain multi-destination transfer and a programmable-USDC hook delivery.

| Evidence | Link |
|---|---|
| Adapter source (commit permalink) | [`src/crosschain/CCTPBridgeAdapter.sol`](https://github.com/dadadave80/lattice/blob/0648ac7/src/crosschain/CCTPBridgeAdapter.sol) · [`CCTPHookExecutor.sol`](https://github.com/dadadave80/lattice/blob/0648ac7/src/crosschain/CCTPHookExecutor.sol) · [`CCTPHookVault.sol`](https://github.com/dadadave80/lattice/blob/0648ac7/src/examples/crosschain/CCTPHookVault.sol) |
| Arc source hub — transfer demo | [`0xfc937CD3d175b890fF668f95fdED5CB4D9247d68`](https://testnet.arcscan.app/address/0xfc937CD3d175b890fF668f95fdED5CB4D9247d68) |
| USDC delivered — Ethereum Sepolia | [mint tx `0xff2326…39aea`](https://sepolia.etherscan.io/tx/0xff2326eb12dfd5b56e553e43f660e0c0cc8bba01dbc215b12109bf05c8039aea) |
| USDC delivered — Base Sepolia | [mint tx `0xf72700…736d3`](https://base-sepolia.blockscout.com/tx/0xf7270031cb59c1ff0c85fc0147768a623b69a7d2a3c12faa4b1d4ded9fc736d3) |
| Hook demo — Arc hub diamond | [`0x6ca99B6179eAc891E3aCD4008b610fcE66F63E2d`](https://testnet.arcscan.app/address/0x6ca99B6179eAc891E3aCD4008b610fcE66F63E2d) (Sourcify-verified) |
| Hook demo — Base destination diamond | [`0x957259C5AEAa521c9DcFaEb6692C25ae53F349f1`](https://base-sepolia.blockscout.com/address/0x957259C5AEAa521c9DcFaEb6692C25ae53F349f1) |
| Auto-credit vault | [`0xe8e10843Ab41B2c359D02eA091b6772C43b05b1f`](https://base-sepolia.blockscout.com/address/0xe8e10843Ab41B2c359D02eA091b6772C43b05b1f) |
| Programmable-USDC delivery, one tx | burn [`0xc9ba15…a77a4`](https://testnet.arcscan.app/tx/0xc9ba159c51f027ab336d56b054a5947be02f8d2ba398ffd304ffbbaf0e5a77a4) → relay [`0x7f82f3…b5d00`](https://base-sepolia.blockscout.com/tx/0x7f82f3c2128bf6026b340cbb1265ca5d5182de076d55d35a2223114ce09b5d00) minted to the vault **and** emitted `Credited(0x11Cf…eC00, 1000000, 26, hub)` |
| Real-attestation replay (reproducible) | [`test/fork/CCTPHookDemoFork.t.sol`](test/fork/CCTPHookDemoFork.t.sol) replays the captured [Iris fixture](test/fixtures/cctp/arc-to-base-hook-v2.json) through the live Base diamond on a pinned fork — credits exactly 1 USDC, second relay reverts (nonce consumed) |
| Receipt NFT (`CCTPHookReceipt`) | [`0x6De791…71a65`](https://base-sepolia.blockscout.com/address/0x6De7919B31b5FCBC771baD221B7A305F43871a65) |
| Receipt demo burn (Arc) | [`0x7a923b…c6f07`](https://testnet.arcscan.app/tx/0x7a923bb854ea4e172cbb452d16cf5c1ff75765189c73f3e36d45ed65bf8c6f07) |
| Receipt relay — direct USDC + NFT (Base) | [`0xbdcd52…5a8a7`](https://base-sepolia.blockscout.com/tx/0xbdcd52bb632dd2f2d031da3ba55ac421ad73b0cf3cf3f679047cfa51d5e5a8a7) — grant-video run; mints 5 USDC and receipt #4 to `0xDAda…C751` |
| Receipt real-attestation replay | [`test/fork/CCTPHookReceiptDemoFork.t.sol`](test/fork/CCTPHookReceiptDemoFork.t.sol) replays the captured [receipt fixture](test/fixtures/cctp/arc-to-base-receipt-v2.json) |
| Broadcast evidence | [`broadcast/multi/`](broadcast/multi) (multichain setups) · [`broadcast/CCTPHookDemo.s.sol/84532/`](broadcast/CCTPHookDemo.s.sol/84532) (hook relay) · [`broadcast/CCTPUSDCDemo.s.sol/`](broadcast/CCTPUSDCDemo.s.sol) (transfer relays) |
| One-command reproduce | `make demo-cctp` · `make demo-cctp-hook KEYSTORE=<name>` · `make demo-cctp-receipt KEYSTORE=<name>` — see the [README demo section](README.md#live-deployments-and-demos) |

All demo contracts are Sourcify-verified (`exact_match`) on both chains. The hook, receipt and round-trip
demo scripts default to the hook demo's Arc hub and Base diamond above (`CANON_*` in
`script/config/cctp-*.sh`); keep this table and those defaults in step.

# Team1 Builder Grants (Avalanche) — Mini Grant application evidence

Lattice's reference vault diamond is live and source-verified on Avalanche Fuji (chain 43113), with the same
evidence as the ENS milestones: a governed vault assembled through `LatticeFactory` in one transaction, then
a shareholder proposal that passes through the vault's own Governor and TimelockController and upgrades it.
The deployment is release [`v0.5.0`](https://github.com/dadadave80/lattice/releases/tag/v0.5.0)
([`cca133b`](https://github.com/dadadave80/lattice/commit/cca133b07abda7fdde4468798d1dce3e36ea7849) on `main`), built with the repository's own
settings. Avalanche runs the Cancun EVM. Lattice compiles to identical creation and runtime code for Cancun
and for the repository's default target (all 1,204 bytecode objects, compared without the metadata hash), so
every facet sits at the address a v0.5.0 release gets on every chain (CreateX `CREATE2`, salt
`lattice.<Name>.0.5.0`). The 14 facets were the first v0.5.0 facets deployed anywhere; a later `DeployRelease`
on Fuji adopts them.

| Evidence | Link |
|---|---|
| Deploy script (commit permalink) | [`script/base/defi/GrantExample.s.sol`](https://github.com/dadadave80/lattice/blob/cca133b07abda7fdde4468798d1dce3e36ea7849/script/base/defi/GrantExample.s.sol) · runner [`run.sh`](https://github.com/dadadave80/lattice/blob/cca133b07abda7fdde4468798d1dce3e36ea7849/examples/governance-upgradeable-diamond/run.sh) |
| Governed vault (diamond) | [`0xd06F72Eabf158CDFAa550450cCb220b42A1068ef`](https://testnet.snowscan.xyz/address/0xd06F72Eabf158CDFAa550450cCb220b42A1068ef#code) · [Snowtrace](https://testnet.snowtrace.io/address/0xd06F72Eabf158CDFAa550450cCb220b42A1068ef/contract/43113/code) · [Sourcify](https://repo.sourcify.dev/43113/0xd06F72Eabf158CDFAa550450cCb220b42A1068ef) |
| Vault asset (test token) | [`0x3cad51414bBd94E19C47Ef47fE2D65f89e467Eea`](https://testnet.snowscan.xyz/address/0x3cad51414bBd94E19C47Ef47fE2D65f89e467Eea#code) · [Snowtrace](https://testnet.snowtrace.io/address/0x3cad51414bBd94E19C47Ef47fE2D65f89e467Eea/contract/43113/code) · [Sourcify](https://repo.sourcify.dev/43113/0x3cad51414bBd94E19C47Ef47fE2D65f89e467Eea) |
| Upgrade probe (facet added by the proposal) | [`0xD22736eCd4a7F1574f99feCff0fD59C96a2d1571`](https://testnet.snowscan.xyz/address/0xD22736eCd4a7F1574f99feCff0fD59C96a2d1571#code) · [Snowtrace](https://testnet.snowtrace.io/address/0xD22736eCd4a7F1574f99feCff0fD59C96a2d1571/contract/43113/code) · [Sourcify](https://repo.sourcify.dev/43113/0xD22736eCd4a7F1574f99feCff0fD59C96a2d1571) |
| LatticeFactory (this run's own instance, not the canonical factory) | [`0xdaC8b1CaBfab28F99D6B572E464a42b37FAC7D1A`](https://testnet.snowscan.xyz/address/0xdaC8b1CaBfab28F99D6B572E464a42b37FAC7D1A#code) · [Snowtrace](https://testnet.snowtrace.io/address/0xdaC8b1CaBfab28F99D6B572E464a42b37FAC7D1A/contract/43113/code) · [Sourcify](https://repo.sourcify.dev/43113/0xdaC8b1CaBfab28F99D6B572E464a42b37FAC7D1A) |
| LatticeRegistry (this run's own instance, owned by the deployer, not the canonical registry) | [`0x9c69eD8Bd87E85AF80d2546e2C4a8F064fc98F4C`](https://testnet.snowscan.xyz/address/0x9c69eD8Bd87E85AF80d2546e2C4a8F064fc98F4C#code) · [Snowtrace](https://testnet.snowtrace.io/address/0x9c69eD8Bd87E85AF80d2546e2C4a8F064fc98F4C/contract/43113/code) · [Sourcify](https://repo.sourcify.dev/43113/0x9c69eD8Bd87E85AF80d2546e2C4a8F064fc98F4C) |
| Vault init contract | [`0xC360591B35BA82ad066b609CCFdCBab4D9f3f810`](https://testnet.snowscan.xyz/address/0xC360591B35BA82ad066b609CCFdCBab4D9f3f810#code) · [Snowtrace](https://testnet.snowtrace.io/address/0xC360591B35BA82ad066b609CCFdCBab4D9f3f810/contract/43113/code) · [Sourcify](https://repo.sourcify.dev/43113/0xC360591B35BA82ad066b609CCFdCBab4D9f3f810) |
| Vault creation through the factory, one transaction | [`0x2e9bc8…0f52`](https://testnet.snowscan.xyz/tx/0x2e9bc871fe9a2ce5b01c92f652ec60218d2bd89e9bc3d7048842774520410f52) |
| Governed upgrade: `ProposalExecuted`, then `grantVersion()` returns 2 through the vault | [`0x5deeea…0ed2`](https://testnet.snowscan.xyz/tx/0x5deeea5bec8a70605decb25261c21c9d14bfe0f6a4a80b1cd029700b85ab0ed2) (block 59,249,355) |
| Governance steps | mint [`0x1451f2…197c`](https://testnet.snowscan.xyz/tx/0x1451f26b8855252cc62e4af260552b183df1702afd68c50963ebb01c1fd7197c) → approve [`0xcfc5b0…59bf`](https://testnet.snowscan.xyz/tx/0xcfc5b09a1f33df1db63f551a743ef6e48032af5b0c5a435db7080186859759bf) → deposit [`0xa288ee…2c27`](https://testnet.snowscan.xyz/tx/0xa288eeb20cb71f5e27ff6efc99dd4ce7849f5aaafc075dd95fc8e7bd6b6f2c27) → delegate [`0xcbe24b…f695`](https://testnet.snowscan.xyz/tx/0xcbe24b158f8c4d66628f983c01e2496e94c38cd324f12d0cbcf3b05b6aa4f695) → propose [`0xc78a91…6490`](https://testnet.snowscan.xyz/tx/0xc78a91b17c8e3fa4c26281c4a00a2d32ff1f9b0572323f04c7bbdd9cb2496490) → vote [`0x098789…9204`](https://testnet.snowscan.xyz/tx/0x098789c72bd701ac4adebbcc74fc305c025e85b065a0215ab092f78c4a929204) → queue [`0x88d746…44e5`](https://testnet.snowscan.xyz/tx/0x88d746fd6840116ea00b7ceaf95b14aa00c1215f99f3852fdbe3b3a71cd744e5) → execute (above) |
| Vault facets, each verified | [AccessControl](https://testnet.snowscan.xyz/address/0x9549f7731866c46F5489E116577C42b4dEAaC1aB#code) · [TimelockController](https://testnet.snowscan.xyz/address/0x6578F2AD703f20d4d52810d7fd8a02c945d04A70#code) · [ERC20](https://testnet.snowscan.xyz/address/0x4E889a826daa5c3cCc9d6E08a5DeB08a41caAdC9#code) · [ERC4626](https://testnet.snowscan.xyz/address/0x31E368b44b0224E9126E6Fc3f97a209FD5769019#code) · [VaultCore](https://testnet.snowscan.xyz/address/0x7411D1D1666aB06b70E0252C1BEdfCC0559dC522#code) · [Votes](https://testnet.snowscan.xyz/address/0xE3910773b4176FC19cE8F55FB33134EE40BCEaf8#code) · [ERC20Votes](https://testnet.snowscan.xyz/address/0x24F4343Bea82Fae2dD53A2306D19e3d29aFbe406#code) · [Governor](https://testnet.snowscan.xyz/address/0xc8112a43aA2C84Ea305E5Fe29D0A28028d18CFfE#code) · [GovernedVault](https://testnet.snowscan.xyz/address/0x04D7b5da3A0a1E4eF1F18EaBb50839423f021cff#code) · [EmergencyStop](https://testnet.snowscan.xyz/address/0x97a28D2C9BE588e6240a9421dF84246992b86E67#code) · [GovernedDiamondCut](https://testnet.snowscan.xyz/address/0x9aC2765B80a5C083499871142Ad145640CFE37cE#code) · [Receive](https://testnet.snowscan.xyz/address/0x924dE4b5AE1991f0e24A7A86fB44D6495A57B652#code) · [ERC165Facet](https://testnet.snowscan.xyz/address/0x16A78da88a6Ff27cA38a7DEa1Be4d94DfB875F0C#code) · [DiamondLoupeFacet](https://testnet.snowscan.xyz/address/0xe3b0eDd953D1c521d26b2ad6eD1AAb1a9c621Dff#code) |
| Broadcast log (20 transactions, 33.3M gas) | [`broadcast/GrantExample.s.sol/43113/run-latest.json`](broadcast/GrantExample.s.sol/43113/run-latest.json) |
| One-command reproduce | `make example-ens-grant-m2 RPC=fuji KEYSTORE=<name>` (about 20 minutes of real governance delays) — see the [example README](examples/governance-upgradeable-diamond/README.md) |

All 20 contracts in the broadcast are verified on Sourcify, Snowscan (Etherscan V2) and Snowtrace
(Routescan). On Sourcify, 18 are exact matches. `ERC165Facet` and `DiamondLoupeFacet` from diamond-lib are
full matches, because Sourcify had already verified the same bytecode from another source tree. Snowtrace
lists the vault as `LatticeDiamond`, an earlier verified contract with identical bytecode.
