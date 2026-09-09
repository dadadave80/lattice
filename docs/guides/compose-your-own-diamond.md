# Compose your own Diamond

Build a self-governed ERC-4626 vault with one address for the share token, Governor, Timelock,
and upgradeable Diamond. This is the worked example for ENS grant Milestone 2.
The contracts are unaudited. The walkthrough uses local development assets.

## Start from a clean checkout

This draft was tested with Foundry **v1.8.1** (forge, cast, anvil), Git, Bash, jq, and Make.
The example compiles with Solidity 0.8.36. All CI jobs use the shared Foundry v1.8.1 pin.
Install the same release locally with `foundryup --install v1.8.1`.

```sh
git clone --recurse-submodules --branch feat/ens-grant-milestone-2 https://github.com/dadadave80/lattice.git
cd lattice
forge --version
make sizes
make test-v MATCH='GovernedVault(Upgrade)?Test'
make test-grant-runner
```

On an existing checkout, run `git submodule update --init --recursive` first. Run from the repository
root: its remappings define `@lattice/=src/`, `@lattice-script/=script/`, `@lattice-test/=test/`,
`@diamond/=lib/diamond-lib/src/`, and `forge-std/=lib/forge-std/src/`.

To consume as a dependency, use `forge install dadadave80/lattice`, then recursively initialize
submodules. Use `@lattice/=lib/lattice/src/`, `@diamond/=lib/lattice/lib/diamond-lib/src/`, and
`forge-std/=lib/lattice/lib/forge-std/src/`. If importing the supplied deployment scripts, also map
`@lattice-script/=lib/lattice/script/` and `@lattice-test/=lib/lattice/test/` (BaseDeploy's legacy
selector helper lives there). Pin the dependency commit rather than silently updating production recipes.

## Pick modules and reconcile selectors

`script/base/defi/DeployGovernedVault.s.sol` installs 14 facets: ERC165, AccessControl,
TimelockController, ERC20, ERC4626, VaultCore, Votes, ERC20Votes, Governor, GovernedVault,
DiamondLoupeFacet, EmergencyStop, GovernedDiamondCut, and Receive.

The `buildCuts` function reads each facet's `exportSelectors()` and uses `_cutExcept` for deliberate
overlaps. `GovernedVault` reconciles transfers and deposit/mint/withdraw/redeem so voting checkpoints
follow share balances. ERC4626 owns share decimals; VaultCore owns strategy-aware `totalAssets`;
ERC20Votes owns balance-aware delegation; GovernedVault owns the shared name, clock, and ballot nonce
reconciliation. Read the recipe's exclusion lists before swapping a facet. Never register the same
selector twice or replace the vote-aware transfer seam with a plain ERC20 transfer.

## Validate storage owners

`DeployGovernedVault.storageNamespaces()` lists unique ERC-7201 storage owners, including shared
EIP712, Nonces, Diamond, and ERC165 dependencies. `buildCuts` invokes
`DiamondValidationLib.assertNamespacesDisjoint` before deploying facets. The collision regression uses an
overridden namespace list and calls the production `deployAtomic` path; removing its validation makes
the test fail.

This is a **declared namespace** check: it does not discover arbitrary assembly storage. Facets that
intentionally share ERC20/Votes library storage represent one owner. Initializable and the reentrancy
guard use fixed non-ERC-7201 slots and are outside that list. `STORAGE_REGISTRY.md` and
`StorageSlotVerificationTest` document/check the actual constants. The separate storage-layout Action
is a Milestone 3 deliverable tracked in #177; it is not required to run this example.

## Initialize in one transaction

Use `DeployGovernedVault.deployAtomic(params, factory, salt)` with the existing `LatticeFactory`.
The factory creates the proxy and calls `Lattice.initialize` in **one transaction**. The factory binds
CREATE2 salts to the caller; reuse of an occupied caller/salt returns the existing deployment, so use a
new salt for a different recipe. The example creates a fresh factory each run.

The grant's “three-call init dance” is three internal stages, not three public transactions:

1. `Lattice.initialize` enters the `initializer` modifier (`preInitializer`).
2. The cut delegatecalls `GovernedVaultInit.init`, which initializes access, upgrade controls, token,
   checkpoints, vault, timelock, and Governor in dependency order. `address(this)` is the proxy.
3. `postInitializer` closes the window and records initialized version 1.

Recipe init contracts must not add another `initializer` modifier: they execute inside the proxy's
window. Each guarded module init checks that window. An initializer replay reverts. A revert rolls back
the cut and its state; a failed factory call also rolls back proxy creation. The older recipe `run(params)`
uses bare assembly and should not be used for this walkthrough; use the atomic example entrypoint.

## Understand authority

| Identity | Authority |
| --- | --- |
| Diamond itself | Governor token and timelock target; default admin and upgrade executor |
| Shareholder | Deposit, delegate, propose, and vote subject to snapshot/threshold/quorum |
| Anyone | Execute a successful queued proposal once its delay expires |
| Deployer / factory | No permanent upgrade authority over the initialized vault |
| Guardian | None appointed initially; governance may appoint one for emergency controls |

