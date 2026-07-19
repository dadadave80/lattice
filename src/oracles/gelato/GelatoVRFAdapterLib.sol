// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IGelatoVRFConsumer} from "@lattice/interfaces/external/gelato/IGelatoVRFConsumer.sol";
import {IGelatoVRFAdapter} from "@lattice/interfaces/oracles/IGelatoVRFAdapter.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.GelatoVRFAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant GELATO_VRF_ADAPTER_STORAGE_SLOT = 0x411b018662c29400f5f1d8919575dbc72aa8b7559a2445103c6d3b36a4058500;

/// @dev 0x648cc6c7 is `type(IGelatoVRFAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x648cc6c7), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IGELATOVRFADAPTER_SLOT = 0x96d079b02f2bbbe165b473b6ab18c1244741cc699c115aaf2550dd64c3fba9dd;

/// @notice ERC-7201 namespaced storage for GelatoVRFAdapter.
/// @custom:storage-location erc7201:lattice.storage.GelatoVRFAdapter
struct GelatoVRFAdapterStorage {
    address _operator;
    uint256 _nextRequestId;
    mapping(uint256 requestId => bytes32 userKey) _pendingRequests;
}

/// @title GelatoVRFAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Gelato (https://github.com/gelatodigital/vrf-contracts)
/// @notice Library that wraps Gelato VRF (drand-backed, quicknet beacon) random
///         requests.  This is the request/track layer only — fulfillment
///         bookkeeping is handled here, but consumer facets inheriting
///         `GelatoVRFAdapter` should override `fulfillRandomness` (calling
///         `super.fulfillRandomness` first) to actually consume the randomness.
library GelatoVRFAdapterLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Genesis timestamp of the drand quicknet beacon used by Gelato VRF.
    uint256 internal constant _GENESIS = 1_692_803_367;

    /// @dev Period (in seconds) between drand quicknet beacon rounds.
    uint256 internal constant _PERIOD = 3;

    /// @notice Returns the ERC-7201 storage struct for GelatoVRFAdapter.
    function gelatoVRFAdapterStorage() internal pure returns (GelatoVRFAdapterStorage storage $) {
        assembly {
            $.slot := GELATO_VRF_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IGelatoVRFAdapter ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __GelatoVRFAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for IGelatoVRFAdapter.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IGELATOVRFADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the configured operator, reverting if unset.
    /// @return op The configured dedicated operator.
    function _requireOperator() internal view returns (address op) {
        GelatoVRFAdapterStorage storage $ = gelatoVRFAdapterStorage();
        op = $._operator;
        if (op == address(0)) revert IGelatoVRFAdapter.GelatoVRFNotConfigured();
    }

    /// @notice Returns the current drand round for the quicknet beacon.
    /// @dev Underflow-guarded so it is safe at low test timestamps.
    function _round() internal view returns (uint256) {
        uint256 elapsed = block.timestamp > _GENESIS ? block.timestamp - _GENESIS : 0;
        return elapsed / _PERIOD + 1;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the configured dedicated operator.
    function getOperator() internal view returns (address) {
        return gelatoVRFAdapterStorage()._operator;
    }

    /// @notice Returns the user key associated with a pending request.
    /// @param requestId The adapter-assigned request ID.
    function getUserKey(uint256 requestId) internal view returns (bytes32) {
        return gelatoVRFAdapterStorage()._pendingRequests[requestId];
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets or replaces the dedicated operator.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    ///      Reverts `GelatoVRFInvalidOperator` if `operator` is zero.
    /// @param operator The new dedicated operator.
    function setOperator(address operator) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (operator == address(0)) revert IGelatoVRFAdapter.GelatoVRFInvalidOperator();
        GelatoVRFAdapterStorage storage $ = gelatoVRFAdapterStorage();
        $._operator = operator;
        emit IGelatoVRFAdapter.GelatoVRFOperatorSet(operator);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Requests randomness from Gelato VRF.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    ///      Stores the `userKey` against the returned `requestId` so the
    ///      fulfillment callback can look it up, then emits both the adapter
    ///      `RandomnessRequested` event and the Gelato `RequestedRandomness`
    ///      event the dedicated operator listens for.
    ///      Reverts `GelatoVRFInvalidUserKey` if `userKey` is the zero sentinel
    ///      and `GelatoVRFNotConfigured` if no operator has been set.
    /// @param userKey Arbitrary key the caller wants associated with this request.
    /// @return requestId The adapter-assigned request ID.
    function requestRandomness(bytes32 userKey) internal returns (uint256 requestId) {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        // bytes32(0) is the sentinel used by fulfillRandomness to detect a
        // missing pending request. Reject it here to prevent silent sentinel collision.
        if (userKey == bytes32(0)) revert IGelatoVRFAdapter.GelatoVRFInvalidUserKey();
        _requireOperator();

        GelatoVRFAdapterStorage storage $ = gelatoVRFAdapterStorage();
        requestId = $._nextRequestId;
        unchecked {
            $._nextRequestId = requestId + 1;
        }
        $._pendingRequests[requestId] = userKey;

        uint256 round = _round();
        bytes memory data = abi.encode(requestId, userKey);
        bytes memory dataWithRound = abi.encode(round, data);
        emit IGelatoVRFAdapter.RandomnessRequested(requestId, userKey, round);
        emit IGelatoVRFConsumer.RequestedRandomness(round, dataWithRound);
    }

    /// @notice Called by the dedicated operator to deliver randomness.
    /// @dev Verifies the caller is the configured operator (`msg.sender`),
    ///      decodes the request, looks up the user key, clears the pending
    ///      entry, domain-separates the randomness per request, and emits
    ///      `RandomnessFulfilled`.
    ///
    ///      NOTE: This function only manages bookkeeping.  Consumer facets that
    ///      inherit `GelatoVRFAdapter` should override `fulfillRandomness` (or
    ///      provide a follow-up hook) to act on the delivered randomness.
    /// @param randomness    The drand-derived randomness for the requested round.
    /// @param dataWithRound The opaque payload originally emitted in `RequestedRandomness`.
    function fulfillRandomness(uint256 randomness, bytes calldata dataWithRound) internal {
        GelatoVRFAdapterStorage storage $ = gelatoVRFAdapterStorage();

        // Authenticate the dedicated operator by its address.
        address op = $._operator;
        if (msg.sender != op) revert IGelatoVRFAdapter.GelatoVRFOnlyOperator(msg.sender);

        (uint256 round, bytes memory data) = abi.decode(dataWithRound, (uint256, bytes));
        (round);
        (uint256 requestId, bytes32 userKey) = abi.decode(data, (uint256, bytes32));

        bytes32 stored = $._pendingRequests[requestId];
        if (stored == bytes32(0) || stored != userKey) {
            revert IGelatoVRFAdapter.GelatoVRFRequestNotFound(requestId);
        }

        delete $._pendingRequests[requestId];

        uint256 derived = uint256(keccak256(abi.encode(randomness, address(this), block.chainid, requestId)));
        emit IGelatoVRFAdapter.RandomnessFulfilled(requestId, userKey, derived);
    }
}
