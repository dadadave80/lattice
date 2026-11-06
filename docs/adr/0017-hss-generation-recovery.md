# 0017. HSS job recovery invalidates generations before native deletion

- **Status:** Accepted for local implementation; native callback identity remains unverified
- **Date:** 2026-11-06; tracked in [#226](https://github.com/dadadave80/lattice/issues/226)

## Context

An HSS self-call job can remain occupied after native deletion, an unfired expiry or a reverted
callback. Clearing that reservation alone is unsafe: an older callback can arrive after replacement
and call the same frozen `completeSelfCall(jobId)` selector. The live HSS namespace and
`IHSSAdapter` interfaceId `0xd07095cf` are frozen by [0008](0008-freeze-once-live.md).

## Options considered

1. **Cancel and clear only.** Restores availability but cannot distinguish a delayed old callback;
   rejected because it can clear a replacement.
2. **Reuse only after a stored expiry.** Does not recover early deletion, and expiry does not prove a
   callback cannot still arrive; rejected as an incomplete lifecycle rule.
3. **Add a generation argument to completion.** Binds completion, but changes the live interface;
   rejected in favor of a separate interface.
4. **Generation envelope with active callback context.** Selected: stale envelopes fail before their
   business payload runs, and existing completion authenticates the active job and generation.

## Decision

- Keep the original seven HSSAdapter selectors and interfaceId. Add `HSSAdapterRecovery` with the
  separate `IHSSAdapterRecovery` id `0x4d10dd54`.
- Append a monotonic generation mapping and active callback job/generation to the existing HSS
  namespace. Never repurpose its original job-to-schedule mapping.
- A new booking schedules `executeSelfCall(jobId,generation,data)`. The dispatcher checks self-call
  authority and the occupied generation before a self-CALL to the original callback. The callback
  completes explicitly and may then schedule its next occurrence. Envelope return never clears a
  newly booked occurrence.
- Cancellation requires `HSS_SCHEDULER_ROLE`, invalidates state and increments generation before
  calling native HSS. Native deletion is best-effort, capped at 100,000 gas with bounded return-data
  copying and event/return gas reserved. Its response cannot preserve the local reservation.
- Callback failure reverts context, completion, business changes and any reschedule atomically.
- Upgrade the base and recovery facets together and register the extra interface through the
  recovery initializer. Existing raw jobs are generation0 and must be cancelled/rescheduled.

## Consequences

- Self-call identity remains a composition trust boundary. Scheduler-role holders and upgrade
  authority remain trusted; unrestricted public self-call executors are incompatible with this guard.
- Cancelling an old **raw** payload cannot prevent its business code from running if native deletion
  fails. It cannot clear a new job, because it has no active generation context. Operators must review
  the old payload before reusing its business operation.
- Each booking adds a generation write; firing adds context writes, checks and a self-CALL. The caller
  must budget its scheduled gas accordingly. Native execution fees are not established by local tests.
- Offline mocks do not prove native payer-as-caller semantics. The existing
  [upstream report](https://github.com/hiero-ledger/hiero-consensus-node/issues/27263) observed testnet
  payer-signature failures before EVM entry on 2026-09-12; current native execution still needs a fresh,
  authorized measurement. Probe6 therefore uses an ungated raw `scheduleCall` to observe the actual
  sender without an envelope manufacturing it.

## Confirmation

- `HSSAdapterRecoveryTest` uses the native ABI at etched address0x16b and real recipe-built diamonds.
  It covers stale fires, cancellation failures, context/replay guards, callback rollback, recurrence
  and legacy state. It explicitly models the unverified sender assumption.
- Storage baseline/append-only checks, frozen-interface proof, slot recomputation and full release
  selector parity guard the ABI and layout boundaries.
- Live acceptance under #226 remains open until sender, schedule ID, date and actual node version are
  recorded. No public broadcast or schedule cancellation is part of this implementation.

## References

- [#226](https://github.com/dadadave80/lattice/issues/226), [Hedera guide](../guides/hedera.md)
- [HSSAdapterLib](../../src/oracles/hedera/HSSAdapterLib.sol)
- [HSS recovery interface](../../src/interfaces/oracles/IHSSAdapterRecovery.sol)
