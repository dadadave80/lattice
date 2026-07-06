// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IReverseRegistrar
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Vendored minimal subset of ENS's `ReverseRegistrar` / ENSIP-11 `L2ReverseRegistrar` (https://github.com/ensdomains/ens-contracts). Upstream is MIT.
/// @notice Minimal vendored interface for the ENS Reverse Registrar — the L1 `ReverseRegistrar` and the
///         ENSIP-11 `L2ReverseRegistrar` — used by the {ENSReverseClaimer} facet for self-claim.
/// @dev Only `setName` is declared, deliberately with NO return value. The L1 `ReverseRegistrar.setName`
///      returns `bytes32` while the L2 `L2ReverseRegistrar.setName` returns nothing; a void-typed call
///      ignores any returndata, so this single declaration works against BOTH (selector `0xc47f0027`).
///      The registrar address is chain-specific and supplied by the deployer; it is never hardcoded.
interface IReverseRegistrar {
    /// @notice Sets the reverse record `name` for `msg.sender` (the calling contract) under
    ///         `addr.reverse`, using the registrar's default resolver. The self-claim form
    ///         (caller == subject) is supported by both the L1 and L2 registrars.
    /// @param name The ENS name to set as the caller's primary (reverse) name.
    function setName(string memory name) external;
}
