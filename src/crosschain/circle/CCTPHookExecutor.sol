// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ICCTPHookExecutor} from "@lattice/interfaces/crosschain/ICCTPHookExecutor.sol";
import {ICCTPHookReceiver} from "@lattice/interfaces/crosschain/ICCTPHookReceiver.sol";

/// @title CCTPHookExecutor
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Circle CCTP v2 (https://github.com/circlefin/evm-cctp-contracts)
/// @notice The role-less, fund-less contract every inbound CCTP hook is executed through — NOT a facet, NOT cut
///         into the diamond. It exists so that the ONLY thing that ever calls an attacker-named hook target is a
///         contract with no funds, no roles and no delegatecall reach; attacker bytes in a CCTP burn's `hookData`
///         therefore gain nothing beyond a plain EOA's authority. Deployed once per diamond by the adapter's init
///         (`new CCTPHookExecutor(address(this))`, delegatecalled so `address(this)` is the diamond) and stored
///         immutably — there is deliberately NO setter (a swappable executor would be a forgeable trust anchor).
/// @dev CCTP does NOT execute hooks; the destination recipient does. This executor is that recipient's
///      indirection: {executeHook} is gated to the immutable {relay} diamond and calls the target with the FIXED
///      {ICCTPHookReceiver-onCCTPHook} selector via assembly, forwarding no value, dropping ALL returndata
///      (return-bomb safe) and NEVER bubbling the target's revert — it returns a plain `bool success`. Every
///      context argument the relay passes is read from the Circle-ATTESTED message, never from `hookData`.
contract CCTPHookExecutor is ICCTPHookExecutor {
    /// @inheritdoc ICCTPHookExecutor
    address public immutable relay;

    /// @param relay_ The diamond deploying this executor (its only permitted caller). Non-zero by construction —
    ///        the init passes `address(this)` (the diamond), which is never zero.
    constructor(address relay_) {
        relay = relay_;
    }

    /// @inheritdoc ICCTPHookExecutor
    function executeHook(
        uint32 sourceDomain,
        bytes32 sender,
        bytes32 mintRecipient,
        uint256 amount,
        bytes32, /* nonce */
        address target,
        bytes calldata payload
    ) external returns (bool success) {
        if (msg.sender != relay) revert CCTPHookExecutorUnauthorized();

        // FIXED-selector calldata: the attacker chose `target` and `payload`, but NEVER which function runs.
        bytes memory callData =
            abi.encodeCall(ICCTPHookReceiver.onCCTPHook, (sourceDomain, sender, mintRecipient, amount, payload));

        // Low-level call: forward no value, copy NO returndata (return-bomb safe), and let a reverting target
        // surface only as `success == false` — the relay is LENIENT (the mint already stands, nonce consumed).
        assembly ("memory-safe") {
            success := call(gas(), target, 0, add(callData, 0x20), mload(callData), 0x00, 0x00)
        }
    }
}
