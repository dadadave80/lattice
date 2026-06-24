// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAPI3QRNGAdapter} from "@lattice/interfaces/IAPI3QRNGAdapter.sol";
import {IAirnodeRrpV0} from "@lattice/interfaces/external/IAirnodeRrpV0.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.API3QRNGAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant API3_QRNG_ADAPTER_STORAGE_SLOT = 0xb551ab661bfaed153d497ffdaa9cbb1d46fa1d799d8e6f2a2aa8ecfb66104b00;

/// @dev 0xae37b187 is `type(IAPI3QRNGAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xae37b187), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IAPI3QRNGADAPTER_SLOT = 0x686b5c002fca8114a8568270b3aef529a60083a8d9c09dbd16e3a0bb6b30bfcf;

/// @notice ERC-7201 namespaced storage for API3QRNGAdapter.
/// @custom:storage-location erc7201:lattice.storage.API3QRNGAdapter
struct API3QRNGAdapterStorage {
    address _airnodeRrp;
    address _airnode;
    bytes32 _endpointId;
    address _sponsorWallet;
    mapping(bytes32 requestId => bytes32 userKey) _pendingRequests;
}

/// @title API3QRNGAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from API3 (https://github.com/api3dao/airnode)
/// @notice Library that wraps API3 QRNG (quantum randomness) over the Airnode
///         Request-Response Protocol (self-sponsoring).  This is the
///         request/track layer only — fulfillment bookkeeping is handled here,
///         but consumer facets inheriting `API3QRNGAdapter` should override
///         `fulfillRandomNumber` (calling `super.fulfillRandomNumber` first) to
///         actually consume the delivered randomness.
library API3QRNGAdapterLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the ERC-7201 storage struct for API3QRNGAdapter.
    function api3QRNGAdapterStorage() internal pure returns (API3QRNGAdapterStorage storage $) {
        assembly {
            $.slot := API3_QRNG_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IAPI3QRNGAdapter ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __API3QRNGAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for IAPI3QRNGAdapter.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IAPI3QRNGADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the current QRNG configuration.
    function getConfig() internal view returns (IAPI3QRNGAdapter.QRNGConfig memory config) {
        API3QRNGAdapterStorage storage $ = api3QRNGAdapterStorage();
        config = IAPI3QRNGAdapter.QRNGConfig({
            airnodeRrp: $._airnodeRrp, airnode: $._airnode, endpointId: $._endpointId, sponsorWallet: $._sponsorWallet
        });
    }

    /// @notice Returns the user key associated with a pending request.
    /// @param requestId The RRP-assigned request ID.
    function getUserKey(bytes32 requestId) internal view returns (bytes32) {
        return api3QRNGAdapterStorage()._pendingRequests[requestId];
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets or replaces the QRNG configuration.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    ///      Reverts `QRNGInvalidConfig` if any field is zero.
    /// @param c The new QRNG configuration.
    function setConfig(IAPI3QRNGAdapter.QRNGConfig calldata c) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (
            c.airnodeRrp == address(0) || c.airnode == address(0) || c.endpointId == bytes32(0)
                || c.sponsorWallet == address(0)
        ) {
            revert IAPI3QRNGAdapter.QRNGInvalidConfig();
        }
        API3QRNGAdapterStorage storage $ = api3QRNGAdapterStorage();
        $._airnodeRrp = c.airnodeRrp;
        $._airnode = c.airnode;
        $._endpointId = c.endpointId;
        $._sponsorWallet = c.sponsorWallet;
        emit IAPI3QRNGAdapter.QRNGConfigSet(c.airnodeRrp, c.airnode, c.endpointId, c.sponsorWallet);
    }

    /// @notice Registers (or revokes) this contract as its own sponsor with the Airnode RRP.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    ///      Reverts `QRNGNotConfigured` if the Airnode RRP has not been set.
    /// @param status True to self-sponsor, false to revoke.
    function setSelfSponsorship(bool status) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        address r = _requireAirnodeRrp();
        IAirnodeRrpV0(r).setSponsorshipStatus(address(this), status);
        emit IAPI3QRNGAdapter.QRNGSelfSponsorshipSet(status);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Requests a quantum random number via the Airnode RRP.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    ///      Stores the `userKey` against the returned `requestId` so the
    ///      fulfillment callback can look it up.
    ///      Reverts `QRNGNotConfigured` if the Airnode RRP has not been set.
    /// @param userKey Arbitrary key the caller wants associated with this request.
    /// @return requestId The RRP-assigned request ID.
    function requestRandomNumber(bytes32 userKey) internal returns (bytes32 requestId) {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        // bytes32(0) is the sentinel used by fulfillRandomNumber to detect a
        // missing pending request. Reject it here to prevent silent sentinel collision.
        if (userKey == bytes32(0)) revert IAPI3QRNGAdapter.QRNGInvalidUserKey();
        address r = _requireAirnodeRrp();
        API3QRNGAdapterStorage storage $ = api3QRNGAdapterStorage();

        requestId = IAirnodeRrpV0(r)
            .makeFullRequest(
                $._airnode,
                $._endpointId,
                address(this),
                $._sponsorWallet,
                address(this),
                IAPI3QRNGAdapter.fulfillRandomNumber.selector,
                ""
            );
        $._pendingRequests[requestId] = userKey;
        emit IAPI3QRNGAdapter.RandomNumberRequested(requestId, userKey);
    }

    /// @notice Called by the Airnode RRP to deliver the random number.
    /// @dev Verifies the caller is the configured Airnode RRP by its address (`msg.sender`),
    ///      looks up the user key, clears the pending entry, decodes the random
    ///      number, and emits `RandomNumberFulfilled`.
    ///
    ///      NOTE: This function only manages bookkeeping.  Consumer facets that
    ///      inherit `API3QRNGAdapter` should override `fulfillRandomNumber` (or
    ///      provide a follow-up hook) to act on the delivered randomness.
    /// @param requestId The RRP-assigned request ID.
    /// @param data      The ABI-encoded random number (`abi.encode(uint256)`).
    function fulfillRandomNumber(bytes32 requestId, bytes calldata data) internal {
        API3QRNGAdapterStorage storage $ = api3QRNGAdapterStorage();

        // Authenticate the Airnode RRP by its address.
        if (msg.sender != $._airnodeRrp) revert IAPI3QRNGAdapter.QRNGOnlyAirnodeRrp(msg.sender);

        bytes32 userKey = $._pendingRequests[requestId];
        if (userKey == bytes32(0)) revert IAPI3QRNGAdapter.QRNGRequestNotFound(requestId);

        delete $._pendingRequests[requestId];
        uint256 randomNumber = abi.decode(data, (uint256));
        emit IAPI3QRNGAdapter.RandomNumberFulfilled(requestId, userKey, randomNumber);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the configured Airnode RRP address, reverting if unset.
    function _requireAirnodeRrp() private view returns (address r) {
        r = api3QRNGAdapterStorage()._airnodeRrp;
        if (r == address(0)) revert IAPI3QRNGAdapter.QRNGNotConfigured();
    }
}
