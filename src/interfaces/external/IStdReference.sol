// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IStdReference
/// @author Modified from Band Protocol (https://github.com/bandprotocol/contract-tools/blob/master/spec/StdReference.sol)
/// @notice Minimal interface for the Band Protocol standard reference (StdReferenceProxy) oracle.
/// @dev Vendored subset — do not add a Band contracts dependency. Band uses a SINGLE global reference
///      contract per chain; feeds are keyed by a `(base, quote)` symbol pair (e.g. `("ETH","USD")`).
///      `rate` is already 18-decimals (WAD), and `lastUpdatedBase` / `lastUpdatedQuote` are the unix
///      timestamps the consumer validates for staleness.
interface IStdReference {
    /// @notice A Band reference-data result for a `(base, quote)` symbol pair.
    /// @param rate The base/quote exchange rate, scaled to 1e18 (18 decimals).
    /// @param lastUpdatedBase The unix timestamp the base symbol was last updated.
    /// @param lastUpdatedQuote The unix timestamp the quote symbol was last updated.
    struct ReferenceData {
        uint256 rate;
        uint256 lastUpdatedBase;
        uint256 lastUpdatedQuote;
    }

    /// @notice Returns the reference data for the `base`/`quote` symbol pair.
    /// @param base The base symbol (e.g. `"ETH"`).
    /// @param quote The quote symbol (e.g. `"USD"`).
    /// @return referenceData The `(rate, lastUpdatedBase, lastUpdatedQuote)` result.
    function getReferenceData(string memory base, string memory quote)
        external
        view
        returns (ReferenceData memory referenceData);
}
