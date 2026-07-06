// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ITWAPOracle
/// @author Modified from Uniswap V2 (https://github.com/Uniswap/v2-periphery/blob/master/contracts/examples/ExampleSlidingWindowOracle.sol)
/// @notice Interface for the TWAPOracle Diamond facet.
/// @dev Implements a Uniswap V2-style time-weighted average price oracle.  Any
///      address can call `recordObservation` to push a new snapshot; `consult`
///      then computes the TWAP over the requested window from the stored history.
interface ITWAPOracle {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a Uniswap V2 pair is registered.
    /// @param key  Arbitrary identifier for this pair.
    /// @param pair Address of the IUniswapV2Pair contract.
    event PairRegistered(bytes32 indexed key, address pair);

    /// @notice Emitted when a pair is unregistered.
    /// @param key The identifier of the removed pair.
    event PairUnregistered(bytes32 indexed key);

    /// @notice Emitted when a new cumulative price observation is recorded.
    /// @param key               The pair identifier.
    /// @param timestamp         Block timestamp of the observation.
    /// @param price0Cumulative  Cumulative price of token0 at this timestamp.
    /// @param price1Cumulative  Cumulative price of token1 at this timestamp.
    event ObservationRecorded(
        bytes32 indexed key, uint32 timestamp, uint256 price0Cumulative, uint256 price1Cumulative
    );

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice No pair is registered under the given key.
    error TWAPPairNotRegistered(bytes32 key);

    /// @notice Fewer than two observations have been recorded; cannot compute TWAP.
    error TWAPInsufficientHistory(bytes32 key);

    /// @notice The requested TWAP window is larger than the oldest available observation.
    /// @param requested The requested window in seconds.
    /// @param oldest    The age (seconds ago) of the oldest stored observation.
    error TWAPWindowTooLarge(uint32 requested, uint32 oldest);

    /// @notice `consult` was called with `windowSeconds == 0`.
    /// @dev A zero window would divide by elapsed time which may itself be zero,
    ///      producing a division-by-zero panic.
    error TWAPZeroWindow();

    /// @notice The newest stored observation is too old to satisfy the request.
    /// @dev Guards against returning a confidently-priced but stale TWAP when
    ///      recording stopped long ago. `consult` reverts when
    ///      `block.timestamp - newestTimestamp > windowSeconds`, i.e. the freshest
    ///      data point does not even fall within the requested window.
    /// @param newestTimestamp Timestamp of the most recent observation.
    /// @param currentTimestamp The current block timestamp.
    error TWAPStaleObservation(uint32 newestTimestamp, uint32 currentTimestamp);

    /// @notice The usable time span between the selected observations is zero.
    /// @dev Prevents a division-by-zero panic (0x12) when the newest and the base
    ///      observation share a timestamp (e.g. the oldest and newest observations
    ///      carry the same timestamp). Reverts with a clear error instead.
    /// @param key The pair identifier.
    error TWAPElapsedZero(bytes32 key);

    // -------------------------------------------------------------------------
    //                                  Types
    // -------------------------------------------------------------------------

    /// @notice A single cumulative price snapshot.
    struct Observation {
        /// @notice Block timestamp when this snapshot was taken (mod 2**32).
        uint32 timestamp;
        /// @notice Cumulative price of token0 at `timestamp`.
        uint256 price0Cumulative;
        /// @notice Cumulative price of token1 at `timestamp`.
        uint256 price1Cumulative;
    }

    // -------------------------------------------------------------------------
    //                                   Reads
    // -------------------------------------------------------------------------

    /// @notice Returns the address of the Uniswap V2 pair registered under `key`.
    /// @param key The pair identifier.
    function getPair(bytes32 key) external view returns (address pair);

    /// @notice Returns the most recently recorded observation for a pair.
    /// @param key The pair identifier.
    function getLatestObservation(bytes32 key) external view returns (Observation memory);

    /// @notice Computes the TWAP over the last `windowSeconds` for a registered pair.
    /// @dev Selects the oldest observation that is at least `windowSeconds` old and
    ///      computes `(cumulativeNow - cumulativeOld) / (timestampNow - timestampOld)`.
    /// @param key           The pair identifier.
    /// @param windowSeconds The desired TWAP window in seconds.
    /// @return price0Twap   TWAP of token0 over the window (UQ112x112 fixed-point).
    /// @return price1Twap   TWAP of token1 over the window (UQ112x112 fixed-point).
    function consult(bytes32 key, uint32 windowSeconds) external view returns (uint256 price0Twap, uint256 price1Twap);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Registers a Uniswap V2 pair under the given key and records an
    ///         initial observation.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param key  Arbitrary identifier for this pair.
    /// @param pair Address of the IUniswapV2Pair contract.
    function registerPair(bytes32 key, address pair) external;

    /// @notice Removes a registered pair and all its stored observations.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param key The pair identifier to remove.
    function unregisterPair(bytes32 key) external;

    // -------------------------------------------------------------------------
    //                                Operations
    // -------------------------------------------------------------------------

    /// @notice Records a new cumulative price observation for the pair.
    /// @dev Open to any caller to allow permissionless oracle maintenance.
    /// @param key The pair identifier.
    function recordObservation(bytes32 key) external;
}
