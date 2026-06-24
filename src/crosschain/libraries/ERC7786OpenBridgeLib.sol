// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IERC7786OpenBridge} from "@lattice/interfaces/IERC7786OpenBridge.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/IERC7786.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC7786OpenBridge")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC7786_OPEN_BRIDGE_STORAGE_SLOT = 0xca75154ce55fdf901a786b6fa60962886fadca5cda61c777098bc66b49134a00;

/// @notice Per-message attestation tracker (N-of-M).
struct OpenBridgeTracker {
    mapping(address gateway => bool received) receivedBy;
    uint8 countReceived;
    bool executed;
}

/// @notice ERC-7201 namespaced storage for the ERC-7786 OpenBridge aggregator.
/// @custom:storage-location erc7201:lattice.storage.ERC7786OpenBridge
struct ERC7786OpenBridgeStorage {
    /// @notice The M gateways the bridge fans messages across / accepts attestations from. APPEND-ONLY.
    EnumerableSet.AddressSet _gateways;
    /// @notice The N attestation threshold required to deliver. APPEND-ONLY.
    uint8 _threshold;
    /// @notice Outbound de-dup nonce. APPEND-ONLY.
    uint256 _nonce;
    /// @notice Matching remote bridge per chain (full ERC-7930 address). APPEND-ONLY.
    mapping(bytes2 chainType => mapping(bytes chainReference => bytes bridge)) _remotes;
    /// @notice Inbound attestation trackers by message id. APPEND-ONLY.
    mapping(bytes32 id => OpenBridgeTracker tracker) _trackers;
}

