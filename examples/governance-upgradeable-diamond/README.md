# Governance-upgradeable Diamond

The executable example reuses the production `DeployGovernedVault` recipe and `LatticeFactory`.

```sh
git submodule update --init --recursive
forge test --match-contract 'GovernedVault(Upgrade)?Test' -vv
```

The canonical test is `test/unit/GovernedVaultUpgradeTest.t.sol`. It proves namespace preflight,
one-time initialization, the real proxy's governed cut, timelock/replay rejection, and state preservation.
The companion integration suite tests quorum and the vault's self-governed wiring.

For actual local transactions, start `anvil` in another terminal, then run:

```sh
./examples/governance-upgradeable-diamond/run-local.sh
```

This uses Anvil's public unlocked development account and refuses other chain IDs.
The factory creates and initializes the proxy atomically. The script then deposits, delegates,
proposes a new facet, votes, queues, advances local time, executes, and checks the result.

See [Compose your own Diamond](../../docs/guides/compose-your-own-diamond.md).
