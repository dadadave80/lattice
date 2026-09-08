# Lattice quickstart

Lattice composes stateless facets and ERC-7201 library storage into a governance-upgradeable Diamond.
Start with the [composition guide](compose-your-own-diamond.md) and its real-proxy Foundry example.

```sh
git clone --recurse-submodules https://github.com/dadadave80/lattice.git
cd lattice
forge test --match-contract 'GovernedVault(Upgrade)?Test' -vv
```

The guide also provides an Anvil transaction walkthrough. Generated API reference appears below the
guides in the navigation. These contracts are unaudited; use local/testnet assets while evaluating.

To check storage snapshots locally:

```sh
./script/upgrades/check-storage-layout.sh
./script/upgrades/check-storage-layout.sh --baseline-ref YOUR_TRUSTED_RELEASE_COMMIT
```

The first command checks snapshot drift only. The second additionally checks compatibility with the
trusted prior snapshot. See the [storage Action guide](storage-action.md) for external consumption,
coverage boundaries, and baseline updates.
