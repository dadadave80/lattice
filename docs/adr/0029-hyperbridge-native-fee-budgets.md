# 0029. Hyperbridge native fees use bounded exact-output budgets

- **Status:** Accepted
- **Date:** 2026-11-06; issue [#213](https://github.com/dadadave80/lattice/issues/213)

## Context

The Hyperbridge adapter's zero-value sends already pay the host's per-byte and optional relayer
fees in its live ERC-20 fee token. The compatible legacy host also accepts native value and swaps
for the exact fee-token output, but the router returns any excess native input to the host rather
than the user. Forwarding a caller's entire budget could strand that excess. Current upstream host
revisions have changed fee and callback ABIs and cannot silently replace the vendored host contract.

## Options considered

1. **Quote and forward the exact native input.** Reuse the compatible host's public router getter,
   normal-call `getAmountsIn` and exact-output dispatch. Reject host-retained surplus and refund the
   adapter's current-call native delta. No new storage, routed selector or runtime dependency.
2. **Forward the full budget.** Smaller, but the legacy host retains router refunds. Rejected.
3. **Swap in the adapter or configure a second router.** Adds token approvals, protocol-specific swap
   handling and another configuration/trust boundary. Unnecessary for the existing host interface.
4. **Adopt the newest host ABI.** Changes callback and fee semantics; a separate integration decision.

## Decision

Positive `msg.value` selects native payment for both send entrypoints; zero value preserves the
existing ERC-20 helper unchanged. `sendMessageWithFee` widens from nonpayable to payable, with the
same selector and interfaceId. The optional relayer fee remains denominated in the host's fee token.
The read-only `quoteDispatchFee` continues to quote fee-token units.

The native path snapshots adapter and host native balances before external quote work. It reads
the live host configuration, checks the two-token path and exact output quote, and forwards only
the quoted input from the current budget. A zero total skips the router. The host balance must
remain unchanged after dispatch, so retained surplus or other custody changes revert atomically.
The adapter refunds only its native balance delta above its standing balance. Rejecting a nonzero
refund reverts the entire send. The existing guard covers quote, dispatch and refund.
The unchanged zero-value ERC-20 helper does not acquire that guard. A nested ERC-20 send remains
allowed when its sender separately funds and approves the fee tokens; it uses a distinct nonce
and cannot spend the native budget or standing balance. Existing callback/reply behavior is retained.

Compatibility is pinned to the [legacy host at 8dce6799](https://github.com/polytope-labs/hyperbridge/blob/8dce6799f1d376443ae40054b80e16d60ac447d1/evm/src/core/EvmHost.sol).
The normal-call quote declaration also admits the [stateful quote-wrapper ABI](https://github.com/polytope-labs/hyperbridge/blob/b04bee03e4dd0b1c5958836994aabf2dfc09aa38/evm/src/utils/uniswapv2/UniV3UniswapV2Wrapper.sol).
The host/router, their live configuration and quote-to-swap behavior remain explicit trust
assumptions. No public deployment or router compatibility is certified by the local tests.

## Consequences

The namespace, storage, routed selectors, interfaceId, canonical recipe cuts and initializer are
unchanged. The payable ABI annotation widens and facet bytecode changes, so this is a `feat` release.
The old native-rejection error remains declared. Native payment requires extra quote calls and
balance checks. The host pays timeout refunds only in fee tokens: the relayer fee goes to the
original user (`DispatchPost.payer`), while the protocol fee and native swap cost remain spent.

The canonical recipe has no Receive route; forwarding native from a payable call needs none.
Defensive tests of a nonstandard host returning bare native use a separately composed Receive facet.
This decision does not add GET requests, a native quote selector, arbitrary-router execution or
new source authentication.

## Confirmation

`HyperbridgeNativeFeeTest` exercises exact quotes, malformed/reverting quotes, zero fees, budget
limits, live token migration, host-retained and direct-adapter refunds, pre-funded balances,
reentrancy, refund rejection, rollback/retry and timeout refund destination/asset. Existing
`HyperbridgeGatewayAdapterTest` covers the unchanged ERC-20 path and inbound authentication.
Cross-mode controls exercise independently funded ERC-20 sends during native quoting and refund.

## References

- [Issue #213](https://github.com/dadadave80/lattice/issues/213)
- [Hyperbridge fee compatibility](../../CROSSCHAIN.md#hyperbridge-native-fee-compatibility)
- [Adapter library](../../src/crosschain/hyperbridge/HyperbridgeGatewayAdapterLib.sol)
