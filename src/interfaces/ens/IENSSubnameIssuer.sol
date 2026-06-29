// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IENSSubnameIssuer
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Integrates the ENS NameWrapper (https://docs.ens.domains/wrapper/overview)
/// @notice External interface for the ENS subname-issuer facet: lets a diamond that owns a parent ENS
///         name mint subnames (e.g. `treasury.myproto.eth`) via the ENS NameWrapper.
/// @dev Issuance is gated on `ENS_SUBNAME_ISSUER_ROLE`. The diamond must be authorized to modify the
///      parent name in the NameWrapper. Setting the new subname's forward `addr` record and the
///      child's reverse record are the owner's / child's responsibility (a future ENS reverse-record
///      module). Verify the deployed NameWrapper signature for your chain before mainnet — see {INameWrapper}.
interface IENSSubnameIssuer {
    /// @dev Thrown when a zero address is supplied as the NameWrapper.
    error ENSSubnameIssuerZeroNameWrapper();

    /// @dev Emitted when the configured NameWrapper is set or rotated.
    /// @param nameWrapper The NameWrapper address now in use.
    event NameWrapperSet(address indexed nameWrapper);

    /// @dev Emitted when a subname is issued.
    /// @param parentNode The parent name's node.
    /// @param node       The newly created subname's node.
    /// @param owner      The owner assigned to the new subname.
    event SubnameIssued(bytes32 indexed parentNode, bytes32 indexed node, address indexed owner);

    /// @notice Mints `label`.<parent> via the NameWrapper, owned by `owner` with `resolver` set.
    /// @dev Gated on `ENS_SUBNAME_ISSUER_ROLE`. The diamond must own/approve `parentNode` in the
    ///      NameWrapper. To make the subname forward-resolve, the owner sets the addr record on
    ///      `resolver`; the child sets its reverse record via a future ENS reverse-record module.
    /// @param parentNode The parent name's node (wrapped + controlled by this diamond).
    /// @param label      The subname label.
    /// @param owner      The owner of the new subname.
    /// @param resolver   The resolver to set for the new subname.
    /// @param ttl        The TTL for the new subname.
    /// @param fuses      The fuses to burn on the new subname.
    /// @param expiry     The expiry timestamp for the new subname.
    /// @return node The newly created subname's node.
    function issueSubname(
        bytes32 parentNode,
        string calldata label,
        address owner,
        address resolver,
        uint64 ttl,
        uint32 fuses,
        uint64 expiry
    ) external returns (bytes32 node);

    /// @notice Sets or rotates the NameWrapper (per-chain configuration).
    /// @dev Gated on `ENS_SUBNAME_ISSUER_ROLE`. Reverts {ENSSubnameIssuerZeroNameWrapper} for zero.
    /// @param nameWrapper The NameWrapper to use.
    function setNameWrapper(address nameWrapper) external;

    /// @notice Returns the configured NameWrapper.
    function nameWrapper() external view returns (address);
}
