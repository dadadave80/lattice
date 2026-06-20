// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title INameWrapper
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Minimal vendored interface for the ENS NameWrapper, used by {ENSSubnameIssuer} to mint
///         subnames. Only `setSubnodeRecord` is declared.
/// @dev VERIFY the exact `setSubnodeRecord` signature (parameter order, fuses/expiry widths) against
///      the deployed NameWrapper for your target chain before mainnet use — ENS has shipped multiple
///      NameWrapper revisions. The selector for this signature is `0x24c1af44`.
interface INameWrapper {
    /// @notice Creates `label`.<parent> as a subname, setting its owner, resolver, ttl, fuses, and
    ///         expiry. The caller must be authorized to modify `parentNode` in the NameWrapper.
    /// @param parentNode The namehash of the parent name (wrapped + owned/approved by the caller).
    /// @param label      The subname label (e.g. "treasury" for treasury.parent.eth).
    /// @param owner      The owner of the new subname.
    /// @param resolver   The resolver to set for the new subname.
    /// @param ttl        The TTL for the new subname.
    /// @param fuses      The fuses to burn on the new subname.
    /// @param expiry     The expiry timestamp for the new subname.
    /// @return node The namehash of the newly created subname.
    function setSubnodeRecord(
        bytes32 parentNode,
        string calldata label,
        address owner,
        address resolver,
        uint64 ttl,
        uint32 fuses,
        uint64 expiry
    ) external returns (bytes32 node);
}
