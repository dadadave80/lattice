// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {BridgeFungibleLib} from "@lattice/crosschain/libraries/BridgeFungibleLib.sol";
import {NonEvmAddress} from "@lattice/crosschain/libraries/NonEvmAddress.sol";
import {AdapterBaseLib} from "@lattice/defi/libraries/AdapterBaseLib.sol";
import {IAcrossBridgeAdapter} from "@lattice/interfaces/crosschain/IAcrossBridgeAdapter.sol";
import {V3SpokePoolInterface} from "@lattice/interfaces/external/across/V3SpokePoolInterface.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.AcrossBridgeAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ACROSS_BRIDGE_ADAPTER_STORAGE_SLOT =
    0xd1f2b3a38609618605209c75d051e4ac61236c94f39400c851dd252f5fe1d000;

/// @dev 0x4615a4f1 is `type(IAcrossBridgeAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x4615a4f1), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IACROSSBRIDGEADAPTER_SLOT =
    0xd64961c0a774526940a248ad01e6f5f33fadd297074bcba45861d774858b837c;

/// @notice ERC-7201 namespaced storage for the Across v3 intent/optimistic token-bridge adapter.
/// @custom:storage-location erc7201:lattice.storage.AcrossBridgeAdapter
struct AcrossBridgeAdapterStorage {
    /// @notice The LOCAL chain's canonical Across v3 SpokePool (set once at init, no admin surface). APPEND-ONLY.
    address _spokePool;
}

