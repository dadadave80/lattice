// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {BridgeFungibleLib} from "@lattice/crosschain/libraries/BridgeFungibleLib.sol";
import {NonEvmAddress} from "@lattice/crosschain/libraries/NonEvmAddress.sol";
import {AdapterBaseLib} from "@lattice/defi/libraries/AdapterBaseLib.sol";
import {IStargateBridgeAdapter} from "@lattice/interfaces/crosschain/IStargateBridgeAdapter.sol";
import {MessagingFee, MessagingReceipt} from "@lattice/interfaces/external/ILayerZeroEndpointV2.sol";
import {IStargate, OFTReceipt, SendParam} from "@lattice/interfaces/external/IStargate.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.StargateBridgeAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant STARGATE_BRIDGE_ADAPTER_STORAGE_SLOT =
    0x2076bfc799b61fb4ea9b1d4a406060be54015b08cd19ef147b102a3e634c0800;

/// @dev 0x199fc6b0 is `type(IStargateBridgeAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x199fc6b0), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ISTARGATEBRIDGEADAPTER_SLOT =
    0x326cc60e86592cbb0d41c91042ab150a4f99ae6dd5d49d392cfc87d10b32650d;

/// @notice ERC-7201 namespaced storage for the Stargate v2 pooled-liquidity token-bridge adapter.
/// @custom:storage-location erc7201:lattice.storage.StargateBridgeAdapter
struct StargateBridgeAdapterStorage {
    /// @notice EVM chainId => LayerZero eid (0 = unset). Admin-registered identity, never inferred. APPEND-ONLY.
    mapping(uint256 chainId => uint32 eid) _chainIdToEid;
    /// @notice LayerZero eid => EVM chainId (0 = unset). Admin-registered identity, never inferred. APPEND-ONLY.
    mapping(uint32 eid => uint256 chainId) _eidToChainId;
    /// @notice ERC-20 token => its LOCAL Stargate pool (0 = unset). Identity — register once, `pool.token()`
    ///         cross-checked fail-closed at registration; ERC-20 pools ONLY in v1. APPEND-ONLY.
    mapping(address token => address pool) _pools;
}

