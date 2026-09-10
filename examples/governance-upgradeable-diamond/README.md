# Governance-upgradeable Diamond

Milestone 2 uses the existing `DeployGovernedVault` recipe and experimental `LatticeFactory`.
Run everything from the repository root through Make. Install Foundry v1.8.1, Git, Bash, jq, and Make.

```sh
make install
make test MATCH='GovernedVault(Upgrade)?Test'
make test-grant-runner
```

## Testnet or another EVM RPC

Use a funded test wallet in a Foundry encrypted keystore. `RPC` accepts a configured Foundry alias
(such as `sepolia`) or an RPC URL. Source verification defaults to Sourcify, without an Etherscan API key.
Existing `KEYSTORE` authentication uses the project's Keychain helper on
macOS; on other platforms, Foundry prompts for the password.

One command deploys the vault, open-mint **test asset**, and upgrade probe, then runs the entire example:

```sh
make example-ens-grant-m2 RPC=sepolia KEYSTORE=my-testnet-wallet
```

Or supply an RPC URL:

```sh
make example-ens-grant-m2 RPC=https://your-evm-rpc.example KEYSTORE=my-testnet-wallet
```

The walkthrough mints and deposits 1,000 test assets, delegates, proposes, votes, queues, waits,
executes the upgrade, and checks that the new facet works with assets and shares preserved. On a
public network it **waits for real blocks**: 60-second voting delay, 600-second voting period, and
300-second timelock, plus transaction inclusion time. `POLL_INTERVAL=5` controls polling;
`WAIT_TIMEOUT=3600` bounds each wait. A stalled clock or failed transaction stops the script.
Each invocation starts a fresh example; a partially completed run may need manual recovery.

Deployment enables `--verify --verifier sourcify` by default. Set `VERIFIER_URL` only for a custom
endpoint; an empty value uses the provider default. For a Blockscout explorer:

```sh
make example-ens-grant-m2 RPC=https://your-evm-rpc.example KEYSTORE=my-testnet-wallet \
  VERIFIER=blockscout VERIFIER_URL=https://your-explorer.example/api/
```

`VERIFY=0` is available for private/development RPCs without an explorer. Verify public deployments.
The sample asset has an unrestricted faucet; this is an experimental demonstration, not a production
asset/vault configuration. An arbitrary RPC still needs compatible EVM execution and sufficient gas.

## Local Anvil

In one terminal:

```sh
make anvil
```

In another:

```sh
make example-ens-grant-m2 LOCAL=1
```

`LOCAL=1` uses the public unlocked Anvil account, skips explorer verification, and advances local time.
It requires a loopback URL, chain ID 31337, and an Anvil client. For another port, use
`make anvil ANVIL_PORT=8547` and `make example-ens-grant-m2 LOCAL=1 ANVIL_PORT=8547`.
Without `LOCAL=1`, the runner never invokes time-travel RPC methods, even on a local endpoint.

The canonical Solidity test is `test/unit/GovernedVaultUpgradeTest.t.sol`; the runner is `run.sh`.
See [Compose your own Diamond](../../docs/guides/compose-your-own-diamond.md) for composition and authority.
