// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IReverseRegistrar
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Vendored minimal subset of ENS's `ReverseRegistrar` / ENSIP-11 `L2ReverseRegistrar` (https://github.com/ensdomains/ens-contracts). Upstream is MIT.
/// @notice Minimal vendored interface for ENS reverse registrars: cross-compatible `setName`, plus the L1
///         `ReverseRegistrar.claim` ownership path used by standalone infrastructure contracts.
/// @dev `setName` is deliberately declared with NO return value. The L1 `ReverseRegistrar.setName`
///      returns `bytes32` while the L2 `L2ReverseRegistrar.setName` returns nothing; a void-typed call
///      ignores any returndata, so this single declaration works against BOTH (selector `0xc47f0027`).
///      `claim(address)` must only be used with registrars implementing that L1 ABI. The registrar address
///      is chain-specific and supplied by the deployer; it is never hardcoded.
interface IReverseRegistrar {
    /// @notice Claims `msg.sender`'s reverse node for `owner` using the registrar's default resolver.
    /// @param owner The account that will own and manage the reverse node.
    /// @return node The claimed reverse node.
    function claim(address owner) external returns (bytes32 node);

    /// @notice Sets the reverse record `name` for `msg.sender` (the calling contract) under
    ///         `addr.reverse`, using the registrar's default resolver. The self-claim form
    ///         (caller == subject) is supported by both the L1 and L2 registrars.
    /// @param name The ENS name to set as the caller's primary (reverse) name.
    function setName(string memory name) external;
}
