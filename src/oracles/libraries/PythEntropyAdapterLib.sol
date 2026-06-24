// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IPythEntropyAdapter} from "@lattice/interfaces/IPythEntropyAdapter.sol";
import {IEntropy} from "@lattice/interfaces/external/IEntropy.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.PythEntropyAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant PYTH_ENTROPY_ADAPTER_STORAGE_SLOT = 0xf5638fd8a7410f61ded501225ccb03fd632a93dd0cfb1615ce2666e2781d4f00;

/// @dev 0x4da4fb45 is `type(IPythEntropyAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x4da4fb45), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IPYTHENTROPYADAPTER_SLOT =
    0x0b3233815ce1b1f92051bbb497fa74751e231e11c662dee243cd17d8f2a816f7;

/// @notice ERC-7201 namespaced storage for PythEntropyAdapter.
/// @custom:storage-location erc7201:lattice.storage.PythEntropyAdapter
struct PythEntropyAdapterStorage {
    address _entropy;
    address _provider;
    mapping(uint64 sequenceNumber => bytes32 userKey) _pendingRequests;
}

/// @title PythEntropyAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Pyth (https://github.com/pyth-network/pyth-crosschain)
/// @notice Library that wraps Pyth Entropy on-demand (commit/reveal) randomness requests. This is the
///         request/track layer only — fulfillment bookkeeping is handled here, but consumer facets
///         inheriting `PythEntropyAdapter` should override `entropyCallback` (calling
///         `super.entropyCallback` first) to actually consume the delivered randomness.
library PythEntropyAdapterLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the ERC-7201 storage struct for PythEntropyAdapter.
    function pythEntropyAdapterStorage() internal pure returns (PythEntropyAdapterStorage storage $) {
        assembly {
            $.slot := PYTH_ENTROPY_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IPythEntropyAdapter ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __PythEntropyAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for IPythEntropyAdapter.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IPYTHENTROPYADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the current Entropy configuration.
    function getConfig() internal view returns (IPythEntropyAdapter.EntropyConfig memory config) {
        PythEntropyAdapterStorage storage $ = pythEntropyAdapterStorage();
        config = IPythEntropyAdapter.EntropyConfig({entropy: $._entropy, provider: $._provider});
    }

    /// @notice Returns the fee (in wei) required for one request under the current config.
    /// @dev Reverts `EntropyNotConfigured` if the Entropy contract has not been set.
    function getFee() internal view returns (uint256) {
        address e = _requireEntropy();
        return uint256(IEntropy(e).getFee(_resolveProvider(pythEntropyAdapterStorage())));
    }

    /// @notice Returns the user key associated with a pending request.
    /// @param sequenceNumber The Entropy-assigned sequence number.
    function getUserKey(uint64 sequenceNumber) internal view returns (bytes32) {
        return pythEntropyAdapterStorage()._pendingRequests[sequenceNumber];
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets or replaces the Entropy configuration.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    ///      Reverts `EntropyInvalidConfig` if the Entropy contract is zero.
    /// @param config The new Entropy configuration.
    function setConfig(IPythEntropyAdapter.EntropyConfig calldata config) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (config.entropy == address(0)) revert IPythEntropyAdapter.EntropyInvalidConfig();
        PythEntropyAdapterStorage storage $ = pythEntropyAdapterStorage();
        $._entropy = config.entropy;
        $._provider = config.provider;
        emit IPythEntropyAdapter.EntropyConfigSet(config.entropy, config.provider);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Requests a random number from Pyth Entropy, caller-funded with excess refunded.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    ///      Stores the `userKey` against the returned `sequenceNumber` so the fulfillment callback can
    ///      look it up. Reverts `EntropyNotConfigured` if the Entropy contract has not been set,
    ///      `EntropyInvalidUserKey` on a zero `userKey`, and `EntropyInsufficientFee` if `msg.value`
    ///      is below the quoted fee.
    /// @param userKey          Arbitrary key the caller wants associated with this request.
    /// @param userRandomNumber The caller's commitment to its half of the randomness.
    /// @return sequenceNumber The Entropy-assigned sequence number.
    function requestRandomNumber(bytes32 userKey, bytes32 userRandomNumber) internal returns (uint64 sequenceNumber) {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        // bytes32(0) is the sentinel used by entropyCallback to detect a missing pending request.
        // Reject it here to prevent silent sentinel collision.
        if (userKey == bytes32(0)) revert IPythEntropyAdapter.EntropyInvalidUserKey();

        PythEntropyAdapterStorage storage $ = pythEntropyAdapterStorage();
        address e = _requireEntropy();
        address p = _resolveProvider($);

        uint256 fee = uint256(IEntropy(e).getFee(p));
        if (msg.value < fee) revert IPythEntropyAdapter.EntropyInsufficientFee(msg.value, fee);

        sequenceNumber = IEntropy(e).requestWithCallback{value: fee}(p, userRandomNumber);
        $._pendingRequests[sequenceNumber] = userKey;
        emit IPythEntropyAdapter.RandomNumberRequested(sequenceNumber, userKey);

        uint256 refund = msg.value - fee;
        if (refund != 0) {
            (bool ok,) = msg.sender.call{value: refund}("");
            if (!ok) revert IPythEntropyAdapter.EntropyRefundFailed();
        }
    }

    /// @notice Called by the Entropy contract to deliver a random number.
    /// @dev Verifies the caller is the configured Entropy contract by its address (`msg.sender`),
    ///      looks up the user key, clears the pending entry, and emits `RandomNumberFulfilled`.
    ///
    ///      NOTE: This function only manages bookkeeping. Consumer facets that inherit
    ///      `PythEntropyAdapter` should override `entropyCallback` (calling `super.entropyCallback`
    ///      first) to act on the delivered randomness.
    /// @param sequence     The Entropy-assigned sequence number.
    /// @param provider     The provider that fulfilled the request (unused at this layer).
    /// @param randomNumber The delivered random number.
    function entropyCallback(uint64 sequence, address provider, bytes32 randomNumber) internal {
        PythEntropyAdapterStorage storage $ = pythEntropyAdapterStorage();

        // Authenticate the Entropy contract by its address.
        if (msg.sender != $._entropy) revert IPythEntropyAdapter.EntropyOnlyEntropy(msg.sender);

        bytes32 userKey = $._pendingRequests[sequence];
        if (userKey == bytes32(0)) revert IPythEntropyAdapter.EntropyRequestNotFound(sequence);

        delete $._pendingRequests[sequence];
        emit IPythEntropyAdapter.RandomNumberFulfilled(sequence, userKey, randomNumber);

        // provider is passed in but not consumed at this layer.
        // Silence the unused-variable warning.
        (provider);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Resolves the effective provider, falling back to the Entropy default provider.
    function _resolveProvider(PythEntropyAdapterStorage storage $) private view returns (address) {
        return $._provider == address(0) ? IEntropy($._entropy).getDefaultProvider() : $._provider;
    }

    /// @notice Returns the configured Entropy contract or reverts `EntropyNotConfigured`.
    function _requireEntropy() private view returns (address e) {
        e = pythEntropyAdapterStorage()._entropy;
        if (e == address(0)) revert IPythEntropyAdapter.EntropyNotConfigured();
    }
}
