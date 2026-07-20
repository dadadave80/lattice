// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAggregatorV3} from "@lattice/interfaces/external/chainlink/IAggregatorV3.sol";
import {IChainlinkAdapter} from "@lattice/interfaces/oracles/IChainlinkAdapter.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ChainlinkAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant CHAINLINK_ADAPTER_STORAGE_SLOT = 0xdbb02d424081d7fb4c59a631e74d23250f514b627bc328ad0ec973d94b228000;

/// @dev 0x364fdec9 is `type(IChainlinkAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x364fdec9), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ICHAINLINKADAPTER_SLOT = 0x65e721c748691ae5a9544827b82a8602440249a42e1438a441599564727a3bd2;

/// @notice Packed data for a single registered price feed.
struct Feed {
    /// @notice Address of the AggregatorV3 contract.
    address feed;
    /// @notice Maximum age in seconds before an answer is considered stale.
    uint48 maxStaleness;
    /// @notice Number of decimals used by this feed (cached at registration time).
    uint8 decimals;
}

/// @notice ERC-7201 namespaced storage for ChainlinkAdapter.
/// @custom:storage-location erc7201:lattice.storage.ChainlinkAdapter
struct ChainlinkAdapterStorage {
    mapping(bytes32 key => Feed) _feeds;
}

/// @title ChainlinkAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Chainlink (https://github.com/smartcontractkit/chainlink-evm/blob/develop/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol)
/// @notice Library that wraps Chainlink AggregatorV3 price feeds with
///         per-feed staleness configuration and WAD normalisation.
library ChainlinkAdapterLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the ERC-7201 storage struct for ChainlinkAdapter.
    function chainlinkAdapterStorage() internal pure returns (ChainlinkAdapterStorage storage $) {
        assembly {
            $.slot := CHAINLINK_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IChainlinkAdapter ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __ChainlinkAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for IChainlinkAdapter.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ICHAINLINKADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the registered feed address and staleness threshold.
    /// @param key The feed identifier.
    /// @return feed         Address of the AggregatorV3 feed.
    /// @return maxStaleness Maximum age in seconds before data is stale.
    function getFeed(bytes32 key) internal view returns (address feed, uint48 maxStaleness) {
        Feed storage f = chainlinkAdapterStorage()._feeds[key];
        return (f.feed, f.maxStaleness);
    }

    /// @notice Returns the raw latest price, update timestamp, and feed decimals.
    /// @param key The feed identifier.
    /// @return answer    Raw answer from the feed (must be > 0).
    /// @return updatedAt Timestamp of the last update.
    /// @return decimals_ Number of decimals used by this feed.
    function latestAnswerRaw(bytes32 key) internal view returns (int256 answer, uint256 updatedAt, uint8 decimals_) {
        ChainlinkAdapterStorage storage $ = chainlinkAdapterStorage();
        Feed storage f = $._feeds[key];

        if (f.feed == address(0)) revert IChainlinkAdapter.ChainlinkFeedNotRegistered(key);

        uint80 roundId;
        uint80 answeredInRound;
        (roundId, answer,, updatedAt, answeredInRound) = IAggregatorV3(f.feed).latestRoundData();

        if (updatedAt == 0 || answeredInRound < roundId) {
            revert IChainlinkAdapter.ChainlinkRoundIncomplete(key);
        }
        if (answer <= 0) revert IChainlinkAdapter.ChainlinkInvalidAnswer(key, answer);
        // Guard against a future updatedAt to avoid an arithmetic underflow panic
        // (Solidity 0.8 checked math). Treat a future timestamp the same as stale data.
        if (updatedAt > block.timestamp || block.timestamp - updatedAt > f.maxStaleness) {
            revert IChainlinkAdapter.ChainlinkStaleData(key, updatedAt, f.maxStaleness);
        }

        decimals_ = f.decimals;
    }

    /// @notice Returns the latest price normalised to 18 decimal places (WAD).
    /// @param key The feed identifier.
    /// @return answerWad The price scaled to 1e18.
    function latestAnswer(bytes32 key) internal view returns (int256 answerWad) {
        (int256 answer,, uint8 decimals_) = latestAnswerRaw(key);

        if (decimals_ < 18) {
            answerWad = answer * int256(10 ** uint256(18 - decimals_));
        } else if (decimals_ > 18) {
            answerWad = answer / int256(10 ** uint256(decimals_ - 18));
        } else {
            answerWad = answer;
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers a Chainlink price feed under the given key.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.  Caches the feed's `decimals()`
    ///      to avoid a read on every price query.  Reverts if `feed` is the zero
    ///      address or `maxStaleness` is zero.
    /// @param key          Arbitrary identifier for this feed.
    /// @param feed         Address of the AggregatorV3 contract.
    /// @param maxStaleness Maximum age (seconds) before an answer is stale.
    function registerFeed(bytes32 key, address feed, uint48 maxStaleness) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (feed == address(0)) revert IChainlinkAdapter.ChainlinkFeedNotRegistered(key);
        if (maxStaleness == 0) revert IChainlinkAdapter.ChainlinkInvalidConfig();

        uint8 dec = IAggregatorV3(feed).decimals();
        chainlinkAdapterStorage()._feeds[key] = Feed({feed: feed, maxStaleness: maxStaleness, decimals: dec});
        emit IChainlinkAdapter.FeedRegistered(key, feed, maxStaleness);
    }

    /// @notice Removes a registered price feed.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    /// @param key The feed identifier to remove.
    function unregisterFeed(bytes32 key) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        delete chainlinkAdapterStorage()._feeds[key];
        emit IChainlinkAdapter.FeedUnregistered(key);
    }
}
