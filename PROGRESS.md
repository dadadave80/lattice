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

Not started.

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
