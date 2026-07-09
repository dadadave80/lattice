// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {BridgeFungibleLib} from "@lattice/crosschain/libraries/BridgeFungibleLib.sol";
import {AdapterBaseLib} from "@lattice/defi/libraries/AdapterBaseLib.sol";
import {IAggregatorExecAdapter} from "@lattice/interfaces/defi/IAggregatorExecAdapter.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.AggregatorExecAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant AGGREGATOR_EXEC_ADAPTER_STORAGE_SLOT =
    0xa2d04b4e843f01463940d93cd4d536111875b48fb08f2c3a7d094e91e39a5100;

/// @dev 0xe95f85f2 is `type(IAggregatorExecAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xe95f85f2), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IAGGREGATOREXECADAPTER_SLOT =
    0x3b0da15f74db1bb0d7ebc58a8d802243b2c7050873887bf8e60ab5b971b5a8e9;

/// @notice ERC-7201 namespaced storage for the aggregator execution adapter.
/// @custom:storage-location erc7201:lattice.storage.AggregatorExecAdapter
struct AggregatorExecAdapterStorage {
    /// @notice `(aggregator, selector)` allow-list: only pairs flagged `true` may be {execute}d. APPEND-ONLY.
    mapping(address aggregator => mapping(bytes4 selector => bool allowed)) _allowedCall;
}

