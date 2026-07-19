// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ITellor} from "@lattice/interfaces/external/tellor/ITellor.sol";
import {ITellorAdapter} from "@lattice/interfaces/oracles/ITellorAdapter.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.TellorAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant TELLOR_ADAPTER_STORAGE_SLOT = 0xf830cd05b050ba9ecf73559ef9b50793eb6cd90a674e3621847f667a1210d100;

/// @dev 0xddc762ca is `type(ITellorAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xddc762ca), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ITELLORADAPTER_SLOT = 0xd0880994b1b91b07c905771aa510c46b61d48fe80d33acc431dc49f1cf7b22c5;

/// @notice Packed data for a single registered Tellor feed.
/// @dev APPEND-ONLY. A registered feed has `maxStaleness != 0` (the not-registered sentinel).
struct TellorFeed {
    /// @notice The Tellor query id.
    bytes32 queryId;
    /// @notice Seconds subtracted from `block.timestamp` when reading (dispute window); 0 = no buffer.
    uint48 disputeBuffer;
    /// @notice Maximum age in seconds before a value is considered stale.
    uint48 maxStaleness;
}

/// @notice ERC-7201 namespaced storage for TellorAdapter.
/// @dev APPEND-ONLY: new fields may only be added at the end.
/// @custom:storage-location erc7201:lattice.storage.TellorAdapter
struct TellorAdapterStorage {
    /// @dev feed key => feed config.
    mapping(bytes32 key => TellorFeed) _feeds;
    /// @dev the Tellor contract.
    address _tellor;
}

/// @title TellorAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Tellor (https://github.com/tellor-io)
/// @notice Library wrapping the dispute-based Tellor oracle with per-feed dispute-buffer + staleness
///         configuration and WAD normalization, exposing the shared {IPriceOracleReader} read surface.
/// @dev Three-layer pattern: this library holds the logic + namespaced storage; the stateless
///      {TellorAdapter} facet forwards to it. Reads use Tellor's `getDataBefore` at a dispute buffer
///      offset (so disputed values are removed first) and validate presence, future timestamp, and
///      staleness on-chain. SpotPrice values are `abi.encode(uint256)` at 18 decimals (WAD).
library TellorAdapterLib {
    function tellorAdapterStorage() internal pure returns (TellorAdapterStorage storage $) {
        assembly {
            $.slot := TELLOR_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes TellorAdapter with the Tellor contract and registers the ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __TellorAdapter_init(address tellor_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        if (tellor_ == address(0)) revert ITellorAdapter.TellorContractIsZero();
        tellorAdapterStorage()._tellor = tellor_;
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for ITellorAdapter.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ITELLORADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function tellor() internal view returns (address) {
        return tellorAdapterStorage()._tellor;
    }

    function getFeed(bytes32 key) internal view returns (bytes32 queryId, uint48 disputeBuffer, uint48 maxStaleness) {
        TellorFeed storage f = tellorAdapterStorage()._feeds[key];
        return (f.queryId, f.disputeBuffer, f.maxStaleness);
    }

    /// @notice Returns the validated raw Tellor value bytes and report timestamp, read with the feed's
    ///         dispute buffer.
    /// @dev Validates: registration, presence (found + non-empty), future timestamp, and staleness. Reads
    ///      `getDataBefore` at `block.timestamp - disputeBuffer` so disputed values have time to be removed
    ///      first.
    function getDataBefore(bytes32 key) internal view returns (bytes memory value, uint256 timestamp) {
        TellorFeed storage f = tellorAdapterStorage()._feeds[key];
        if (f.maxStaleness == 0) revert ITellorAdapter.TellorFeedNotRegistered(key);

        bool found;
        (found, value, timestamp) =
            ITellor(_requireTellor()).getDataBefore(f.queryId, block.timestamp - f.disputeBuffer);
        if (!found || value.length == 0) revert ITellorAdapter.TellorNoData(key);
        // Future-timestamp guard (avoids an underflow panic and rejects impossible data); treated as stale.
        if (timestamp > block.timestamp || block.timestamp - timestamp > f.maxStaleness) {
            revert ITellorAdapter.TellorStaleData(key, timestamp, f.maxStaleness);
        }
    }

    /// @notice Returns the latest Tellor value normalized to 18 decimals (WAD).
    /// @dev SpotPrice values are already 1e18-scaled `abi.encode(uint256)`, so this only widens
    ///      `uint256 -> int256`. `getDataBefore` already validated presence + staleness; a zero price or
    ///      one `>= 2^255` (which would wrap to a negative `int256`) is treated as missing data. `value`
    ///      comes from a permissionless reporter, so the upper-bound guard is load-bearing, not defensive.
    function latestAnswer(bytes32 key) internal view returns (int256 answerWad) {
        (bytes memory value,) = getDataBefore(key);

        uint256 price = abi.decode(value, (uint256));
        if (price == 0 || price > uint256(type(int256).max)) revert ITellorAdapter.TellorNoData(key);
        answerWad = int256(price);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    function setTellor(address tellor_) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (tellor_ == address(0)) revert ITellorAdapter.TellorContractIsZero();
        tellorAdapterStorage()._tellor = tellor_;
        emit ITellorAdapter.TellorContractSet(tellor_);
    }

    function registerFeed(bytes32 key, bytes32 queryId, uint48 disputeBuffer, uint48 maxStaleness) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (queryId == bytes32(0) || maxStaleness == 0) revert ITellorAdapter.TellorInvalidConfig();
        tellorAdapterStorage()._feeds[key] =
            TellorFeed({queryId: queryId, disputeBuffer: disputeBuffer, maxStaleness: maxStaleness});
        emit ITellorAdapter.FeedRegistered(key, queryId, disputeBuffer, maxStaleness);
    }

    function unregisterFeed(bytes32 key) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        delete tellorAdapterStorage()._feeds[key];
        emit ITellorAdapter.FeedUnregistered(key);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    function _requireTellor() private view returns (address t) {
        t = tellorAdapterStorage()._tellor;
        if (t == address(0)) revert ITellorAdapter.TellorContractNotSet();
    }
}
