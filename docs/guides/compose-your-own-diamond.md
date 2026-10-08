# Compose your own Diamond

Build a self-governed ERC-4626 vault with one address for the share token, Governor, Timelock,
and upgradeable Diamond. This is the worked example for ENS grant Milestone 2.
The contracts are unaudited. The walkthrough uses local development assets.

## Start from a clean checkout

The `grant-m2` tag was tested with Foundry **v1.8.1** (forge, cast, anvil), Git, Bash, jq, and Make, and it
also passes on v1.8.5. The example compiles with Solidity 0.8.36. Install the tag's release locally with
`foundryup --install v1.8.1`.

```sh
git clone --recurse-submodules --branch grant-m2 https://github.com/dadadave80/lattice.git
cd lattice
forge --version
make sizes
forge test --match-contract 'GovernedVault(Upgrade)?Test' -vvv
make test-grant-runner
```

Expected:
- `make sizes` lists every contract with a positive runtime margin.
- The `forge test` line reports `13 tests passed, 0 failed` across `GovernedVaultTest` (6) and
  `GovernedVaultUpgradeTest` (7).
- `make test-grant-runner` exits 0.

Call `forge test` directly, as above. At the tag, `make test MATCH=<regex>` passes the pattern to the shell
unquoted, so a regex containing parentheses fails with a shell syntax error.

On an existing checkout, run `git submodule update --init --recursive` first. Run from the repository
root: its remappings define `@lattice/=src/`, `@lattice-script/=script/`, `@lattice-test/=test/`,
`@diamond/=lib/diamond-lib/src/`, and `forge-std/=lib/forge-std/src/`.

