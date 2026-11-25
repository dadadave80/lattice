// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ENS_MANAGER_ROLE} from "@lattice/ens/libraries/ENSResolverLib.sol";
import {IENSSubnameIssuerV2} from "@lattice/interfaces/ens/IENSSubnameIssuerV2.sol";
import {IPermissionedRegistry} from "@lattice/interfaces/external/ens/IPermissionedRegistry.sol";
import {IUniversalHelper} from "@lattice/interfaces/external/ens/IUniversalHelper.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @dev ERC-7201 root for `lattice.storage.ENSSubnameIssuerV2`.
bytes32 constant ENS_SUBNAME_ISSUER_V2_STORAGE_SLOT =
    0xa5e628eceea1fa97930014ad2ebe76d14de43931d5fc9f39670cc538ee248300;

/// @dev `0x5db4438d` is `type(IENSSubnameIssuerV2).interfaceId`.
///      `keccak256(abi.encode(bytes4(0x5db4438d), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IENSSUBNAMEISSUERV2_SLOT =
    0xef9b23848a1b8d4d0e2cb08ecee08f1ca838aea62594c97b7b39cddbcd831dd6;

bytes32 constant ENS_V2_SUBNAME_ISSUER_ROLE = keccak256("ENS_V2_SUBNAME_ISSUER_ROLE");

/// @custom:storage-location erc7201:lattice.storage.ENSSubnameIssuerV2
struct ENSSubnameIssuerV2Storage {
    address _ensUniversalHelper;
}

/// @title ENSSubnameIssuerV2Lib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ENS (https://github.com/ensdomains/contracts-v2)
/// @notice Uses the canonical parent registry to issue an ENSv2 subname as the diamond.
library ENSSubnameIssuerV2Lib {
    function ensSubnameIssuerV2Storage() internal pure returns (ENSSubnameIssuerV2Storage storage $) {
        assembly ("memory-safe") {
            $.slot := ENS_SUBNAME_ISSUER_V2_STORAGE_SLOT
        }
    }

    function __ENSSubnameIssuerV2_init(address helper) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        ENSSubnameIssuerV2Storage storage $ = ensSubnameIssuerV2Storage();
        if ($._ensUniversalHelper != address(0)) revert IENSSubnameIssuerV2.ENSSubnameIssuerV2AlreadyInitialized();
        _validateHelper(helper);
        $._ensUniversalHelper = helper;
        registerInterface();
    }

    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IENSSUBNAMEISSUERV2_SLOT, true)
        }
    }

    function issueEnsSubnameV2(
        bytes calldata parentDnsName,
        string calldata label,
        address owner,
        address childRegistry,
        address resolver,
        uint256 ownerRoles,
        uint64 expiry
    ) internal returns (uint256 tokenId) {
        AccessControlLib.checkRole(ENS_V2_SUBNAME_ISSUER_ROLE);
        if (parentDnsName.length < 2 || parentDnsName[0] == 0) {
            revert IENSSubnameIssuerV2.ENSSubnameIssuerV2InvalidParentName();
        }
        if (owner == address(0)) revert IENSSubnameIssuerV2.ENSSubnameIssuerV2InvalidOwner();
        if (expiry <= block.timestamp) revert IENSSubnameIssuerV2.ENSSubnameIssuerV2InvalidExpiry(expiry);
        _validateLabel(bytes(label));

        address parent = IUniversalHelper(ensUniversalHelper()).findCanonicalRegistry(parentDnsName);
        if (parent.code.length == 0) revert IENSSubnameIssuerV2.ENSSubnameIssuerV2InvalidParentRegistry(parent);
        tokenId = IPermissionedRegistry(parent).register(label, owner, childRegistry, resolver, ownerRoles, expiry);
        emit IENSSubnameIssuerV2.EnsSubnameIssuedV2(parent, tokenId, owner, label);
    }

    function ensUniversalHelper() internal view returns (address) {
        return ensSubnameIssuerV2Storage()._ensUniversalHelper;
    }

    function setEnsUniversalHelper(address helper) internal {
        AccessControlLib.checkRole(ENS_MANAGER_ROLE);
        ENSSubnameIssuerV2Storage storage $ = ensSubnameIssuerV2Storage();
        if ($._ensUniversalHelper == address(0)) {
            revert IENSSubnameIssuerV2.ENSSubnameIssuerV2InvalidHelper(address(0));
        }
        _validateHelper(helper);
        $._ensUniversalHelper = helper;
        emit IENSSubnameIssuerV2.EnsUniversalHelperSet(helper);
    }

    function _validateHelper(address helper) private view {
        if (helper.code.length == 0) revert IENSSubnameIssuerV2.ENSSubnameIssuerV2InvalidHelper(helper);
        (bool success, bytes memory data) = helper.staticcall(abi.encodeCall(IUniversalHelper.ROOT_REGISTRY, ()));
        if (!success || data.length != 32) revert IENSSubnameIssuerV2.ENSSubnameIssuerV2InvalidHelper(helper);
        uint256 root = abi.decode(data, (uint256));
        if (root > type(uint160).max || address(uint160(root)).code.length == 0) {
            revert IENSSubnameIssuerV2.ENSSubnameIssuerV2InvalidHelper(helper);
        }
    }

    function _validateLabel(bytes calldata label) private pure {
        if (label.length == 0 || label.length > type(uint8).max) {
            revert IENSSubnameIssuerV2.ENSSubnameIssuerV2InvalidLabel();
        }
        for (uint256 i; i < label.length; ++i) {
            if (label[i] == "." || label[i] == 0) revert IENSSubnameIssuerV2.ENSSubnameIssuerV2InvalidLabel();
        }
    }
}