Open execution does not authorize arbitrary calldata: the timelock authenticates the queued operation.
Only the diamond's timelock self-call reaches the upgrade executor role. Voting uses the timestamp
clock; voting delay/period and timelock delay are expressed in seconds. The example uses 60, 600,
and 300 seconds respectively, a zero proposal threshold and 4% quorum. These are demo settings.

## Deploy and upgrade through Make

For a testnet or another EVM-compatible RPC, use a funded encrypted keystore and a Foundry RPC alias
or URL. Verification defaults to Sourcify and does not require an Etherscan API key:

```sh
make example-ens-grant-m2 RPC=sepolia KEYSTORE=my-testnet-wallet
```

This deploys the vault, faucet asset, and upgrade probe, then executes the full governance walkthrough.
An RPC URL works the same way:

```sh
make example-ens-grant-m2 RPC=https://your-evm-rpc.example KEYSTORE=my-testnet-wallet
```

Each invocation starts a fresh example. A partially completed run may need manual recovery.

Public RPC mode waits for the voting clock and block timestamps; it never requests time travel.
The configured 60/600/300-second phases take approximately 16 minutes plus transaction inclusion.
Set `POLL_INTERVAL` (1–60 seconds) and `WAIT_TIMEOUT` (1–86400 seconds per phase) as needed.
Failed receipts or stalled clocks stop subsequent steps.

Deployments enable Sourcify source verification by default. An empty `VERIFIER_URL` uses the provider
default. For another explorer, pass `VERIFIER=blockscout` and
`VERIFIER_URL=https://your-explorer.example/api/`, or another supported Foundry verifier.
Private/development RPCs without an explorer can use `VERIFY=0`; verify public deployments.
The example always uses an open-mint test asset and experimental Registry/Factory contracts.

### Local Anvil

In terminal one:

```sh
make anvil
```

In terminal two, from the checkout root:

```sh
make example-ens-grant-m2 LOCAL=1
```

The Make targets default to `http://127.0.0.1:8545`; set `RPC` or `ANVIL_PORT` for another port.
`LOCAL=1` requires a loopback URL, chain ID 31337, and an Anvil client. It uses the public unlocked
Anvil account and skips explorer verification. It prints VAULT, ASSET, and PROBE addresses, then:

1. Mints 1,000 faucet assets, approves the vault, deposits, and delegates shares to the voter.
2. Builds a `diamondCut` to add `GrantUpgradeProbe.grantVersion` and proposes it to the vault's Governor.
3. Reads the proposal snapshot, advances the Anvil timestamp, votes, and advances past the deadline.
4. Queues the operation, reads its ETA, advances time, and executes through Governor.
5. Checks `grantVersion() == 2` through the proxy and that all deposited assets remain.

Expected final line: `Governed upgrade verified at …; grantVersion() = 2; assets and shares preserved.`
CI starts Anvil and runs `make example-ens-grant-m2 LOCAL=1`, exercising the real Forge/Cast runner
in addition to the mocked failure cases. In public RPC mode the same runner polls instead of advancing time.
The runnable test additionally checks historical voting power, loupe routing, executor identity,
initialization replay, and execution replay. The factory unit suite covers failed initialization rollback.

## Optional public testnet / ENS reference

The root README's “Live testnet deployment” section and `PROGRESS.md` retain the verified Milestone 1
Sepolia vault and its ENS name. `DeployGovernedVaultENS.buildCutsWithENS` composes the additional
ENSReverseClaimer facet and combined initializer; send those cuts through `LatticeFactory.deploy` for
atomic creation. Add the ENSReverseClaimer storage owner to preflight for your extended composition.
Configure the chain's reverse registrar and ensure the name owner sets the matching forward record.

For the standalone non-ENS example on Sepolia, import your wallet into an encrypted Foundry keystore,
configure the RPC alias, then run:

```sh
make example-ens-grant-m2 RPC=sepolia KEYSTORE=YOUR_KEYSTORE
```

Use only test assets. Omit `LOCAL=1` on public networks; use keystore authentication and verification.

## Compose a different module or upgrade

Keep the same recipe pattern: add the facet's exported selectors, reconcile intentional overlaps, add
its distinct storage owner, and run its module initializer in dependency order. Do not grow an
inheritance mega-facet past the deployment size limit. For an existing-state upgrade, preserve storage
compatibility or implement and test an explicit migration before proposing the cut through Governor.
Fresh pre-major deployments may use intentionally breaking layouts; document that deployment choice
and update the reviewed baseline. If a cut runs a new initializer, use a strictly
increasing reinitializer version; never rerun the original init or overwrite existing user state.

## Troubleshooting

| Failure | Check |
| --- | --- |
| Import/file not found | Recursive submodules and project-root remappings |
| Selector already exists | `_cutExcept` reconciliation and no exported introspection selector |
| NamespaceCollision | Duplicate owners in the declared namespace list |
| InvalidInitialization / NotInitializing | Single outer guard and correct init dependency order |
| Zero votes / threshold failure | Deposit, delegate, then move past the checkpoint before proposing |
| Defeated proposal | Voting window, delegation at snapshot, and quorum |
| Timelock operation not ready | Queue first; execute strictly after the reported ETA |
| Stale storage snapshot | Run the local update command and review compatibility with the prior baseline |

The documentation site and reusable guard are separate Milestone 3 work tracked in
[#177](https://github.com/dadadave80/lattice/issues/177).
