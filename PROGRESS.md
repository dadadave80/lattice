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

Not started.

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
| Hook demo — Arc hub diamond | [`0x3446dC6de6373a139405A524085fdfB52ABfFe1c`](https://testnet.arcscan.app/address/0x3446dC6de6373a139405A524085fdfB52ABfFe1c) (Sourcify-verified) |
| Hook demo — Base destination diamond | [`0x3E10c69c1e9b22325d556E1c9e4Db681a9E63b73`](https://base-sepolia.blockscout.com/address/0x3E10c69c1e9b22325d556E1c9e4Db681a9E63b73) |
| Auto-credit vault | [`0xD23D22c807eB95993f7FEf4d0349CB89643Daf1A`](https://base-sepolia.blockscout.com/address/0xD23D22c807eB95993f7FEf4d0349CB89643Daf1A) |
| Programmable-USDC delivery, one tx | burn [`0x45071a…5ac39`](https://testnet.arcscan.app/tx/0x45071a3ebec12e51ad2e41d6a7262995781a7595770c8e76ab6e81583da5ac39) → relay [`0xc41fbe…badfc`](https://base-sepolia.blockscout.com/tx/0xc41fbea24e4dcf810c3d4aaf8efda138037a03b07d44f8ee14a58e5aafabadfc) minted to the vault **and** emitted `Credited(0x11Cf…C00, 1000000, 26, hub)` |
| Real-attestation replay (reproducible) | [`test/fork/CCTPHookDemoFork.t.sol`](test/fork/CCTPHookDemoFork.t.sol) replays the captured [Iris fixture](test/fixtures/cctp/arc-to-base-hook-v2.json) through the live Base diamond on a pinned fork — credits exactly 1 USDC, second relay reverts (nonce consumed) |
| Broadcast evidence | [`broadcast/multi/`](broadcast/multi) (multichain setups) · [`broadcast/CCTPHookDemo.s.sol/84532/`](broadcast/CCTPHookDemo.s.sol/84532) (hook relay) · [`broadcast/CCTPUSDCDemo.s.sol/`](broadcast/CCTPUSDCDemo.s.sol) (transfer relays) |
| One-command reproduce | `make demo-cctp` · `make demo-cctp-hook KEYSTORE=<name>` — see the [README demo section](README.md#live-cross-chain-usdc-demos-circle-cctp-v2--arc-testnet) |
