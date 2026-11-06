# 0028. ZetaChain messages accept bounded recovery options without callbacks

- **Status:** Accepted
- **Date:** 2026-11-06; recorded for [#213](https://github.com/dadadave80/lattice/issues/213).

## Context

The deployed ZetaChain adapter exposes the frozen ERC-7786 source selector set. Its admin default
cannot express a caller's per-message recovery destinations or data. The protocol's plain-call path
forbids revert callbacks, caps revert gas, and limits the combined message and recovery data size.

## Options considered

1. **One attribute encoding on the existing source ABI.** Preserves storage and selectors while
   validating protocol limits and binding recovery data to the real sender.
2. **Keep only the admin default.** Does not provide the requested per-message recovery options.
3. **Forward unrestricted raw options.** Accepts unsupported callbacks and ambiguous recovery data.

## Decision

Accept one canonical `IZetaChainGatewayAttributes.revertOptions` attribute. Require two nonzero
recovery addresses, `callOnRevert=false`, gas at most 2,000,000, and a combined encoded size at most
2,880 bytes. Wrap custom recovery data with the actual source caller, recipient and outbound nonce.
Retain the existing no-attribute defaults, envelope, selector set, interface IDs and storage layout.
Forward only the call's native value; let the configured gateway enforce its required fee.

## Consequences

Callers can choose recovery destinations without changing global configuration. They must control
those addresses on the relevant chains. Recovery consumers still authenticate the protocol caller,
source adapter and source chain; an envelope is not an authorization mechanism. No callback router
or delivery guarantee is added. Canonical decoding and the extra envelope consume gas and message
space. Existing oversized messages or invalid default gas now fail before the protocol call, under
the same bounds enforced by the pinned upstream. A future upstream change requires explicit review.

## Confirmation

Real-diamond tests cover canonical encoding, duplicate/malformed attributes, recovery provenance,
gas and encoded-size boundaries, default isolation, fee rejection, nonce rollback and existing funds.
Selector parity and storage-layout gates check that no frozen surface changes.

## References

- [#213 hardening tracker](https://github.com/dadadave80/lattice/issues/213), including the comparison.
- [Adapter library](../../src/crosschain/zetachain/ZetaChainGatewayAdapterLib.sol).
- [Gateway validation at 48ecdbcc](https://github.com/zeta-chain/protocol-contracts/blob/48ecdbcc4c30a8e8a7f2f5756b6a544b316670a0/contracts/evm/libraries/GatewayEVMValidations.sol).
- [Gateway fee validation at 48ecdbcc](https://github.com/zeta-chain/protocol-contracts/blob/48ecdbcc4c30a8e8a7f2f5756b6a544b316670a0/contracts/evm/GatewayEVM.sol).
