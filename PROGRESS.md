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
| Verified diamond (Sepolia) | [`0x7a498c34A8Dc3B6502889C21218Da0F8696b7bb6`](https://sepolia.etherscan.io/address/0x7a498c34a8dc3b6502889c21218da0f8696b7bb6#code) — all 14 facets verified, full list in the [README deployment section](README.md#live-testnet-deployment-sepolia) |
| Primary ENS name (forward + reverse) | [`milestone1vault.lattice.studio.eth`](https://sepolia.app.ens.domains/milestone1vault.lattice.studio.eth) |
| Governance lifecycle executed on-chain | [`ProposalExecuted` tx `0xfba2c5…df64`](https://sepolia.etherscan.io/tx/0xfba2c57a3063883b43edb905fabcbe508c3ff9d3f0447d2d58fa2739c832df64) — proposal froze the loupe/cut selectors and reasserted the ENS name via the diamond's own Governor + TimelockController |
| Deploy broadcast log | [`broadcast/DeployGovernedVaultENS.s.sol/11155111/run-latest.json`](broadcast/DeployGovernedVaultENS.s.sol/11155111/run-latest.json) |
| Governance-demo broadcast log | [`broadcast/DeployGovernedVaultENS.s.sol/11155111/governanceDemo-latest.json`](broadcast/DeployGovernedVaultENS.s.sol/11155111/governanceDemo-latest.json) |
| ENS registration broadcast log | [`broadcast/RegisterEnsName.s.sol/11155111/register-latest.json`](broadcast/RegisterEnsName.s.sol/11155111/register-latest.json) |
| One-command reproduce | [README deployment section](README.md#live-testnet-deployment-sepolia) |
| Community files | [`LICENSE`](LICENSE) · [`SECURITY.md`](SECURITY.md) · [`CONTRIBUTING.md`](CONTRIBUTING.md) |

Tag: `grant-m1` — created on `main` when this evidence is promoted from `dev`.

## Milestone 2 — Worked integration example + composition guide

Draft implementation for [#173](https://github.com/dadadave80/lattice/issues/173), split from the
reverted combined PR #174. Not accepted or released.

- [Composition guide](docs/guides/compose-your-own-diamond.md) and [RPC example](examples/governance-upgradeable-diamond/README.md).
- `make example RPC=<alias-or-URL> KEYSTORE=<name>` deploys and runs the full governance example
  with real-clock polling. Local Anvil acceleration requires `LOCAL=1`.
- [Canonical upgrade test](test/unit/GovernedVaultUpgradeTest.t.sol) exercises the factory deployment path.
- Review, fresh validation, accepted commit permalinks, public CI evidence, and the authorized
  `grant-m2` tag remain outstanding. Historical combined-branch runs do not complete this milestone.

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
| Broadcast evidence | [`broadcast/multi/`](broadcast/multi) (multichain setups) · [`broadcast/CCTPHookDemo.s.sol/84532/`](broadcast/CCTPHookDemo.s.sol/84532) (hook relay) · [`broadcast/CCTPUSDCDemo.s.sol/`](broadcast/CCTPUSDCDemo.s.sol) (transfer relays) |
| One-command reproduce | `make demo-cctp` · `make demo-cctp-hook KEYSTORE=<name>` — see the [README demo section](README.md#live-cross-chain-usdc-demos-circle-cctp-v2--arc-testnet) |
