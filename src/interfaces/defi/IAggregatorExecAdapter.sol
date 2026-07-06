// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAggregatorExecAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Admin / read / action surface of the generic swap/bridge EXECUTION adapter. It forwards
///         user-supplied calldata (built off-chain by an aggregator's API/SDK — the LI.FI Diamond being the
///         canonical first aggregator) to an admin-ALLOW-LISTED `(aggregator, selector)` pair. This is the most
///         security-sensitive adapter in the suite: it makes an ARBITRARY external call from a fund-holding
///         diamond, so the whole design is confused-deputy prevention. It is NOT an ERC-7786 gateway.
/// @dev TRUST MODEL: the diamond only ever exposes `msg.sender`-supplied funds plus an EXACT, immediately-reset
///      approval. The `(aggregator, selector)` allow-list is the sole authorization primitive; the calldata
///      body is opaque and untrusted. `address(0)` and `address(this)` can never be allow-listed (the latter
///      would let crafted calldata re-enter privileged facets). After every call the input allowance is reset
///      to 0 and all leftovers (unspent input, output delta, unspent native) are swept back to `msg.sender`.
interface IAggregatorExecAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when the admin toggles an `(aggregator, selector)` allow-list entry.
    event AllowedCallSet(address indexed aggregator, bytes4 indexed selector, bool allowed);

    /// @notice Emitted when a swap/bridge is executed against an allow-listed aggregator.
    event AggregatorCall(
        address indexed sender,
        address indexed aggregator,
        bytes4 indexed selector,
        address inputToken,
        uint256 amount,
        address outputToken
    );

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice The admin was the zero address at init.
    error AggregatorExecZeroAdmin();

    /// @notice An aggregator of `address(0)` or `address(this)` may never be allow-listed (confused-deputy guard).
    error AggregatorExecInvalidAggregator(address aggregator);

    /// @notice The supplied calldata was shorter than a 4-byte selector.
    error AggregatorExecEmptyCallData();

    /// @notice The `(aggregator, selector)` pair is not on the allow-list.
    error AggregatorExecNotAllowed(address aggregator, bytes4 selector);

    /// @notice A native-value transfer to `msg.sender` (leftover sweep) failed.
    error AggregatorExecNativeTransferFailed();

    // -------------------------------------------------------------------------
    //                                  Reads
    // -------------------------------------------------------------------------

    /// @notice Whether the `(aggregator, selector)` pair is allow-listed for {execute}.
    function isAllowedCall(address aggregator, bytes4 selector) external view returns (bool);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Toggles allow-listing of `(aggregator, selector)`. Admin only. Reverts
    ///         {AggregatorExecInvalidAggregator} for `address(0)` / `address(this)`.
    function setAllowedCall(address aggregator, bytes4 selector, bool allowed) external;

    // -------------------------------------------------------------------------
    //                                  Actions
    // -------------------------------------------------------------------------

    /// @notice Pulls `amount` of `inputToken` from `msg.sender`, approves `aggregator` for EXACTLY that amount,
    ///         forwards `callData` (its leading selector must be allow-listed for `aggregator`), then resets the
    ///         approval to 0 and sweeps every leftover (unspent input, output delta, unspent native) back to
    ///         `msg.sender`. Strict CEI under a reentrancy guard. Reverts bubble up from the aggregator verbatim.
    /// @param aggregator  The allow-listed aggregator target (e.g. the LI.FI Diamond).
    /// @param inputToken  The token pulled from the caller and approved to the aggregator (`address(0)` = native).
    /// @param amount      The exact amount of `inputToken` to pull and approve.
    /// @param outputToken The token the caller expects back; its balance DELTA is swept out (`address(0)` = none).
    /// @param callData    The opaque aggregator calldata (built off-chain); `bytes4(callData)` is the gated selector.
    /// @return ret        The raw return data of the aggregator call.
    function execute(
        address aggregator,
        address inputToken,
        uint256 amount,
        address outputToken,
        bytes calldata callData
    ) external payable returns (bytes memory ret);
}
