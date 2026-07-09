// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IENSSubnameIssuer} from "@lattice/interfaces/ens/IENSSubnameIssuer.sol";
import {INameWrapper} from "@lattice/interfaces/external/INameWrapper.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ENSSubnameIssuer")) - 1)) & ~bytes32(uint256(0xff))`.
///      Verify with: `cast index-erc7201 "lattice.storage.ENSSubnameIssuer"`.
bytes32 constant ENS_SUBNAME_ISSUER_STORAGE_SLOT = 0xecd97908615d460a8806be2f460463395b75373d406444064e9704ed5d892e00;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ENS_SUBNAME_ISSUER_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x6ead39e3 is `type(IENSSubnameIssuer).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x6ead39e3), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IENSSUBNAMEISSUER_SLOT = 0x19f98b1c052723a0f45e31ccce192390fdd3867a76366f19df750eb883381f60;

/// @dev Role allowed to mint subnames under the diamond's parent name(s). Distinct from
///      `ENS_MANAGER_ROLE` because issuing identities is a higher-stakes, separable permission.
bytes32 constant ENS_SUBNAME_ISSUER_ROLE = keccak256("ENS_SUBNAME_ISSUER_ROLE");

/// @notice ERC-7201 namespaced storage for the ENSSubnameIssuer module.
/// @dev APPEND-ONLY: new fields may only be added at the end to preserve the upgrade-safe layout.
/// @custom:storage-location erc7201:lattice.storage.ENSSubnameIssuer
struct ENSSubnameIssuerStorage {
    /// @dev The ENS NameWrapper used to mint subnames.
    address _nameWrapper;
}

/// @title ENSSubnameIssuerLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ENS (https://github.com/ensdomains/ens-contracts)
/// @notice Library letting a diamond that owns a parent ENS name mint subnames via the ENS NameWrapper.
/// @dev Three-layer pattern: this library holds the logic and namespaced storage; the stateless
///      {ENSSubnameIssuer} facet forwards to it. A thin, role-gated wrapper over the canonical
///      `NameWrapper.setSubnodeRecord` — it makes no assumptions about resolver authorization or token
///      transfer. Setting the new subname's forward `addr` record is the new owner's job; the child
///      sets its own reverse record via a future ENS reverse-record module.
library ENSSubnameIssuerLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function ensSubnameIssuerStorage() internal pure returns (ENSSubnameIssuerStorage storage $) {
        assembly {
            $.slot := ENS_SUBNAME_ISSUER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the ENSSubnameIssuer module with the NameWrapper to use.
    /// @dev Must be called inside a pre/postInitializer block. Reverts
    ///      {ENSSubnameIssuerZeroNameWrapper} for a zero NameWrapper. Registers IENSSubnameIssuer for ERC-165.
    /// @param _nameWrapper The ENS NameWrapper for this chain.
    function __ENSSubnameIssuer_init(address _nameWrapper) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        if (_nameWrapper == address(0)) revert IENSSubnameIssuer.ENSSubnameIssuerZeroNameWrapper();
        ensSubnameIssuerStorage()._nameWrapper = _nameWrapper;
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IENSSubnameIssuer interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IENSSUBNAMEISSUER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             SUBNAME ISSUANCE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Mints `label`.<parent> via the NameWrapper, owned by `owner` with `resolver` set.
    /// @dev Gated on `ENS_SUBNAME_ISSUER_ROLE`. The diamond must own/approve `parentNode` in the
    ///      NameWrapper. The library makes no further calls (no addr-record write, no token transfer).
    ///      See {INameWrapper}: verify the deployed `setSubnodeRecord` selector (0x24c1af44) on your
    ///      target chain before mainnet use.
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
    ) internal returns (bytes32 node) {
        AccessControlLib.checkRole(ENS_SUBNAME_ISSUER_ROLE);
        node = INameWrapper(ensSubnameIssuerStorage()._nameWrapper)
            .setSubnodeRecord(parentNode, label, owner, resolver, ttl, fuses, expiry);
        emit IENSSubnameIssuer.SubnameIssued(parentNode, node, owner);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              CONFIGURATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets or rotates the NameWrapper.
    /// @dev Gated on `ENS_SUBNAME_ISSUER_ROLE`. Reverts {ENSSubnameIssuerZeroNameWrapper} for zero.
    /// @param _nameWrapper The NameWrapper to use.
    function setNameWrapper(address _nameWrapper) internal {
        AccessControlLib.checkRole(ENS_SUBNAME_ISSUER_ROLE);
        if (_nameWrapper == address(0)) revert IENSSubnameIssuer.ENSSubnameIssuerZeroNameWrapper();
        ensSubnameIssuerStorage()._nameWrapper = _nameWrapper;
        emit IENSSubnameIssuer.NameWrapperSet(_nameWrapper);
    }

    /// @notice Returns the configured NameWrapper.
    function nameWrapper() internal view returns (address) {
        return ensSubnameIssuerStorage()._nameWrapper;
    }
}
