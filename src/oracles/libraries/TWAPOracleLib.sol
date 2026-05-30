// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ITWAPOracle} from "@lattice/interfaces/ITWAPOracle.sol";
import {IUniswapV2Pair} from "@lattice/interfaces/external/IUniswapV2Pair.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.TWAPOracle")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant TWAP_ORACLE_STORAGE_SLOT = 0xc2bcc163613aea761b734a9692ad3548aab9088be29b53e03facf6a2a351df00;

/// @dev 0xd1baebe0 is `type(ITWAPOracle).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xd1baebe0), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ITWAPORACLE_SLOT = 0x3edcb012a40cef5fed8aba3a5816c3233af9ecd91b8a1965a2b67b8940a0f49f;

/// @notice ERC-7201 namespaced storage for TWAPOracle.
/// @custom:storage-location erc7201:lattice.storage.TWAPOracle
struct TWAPOracleStorage {
    mapping(bytes32 key => address) _pairs;
    mapping(bytes32 key => ITWAPOracle.Observation[]) _observations;
}

/// @title TWAPOracleLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library implementing a Uniswap V2-style time-weighted average price
///         oracle.  Any address may call `recordObservation` to push a cumulative
///         price snapshot; `consult` computes the TWAP over a requested window.
///
/// @dev Prices are returned as Uniswap V2 UQ112x112 fixed-point values
///      (cumulative delta / time delta).  The precision is the same as the
///      underlying pair's `price0CumulativeLast` / `price1CumulativeLast`.
library TWAPOracleLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the ERC-7201 storage struct for TWAPOracle.
    function twapOracleStorage() internal pure returns (TWAPOracleStorage storage $) {
        assembly {
            $.slot := TWAP_ORACLE_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the ITWAPOracle ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __TWAPOracle_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for ITWAPOracle.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ITWAPORACLE_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the pair address registered under `key`.
    function getPair(bytes32 key) internal view returns (address pair) {
        return twapOracleStorage()._pairs[key];
    }

    /// @notice Returns the most recently recorded observation for a pair.
    /// @dev Reverts `TWAPPairNotRegistered` if the key has no pair.
    ///      Reverts `TWAPInsufficientHistory` if no observations exist.
    function getLatestObservation(bytes32 key) internal view returns (ITWAPOracle.Observation memory) {
        TWAPOracleStorage storage $ = twapOracleStorage();
        if ($._pairs[key] == address(0)) revert ITWAPOracle.TWAPPairNotRegistered(key);
        ITWAPOracle.Observation[] storage obs = $._observations[key];
        if (obs.length == 0) revert ITWAPOracle.TWAPInsufficientHistory(key);
        return obs[obs.length - 1];
    }

    /// @notice Computes the TWAP over the last `windowSeconds` for a pair.
    /// @dev Selects the oldest observation that is at least `windowSeconds` old
    ///      and computes `(cumulativeNow - cumulativeOld) / (timestampNow - timestampOld)`.
    ///
    ///      The search walks backward from the second-to-last observation to find
    ///      the most recent one that is old enough to satisfy the window, ensuring
    ///      we return a TWAP that covers at least the requested period.
    /// @param key           The pair identifier.
    /// @param windowSeconds Desired TWAP window in seconds.
    /// @return price0Twap   TWAP of token0 in UQ112x112 fixed-point per second units.
    /// @return price1Twap   TWAP of token1 in UQ112x112 fixed-point per second units.
    function consult(bytes32 key, uint32 windowSeconds) internal view returns (uint256 price0Twap, uint256 price1Twap) {
        if (windowSeconds == 0) revert ITWAPOracle.TWAPZeroWindow();
        TWAPOracleStorage storage $ = twapOracleStorage();
        if ($._pairs[key] == address(0)) revert ITWAPOracle.TWAPPairNotRegistered(key);

        ITWAPOracle.Observation[] storage obs = $._observations[key];
        uint256 len = obs.length;
        if (len < 2) revert ITWAPOracle.TWAPInsufficientHistory(key);

        ITWAPOracle.Observation storage newest = obs[len - 1];

        // Walk backward to find the best (oldest) observation that is still
        // within the requested window.  We want the observation where:
        //   newest.timestamp - obs[i].timestamp >= windowSeconds
        // Use the oldest such observation so the TWAP covers the full window.
        uint32 newestTs = newest.timestamp;

        // Check that any observation is old enough.
        uint32 oldestTs = obs[0].timestamp;
        uint32 oldestAge = newestTs - oldestTs; // safe: uint32 wraps correctly
        if (oldestAge < windowSeconds) {
            revert ITWAPOracle.TWAPWindowTooLarge(windowSeconds, oldestAge);
        }

        // Binary search for the oldest observation satisfying the window.
        uint256 lo = 0;
        uint256 hi = len - 2; // exclude the newest
        while (lo < hi) {
            uint256 mid = (lo + hi) / 2;
            uint32 age = newestTs - obs[mid].timestamp;
            if (age >= windowSeconds) {
                hi = mid; // mid is old enough; try to find an older one
            } else {
                lo = mid + 1; // mid is too recent
            }
        }

        ITWAPOracle.Observation storage base = obs[lo];
        uint32 elapsed = newestTs - base.timestamp;

        price0Twap = (newest.price0Cumulative - base.price0Cumulative) / elapsed;
        price1Twap = (newest.price1Cumulative - base.price1Cumulative) / elapsed;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers a Uniswap V2 pair and records the initial observation.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    /// @param key  Arbitrary identifier for this pair.
    /// @param pair Address of the IUniswapV2Pair contract.
    function registerPair(bytes32 key, address pair) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        require(pair != address(0));
        TWAPOracleStorage storage $ = twapOracleStorage();
        $._pairs[key] = pair;
        _appendObservation($, key, pair);
        emit ITWAPOracle.PairRegistered(key, pair);
    }

    /// @notice Removes a registered pair and all its stored observations.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    /// @param key The pair identifier to remove.
    function unregisterPair(bytes32 key) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        TWAPOracleStorage storage $ = twapOracleStorage();
        delete $._pairs[key];
        delete $._observations[key];
        emit ITWAPOracle.PairUnregistered(key);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Records a new cumulative price observation for the pair.
    /// @dev Open to any caller; reverts `TWAPPairNotRegistered` if the pair is
    ///      not registered.
    /// @param key The pair identifier.
    function recordObservation(bytes32 key) internal {
        TWAPOracleStorage storage $ = twapOracleStorage();
        address pair = $._pairs[key];
        if (pair == address(0)) revert ITWAPOracle.TWAPPairNotRegistered(key);
        _appendObservation($, key, pair);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Reads the current cumulatives from the pair and appends an observation.
    /// @dev Skips the push if an observation with the same timestamp was already
    ///      recorded (same-block deduplication). This prevents unbounded array
    ///      growth from permissionless callers spamming recordObservation within
    ///      a single block and avoids wasted gas on redundant SSTOREs.
    function _appendObservation(TWAPOracleStorage storage $, bytes32 key, address pair) internal {
        uint256 price0Cumulative = IUniswapV2Pair(pair).price0CumulativeLast();
        uint256 price1Cumulative = IUniswapV2Pair(pair).price1CumulativeLast();
        (,, uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();

        // Same-block deduplication: if the newest stored observation already has
        // this timestamp, do nothing. Prevents griefing via repeated same-block
        // recordObservation calls (M2) and skips wasteful identical entries (L2).
        ITWAPOracle.Observation[] storage obs = $._observations[key];
        if (obs.length > 0 && obs[obs.length - 1].timestamp == blockTimestampLast) return;

        ITWAPOracle.Observation memory newObs = ITWAPOracle.Observation({
            timestamp: blockTimestampLast, price0Cumulative: price0Cumulative, price1Cumulative: price1Cumulative
        });
        obs.push(newObs);
        emit ITWAPOracle.ObservationRecorded(key, blockTimestampLast, price0Cumulative, price1Cumulative);
    }
}