/// @title AggregatorExecAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from LI.FI (https://github.com/lifinance/contracts)
/// @notice Logic + ERC-7201 storage for the generic swap/bridge EXECUTION adapter. {execute} forwards
///         off-chain-built calldata to an admin-allow-listed `(aggregator, selector)` pair, making an ARBITRARY
///         external call from a fund-holding diamond — so the entire design is confused-deputy prevention.
/// @dev SECURITY MODEL (why each step exists):
///      - Allow-list: `bytes4(callData)` is the selector the aggregator dispatches on, so gating
///        `_allowedCall[aggregator][selector]` gates exactly what the aggregator will do. `address(0)` and
///        `address(this)` can never be allow-listed (the latter would let crafted calldata re-enter privileged
///        facets — the classic confused-deputy on a diamond).
///      - Fund isolation: funds are pulled from `msg.sender` (never the diamond balance) and the aggregator is
///        granted an EXACT, immediately-reset approval. Balance snapshots taken BEFORE the pull/call make every
///        sweep DELTA-based, so a pre-existing standing balance of any token (or native) is provably untouched:
///        crafted calldata cannot route the diamond's OTHER holdings out.
///      - Approval hygiene: the input allowance is reset to 0 after every call (no standing grant to drain).
///      - Leftover sweep: unspent input (delta above the standing balance), the output-token delta, and any
///        unspent native are all returned to `msg.sender`, so the diamond nets zero from the call.
///      COMPOSITION INVARIANT (the delta-sweep protects ONLY input/output/native): this adapter itself never
///      leaves a standing ERC-20 allowance to any aggregator (it resets to 0 on every call), so it is safe
///      standalone. But if a DIFFERENT facet composed into the same diamond leaves a live allowance to an
///      allow-listed aggregator for some third token Z the diamond also holds, crafted calldata could swap that Z
///      out (its proceeds swept as the output delta). Integrators MUST NOT grant standing allowances to any
///      address that is (or may become) an allow-listed aggregator; a composability CI guard asserting zero
///      standing aggregator allowances is the recommended enforcement.
///      Reuses the shared safe-transfer / force-approve helpers ({BridgeFungibleLib.pullExact},
///      {AdapterBaseLib.forceApprove/transferHonest/balanceOfSelf}); no bespoke ERC-20 plumbing.
library AggregatorExecAdapterLib {
    function aggregatorExecAdapterStorage() internal pure returns (AggregatorExecAdapterStorage storage $) {
        assembly {
            $.slot := AGGREGATOR_EXEC_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IAggregatorExecAdapter ERC-165 id. Called inside the diamond initializing window.
    function __AggregatorExecAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for `IAggregatorExecAdapter`.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IAGGREGATOREXECADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function isAllowedCall(address aggregator, bytes4 selector) internal view returns (bool) {
        return aggregatorExecAdapterStorage()._allowedCall[aggregator][selector];
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Toggles allow-listing of the `(aggregator, selector)` pair. Admin only. `address(0)` and
    ///         `address(this)` are rejected — the diamond must NEVER be able to call ITSELF through this adapter.
    function setAllowedCall(address aggregator, bytes4 selector, bool allowed) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (aggregator == address(0) || aggregator == address(this)) {
            revert IAggregatorExecAdapter.AggregatorExecInvalidAggregator(aggregator);
        }
        aggregatorExecAdapterStorage()._allowedCall[aggregator][selector] = allowed;
        emit IAggregatorExecAdapter.AllowedCallSet(aggregator, selector, allowed);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  EXECUTE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Forwards `callData` to an allow-listed `(aggregator, bytes4(callData))` under strict CEI, pulling
    ///         `amount` of `inputToken` from `msg.sender`, approving EXACTLY that amount, then resetting the
    ///         approval to 0 and sweeping every leftover (unspent input, output delta, unspent native) back to
    ///         the caller. See {AggregatorExecAdapterLib} security model for why each step is present.
    function execute(
        address aggregator,
        address inputToken,
        uint256 amount,
        address outputToken,
        bytes calldata callData
    ) internal returns (bytes memory ret) {
        ReentrancyGuardLib.nonReentrantBefore();

        // --- Checks: the allow-list is the sole authorization primitive. ---
        if (callData.length < 4) revert IAggregatorExecAdapter.AggregatorExecEmptyCallData();
        bytes4 selector = bytes4(callData[:4]);
        if (!aggregatorExecAdapterStorage()._allowedCall[aggregator][selector]) {
            revert IAggregatorExecAdapter.AggregatorExecNotAllowed(aggregator, selector);
        }

        // Delta baselines taken BEFORE any movement so every sweep isolates pre-existing standing balances.
        bool sweepOutput = outputToken != address(0) && outputToken != inputToken;
        uint256 nativeBefore = address(this).balance - msg.value;
        uint256 inputBefore;
        uint256 outputBefore;

        // --- Effects/Interactions: pull from the CALLER, approve the aggregator for EXACTLY `amount`. ---
        if (inputToken != address(0)) {
            inputBefore = AdapterBaseLib.balanceOfSelf(inputToken);
            BridgeFungibleLib.pullExact(inputToken, msg.sender, amount);
            AdapterBaseLib.forceApprove(inputToken, aggregator, amount);
        }
        if (sweepOutput) outputBefore = AdapterBaseLib.balanceOfSelf(outputToken);

        // --- The arbitrary external call (opaque, untrusted calldata); bubble the revert verbatim. ---
        {
            (bool ok, bytes memory r) = aggregator.call{value: msg.value}(callData);
            if (!ok) {
                assembly ("memory-safe") {
                    revert(add(r, 0x20), mload(r))
                }
            }
            ret = r;
        }

        // --- Approval hygiene + leftover sweep (all deltas, so standing balances stay put). ---
        if (inputToken != address(0)) {
            AdapterBaseLib.forceApprove(inputToken, aggregator, 0);
            uint256 inputLeftover = AdapterBaseLib.balanceOfSelf(inputToken) - inputBefore;
            if (inputLeftover != 0) AdapterBaseLib.transferHonest(inputToken, msg.sender, inputLeftover);
        }
        if (sweepOutput) {
            uint256 outputDelta = AdapterBaseLib.balanceOfSelf(outputToken) - outputBefore;
            if (outputDelta != 0) AdapterBaseLib.transferHonest(outputToken, msg.sender, outputDelta);
        }
        {
            uint256 nativeLeftover = address(this).balance - nativeBefore;
            if (nativeLeftover != 0) {
                (bool sent,) = payable(msg.sender).call{value: nativeLeftover}("");
                if (!sent) revert IAggregatorExecAdapter.AggregatorExecNativeTransferFailed();
            }
        }

        emit IAggregatorExecAdapter.AggregatorCall(msg.sender, aggregator, selector, inputToken, amount, outputToken);
        ReentrancyGuardLib.nonReentrantAfter();
    }
}
