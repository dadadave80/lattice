# 0013. A timelock in the Governor's diamond enforces the proposal grace period

- **Status:** Accepted
- **Date:** 2026-10-09, [#325](https://github.com/dadadave80/lattice/pull/325)
  (2026-10-09); recorded 2026-10-09

## Context

`GovernorLib.state` reports a queued proposal as Expired once `eta + GRACE_PERIOD` (14 days) has passed,
and `GovernorLib.execute` refuses it. The timelock keeps its own schedule and has no notion of a grace
period, so the operation still reads Ready. `GovernedVaultInit` and `GovernedVaultENSInit` leave the
timelock's `EXECUTOR_ROLE` open (`address(0)`), so anyone could call `executeBatch` directly and run an
Expired proposal, which then read Executed. OpenZeppelin treats Expired as terminal. The diamond invariant
suite from [#319](https://github.com/dadadave80/lattice/pull/319) found this.

The Governor and TimelockController modules are live, so the fix cannot change their namespaces, struct
layouts, selectors or interfaceIds ([0008](0008-freeze-once-live.md)).

## Options considered

1. **The timelock checks the grace before it runs an operation.** `TimelockControllerLib._beforeCall`
   calls `GovernorLib.checkTimelockOperation(id)`, which maps the operation to its proposal through the
   Governor's existing `_timelockIds` index and reverts once the proposal is past its grace. No storage,
   selector or interfaceId changes.
2. **A Governor-only check.** `execute` already refuses Expired. A direct `executeBatch` call never reaches
   the Governor, so this does not fix the bug.
3. **Let anyone cancel an Expired proposal's operation.** Expiry would then depend on someone sending the
   cancel before an executor runs the operation, a race the open executor can win.
4. **Close the executor role in the recipes.** Live diamonds keep the open role they were initialized with,
   so only fresh deployments would be fixed, and the recipes' open execution is a documented feature.
5. **Drop the Expired state,** as OpenZeppelin's `GovernorTimelockControl` does. An approved proposal would
   then stay executable forever, and `state` would change meaning for integrators.

## Decision

- A TimelockController that shares a diamond with the Governor refuses to execute an operation the
  Governor queued once that proposal is past `eta + GRACE_PERIOD`. It reverts with
  `GovernorUnexpectedProposalState(proposalId, Expired, bitmap(Queued))`, as `GovernorLib.execute` does.
- An operation the Governor did not queue maps to proposal 0 and passes, so a TimelockController facet
  without a Governor, or one scheduling its own operations, behaves as before.
- The timelock reads the Governor namespace only through `GovernorLib.checkTimelockOperation`, so
  `GovernorLib` remains the only code that touches `lattice.storage.Governor`. This does not supersede
  [0002](0002-erc7201-namespaced-storage.md): each namespace still has one owning library, and another
  module's library may read it only through that library's functions.
- A timelock deployed apart from its Governor, such as `TimelockControllerStandalone`, cannot see the
  grace. With an open executor it still runs an Expired proposal's operation. Its integrators must give
  `EXECUTOR_ROLE` to the Governor alone, as its constructor NatSpec says.

## Consequences

- Expired is terminal in the `GovernedVault` recipes: the Governor, a direct timelock call and the
  proposer's cancel all refuse it.
- The timelock's views (`isOperationReady`, `getOperationState`) still report such an operation as Ready,
  because the timelock's own schedule is unchanged. Keepers and frontends must check
  `IGovernor.state(proposalId)` before they execute; the interface NatSpec says so.
- `TimelockControllerLib` now imports `GovernorLib`, and every timelock execution pays one extra storage
  read, cold on the first access, even in a diamond without a Governor.
- The fix ships as new TimelockController and Governor facet bytecode. A live diamond gets the timelock
  check only after a `diamondCut` replaces its TimelockController facet; replacing the Governor facet alone
  leaves direct execution open.

## Confirmation

- `GovernorDiamondInvariant.test_ExpiredProposalIsTerminal` and
  `test_QueuedProposalRunsDirectlyUntilGraceEnds` pin the grace on a `GovernedVault`-style diamond. The
  suite's `executeDirect` handler aims one call in three at an Expired proposal and expects the refusal, and
  `invariant_StateMatchesModel` and `invariant_TimelockRunsOnlyQueued` hold under random call sequences.
- `GovernorTest.test_ExecuteExpiredProposalReverts` pins the Governor side, and
  `GovernorTest.test_SeparateOpenTimelockStillRunsExpiredOperation` pins the separate-timelock limitation.

## References

- [#322](https://github.com/dadadave80/lattice/issues/322), [#319](https://github.com/dadadave80/lattice/pull/319)
- [`GovernorLib.sol`](../../src/governance/libraries/GovernorLib.sol),
  [`TimelockControllerLib.sol`](../../src/governance/libraries/TimelockControllerLib.sol),
  [`TimelockControllerStandalone.sol`](../../src/governance/TimelockControllerStandalone.sol)
- [`GovernedVaultInit.sol`](../../src/defi/GovernedVaultInit.sol)
