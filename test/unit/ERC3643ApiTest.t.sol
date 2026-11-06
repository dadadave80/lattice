// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import {IAgentRole} from "@lattice/interfaces/tokens/erc3643/IAgentRole.sol";
import {IClaimTopicsRegistry} from "@lattice/interfaces/tokens/erc3643/IClaimTopicsRegistry.sol";
import {ICompliance} from "@lattice/interfaces/tokens/erc3643/ICompliance.sol";
import {IERC3643} from "@lattice/interfaces/tokens/erc3643/IERC3643.sol";
import {IIdentityRegistry} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistry.sol";
import {IIdentityRegistryStorage} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistryStorage.sol";
import {ITrustedIssuersRegistry} from "@lattice/interfaces/tokens/erc3643/ITrustedIssuersRegistry.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Pins the independent CC0 ABI selector sets before implementation.
contract ERC3643ApiTest is Test {
    function test_IClaimTopicsRegistryInterfaceId() public pure {
        assertEq(type(IClaimTopicsRegistry).interfaceId, bytes4(0x10928b13));
    }

    function test_IComplianceInterfaceId() public pure {
        assertEq(type(ICompliance).interfaceId, bytes4(0xa87a1289));
    }

    function test_IERC3643InterfaceId() public pure {
        assertEq(type(IERC3643).interfaceId, bytes4(0xb97d944c));
    }

    function test_IIdentityRegistryInterfaceId() public pure {
        assertEq(type(IIdentityRegistry).interfaceId, bytes4(0x8ff89f73));
    }

    function test_IIdentityRegistryStorageInterfaceId() public pure {
        assertEq(type(IIdentityRegistryStorage).interfaceId, bytes4(0x57defe0d));
    }

    function test_ITrustedIssuersRegistryInterfaceId() public pure {
        assertEq(type(ITrustedIssuersRegistry).interfaceId, bytes4(0xb0f773b8));
    }

    function test_IAgentRoleInterfaceId() public pure {
        assertEq(type(IAgentRole).interfaceId, bytes4(0x0cba0fa8));
    }
}