/// @title AcrossBridgeAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Across (https://github.com/across-protocol/contracts)
/// @notice Logic + ERC-7201 storage for the Across v3 intent/optimistic token-bridge adapter. Outbound
///         {deposit} pulls exactly `inputAmount` from the caller, force-approves the SpokePool for exactly that
///         amount, escrows the deposit intent, then resets the allowance to 0. Inbound {handleV3AcrossMessage}
///         is authenticated to the SpokePool and ONLY emits (no handler registry in v1 — the diamond itself is
///         the recipient and other facets manage the received funds).
/// @dev TRUST MODEL: Across is an INTENT bridge — a relayer fronts `outputToken` on the destination at fill
///      time and is later reimbursed via UMA optimistic settlement. There is NO guaranteed fill: an unfilled
///      deposit past `fillDeadline` is refunded ON THIS CHAIN to the deposit's `depositor`, which is why the
///      adapter ALWAYS passes `depositor = msg.sender` (see {deposit}). Inbound fills are relayer-pushed and
///      optimistic — NOT yet UMA-finalized when `handleV3AcrossMessage` runs — so received funds/messages are
///      reversible-until-finalized and are never routed into OpenBridge (no M-of-N, no `receiveId`). Across
///      chain ids are passed raw by callers (no domain table, no admin surface). Reuses the shared
///      safe-transfer / force-approve helpers ({BridgeFungibleLib.pullExact}, {AdapterBaseLib.forceApprove});
///      no bespoke ERC-20 plumbing.
library AcrossBridgeAdapterLib {
    function acrossBridgeAdapterStorage() internal pure returns (AcrossBridgeAdapterStorage storage $) {
        assembly {
            $.slot := ACROSS_BRIDGE_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Configures the local SpokePool and registers the IAcrossBridgeAdapter ERC-165 id.
    /// @dev Reverts {AcrossZeroAddress} if `spokePool_` is zero (so an unconfigured module cannot exist).
    ///      Called inside the diamond initializing window.
    function __AcrossBridgeAdapter_init(address spokePool_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        if (spokePool_ == address(0)) revert IAcrossBridgeAdapter.AcrossZeroAddress();
        acrossBridgeAdapterStorage()._spokePool = spokePool_;
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for `IAcrossBridgeAdapter`.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IACROSSBRIDGEADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function spokePool() internal view returns (address) {
        return acrossBridgeAdapterStorage()._spokePool;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  DEPOSIT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Escrows `params.inputAmount` of `params.inputToken` (pulled from `msg.sender`) as an Across v3
    ///         deposit intent toward the ERC-7930 `params.recipient` on `params.destinationChainId`. Strict CEI
    ///         under the reentrancy guard: checks, pull exactly `inputAmount`, approve the SpokePool for exactly
    ///         `inputAmount`, deposit, then reset the allowance to 0.
    /// @dev REFUND SAFETY (fund-safety critical): the SpokePool `depositor` field is who Across refunds ON THIS
    ///      CHAIN when the deposit expires unfilled, and the only party able to speed up the deposit. It is
    ///      ALWAYS `msg.sender` (the calling user) and NEVER `address(this)` — `depositor = address(this)` would
    ///      strand every expired-deposit refund in the diamond.
    ///      DESTINATION CROSS-CHECK (fail-closed, mirrors the ZetaChain `SourceChainMismatch` precedent): when
    ///      the ERC-7930 recipient's chainType is eip-155 (`0x0000`), its chain reference must equal
    ///      `params.destinationChainId`, else {AcrossDestinationMismatch}. For non-EVM chainTypes no cross-check
    ///      is possible (Across uses its own numeric ids for non-EVM chains) — the recipient `bytes32` and
    ///      `destinationChainId` are then trusted as caller-supplied.
    ///      NOT payable: ERC-20 inputs only in v1 (`msg.value == 0` is implicit — the SpokePool reverts on
    ///      non-zero value for non-wrapped-native inputs; native ETH users wrap first). No leftover sweep is
    ///      needed: the SpokePool pulls exactly `inputAmount` and the approve reset guarantees zero standing
    ///      allowance.
    function deposit(IAcrossBridgeAdapter.DepositParams calldata params) internal {
        ReentrancyGuardLib.nonReentrantBefore();
        address pool = acrossBridgeAdapterStorage()._spokePool;

        // --- Checks (quote-derived fields are SpokePool-validated). The SpokePool check is unreachable in a
        // properly-initialized diamond (init reverts on zero) — it fail-closes a facet cut without init. ---
        if (pool == address(0)) revert IAcrossBridgeAdapter.AcrossZeroAddress();
        if (params.inputToken == address(0)) revert IAcrossBridgeAdapter.AcrossZeroAddress();
        if (params.inputAmount == 0) revert IAcrossBridgeAdapter.AcrossZeroAmount();
        if (params.outputToken == bytes32(0)) revert IAcrossBridgeAdapter.AcrossZeroOutputToken();
        if (params.destinationChainId == block.chainid) {
            revert IAcrossBridgeAdapter.AcrossSameChainDeposit(params.destinationChainId);
        }
        bytes32 recipient = _parseAndCheckRecipient(params.recipient, params.destinationChainId);

        // --- Effects/Interactions: pull EXACTLY `inputAmount` from the caller, approve EXACTLY that. ---
        BridgeFungibleLib.pullExact(params.inputToken, msg.sender, params.inputAmount);
        AdapterBaseLib.forceApprove(params.inputToken, pool, params.inputAmount);

        _callSpokePool(recipient, params);

        // Approval hygiene: reset the SpokePool allowance to 0 (no residual approval left behind). The pool
        // pulled exactly `inputAmount`, so no leftover sweep is needed either.
        AdapterBaseLib.forceApprove(params.inputToken, pool, 0);

        emit IAcrossBridgeAdapter.AcrossDepositSent(
            msg.sender,
            params.destinationChainId,
            params.inputToken,
            params.inputAmount,
            params.outputToken,
            params.outputAmount,
            recipient
        );
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Parses the ERC-7930 recipient (canonical widths enforced; reverts on empty/oversized/short-EVM
    ///         address fields) and fail-closed cross-checks a declared eip-155 chain reference against the raw
    ///         Across `destinationChainId` (reverts {AcrossDestinationMismatch} — see the {deposit} dev notes).
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
                revert IAcrossBridgeAdapter.AcrossDestinationMismatch(declared, destinationChainId);
            }
        }
    }

    /// @dev The 12-arg SpokePool call lives in its own frame with the pool re-read from storage and `message`
    ///      copied to memory (a 1-slot value instead of a 2-slot calldata slice) — both are stack-too-deep
    ///      relief for {deposit} under the legacy codegen pipeline.
    function _callSpokePool(bytes32 recipient, IAcrossBridgeAdapter.DepositParams calldata params) private {
        bytes memory message = params.message;
        V3SpokePoolInterface(acrossBridgeAdapterStorage()._spokePool)
            .deposit(
                bytes32(uint256(uint160(msg.sender))), // depositor = the CALLING USER (refund safety, see @dev)
                recipient,
                bytes32(uint256(uint160(params.inputToken))),
                params.outputToken,
                params.inputAmount,
                params.outputAmount,
                params.destinationChainId,
                params.exclusiveRelayer,
                params.quoteTimestamp,
                params.fillDeadline,
                params.exclusivityParameter,
                message
            );
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  HANDLE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice SpokePool-authenticated fill-time delivery hook: reverts {AcrossNotSpokePool} unless
    ///         `msg.sender` is the configured SpokePool, then emits {AcrossMessageReceived}. NOTHING else in v1
    ///         — no handler registry (the diamond itself is the recipient; other facets manage received funds).
    /// @dev OPTIMISTIC: fills are relayer-pushed and NOT yet UMA-finalized when this is called — treat the
    ///      received funds/message as reversible-until-finalized. Never routed into OpenBridge (no M-of-N
    ///      confirmation, no `receiveId`).
    function handleV3AcrossMessage(address tokenSent, uint256 amount, address relayer, bytes calldata message)
        internal
    {
        ReentrancyGuardLib.nonReentrantBefore();
        if (msg.sender != acrossBridgeAdapterStorage()._spokePool) {
            revert IAcrossBridgeAdapter.AcrossNotSpokePool(msg.sender);
        }
        // GUARD-RAIL: this event is NOT an authenticated message — any party can originate the underlying
        // deposit (see the event natspec). Never let a future consumer treat it as attributed provenance.
        emit IAcrossBridgeAdapter.AcrossMessageReceived(tokenSent, amount, relayer, message);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Right-aligns an ERC-7930 chain-reference (<= 32 bytes, big-endian) into a uint256 chainId.
    /// @dev For eip-155 chains the reference IS the chainId. Reverts {AcrossChainReferenceTooLong} if > 32 bytes.
    function _chainIdFromReference(bytes memory ref) private pure returns (uint256 chainId) {
        uint256 len = ref.length;
        if (len > 32) revert IAcrossBridgeAdapter.AcrossChainReferenceTooLong(len);
        assembly ("memory-safe") {
            chainId := shr(mul(sub(32, len), 8), mload(add(ref, 0x20)))
        }
    }
}
