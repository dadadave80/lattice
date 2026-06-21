// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IPriceOracleReader
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice The provider-agnostic READ surface for a Lattice price-oracle adapter: a single
///         `latestAnswer(bytes32 key)` returning a WAD-normalized (1e18) price. A consumer can depend on
///         this interface to read any adapter that exposes a matching `latestAnswer`, without coupling to
///         a specific provider.
/// @dev This interface unifies only the normalized READ — each adapter keeps its own provider-specific
///      surface (registration, write semantics, etc.) entirely separate. An adapter that wishes to be
///      read through this interface declares a `latestAnswer(bytes32)->int256` with the SAME selector
///      DIRECTLY (not by inheriting this interface): Solidity excludes inherited functions from
///      `type(I).interfaceId`, so inheriting would shift the adapter's ERC-165 id.
interface IPriceOracleReader {
    /// @notice Returns the latest price for `key`, normalized to 18 decimals (WAD).
    /// @param key The feed identifier (chosen by the administrator).
    /// @return answerWad The latest price scaled to 1e18.
    function latestAnswer(bytes32 key) external view returns (int256 answerWad);
}