/// @title StargateBridgeAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Stargate (https://github.com/stargate-protocol/stargate-v2)
/// @notice Logic + ERC-7201 storage for the Stargate v2 POOLED-LIQUIDITY token-bridge adapter (the third
///         token rail: neither burn/mint CCTP nor intent Across). Outbound {sendToken} pulls exactly
///         `amountLD` from the caller, force-approves the token's registered pool for exactly that amount,
///         dispatches a TAXI-mode OFT send, resets the allowance to 0, then sweeps any un-debited dust back
///         to the caller (pools truncate `amountLD` to shared decimals, so `amountSentLD` may be LESS than
///         what was pulled — the diamond nets zero).
/// @dev TRUST MODEL / SCOPE: Stargate pools hold unified liquidity; the DESTINATION pool is the LayerZero
///      receiver that credits the recipient — no Lattice inbound surface exists (outbound-only for plain
///      transfers; never routed through OpenBridge, no `receiveId`). DEFERRED (documented, deliberate):
///      `composeMsg`/`lzCompose` destination hooks and BUS mode (non-empty `oftCmd`; issue #77 Q11) — every
///      send here is a taxi (empty `oftCmd`); native-ETH pools (`StargatePoolNative`), whose `msg.value`
///      mixes fee + amount — v1 is ERC-20 ONLY and `msg.value` is the LayerZero fee EXCLUSIVELY. REFUND
///      SAFETY: `refundAddress` is ALWAYS `msg.sender` — excess LayerZero fee refunds go to the USER, never
///      the diamond (same stranding class as the Across depositor). Reuses the shared safe-transfer /
///      force-approve helpers ({BridgeFungibleLib.pullExact}, {AdapterBaseLib.forceApprove}); no bespoke
///      ERC-20 plumbing.
library StargateBridgeAdapterLib {
    function stargateBridgeAdapterStorage() internal pure returns (StargateBridgeAdapterStorage storage $) {
        assembly {
            $.slot := STARGATE_BRIDGE_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IStargateBridgeAdapter ERC-165 id. Called inside the diamond initializing
    ///         window. No protocol wiring happens at init — Stargate is per-token pools, all admin-registered
    ///         ({registerStargateEid}/{registerPool}) after deploy.
    function __StargateBridgeAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for `IStargateBridgeAdapter`.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ISTARGATEBRIDGEADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function stargateEidOf(uint256 chainId) internal view returns (uint32) {
        return stargateBridgeAdapterStorage()._chainIdToEid[chainId];
    }

    function stargateChainIdOf(uint32 eid) internal view returns (uint256) {
        return stargateBridgeAdapterStorage()._eidToChainId[eid];
    }

    function poolOf(address token) internal view returns (address) {
        return stargateBridgeAdapterStorage()._pools[token];
    }

    /// @notice Quotes the LayerZero native fee of `p`, building the IDENTICAL `SendParam` (same
    ///         {_buildSendParam} builder, same checks) the {sendToken} path dispatches — quote and send can
    ///         never drift.
    function quoteSendFee(IStargateBridgeAdapter.SendTokenParams calldata p) internal view returns (uint256 nativeFee) {
        (address pool, SendParam memory sendParam) = _buildSendParam(p);
        return IStargate(pool).quoteSend(sendParam, false).nativeFee;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers an EVM chainId ↔ LayerZero eid equivalence (both directions). FAIL-LOUD identity
    ///         admin: an already-mapped chainId OR eid reverts — identities are never remapped. `chainId` 0
    ///         and `eid` 0 are rejected (0 is each map's unset sentinel). Admin only.
    /// @dev Stargate rides LayerZero, so this eid equals the LayerZero adapter's eid for the same chain —
    ///      recorded in this adapter's OWN map (adapters never share hot-path storage).
    function registerStargateEid(uint256 chainId, uint32 eid) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (chainId == 0) revert IStargateBridgeAdapter.StargateZeroChainId();
        if (eid == 0) revert IStargateBridgeAdapter.StargateZeroEid();
        StargateBridgeAdapterStorage storage $ = stargateBridgeAdapterStorage();
        if ($._chainIdToEid[chainId] != 0 || $._eidToChainId[eid] != 0) {
            revert IStargateBridgeAdapter.StargateEidAlreadyRegistered(chainId, eid);
        }
        $._chainIdToEid[chainId] = eid;
        $._eidToChainId[eid] = chainId;
        emit IStargateBridgeAdapter.RegisteredEid(chainId, eid);
    }

    /// @notice Registers `token`'s LOCAL Stargate pool. FAIL-LOUD identity per token
    ///         ({StargateTokenAlreadyRegistered} — a pool upgrade cannot re-point a token entry in v1;
    ///         deliberate YAGNI) and FAIL-CLOSED: `IStargate(pool).token()` must equal `token`
    ///         ({StargatePoolTokenMismatch}) — a mis-registered pool would burn user approvals against the
    ///         wrong asset. Admin only.
    /// @dev ERC-20 pools ONLY in v1: a `StargatePoolNative` reports `token() == address(0)` and is rejected
    ///      by the cross-check against the non-zero `token` argument.
    function registerPool(address token, address pool) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (token == address(0) || pool == address(0)) revert IStargateBridgeAdapter.StargateZeroAddress();
        StargateBridgeAdapterStorage storage $ = stargateBridgeAdapterStorage();
        if ($._pools[token] != address(0)) revert IStargateBridgeAdapter.StargateTokenAlreadyRegistered(token);
        address poolToken = IStargate(pool).token();
        if (poolToken != token) revert IStargateBridgeAdapter.StargatePoolTokenMismatch(token, poolToken);
        $._pools[token] = pool;
        emit IStargateBridgeAdapter.RegisteredPool(token, pool);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   SEND
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sends `p.amountLD` of `p.token` (pulled from `msg.sender`) through its registered Stargate
    ///         pool toward the ERC-7930 `p.recipient` on `p.destinationChainId`. Strict CEI under the
    ///         reentrancy guard: checks + fee precheck, pull exactly `amountLD`, approve the pool for exactly
    ///         `amountLD`, send (taxi), reset the allowance to 0, sweep un-debited dust back to the caller.
    /// @dev FEE PRECHECK (mirrors the Hyperlane sibling): `quoteSend(...).nativeFee` is compared against
    ///      `msg.value` BEFORE any funds move — a shortfall reverts {StargateInsufficientFee} instead of
    ///      bubbling an opaque pool revert after the pull. `msg.value` is then forwarded WHOLE as the
    ///      `MessagingFee.nativeFee` with `refundAddress = msg.sender`, so any excess refunds to the USER,
    ///      never the diamond (REFUND-CRITICAL — same stranding class as the Across depositor).
    ///      DUST-CRITICAL: the pool debits `oftReceipt.amountSentLD`, which may be LESS than `amountLD`
    ///      (shared-decimal truncation) — the exact leftover (`balance now - snapshot`) is transferred back
    ///      to `msg.sender`, so the diamond nets zero even for dusty amounts.
    function sendToken(IStargateBridgeAdapter.SendTokenParams calldata p)
        internal
        returns (bytes32 guid, uint256 amountSentLD, uint256 amountReceivedLD)
    {
        ReentrancyGuardLib.nonReentrantBefore();

        // --- Checks (shared builder with the quote path) + fee precheck, all before any funds move. ---
        (address pool, SendParam memory sendParam) = _buildSendParam(p);
        uint256 fee = IStargate(pool).quoteSend(sendParam, false).nativeFee;
        if (msg.value < fee) revert IStargateBridgeAdapter.StargateInsufficientFee(fee, msg.value);

        // --- Effects/Interactions: pull EXACTLY `amountLD` from the caller, approve EXACTLY that. ---
        uint256 snapshot = AdapterBaseLib.balanceOfSelf(p.token);
        BridgeFungibleLib.pullExact(p.token, msg.sender, p.amountLD);
        AdapterBaseLib.forceApprove(p.token, pool, p.amountLD);

        (guid, amountSentLD, amountReceivedLD) = _callPool(pool, sendParam);

        // Approval hygiene: reset the pool allowance to 0 (no residual approval left behind).
        AdapterBaseLib.forceApprove(p.token, pool, 0);

        // Dust sweep: the pool debited only `amountSentLD` (shared-decimal truncation) — return the exact
        // un-debited remainder to the caller so the diamond nets zero.
        uint256 leftover = AdapterBaseLib.balanceOfSelf(p.token) - snapshot;
        if (leftover != 0) AdapterBaseLib.transferHonest(p.token, msg.sender, leftover);

        emit IStargateBridgeAdapter.StargateTokenSent(
            msg.sender, p.token, p.destinationChainId, guid, amountSentLD, amountReceivedLD, sendParam.to
        );
        ReentrancyGuardLib.nonReentrantAfter();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Validates `p` and builds the TAXI-mode `SendParam` both the quote and send paths use: empty
    ///         `extraOptions` (pool default executor options), empty `composeMsg` (no `lzCompose` hook) and
    ///         empty `oftCmd` (taxi — bus mode deferred, issue #77 Q11).
    /// @dev Check order: pool registered, non-zero amount, non-zero minAmount (mandatory slippage floor —
    ///      pools charge fees so output < input; 0 would mean unlimited slippage), not same-chain, eid
    ///      registered, then the ERC-7930 recipient parse + fail-closed eip-155 cross-check.
    function _buildSendParam(IStargateBridgeAdapter.SendTokenParams calldata p)
        private
        view
        returns (address pool, SendParam memory sendParam)
    {
        StargateBridgeAdapterStorage storage $ = stargateBridgeAdapterStorage();
        pool = $._pools[p.token];
        if (pool == address(0)) revert IStargateBridgeAdapter.StargateTokenNotRegistered(p.token);
        if (p.amountLD == 0) revert IStargateBridgeAdapter.StargateZeroAmount();
        if (p.minAmountLD == 0) revert IStargateBridgeAdapter.StargateZeroMinAmount();
        if (p.destinationChainId == block.chainid) {
            revert IStargateBridgeAdapter.StargateSameChain(p.destinationChainId);
        }
        uint32 eid = $._chainIdToEid[p.destinationChainId];
        if (eid == 0) revert IStargateBridgeAdapter.StargateUnknownDestinationChain(p.destinationChainId);

        sendParam = SendParam({
            dstEid: eid,
            to: _parseAndCheckRecipient(p.recipient, p.destinationChainId),
            amountLD: p.amountLD,
            minAmountLD: p.minAmountLD,
            extraOptions: "",
            composeMsg: "",
            oftCmd: "" // taxi mode — bus (non-empty oftCmd) deferred
        });
    }

    /// @dev The pool call lives in its own frame (returns collapse the two receipts into scalars) — stack
    ///      relief for {sendToken} under the legacy codegen pipeline. Forwards `msg.value` WHOLE as the
    ///      native fee; `refundAddress = msg.sender` (REFUND-CRITICAL, see {sendToken}). The returned bus
    ///      {Ticket} is ignored: taxi-mode sends always return an empty one.
    function _callPool(address pool, SendParam memory sendParam)
        private
        returns (bytes32 guid, uint256 amountSentLD, uint256 amountReceivedLD)
    {
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt,) = IStargate(pool)
        .sendToken{value: msg.value}(
            sendParam, MessagingFee({nativeFee: msg.value, lzTokenFee: 0}), msg.sender
        );
        return (msgReceipt.guid, oftReceipt.amountSentLD, oftReceipt.amountReceivedLD);
    }

    /// @notice Parses the ERC-7930 recipient (canonical widths enforced; reverts on empty/oversized/short-EVM
    ///         address fields) and fail-closed cross-checks a declared eip-155 chain reference against
    ///         `destinationChainId` (reverts {StargateDestinationMismatch} — mirrors the Across sibling).
    ///         For non-EVM chainTypes no cross-check is possible; the bytes32 is trusted as caller-supplied.
    function _parseAndCheckRecipient(bytes calldata recipientBytes, uint256 destinationChainId)
        private
        pure
        returns (bytes32 recipient)
    {
        bytes2 chainType;
        bytes memory chainReference;
        (chainType, chainReference, recipient) = NonEvmAddress.parseV1ToBytes32(recipientBytes);
        if (chainType == bytes2(0x0000)) {
            uint256 declared = _chainIdFromReference(chainReference);
            if (declared != destinationChainId) {
                revert IStargateBridgeAdapter.StargateDestinationMismatch(declared, destinationChainId);
            }
        }
    }

    /// @notice Right-aligns an ERC-7930 chain-reference (<= 32 bytes, big-endian) into a uint256 chainId.
    /// @dev For eip-155 chains the reference IS the chainId. Reverts {StargateChainReferenceTooLong} if > 32 bytes.
    function _chainIdFromReference(bytes memory ref) private pure returns (uint256 chainId) {
        uint256 len = ref.length;
        if (len > 32) revert IStargateBridgeAdapter.StargateChainReferenceTooLong(len);
        assembly ("memory-safe") {
            chainId := shr(mul(sub(32, len), 8), mload(add(ref, 0x20)))
        }
    }
}
