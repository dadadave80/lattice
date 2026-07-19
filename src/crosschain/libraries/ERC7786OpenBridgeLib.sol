// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ChainRegistryLib} from "@lattice/crosschain/libraries/ChainRegistryLib.sol";
import {IERC7786OpenBridge} from "@lattice/interfaces/crosschain/IERC7786OpenBridge.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC7786OpenBridge")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC7786_OPEN_BRIDGE_STORAGE_SLOT = 0xca75154ce55fdf901a786b6fa60962886fadca5cda61c777098bc66b49134a00;

/// @dev ERC-165 map slot for `IERC7786GatewaySource` (`0x11967553`). SHARED by all gateway adapters —
///      `keccak256(abi.encode(bytes4(0x11967553), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC7786GATEWAYSOURCE_SLOT =
    0x3c75b8ea75c097979221eb9302e2f0f6009b4ffe0a7198db5dc29979e09ea0e3;

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
    /// @notice Minimum DIRECT {ChainRegistryLib} coverage `sendMessage` requires of a destination
    ///         (0 = check disabled, the default — preserves pre-registry behavior). APPEND-ONLY.
    uint8 _minDirectCoverage;
}

/// @title ERC7786OpenBridgeLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin community-contracts `ERC7786OpenBridge` (https://github.com/OpenZeppelin/openzeppelin-community-contracts, commit f7e5f08).
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
            sstore(ERC165_MAP_IERC7786GATEWAYSOURCE_SLOT, true)
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

    function minDirectCoverage() internal view returns (uint8) {
        return erc7786OpenBridgeStorage()._minDirectCoverage;
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

    /// @notice Sets the M-of-N coverage-awareness knob (issue #77 Q5): when non-zero, {sendMessage} refuses
    ///         destinations whose DIRECT registry coverage is below it (set 2+ to hard-refuse M=1 routes; 0 —
    ///         the default — disables the check entirely, so a diamond without a chain registry keeps working).
    function setMinDirectCoverage(uint8 minDirectCoverage_) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        erc7786OpenBridgeStorage()._minDirectCoverage = minDirectCoverage_;
        emit IERC7786OpenBridge.MinDirectCoverageUpdated(minDirectCoverage_);
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
    /// @dev COVERAGE GATE (issue #77 Q5): when the admin has set `_minDirectCoverage` non-zero, the parsed
    ///      destination chain must have at least that many DIRECT (non-hub-routed) gateways recorded in the
    ///      chain registry — {OpenBridgeInsufficientCoverage} otherwise. The default 0 skips the registry
    ///      read entirely, so a diamond without a chain registry record (or facet) behaves exactly as before.
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        internal
        returns (bytes32 sendId)
    {
        if (msg.value != 0) revert IERC7786OpenBridge.UnsupportedNativeTransfer();
        if (attributes.length > 0) revert IERC7786GatewaySource.UnsupportedAttribute(bytes4(attributes[0]));

        ERC7786OpenBridgeStorage storage $ = erc7786OpenBridgeStorage();
        bytes memory sender = InteroperableAddress.formatEvmV1(block.chainid, msg.sender);
        bytes memory wrapped = abi.encode(++$._nonce, sender, recipient, payload);
        sendId = _fanOut($, _resolveRemoteBridge($, recipient), wrapped, attributes);
        emit IERC7786GatewaySource.MessageSent(sendId, sender, recipient, payload, 0, attributes);
    }

    /// @notice Parses the destination chain out of `recipient` ONCE, enforces the coverage gate on it, and
    ///         resolves the matching remote bridge (split into a helper to stay under the non-via-IR stack
    ///         limit — see {sendMessage} for the gate semantics).
    function _resolveRemoteBridge(ERC7786OpenBridgeStorage storage $, bytes calldata recipient)
        private
        view
        returns (bytes memory bridge)
    {
        (bytes2 chainType, bytes calldata chainReference,) = InteroperableAddress.parseV1Calldata(recipient);
        uint8 wantCoverage = $._minDirectCoverage;
        if (wantCoverage != 0) {
            uint256 haveCoverage =
                ChainRegistryLib.directCoverageOf(ChainRegistryLib.chainKeyOf(chainType, chainReference));
            if (haveCoverage < wantCoverage) {
                revert IERC7786OpenBridge.OpenBridgeInsufficientCoverage(haveCoverage, wantCoverage);
            }
        }
        bridge = $._remotes[chainType][chainReference];
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