To consume as a dependency, follow the [README install steps](../../README.md#install--usage): install
a release tag with `forge install dadadave80/lattice@vX.Y.Z`, then commit it straight away with
`git add lib/lattice .gitmodules foundry.lock && git commit`. `forge install` checks out the nested
submodules itself; a `git submodule update` before that commit can move `lib/lattice` off the tag. No
remappings are needed, because Forge derives them from `lib/lattice/remappings.txt`. If you keep your own,
use `@lattice/=lib/lattice/src/`, `@diamond/=lib/lattice/lib/diamond-lib/src/`, and
`forge-std/=lib/forge-std/src/`. If importing the supplied deployment scripts, also map
`@lattice-script/=lib/lattice/script/` and `@lattice-test/=lib/lattice/test/` (BaseDeploy's legacy
selector helper lives there). Pin a release tag rather than silently updating production recipes.

## Pick modules and reconcile selectors

`script/base/defi/DeployGovernedVault.s.sol` installs 14 facets: ERC165, AccessControl,
TimelockController, ERC20, ERC4626, VaultCore, Votes, ERC20Votes, Governor, GovernedVault,
DiamondLoupeFacet, EmergencyStop, GovernedDiamondCut, and Receive.

The `buildCuts` function reads each facet's `exportSelectors()` and uses `_cutExcept` for deliberate
overlaps. `GovernedVault` reconciles transfers and deposit/mint/withdraw/redeem so voting checkpoints
follow share balances. ERC4626 owns share decimals; VaultCore owns strategy-aware `totalAssets` and the
deposit-latch-aware `maxDeposit`/`maxMint` (exclude both from ERC4626 or Replace them);
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
The factory creates the proxy and calls `Lattice.initialize` in **one transaction**. This matters
because `initialize` is first-caller-wins. A proxy that is deployed in one transaction and initialized in a
later one can be front-run: anyone who sees the deployment can call `initialize` first with their own cut
and take the diamond. The factory binds
CREATE2 salts to the caller; reuse of an occupied caller/salt returns the existing deployment, so use a
new salt for a different recipe. The example creates a fresh factory each run.

The grant's “three-call init dance” is three internal stages, not three public transactions:

1. `Lattice.initialize` enters the `initializer` modifier (`preInitializer`).
2. The cut delegatecalls `GovernedVaultInit.init`, which initializes access, upgrade controls, token,
   checkpoints, vault, timelock, and Governor in dependency order. `address(this)` is the proxy.
3. `postInitializer` closes the window and records initialized version 1.

Recipe init contracts must not add another `initializer` modifier: they execute inside the proxy's
window. Each guarded module init checks that window. An initializer replay reverts. A revert rolls back
the cut and its state; a failed factory call also rolls back proxy creation. `run(params)` also deploys
through `LatticeFactory` in one transaction; `deployAtomic` additionally lets you choose the factory and salt.

## Understand authority

| Identity | Authority |
| --- | --- |
| Diamond itself | Governor token and timelock target; default admin and upgrade executor |
| Shareholder | Deposit, delegate, propose, and vote subject to snapshot/threshold/quorum |
| Anyone | Execute a successful queued proposal once its delay expires |
| Deployer / factory | No permanent upgrade authority over the initialized vault |
| Guardian | None appointed initially; governance may appoint one for emergency controls. Trusted for governance liveness (see below) |

Open execution does not authorize arbitrary calldata: the timelock authenticates the queued operation.
In this recipe only the diamond's timelock self-call reaches the upgrade executor role. The role is held by the
diamond itself, so a facet that lets an outside key make the diamond call itself, such as a co-cut
AccessManager, would reach it too (see [Composition hazards](#composition-hazards)). Voting uses the timestamp
clock; voting delay/period and timelock delay are expressed in seconds. The example uses 60, 600,
and 300 seconds respectively, a zero proposal threshold and 4% quorum. These are demo settings.

A guardian's `emergencyRemoveCut` can only remove selectors. It can never remove `diamondCut` itself,
the selectors needed to recover from an emergency stop (`emergencyResume`, `removeGuardian`,
`revokeRole`), or a frozen selector. Nothing is frozen at init, so a guardian can still remove an
unfrozen Governor or Timelock function a proposal needs, leaving `diamondCut` unreachable. Treat the
guardian as trusted for governance liveness, or have the first proposal freeze
`DeployGovernedVault.recommendedFreezeSelectors()`. With that path frozen, a guardian that trips the
stop can only delay: a proposal resumes the vault and the next one upgrades it.
Freezing is permanent: governance can never replace or remove a frozen selector afterwards.
`GovernedVaultUpgradeTest.test_GuardianTrustedForLivenessUntilFrozen` and
`test_RecommendedFreezeBoundsGuardian` pin both cases.

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

ENS ties the milestones together. The Milestone 1 vault is ENS-named, and so is the shared Sepolia
`LatticeFactory` (`factory.lattice.studio.eth`), both through the ENSReverseClaimer facet. The ENS variant
of this example is the same composition plus that one facet: `DeployGovernedVaultENS.buildCutsWithENS`
adds ENSReverseClaimer and a combined initializer that replays the base init sequence. Send those cuts
through `LatticeFactory.deploy` for atomic creation. `PROGRESS.md` records the verified Milestone 1 vault
and its ENS name; the root README's “Live deployments and demos” section has the reproduce command.

On `dev` and `main` after the `grant-m2` tag, `buildCutsWithENS` also runs the namespace preflight over
`storageNamespacesWithENS()`, which is the base list plus `lattice.storage.ENSReverseClaimer`. At the tag,
add that owner to your own preflight. Configure the chain's reverse registrar, and make sure the name owner
sets the matching forward record.

For the standalone non-ENS example on Sepolia, import your wallet into an encrypted Foundry keystore and
set `SEPOLIA_RPC_URL` (copy `.env.example` to `.env`; the `sepolia` alias reads it). On macOS, `KEYSTORE`
reads the keystore password from the login Keychain item `foundry-<name>`; add it once with
`security add-generic-password -a "$USER" -s foundry-<name> -w`. Other systems prompt for the password.
Then run:

```sh
make example-ens-grant-m2 RPC=sepolia KEYSTORE=YOUR_KEYSTORE
```

Use only test assets. Omit `LOCAL=1` on public networks; use keystore authentication and verification.

## Compose a different module or upgrade

The same four steps build any composition. A worked example, an admin-upgradeable capped ERC-20, lives in
[`test/integration/ComposeYourOwnDiamondTest.t.sol`](https://github.com/dadadave80/lattice/blob/dev/test/integration/ComposeYourOwnDiamondTest.t.sol), so CI keeps it compiling. It was added after the
`grant-m2` tag, so read it on `dev` or `main`.

1. **Pick modules.** Cut each facet for its own exported selectors. These facets share no selector, so no
   `_cutExcept` is needed; the vault recipe above shows that case. Leave out `Receive` unless the diamond
   must accept plain (empty-calldata) native sends: it holds native value, or something pays it back
   with a plain send. Forwarding `msg.value` from a payable call, as the bridge adapters do, does not
   need it. The vault cuts it because its timelock spends ETH; a token does not, so without it a plain ETH
   send reverts instead of being locked.

   ```solidity
   cuts[0] = _cut(address(new ERC165Facet()));
   cuts[1] = _cut(address(new AccessControl()));
   cuts[2] = _cut(address(new AccessControlDiamondCut())); // upgrades gated on DEFAULT_ADMIN_ROLE
   cuts[3] = _cut(address(new DiamondLoupeFacet()));
   cuts[4] = _cut(address(new ERC20()));
   cuts[5] = _cut(address(new ERC20Capped()));
   ```

2. **Declare every storage owner, including transitive ones,** and validate them before deploying. The cut
   facet calls `EmergencyStopLib.checkNotStopped`, so EmergencyStop storage is an owner even though no
   EmergencyStop facet is cut.

   ```solidity
   ids[0] = "diamond.lib.storage";
   ids[1] = "diamond.lib.storage.ERC165";
   ids[2] = "lattice.storage.AccessControl";
   ids[3] = "lattice.storage.EmergencyStop";
   ids[4] = "lattice.storage.ERC20";
   ids[5] = "lattice.storage.ERC20Capped";
   // in buildCuts, before any facet is deployed:
   DiamondValidationLib.assertNamespacesDisjoint(storageNamespaces());
   ```

3. **Write one initializer** that runs the module inits in dependency order. It opens no window of its own.

   ```solidity
   AccessControlLib.__AccessControl_init(p.admin);           // authority first
   ERC165Lib.registerInterface();                             // IERC165's own ERC-165 flag
   DiamondLib.registerInterface();                            // cut + loupe ERC-165 flags
   ERC20Lib.__ERC20_init(p.name, p.symbol);                   // the token
   ERC20CappedLib.__ERC20Capped_init(p.cap);                  // then its cap
   ERC20CappedLib._checkCap(ERC20Lib.totalSupply() + p.supply);
   ERC20Lib._mint(p.holder, p.supply);                        // seed supply last
   ```

4. **Deploy in one transaction** with `factory.deploy(new RecipeEntry[](0), cuts, init, data, salt)`.

The test also shows a later upgrade: the admin cuts `ERC20Burnable` in with `diamondCut`, and a stranger's
attempt reverts. For governed upgrades, cut GovernedDiamondCut and EmergencyStop instead of
AccessControlDiamondCut, and wire Governor and the timelock as `GovernedVaultInit` does.

Do not grow an inheritance mega-facet past the deployment size limit. For an existing-state upgrade, preserve storage
compatibility or implement and test an explicit migration before proposing the cut through Governor.
Fresh pre-major deployments may use intentionally breaking layouts; document that deployment choice
and update the reviewed baseline. If a cut runs a new initializer, use a strictly
increasing reinitializer version; never rerun the original init or overwrite existing user state.

## Composition hazards

Every facet in a diamond runs as one contract at one address, with one balance. Modules ported from standalone
OpenZeppelin contracts assume they are alone there. These hazards follow from that. No shipped recipe hits one,
and a selector clash reverts at cut time. The authority, override and custody rows do not revert: the diamond
deploys, then misbehaves. Each row's core case is pinned by a test that fails if the behaviour changes
([#240](https://github.com/dadadave80/lattice/issues/240)): the guardian row by `GovernedVaultUpgradeTest`, the
others by [`CompositionHazardsTest`](../../test/composability/CompositionHazardsTest.t.sol), with every shared
selector also covered by `SelectorCompatibilityTest`. The ERC20Wrapper and ShieldedPool custody effects are
documented, not tested: the base wrapper facet does not expose `recover`.

| Hazard | Modules | Effect | Recommended layout |
| --- | --- | --- | --- |
| One in-diamond ERC-7786 handler per link diamond | BridgeERC20, BridgeERC7802, ERC20Crosschain, CrosschainTimelockHandler | All four export `processMessage` (`0x902d5027`), and CrosschainLink calls that selector for every tag. A second handler facet reverts the cut | One handler facet per link diamond. Route other tags to an external handler contract or a second link diamond |
| One price adapter per diamond | The eight price adapters (Chainlink, Pyth, API3, Band, Chronicle, DIA, RedStone, Tellor) | They share `getFeed`, `latestAnswer` and `unregisterFeed` over separate storage. A second adapter reverts the cut | One adapter per diamond; put each extra source in its own diamond |
| Standard-imposed clashes | ERC20 and ERC721; ERC721 and ERC1155 | Same selector, different meaning and storage (`balanceOf`, `approve`, `transferFrom`, `setApprovalForAll`, ...). The cut reverts | One token standard per diamond |
| Lattice-chosen clashes | `getConfig()` on the randomness and automation adapters; `getForwarder()` on Chainlink Automation and CRE; the GovernedSafeDiamondCut operation views and TimelockController; `owner()` on AccountSigner and OwnableFacet; `token()` on Governor and the bridges | Same name, different return type or meaning. The cut reverts | Do not combine them. The names are listed in the [matrix](selector-compatibility.md), not renamed |
| One ERC-20 movement-replacing extension per diamond, and no direct mover or minter beside it or beside a cap ([D25](selector-compatibility.md#token-extension-hook-model)) | ERC20Pausable, ERC20Votes, GovernedVault; the mint-gating ERC20Capped; the direct movers ERC20Burnable, ERC20FlashMint, ERC20Crosschain, ERC20Wrapper, ERC7802, ERC4626, VaultCore | Each family member replaces `transfer`/`transferFrom`. `Add` reverts; a `Replace` is silent and drops the other's logic. Pausable over Votes stops moving votes, so delegated votes can exceed supply. Votes over Pausable ignores the pause. A direct mover shares no selector, so the cut succeeds, but its mints and burns skip the pause and the vote checkpoints. ERC20Capped's cap holds only on a composing facet's `_mint`, so every direct minter lifts the supply past it | Pick one family member. Mint and burn only through a facet that applies its logic: `PausableLib.checkNotPaused` before `ERC20Lib._mint`/`_burn`, `ERC20VotesLib._mint`/`_burn`, or `ERC20CappedLib._checkCap` before the mint. For more, write a combined facet the way GovernedVault reconciles ERC4626, VaultCore and ERC20Votes |
| One ERC-1155 burn path per diamond (D25) | ERC1155Burnable, ERC1155Pausable, ERC1155Supply | Each serves `burn`/`burnBatch`: plain, pause-gated or supply-tracking. `Add` reverts; a `Replace` is silent and drops the other's logic. Supply over Pausable or Burnable over Pausable burns while paused. Pausable over Supply burns without lowering `totalSupply`. Mints have no shared facet: a mint facet that calls `ERC1155Lib` directly ignores the pause and the supply counters, and a later supply-tracking burn wraps the unchecked subtraction (as does cutting ERC1155Supply into a diamond that already holds balances) | Pick one. Mint through `ERC1155PausableLib` or `ERC1155SupplyLib`; to combine pause and supply, write a combined facet and mint path |
| One ERC-721 movement override per diamond (D25) | ERC721Enumerable, ERC721Pausable, ERC721Votes | Each replaces `transferFrom` and both `safeTransferFrom` overloads. `Add` reverts; a `Replace` is silent and drops the other's logic: Pausable over Enumerable stops updating the lists, Enumerable over Pausable ignores the pause | Pick one |
| ERC-721 burns and wraps skip movement overrides (D25) | ERC721Burnable, ERC721Wrapper, or any app facet calling `ERC721Lib._mint`/`_burn`/`_transfer`, next to ERC721Enumerable, ERC721Votes or ERC721Pausable | `burn`, `depositFor`, `withdrawTo` and `onERC721Received` move tokens through `ERC721Lib`, which has no hook. Next to Enumerable they desync `totalSupply` and the owner lists, next to Votes they leave delegated votes above the supply, and next to Pausable they still run while paused. No selector is shared, so the cut succeeds | Never cut Burnable or Wrapper next to Enumerable or Votes; mint, burn and do authorization-free transfers through `ERC721EnumerableLib` or `ERC721VotesLib` (`_mint`, `_burn`, `_transfer`, `_safeTransfer`), never `ERC721Lib`. The standalone `CCTPHookReceipt` example mints through `ERC721Lib._mint`; a fork of it that adds enumeration or votes must switch that mint. Next to Pausable, accept that burns and wraps ignore the pause, or gate your own burn facet with `PausableLib.checkNotPaused` |
| A co-cut AccessManager is root | AccessManager next to anything that trusts `address(this)`: GovernedDiamondCut, TimelockController, Governor, the ERC-7786 handlers | `execute(address(this), data)` calls the diamond as the diamond. Selectors default to ADMIN_ROLE, so its holder can `diamondCut` with no vote or delay, or call `processMessage` directly | Keep AccessManager in its own authority diamond, as `DeployAccessManager` does. To govern it, make the governed diamond that authority's initial admin. A co-cut manager whose admin is its own diamond can never be configured |
| One custodian per asset | VestingWallet, ERC4626 (and VaultCore), ERC20Wrapper, BridgeERC20, ShieldedPool | Each counts or holds the diamond's whole `balanceOf(address(this))`. VestingWallet next to an ERC-4626 vault pays the depositors' assets to its beneficiary through its open `release`. A vault next to bridge or pool escrow prices the escrow into its shares | At most one module that holds a given asset per diamond |
| Guardian is trusted for liveness (D10) | GovernedDiamondCut, EmergencyStop, Governor, TimelockController | Until governance freezes the proposal path, a guardian can remove a Governor or Timelock selector and leave `diamondCut` unreachable | Freeze `DeployGovernedVault.recommendedFreezeSelectors()` in the first proposal (see [Understand authority](#understand-authority)) |

`DiamondValidationLib.assertNamespacesDisjoint` catches two modules that declare the same storage namespace. It
does not catch two modules that share an asset or a trust assumption.

**The AccessManager row is Lattice behaviour, not a port bug.** OpenZeppelin's AccessManager runs
`execute(address(this), ...)` through the same admin restrictions, but a standalone manager has no other
functions behind `address(this)`. Refusing self-targeted calls would not protect funds, because the admin can
already `execute` a transfer on any token the diamond holds; it would only close the governance bypass, and it
would break a same-diamond AccessManaged facet that uses delayed execution with the diamond as its authority. Lattice does not add that
guard today (decision D11 on [#219](https://github.com/dadadave80/lattice/issues/219)). The shipped
`DeployAccessManager` admin overload is safe: its diamond holds no AccessControl role, so the self-call cannot
pass `AccessControlDiamondCut`. A test pins that too.

**Selector matrix.** [`selector-compatibility.md`](selector-compatibility.md) lists every selector that two or
more release facets export, classified as variant, override, identical, one per diamond or incompatible.
`SelectorCompatibilityTest` generates it and fails on any new clash.

## Troubleshooting

| Failure | Check |
| --- | --- |
| Import/file not found | Recursive submodules and project-root remappings |
| Selector already exists | `_cutExcept` reconciliation, no exported introspection selector, and the [selector matrix](selector-compatibility.md) |
| NamespaceCollision | Duplicate owners in the declared namespace list |
| InvalidInitialization / NotInitializing | Single outer guard and correct init dependency order |
| Zero votes / threshold failure | Deposit, delegate, then move past the checkpoint before proposing |
| Defeated proposal | Voting window, delegation at snapshot, and quorum |
| Timelock operation not ready | Queue first; execute strictly after the reported ETA |
| Stale storage snapshot | Run `make storage-update` and review the baseline diff against the prior release |

The documentation site and reusable guard are separate Milestone 3 work tracked in
[#177](https://github.com/dadadave80/lattice/issues/177).