/// @title ERC7786OpenBridgeLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin community-contracts `ERC7786OpenBridge` (commit f7e5f08).
/// @notice N-of-M ERC-7786 aggregator: `sendMessage` fans a wrapped message out across M gateways;
///         `receiveMessage` counts independent gateway attestations and delivers to the recipient once N
///         agree (retry-on-failure, executed-flag reentrancy guard). Both a source gateway and a recipient.
library ERC7786OpenBridgeLib {
    using EnumerableSet for EnumerableSet.AddressSet;

    function erc7786OpenBridgeStorage() internal pure returns (ERC7786OpenBridgeStorage storage $) {
        assembly {
            $.slot := ERC7786_OPEN_BRIDGE_STORAGE_SLOT
        }
    }

    /// @notice Registers the shared IERC7786GatewaySource ERC-165 interface.
    function __ERC7786OpenBridge_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the SHARED IERC7786GatewaySource ERC-165 map slot (0x11967553 → ...).
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(0x3c75b8ea75c097979221eb9302e2f0f6009b4ffe0a7198db5dc29979e09ea0e3, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function getGateways() internal view returns (address[] memory) {
        return erc7786OpenBridgeStorage()._gateways.values();
    }

    function getThreshold() internal view returns (uint8) {
        return erc7786OpenBridgeStorage()._threshold;
    }

    function getRemoteBridge(bytes memory chain) internal view returns (bytes memory) {
        (bytes2 chainType, bytes memory chainReference,) = InteroperableAddress.parseV1(chain);
        return erc7786OpenBridgeStorage()._remotes[chainType][chainReference];
    }

    function supportsAttribute(bytes4) internal pure returns (bool) {
        return false;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    function addGateway(address gateway) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        erc7786OpenBridgeStorage()._gateways.add(gateway);
        emit IERC7786OpenBridge.GatewayAdded(gateway);
    }

    function removeGateway(address gateway) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC7786OpenBridgeStorage storage $ = erc7786OpenBridgeStorage();
        $._gateways.remove(gateway);
        if ($._threshold > $._gateways.length()) revert IERC7786OpenBridge.ThresholdViolation();
        emit IERC7786OpenBridge.GatewayRemoved(gateway);
    }

    function setThreshold(uint8 threshold) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC7786OpenBridgeStorage storage $ = erc7786OpenBridgeStorage();
        if (threshold == 0 || threshold > $._gateways.length()) revert IERC7786OpenBridge.ThresholdViolation();
        $._threshold = threshold;
        emit IERC7786OpenBridge.ThresholdUpdated(threshold);
    }

    function registerRemoteBridge(bytes calldata bridge) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        (bytes2 chainType, bytes memory chainReference,) = InteroperableAddress.parseV1(bridge);
        ERC7786OpenBridgeStorage storage $ = erc7786OpenBridgeStorage();
        if ($._remotes[chainType][chainReference].length != 0) {
            revert IERC7786OpenBridge.RemoteBridgeAlreadyRegistered(InteroperableAddress.formatV1(
                    chainType, chainReference, hex""
                ));
        }
        $._remotes[chainType][chainReference] = bridge;
        emit IERC7786OpenBridge.RegisteredRemoteBridge(bridge);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 MESSAGING
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice ERC-7786 source: wraps the message and fans it out across all gateways to the matching
    ///         remote bridge. Rejects value + attributes. `sendId` = keccak of the per-gateway ids (or 0).
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        internal
        returns (bytes32 sendId)
    {
        if (msg.value != 0) revert IERC7786OpenBridge.UnsupportedNativeTransfer();
        if (attributes.length > 0) revert IERC7786GatewaySource.UnsupportedAttribute(bytes4(attributes[0]));

        ERC7786OpenBridgeStorage storage $ = erc7786OpenBridgeStorage();
        bytes memory sender = InteroperableAddress.formatEvmV1(block.chainid, msg.sender);
        bytes memory wrapped = abi.encode(++$._nonce, sender, recipient, payload);
        sendId = _fanOut($, getRemoteBridge(recipient), wrapped, attributes);
        emit IERC7786GatewaySource.MessageSent(sendId, sender, recipient, payload, 0, attributes);
    }

    /// @notice ERC-7786 recipient: count an attesting gateway and, once the N threshold is met, deliver
    ///         the unwrapped message to the final recipient. Idempotent per gateway; retryable on failure.
    function receiveMessage(bytes32, bytes calldata sender, bytes calldata payload) internal returns (bytes4) {
        ERC7786OpenBridgeStorage storage $ = erc7786OpenBridgeStorage();
        if (keccak256(getRemoteBridge(sender)) != keccak256(sender)) {
            revert IERC7786OpenBridge.InvalidCrosschainSender();
        }

        bytes32 id = keccak256(abi.encode(sender, payload));
        OpenBridgeTracker storage t = $._trackers[id];
        if ($._gateways.contains(msg.sender) && !t.receivedBy[msg.sender]) {
            t.receivedBy[msg.sender] = true;
            ++t.countReceived;
            emit IERC7786OpenBridge.Received(id, msg.sender);
        }

        if (!t.executed && t.countReceived >= $._threshold) _execute(t, id, payload);
        return IERC7786Recipient.receiveMessage.selector;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sends `wrapped` to every gateway addressed to `bridge`; returns keccak of the non-zero ids.
    function _fanOut(
        ERC7786OpenBridgeStorage storage $,
        bytes memory bridge,
        bytes memory wrapped,
        bytes[] calldata attributes
    ) private returns (bytes32) {
        address[] memory gws = $._gateways.values();
        bytes32[] memory outbox = new bytes32[](gws.length);
        uint256 n;
        for (uint256 i; i < gws.length; ++i) {
            bytes32 oid = IERC7786GatewaySource(gws[i]).sendMessage(bridge, wrapped, attributes);
            if (oid != bytes32(0)) outbox[n++] = oid;
        }
        if (n == 0) return bytes32(0);
        assembly ("memory-safe") {
            mstore(outbox, n) // shrink to the non-zero count
        }
        bytes32 sendId = keccak256(abi.encode(outbox));
        emit IERC7786OpenBridge.OutboxDetails(sendId, outbox);
        return sendId;
    }

    /// @notice Decodes the wrapped payload and delivers it. Sets `executed` BEFORE the call (reentrancy
    ///         guard); a failing recipient call rolls that back and leaves the message retryable.
    function _execute(OpenBridgeTracker storage t, bytes32 id, bytes calldata payload) private {
        t.executed = true;
        (, bytes memory originalSender, bytes memory recipient, bytes memory unwrapped) =
            abi.decode(payload, (uint256, bytes, bytes, bytes));
        (, address target) = InteroperableAddress.parseEvmV1(recipient);
        (bool ok, bytes memory ret) =
            target.call(abi.encodeCall(IERC7786Recipient.receiveMessage, (id, originalSender, unwrapped)));
        if (!ok) {
            t.executed = false;
            emit IERC7786OpenBridge.ExecutionFailed(id);
        } else if (abi.decode(ret, (bytes4)) != IERC7786Recipient.receiveMessage.selector) {
            revert IERC7786OpenBridge.InvalidExecutionReturnValue();
        } else {
            emit IERC7786OpenBridge.ExecutionSuccess(id);
        }
    }
}
