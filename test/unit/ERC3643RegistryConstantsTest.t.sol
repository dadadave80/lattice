// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IClaimTopicsRegistry} from "@lattice/interfaces/tokens/erc3643/IClaimTopicsRegistry.sol";
import {ICompliance} from "@lattice/interfaces/tokens/erc3643/ICompliance.sol";
import {IIdentityRegistry} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistry.sol";
import {IIdentityRegistryStorage} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistryStorage.sol";
import {ITrustedIssuersRegistry} from "@lattice/interfaces/tokens/erc3643/ITrustedIssuersRegistry.sol";
import {
    ERC165_MAP_ICLAIMTOPICSREGISTRY_SLOT,
    ERC3643_CLAIM_TOPICS_REGISTRY_STORAGE_SLOT
} from "@lattice/tokens/ERC3643/libraries/ERC3643ClaimTopicsRegistryLib.sol";
import {
    ERC165_MAP_ICOMPLIANCE_SLOT,
    ERC3643_COMPLIANCE_STORAGE_SLOT
} from "@lattice/tokens/ERC3643/libraries/ERC3643ComplianceLib.sol";
import {
    ERC165_MAP_IIDENTITYREGISTRY_SLOT,
    ERC3643_IDENTITY_REGISTRY_STORAGE_ROOT
} from "@lattice/tokens/ERC3643/libraries/ERC3643IdentityRegistryLib.sol";
import {
    ERC165_MAP_IIDENTITYREGISTRYSTORAGE_SLOT,
    ERC3643_IDENTITY_REGISTRY_STORAGE_SLOT
} from "@lattice/tokens/ERC3643/libraries/ERC3643IdentityRegistryStorageLib.sol";
import {
    ERC165_MAP_ITRUSTEDISSUERSREGISTRY_SLOT,
    ERC3643_TRUSTED_ISSUERS_REGISTRY_STORAGE_SLOT
} from "@lattice/tokens/ERC3643/libraries/ERC3643TrustedIssuersRegistryLib.sol";
import {Test} from "forge-std/Test.sol";

contract ERC3643RegistryConstantsTest is Test {
    function _slot(string memory namespace) private pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(namespace))) - 1)) & ~bytes32(uint256(0xff));
    }

    function _map(bytes4 interfaceId) private pure returns (bytes32) {
        return
            keccak256(
                abi.encode(interfaceId, bytes32(0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))
            );
    }

    function test_AllFiveNamespacesUseExactPrecomputedERC7201Roots() public pure {
        assertEq(ERC3643_IDENTITY_REGISTRY_STORAGE_ROOT, _slot("lattice.storage.ERC3643IdentityRegistry"));
        assertEq(ERC3643_IDENTITY_REGISTRY_STORAGE_SLOT, _slot("lattice.storage.ERC3643IdentityRegistryStorage"));
        assertEq(ERC3643_TRUSTED_ISSUERS_REGISTRY_STORAGE_SLOT, _slot("lattice.storage.ERC3643TrustedIssuersRegistry"));
        assertEq(ERC3643_CLAIM_TOPICS_REGISTRY_STORAGE_SLOT, _slot("lattice.storage.ERC3643ClaimTopicsRegistry"));
        assertEq(ERC3643_COMPLIANCE_STORAGE_SLOT, _slot("lattice.storage.ERC3643Compliance"));
    }

    function test_AllFiveInterfaceMapSlotsUseTheStandardCC0InterfaceIds() public pure {
        assertEq(type(IIdentityRegistry).interfaceId, bytes4(0x8ff89f73));
        assertEq(type(IIdentityRegistryStorage).interfaceId, bytes4(0x57defe0d));
        assertEq(type(ITrustedIssuersRegistry).interfaceId, bytes4(0xb0f773b8));
        assertEq(type(IClaimTopicsRegistry).interfaceId, bytes4(0x10928b13));
        assertEq(type(ICompliance).interfaceId, bytes4(0xa87a1289));
        assertEq(ERC165_MAP_IIDENTITYREGISTRY_SLOT, _map(type(IIdentityRegistry).interfaceId));
        assertEq(ERC165_MAP_IIDENTITYREGISTRYSTORAGE_SLOT, _map(type(IIdentityRegistryStorage).interfaceId));
        assertEq(ERC165_MAP_ITRUSTEDISSUERSREGISTRY_SLOT, _map(type(ITrustedIssuersRegistry).interfaceId));
        assertEq(ERC165_MAP_ICLAIMTOPICSREGISTRY_SLOT, _map(type(IClaimTopicsRegistry).interfaceId));
        assertEq(ERC165_MAP_ICOMPLIANCE_SLOT, _map(type(ICompliance).interfaceId));
    }
}
