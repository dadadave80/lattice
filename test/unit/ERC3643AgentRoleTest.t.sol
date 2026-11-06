// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {OwnableFacet} from "@diamond/facets/OwnableFacet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IAgentRole} from "@lattice/interfaces/tokens/erc3643/IAgentRole.sol";
import {ERC3643AgentRole} from "@lattice/tokens/ERC3643/ERC3643AgentRole.sol";
import {
    ERC165_MAP_IAGENTROLE_SLOT,
    ERC3643AgentRoleLib,
    ERC3643_AGENT_ROLE
} from "@lattice/tokens/ERC3643/libraries/ERC3643AgentRoleLib.sol";
import {
    ERC3643ExecutionInProgress,
    ERC3643ExecutionLib,
    ERC3643_EXECUTION_SLOT
} from "@lattice/tokens/ERC3643/libraries/ERC3643ExecutionLib.sol";
import {Test} from "forge-std/Test.sol";

interface AgentExport {
    function exportSelectors() external pure returns (bytes memory);
}

/// @notice Unit bootstrap only; the supported production profile has a distinct canonical initializer.
contract AgentRoleUnitInit {
    function init(address owner, address[] memory agents) external {
        OwnableLib.initializeOwner(owner);
        ERC3643AgentRoleLib.__ERC3643AgentRole_init(agents);
    }
}

contract AgentRoleLockProbe {
    function attempt(address agent) external returns (bool, bytes memory) {
        ERC3643ExecutionLib.enter();
        (bool ok, bytes memory result) = address(this).call(abi.encodeCall(IAgentRole.addAgent, (agent)));
        ERC3643ExecutionLib.exit();
        return (ok, result);
    }
}

contract ERC3643AgentRoleTest is Test {
    address diamond;
    IAgentRole agents;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function _selectors(address facet) internal view returns (bytes4[] memory result) {
        bytes memory packed = AgentExport(facet).exportSelectors();
        result = new bytes4[](packed.length / 4);
        for (uint256 i; i < result.length; ++i) {
            bytes4 selector;
            assembly ("memory-safe") { selector := mload(add(add(packed, 32), mul(i, 4))) }
            result[i] = selector;
        }
    }

    function setUp() public {
        address[3] memory facets =
            [address(new ERC3643AgentRole()), address(new OwnableFacet()), address(new ERC165Facet())];
        FacetCut[] memory cuts = new FacetCut[](4);
        for (uint256 i; i < facets.length; ++i) {
            cuts[i] = FacetCut(facets[i], FacetCutAction.Add, _selectors(facets[i]));
        }
        bytes4[] memory one = new bytes4[](1);
        one[0] = AgentRoleLockProbe.attempt.selector;
        cuts[3] = FacetCut(address(new AgentRoleLockProbe()), FacetCutAction.Add, one);
        address[] memory initial = new address[](1);
        initial[0] = alice;
        Lattice d = new Lattice();
        d.initialize(
            cuts, address(new AgentRoleUnitInit()), abi.encodeCall(AgentRoleUnitInit.init, (address(this), initial))
        );
        diamond = address(d);
        agents = IAgentRole(diamond);
    }

    function test_AgentMembershipAndOwnerAdministration() public {
        assertTrue(agents.isAgent(alice));
        agents.addAgent(bob);
        assertTrue(agents.isAgent(bob));
        agents.removeAgent(alice);
        assertFalse(agents.isAgent(alice));
    }

    function test_AgentDoesNotAdministerOtherAgents() public {
        vm.prank(alice);
        vm.expectRevert();
        agents.addAgent(bob);
        vm.prank(alice);
        vm.expectRevert();
        agents.removeAgent(alice);
        assertTrue(agents.isAgent(alice));
        assertFalse(agents.isAgent(bob));
    }

    function test_OwnershipTransferImmediatelyChangesAdministrationAndRetainsAgents() public {
        agents.addAgent(address(this));
        OwnableFacet(diamond).transferOwnership(bob);
        assertTrue(agents.isAgent(alice));
        assertTrue(agents.isAgent(address(this)));
        assertFalse(agents.isAgent(bob));
        vm.expectRevert();
        agents.addAgent(bob);
        vm.prank(bob);
        agents.addAgent(bob);
        vm.prank(bob);
        agents.removeAgent(address(this));
        assertTrue(agents.isAgent(bob));
        assertFalse(agents.isAgent(address(this)));
    }

    function test_DuplicatesAreIdempotentAndZeroRejected() public {
        agents.addAgent(alice);
        agents.removeAgent(bob);
        assertTrue(agents.isAgent(alice));
        assertFalse(agents.isAgent(bob));
        vm.expectRevert(abi.encodeWithSelector(IAgentRole.ERC3643InvalidAgent.selector, address(0)));
        agents.addAgent(address(0));
        vm.expectRevert(abi.encodeWithSelector(IAgentRole.ERC3643InvalidAgent.selector, address(0)));
        agents.removeAgent(address(0));
    }

    function test_RegistersOnlyRoutedStandardAgentInterface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IAgentRole).interfaceId));
        assertFalse(
            ERC165Facet(diamond).supportsInterface(type(IAccessControl).interfaceId),
            "unrouted AccessControl must not be advertised"
        );
        // No DEFAULT_ADMIN_ROLE was seeded by agent bookkeeping.
        bytes32 accessRoot = 0xb914f813e2d49e02dd5aa794466aa4a74f9c100c2b1e98e29e7267020b834d00;
        bytes32 member = keccak256(abi.encode(address(this), keccak256(abi.encode(bytes32(0), accessRoot))));
        assertEq(vm.load(diamond, member), bytes32(0));
    }

    function test_ReentrantRoleMutationRejectedAndGuardClears() public {
        (bool ok, bytes memory result) = AgentRoleLockProbe(diamond).attempt(bob);
        assertFalse(ok);
        assertEq(result, abi.encodeWithSelector(ERC3643ExecutionInProgress.selector));
        agents.addAgent(bob);
        assertTrue(agents.isAgent(bob));
    }

    function test_ConstantsDerivedFromTheirDeclaredInputs() public pure {
        bytes32 root =
            keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC3643Execution")) - 1)) & ~bytes32(uint256(0xff));
        assertEq(ERC3643_EXECUTION_SLOT, root);
        assertEq(ERC3643_AGENT_ROLE, keccak256("lattice.role.ERC3643Agent"));
        assertEq(
            ERC165_MAP_IAGENTROLE_SLOT,
            keccak256(
                abi.encode(
                    type(IAgentRole).interfaceId,
                    bytes32(0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200)
                )
            )
        );
    }
}
