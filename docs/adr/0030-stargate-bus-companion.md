# 0030. Stargate bus enqueue is an optional companion with an exact native fare

- **Status:** Accepted
- **Date:** decided and recorded 2026-11-06; deferred feature tracked in [#213](https://github.com/dadadave80/lattice/issues/213)

## Context

The existing Stargate adapter is a taxi-only token rail. Its live interface, selector set and parameter
tuple stay frozen. Bus rides settle locally and return a queue ticket before an upstream driver sends
the batch. They require a different completion model from a taxi's immediate message GUID.

The reviewed public ABI is Stargate v2's `@stargatefinance/stg-evm-v2@12.0.0`, commit
`35e04fd94bd15cecaccb5c382bd642cafe87d96d`. It returns a `uint72` ticket, including valid ticket zero.
Its enqueue receipt has a zero GUID and nonce. Its surplus native-refund helper ignores a failed
transfer, so routinely forwarding excess value would expose contract callers to a silent refund failure.

## Options considered

1. **A new stateless companion and optional recipe.** Reuse configured pools, endpoint IDs, the shared
   token primitives and guard. Add two selectors and an interface without a new namespace or fields.
2. **Add a mode to the original interface or tuple.** Small implementation surface, but changes a
   frozen capability or makes existing callers opt into different semantics. Rejected.
3. **Accept arbitrary commands/options.** Expands scope into native drops, composition and protocol
   command changes without a demonstrated requirement. Rejected.
4. **Own a ticket ledger and drive/cancel wrapper.** Adds storage, fee custody and authority without
   creating cancellation rights or bounded delivery. Rejected; callers can use upstream driving directly.

## Decision

`StargateBusBridgeAdapter` exposes a bus quote and enqueue method using the original `SendTokenParams`.
It selects one zero byte as the command, with empty options and composition payload. It pulls exactly
the caller's ERC20, approves the configured pool for that amount, resets approval and returns only the
new token balance delta. The original taxi API and five-cut recipe retain their behavior.

The new method requires `msg.value` to equal its current native quote before any token movement. It
accepts only an enqueue receipt with zero GUID/nonce, nonempty passenger bytes, the exact charged native
fare and zero LZ-token fee. A mismatch reverts the entire call, including the pool's effects. Ticket zero
is accepted. These checks detect protocol-shape drift; they do not authenticate a malicious registered pool.

The return and event carry the ticket, opaque passenger data and locally settled amounts. They do not
claim destination delivery. The optional recipe installs both capabilities and initializes their interface
claims; adding bus to an existing configured diamond uses an authorized guarded initializer batch.

## Consequences

There is one extra optional facet and stateless initializer, with a separate precomputed ERC165 map slot.
The original storage struct is unchanged. Only users choosing the new recipe or an authorized upgrade
receive the capability. No gas saving is claimed for the Lattice wrapper; batching cost and timing belong
to the configured upstream protocol. Exact-fare callers must re-quote if configuration changes.

Retain passenger bytes and the source route. A direct upstream drive must provide an authenticated
contiguous prefix starting at the queue's next ticket, which can require earlier passengers' data. Only
the later upstream `BusDriven` event associates that batch with a real GUID. Planner/driver behavior,
queue capacity, pool configuration, liquidity and LayerZero execution affect liveness. No delivery time
bound, per-ticket cancellation, expiry or user refund endpoint is supplied. Native pools, native drops
and destination composition remain unsupported by this capability.

Upstream implementation code is BUSL-1.1 and is not copied or added as a dependency. The integration
uses the existing fresh ABI declaration; the queue test fixture is independently authored and is not
proof of upstream or public-network execution.

## Confirmation

Recipe-built proxy tests distinguish bus and taxi quotes/routes, valid ticket zero, deferred dispatch,
prefix handling, exact-fare ordering, receipt drift, rollback, shared reentrancy, ERC20 oddities and
prefunded balance isolation. A guarded upgrade test preserves existing config and roles. Canonical
recipe/initializer inventories, native export, selector parity and interface-map tests cover the new entry.

## References

- [Deferred work](https://github.com/dadadave80/lattice/issues/213) and [frozen identities](0008-freeze-once-live.md).
- Pinned [pool send/quote/refund implementation](https://github.com/stargate-protocol/stargate-v2/blob/35e04fd94bd15cecaccb5c382bd642cafe87d96d/packages/stg-evm-v2/src/StargateBase.sol).
- Pinned [messaging enqueue/drive implementation](https://github.com/stargate-protocol/stargate-v2/blob/35e04fd94bd15cecaccb5c382bd642cafe87d96d/packages/stg-evm-v2/src/messaging/TokenMessaging.sol)
  and [queue semantics](https://github.com/stargate-protocol/stargate-v2/blob/35e04fd94bd15cecaccb5c382bd642cafe87d96d/packages/stg-evm-v2/src/libs/Bus.sol).
- [Capability interface](../../src/interfaces/crosschain/IStargateBusBridgeAdapter.sol),
  [optional recipe](../../script/base/crosschain/DeployStargateBusBridgeAdapter.s.sol),
  [tests](../../test/unit/StargateBusBridgeAdapterTest.t.sol), and [crosschain reference](../../CROSSCHAIN.md).
