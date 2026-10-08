# Security Policy

Lattice is **unaudited, pre-1.0 software.** It re-implements and adapts
established contracts (OpenZeppelin, Solady, Uniswap V2, Yearn V3) into the
EIP-2535 Diamond facet pattern, but it has **not** received an independent
security audit. Do not deploy it to mainnet with funds at risk without your own
review. [Review evidence](#review-evidence) lists what has been checked so far.

## Supported versions

Lattice is pre-1.0. Only the latest tagged release is supported: fixes land on
the development branch (`dev`) and ship in the next release. Older 0.x releases
receive no backports. See
[Versioning and compatibility](README.md#versioning-and-compatibility) for what
a minor or patch release may change.

## Scope

| Path | Status |
| --- | --- |
| `src/**`, except `src/examples/**` | In scope |
| `script/base/**` (recipe deploy scripts and their one-transaction init rule) | In scope |
| `script/deploy/**`, `script/lib/**` (release and factory deployment) | Reports welcome; in scope once a canonical release deployment exists |
| `src/examples/**`, `test/**`, the testnet demos and their scripts | Reports welcome; not production code |
| `lib/**` (submodules) | Report to the upstream project; tell us if Lattice is affected |

Vendored and ported code is listed in [`lib/VENDORED.md`](lib/VENDORED.md). A
bug inherited from an upstream source is still worth reporting here, since the
Lattice copy may not receive the upstream fix.

## Reporting a vulnerability

**Please do not open public issues, pull requests, or discussions for security
vulnerabilities.**

Report privately through GitHub's private vulnerability reporting:
**Security → Report a vulnerability** on
<https://github.com/dadadave80/lattice>. This opens an advisory visible only to
the maintainer.

If private reporting is unavailable, contact the maintainer (daveproxy80.eth) to
arrange a disclosure channel before posting any details publicly.

<!-- MAINTAINER: add a direct security email -->

A useful report names the affected module, the commit or release tag, and a
reproduction, ideally a failing Foundry test.

## Response

As a solo-maintained project, responses are best-effort. The targets are:

- **Acknowledgement** within 7 days of the report.
- **Initial assessment** (accepted, needs more information, or declined) within
  14 days.
- **Fix** on `dev` as soon as practical, in the next release.

Please allow reasonable time for a fix before public disclosure (90 days is a
good default). Reporters who follow coordinated disclosure will be credited
unless they prefer to remain anonymous.

## Bug bounty

Lattice has **no bug bounty** and offers no payment for reports.

## Advisories and fix announcements

A vulnerability in a tagged release is published as a
[GitHub Security Advisory](https://github.com/dadadave80/lattice/security/advisories)
once a fixed release is out. The fix is also listed in the
[changelog](CHANGELOG.md), which says when a fresh deployment is required.
Bugs found and fixed before they reach a release are handled as ordinary
issues.

## Safe Harbor

Lattice holds no funds and has not adopted the
[SEAL Whitehat Safe Harbor agreement](https://github.com/security-alliance/safe-harbor).
The `SafeHarborAdopter` facet lets a diamond adopt it, but each adopting
deployment publishes and maintains its own agreement. The facet covers only the
on-chain steps: creating the agreement and registering it. SEAL also asks the
adopting protocol to publish a fact page, add the agreement's Exhibit D to its
terms of service, and make the registry call from its decision-making
authority; see SEAL's repository for the current steps.

## Known issues

### Fixed on `dev`, shipping in 0.5.0

These are the P0 and P1 contract bugs from the 2026-09 hardening pass
([#213](https://github.com/dadadave80/lattice/issues/213)), all present in
released versions. Lower-priority fixes are tracked in #213 and will be listed
in the 0.5.0 changelog. Deployed diamonds keep the vulnerable facets until they
cut in the 0.5.0 ones. Each item names the regression tests that replay the
original attack against the fixed code; run one with
`forge test --mt <test name>`. The linked issue has the full reproduction.

- **AccessManager / AccessManaged, v0.1.0 to v0.4.0: fail-open.** Do not use
  these releases to gate anything.
  - `AccessManager.execute` set a persistent "consuming" flag on the managed
    target, and `restrictedCheck` let every caller through while it was set.
    Migrating a target with `execute(target, setAuthority(x))` left the flag
    set for good, and a restricted function that called out could be re-entered
    by anyone during an `execute`
    ([#215](https://github.com/dadadave80/lattice/issues/215), fixed in
    [#267](https://github.com/dadadave80/lattice/pull/267)). Reproduce with
    `test_MigrationViaExecuteDoesNotLeaveTargetOpen` and
    `test_PublicRoleExecuteCalleeCannotReenterAdminFunction` in
    [`AccessManagedTest`](test/unit/AccessManagedTest.t.sol).
  - The manager did not enforce a target's admin delay on
    `setTargetFunctionRole` or `setTargetClosed`, nor a role admin's execution
    delay on `grantRole`/`revokeRole`
    ([#219](https://github.com/dadadave80/lattice/issues/219), fixed in
    [#280](https://github.com/dadadave80/lattice/pull/280)). Reproduce with the
    `test_AdminDelay_*` and `test_RoleAdminDelay_*` tests in
    [`AccessManagerTest`](test/unit/AccessManagerTest.t.sol).

  The fixes follow OpenZeppelin v5 semantics and change the ERC-165 interface
  IDs: `IAccessManager` goes from `0x8fc52f86` to `0x03fde054` and
  `IAccessManaged` from `0xe5b444fd` to `0x4a531f33`.
- **ERC-4626 vaults with strategies, v0.1.0 to v0.4.0: shares priced on idle
  assets.** `ERC4626Lib` priced every conversion, preview and mutator on the
  vault's own asset balance, not VaultCore's full NAV. Once a StrategyManager
  allocated funds, redeemers received only the idle share of their value and
  depositors minted cheap shares at holders' expense; `rebalance()` is
  permissionless, so anyone could move the price around their own deposit
  ([#214](https://github.com/dadadave80/lattice/issues/214), fixed in
  [#269](https://github.com/dadadave80/lattice/pull/269)). Reproduce with
  `test_ConvertersPriceOnFullNav` and `test_DepositWhileAllocated_DoesNotDilute`
  in [`VaultFullNavPricingTest`](test/integration/VaultFullNavPricingTest.t.sol).
  The fix changes share pricing and caps `maxWithdraw`/`maxRedeem` at idle
  assets.
  - **Strategy recalls, v0.1.0 to v0.4.0: `rebalance()` could lock up.**
    `StrategyManager.rebalance()` reverted when an over-target strategy
    returned even 1 wei less than requested, and every adapter could
    under-deliver, so the strategy could be neither recalled nor removed
    ([#221](https://github.com/dadadave80/lattice/issues/221), fixed in
    [#281](https://github.com/dadadave80/lattice/pull/281)). Reproduce with
    `test_Rebalance_HonestPartialRecall_Completes` in
    [`StrategyManagerTest`](test/unit/StrategyManagerTest.t.sol) and the
    `test_PoC_*` tests in
    [`StrategyLiquidityTest`](test/integration/StrategyLiquidityTest.t.sol).
    The second half of #221 is **not fixed**: `CurveStableSwapAdapter` values
    its LP at spot `get_virtual_price()`, which read-only reentrancy can skew.
    It is unsupported in 0.5.0; do not register it with a vault's
    StrategyManager.
- **CCTP hooks, v0.2.0 to v0.4.0: hook skipped on plain relay.** The
  permissionless `CCTPBridgeAdapter.relayMessage` relayed a message carrying a
  Lattice hook envelope without running the hook. The USDC was minted and the
  CCTP nonce consumed, so a receiver that books credit in its hook (such as the
  `CCTPHookVault` example) stranded the funds
  ([#216](https://github.com/dadadave80/lattice/issues/216), fixed in
  [#268](https://github.com/dadadave80/lattice/pull/268)). Reproduce with
  `test_RelayMessageRefusesHookedMessageFromThirdParty` in
  [`CCTPBridgeAdapterTest`](test/unit/CCTPBridgeAdapterTest.t.sol).
- **ERC-7786 OpenBridge, v0.1.0 to v0.4.0: executes at threshold 0.** The
  init leaves the attestation threshold at 0, and `receiveMessage` executed
  once the gateway count reached it, so from `registerRemoteBridge` until the
  first `setThreshold` anyone, gateway or not, could deliver a forged message
  to the recipient. Only a freshly configured bridge is exposed, since the
  threshold cannot return to 0
  ([#217](https://github.com/dadadave80/lattice/issues/217), fixed in
  [#266](https://github.com/dadadave80/lattice/pull/266)). Reproduce with
  `test_ThresholdZeroNonGatewayDeliveryDoesNotExecute` in
  [`ERC7786OpenBridgeTest`](test/unit/ERC7786OpenBridgeTest.t.sol). The fix
  makes `registerRemoteBridge` revert while the threshold is 0.
- **Governed diamond cuts, v0.1.0 to v0.4.0: delay bypass and guardian
  brick.** Both need a privileged role.
  - `GovernedSafeDiamondCut.setMinDelay` took effect at once, so the Safe
    could set the delay to 0, then schedule and execute any cut in one
    transaction. Reproduce with
    `test_SetMinDelayZero_CannotScheduleAndExecuteInOneBlock` in
    [`GovernedSafeDiamondCutTest`](test/unit/GovernedSafeDiamondCutTest.t.sol).
  - With nothing frozen, which is the default, `emergencyRemoveCut` let an
    emergency guardian remove `diamondCut` itself, permanently ending upgrades.
    Reproduce with `test_EmergencyRemove_RefusesDiamondCut` in
    [`GovernedDiamondCutTest`](test/unit/GovernedDiamondCutTest.t.sol) and
    [`SafeDiamondCutTest`](test/unit/SafeDiamondCutTest.t.sol).

  Both are [#218](https://github.com/dadadave80/lattice/issues/218), fixed in
  [#279](https://github.com/dadadave80/lattice/pull/279). A lowered delay now
  applies only after the old delay has passed, and `MinDelayChanged` is
  replaced by `MinDelayChangeScheduled`.
- **SessionKey, v0.1.0 to v0.4.0: spend caps bypassed through approvals.** A
  cap counted only transfers and balance drops inside one batch, so a key
  allowed to call `approve` on a capped token could approve an address it
  controls and pull the balance later, outside the account. Revoking a key also
  left its grants in place for a re-registered key
  ([#220](https://github.com/dadadave80/lattice/issues/220), fixed in
  [#277](https://github.com/dadadave80/lattice/pull/277)). Reproduce with
  `test_SessionKey_ApproveThenLaterPull_Blocked` and
  `test_SessionKey_RevokeClearsGrants` in
  [`SessionKeyApprovalTest`](test/integration/SessionKeyApprovalTest.t.sol).
  Approvals of a capped token are now reset after each batch, and an
  `ANY_TARGET` grant no longer matches the account itself.
- **ERC20Votes, v0.1.0 to v0.4.0: stray storage write.** The ERC20Votes,
  GovernedVault and GovernedVaultENS inits wrote `1` to the un-namespaced slot
  `keccak256(bytes32(0))`. Lattice keeps no state there, so the write matters
  only to a facet that uses slot-0 storage. The live Sepolia M2 vault has the
  write, where it is harmless
  ([#222](https://github.com/dadadave80/lattice/issues/222), fixed in
  [#278](https://github.com/dadadave80/lattice/pull/278)). The guard is the
  `keccak256(0)` check in
  [`RecipeGuards`](test/composability/RecipeGuards.sol), run by
  `test_Upgradeable_ERC20Votes` in
  [`RecipeUpgradeabilityTokensTest`](test/composability/RecipeUpgradeabilityTokensTest.t.sol).
- **Vault deposits after a strategy force-removal (unreleased).** A
  force-removed strategy's funds leave the vault's NAV, so if they later
  returned, depositors who entered at the lower NAV shared in them at the
  expense of the existing holders
  ([#270](https://github.com/dadadave80/lattice/issues/270)). Reproduce with
  `test_ForceRemoval_DonationSandwich_DepositsLatched` in
  [`VaultFullNavPricingTest`](test/integration/VaultFullNavPricingTest.t.sol).
  A force removal now latches deposits closed until the manager admin calls
  `clearDepositLatch()`; exits stay open. Replacing the manager is still
  open; see below.

### Open

- **HSSAdapter `scheduleSelfCall` jobId strand.** A self-call schedule that is
  deleted, expires unfired, or cannot be paid for at fire time holds its
  `jobId` until a diamond cut
  ([#226](https://github.com/dadadave80/lattice/issues/226)).
- **Vault deposits after a strategy-manager replacement.** The deposit latch
  lives in the strategy manager, so `setStrategyManager` drops it: a fresh
  manager starts unlatched, deposits reopen at the lower NAV, and depositors
  who enter then share in any funds the old manager's strategies return later.
  This applies both to the last-resort recovery from an overflowing strategy
  and to a swap made while the old manager is latched
  ([#270](https://github.com/dadadave80/lattice/issues/270)). Pinned by
  `test_DepositLatch_ManagerSwapDropsLatch` in
  [`VaultFullNavPricingTest`](test/integration/VaultFullNavPricingTest.t.sol).
- **Strategy adapter liquidity.** Aave V3 and Compound V3 recalls revert when
  the market lacks cash, and the UniswapV3 adapter's token1 has no exit path to
  the vault ([#271](https://github.com/dadadave80/lattice/issues/271)).
- **Conflicting module inits.** A second EIP-712 or AccessControl init in the
  same diamond silently overwrites the domain or adds an admin
  ([#205](https://github.com/dadadave80/lattice/issues/205)).
- **ERC-165 claims without a routed function.** The GovernedSafeDiamondCut
  recipe reports `IDiamondCut` but routes no `diamondCut`, and several recipes
  report `IEIP712` without routing `eip712Domain()`; a call that trusts the
  claim reverts ([#206](https://github.com/dadadave80/lattice/issues/206)).

## Review evidence

No external audit has been performed. The evidence below is internal review and
automated checking; it is not a substitute for an audit.

- **Hardening pass (2026-09).** A full-repository review filed its findings as
  [#213](https://github.com/dadadave80/lattice/issues/213) and its child issues,
  including the fixed items under [Known issues](#known-issues).
- **Static analysis.** Slither runs in CI and fails on any untriaged High
  result ([#282](https://github.com/dadadave80/lattice/pull/282)). The
  configuration is [`slither.config.json`](slither.config.json); each triaged
  result in [`slither.db.json`](slither.db.json) carries a reason, checked by
  [`script/slither-db.py`](script/slither-db.py). Run it with `make slither`.
- **Differential tests.** Ported math (every `mulDiv` copy, the ERC-4626
  converters and previews, Governor counting, Checkpoints, constant-product
  quotes, ECDSA) is fuzzed against independent references in
  [`test/fuzz/`](test/fuzz/)
  ([#283](https://github.com/dadadave80/lattice/pull/283)).
- **Invariant and fuzz suites.** [`test/invariant/`](test/invariant/) and
  [`test/fuzz/`](test/fuzz/); invariant runs fail on revert. See
  [`test/README.md`](test/README.md) for the testing approach.
- **Storage layout.** Every ERC-7201 namespace in `src/` is checked against a
  committed baseline by
  [`check-storage-layout.sh`](script/upgrades/check-storage-layout.sh)
  (`make storage-check`), and the module slot constants are re-derived and
  checked for collisions in
  [`StorageSlotVerificationTest`](test/unit/StorageSlotVerificationTest.t.sol).
  [`STORAGE_REGISTRY.md`](STORAGE_REGISTRY.md) lists the namespaces and
  ERC-165 interface IDs.
- **CI gates.** [`test.yml`](.github/workflows/test.yml) runs formatting,
  licence notices, EIP-170 sizes, the via-IR build, the storage guard, the test
  suite, the gas snapshots in [`snapshots/`](snapshots/) and Slither, all
  required through one `CI OK` check on `dev` and `main`.
  [`scheduled.yml`](.github/workflows/scheduled.yml) runs the fork suites and
  coverage weekly.
- **Provenance.** [`lib/VENDORED.md`](lib/VENDORED.md) lists vendored, ported
  and adapted code with its upstream source and licence.

### Recording a future audit

An audit is recorded by adding its report under `audits/`, named
`<YYYY-MM-DD>-<auditor>.pdf`, and a row here giving the auditor, the audited
commit SHA, the scope (the files or modules covered), and the commits that fix
each finding. Code changed after the audited commit is not covered by it.
