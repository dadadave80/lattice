// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Selectors} from "@diamond-test/helpers/Selectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {IFacet} from "@diamond/interfaces/IFacet.sol";
import {DiamondLib, FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IAccessControlDiamondCut} from "@lattice/interfaces/governance/IAccessControlDiamondCut.sol";
import {IEmergencyStop} from "@lattice/interfaces/security/IEmergencyStop.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {Test} from "forge-std/Test.sol";

/// @title AdminCutProbeFacet
/// @notice One-selector probe added by an admin cut — calling through it proves the cut applied.
contract AdminCutProbeFacet {
    function adminProbePing() external pure returns (uint256) {
        return 42;
    }
}

/// @title AccessControlDiamondCutInitFixture
/// @notice Test init: seeds the admin, registers the IDiamondCut/IDiamondLoupe ERC-165 flags, and arms the
///         EmergencyStop module — exactly what a Class-A recipe init does once it cuts the admin-gated cut
///         facet + loupe + EmergencyStop.
contract AccessControlDiamondCutInitFixture {
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        DiamondLib.registerInterface();
        EmergencyStopLib.__EmergencyStop_init();
    }
}

/// @title AccessControlDiamondCutTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Proof on a REAL assembled diamond that {AccessControlDiamondCut} makes the module admin the
///         upgrade authority: a `DEFAULT_ADMIN_ROLE` holder can cut, anyone else typed-reverts, the loupe
///         reflects the upgrade, and the canonical `0x1f931c1c` flag is advertised — the single-authority
///         answer to the frozen-diamond bug for admin-owned recipes.
contract AccessControlDiamondCutTest is Test {
    address internal admin = address(0xAD);
    address internal stranger = address(0xBAD);
    address internal diamond;

    /// @dev ERC-8153 Add cut: the facet self-reports its selectors (diamond-lib ≥0.2.0 facets included).
    function _cut8153(address facet) internal view returns (FacetCut memory) {
        return FacetCut({
            facetAddress: facet,
            action: FacetCutAction.Add,
            functionSelectors: Selectors.decode(IFacet(facet).exportSelectors())
        });
    }

    function setUp() public {
        FacetCut[] memory cuts = new FacetCut[](5);
        cuts[0] = _cut8153(address(new ERC165Facet()));
        cuts[1] = _cut8153(address(new AccessControl()));
        cuts[2] = _cut8153(address(new DiamondLoupeFacet()));
        cuts[3] = _cut8153(address(new AccessControlDiamondCut()));
        cuts[4] = _cut8153(address(new EmergencyStop()));
        Diamond d = new Diamond();
        d.initialize(
            cuts,
            address(new AccessControlDiamondCutInitFixture()),
            abi.encodeCall(AccessControlDiamondCutInitFixture.init, (admin))
        );
        diamond = address(d);
    }

    function _probeCuts() internal returns (FacetCut[] memory cuts) {
        AdminCutProbeFacet probe = new AdminCutProbeFacet();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = AdminCutProbeFacet.adminProbePing.selector;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(probe), action: FacetCutAction.Add, functionSelectors: selectors});
    }

    /// @notice The admin — and only the admin — actually upgrades the diamond (and the audit event fires).
    function test_AdminCanDiamondCut() public {
        FacetCut[] memory cuts = _probeCuts();
        vm.expectEmit(true, true, true, true, diamond);
        emit IAccessControlDiamondCut.AdminUpgradeExecuted(admin, 1, address(0));
        vm.prank(admin);
        IAccessControlDiamondCut(diamond).diamondCut(cuts, address(0), "");

        assertEq(AdminCutProbeFacet(diamond).adminProbePing(), 42, "probe facet not routed after the cut");
        assertEq(IDiamondLoupe(diamond).facetAddresses().length, 6, "probe facet joined the loupe");
    }

    /// @notice The stop gate is LIVE: a guardian halt blocks admin cuts until the admin resumes.
    function test_EmergencyStopBlocksAdminCutUntilResume() public {
        address guardian = address(0x6A2D);
        FacetCut[] memory cuts = _probeCuts();

        vm.prank(admin);
        EmergencyStop(diamond).addGuardian(guardian);
        vm.prank(guardian);
        EmergencyStop(diamond).emergencyStop("halt: suspected key compromise");

        vm.prank(admin);
        vm.expectRevert(IEmergencyStop.EmergencyStopActive.selector);
        IAccessControlDiamondCut(diamond).diamondCut(cuts, address(0), "");

        vm.prank(admin);
        EmergencyStop(diamond).emergencyResume();
        vm.prank(admin);
        IAccessControlDiamondCut(diamond).diamondCut(cuts, address(0), "");
        assertEq(AdminCutProbeFacet(diamond).adminProbePing(), 42, "cut must succeed after resume");
    }

    /// @notice A non-admin caller typed-reverts on the DEFAULT_ADMIN_ROLE gate.
    function test_StrangerCannotDiamondCut() public {
        FacetCut[] memory cuts = _probeCuts();
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, bytes32(0))
        );
        IAccessControlDiamondCut(diamond).diamondCut(cuts, address(0), "");
    }

    /// @notice The assembled diamond advertises the canonical cut + loupe interfaces it routes.
    function test_AdvertisesCutAndLoupeInterfaces() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(0x1f931c1c), "IDiamondCut flag missing");
        assertTrue(ERC165Facet(diamond).supportsInterface(0x48e2b093), "IDiamondLoupe flag missing");
    }

    /// @notice interfaceId aliasing: the admin-gated interface IS the canonical IDiamondCut id.
    function test_InterfaceIdIsCanonicalCutSelector() public pure {
        assertEq(type(IAccessControlDiamondCut).interfaceId, bytes4(0x1f931c1c), "interfaceId must alias IDiamondCut");
    }
}
