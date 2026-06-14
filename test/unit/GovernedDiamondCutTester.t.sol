// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib, FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {GovernedDiamondCut} from "@lattice/governance/GovernedDiamondCut.sol";
import {
    GOVERNED_DIAMOND_CUT_STORAGE_SLOT,
    GovernedDiamondCutLib,
    UPGRADE_EXECUTOR_ROLE
} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {IEmergencyStop} from "@lattice/interfaces/IEmergencyStop.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/IGovernedDiamondCut.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice A minimal self-contained Diamond used to exercise the governed cut wrapper.
/// @dev Stacks GovernedDiamondCut + AccessControl + EmergencyStop facet logic and registers
///      UPGRADE_EXECUTOR_ROLE to address(this) at init (matching production wiring). Exposes a
///      view to read the facet bound to a selector so tests can assert a cut took effect.
contract MockGovernedDiamond is GovernedDiamondCut, AccessControl, EmergencyStop {
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        EmergencyStopLib.__EmergencyStop_init();
        DiamondLib.registerInterface(); // sets ERC-165 flag for IDiamondCut (0x1f931c1c) + loupe
        GovernedDiamondCutLib.__GovernedDiamondCut_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _id) external view returns (bool) {
        return ERC165Lib.supportsInterface(_id);
    }

    function facetOf(bytes4 _selector) external view returns (address) {
        return DiamondLib.diamondStorage().selectorToFacetAndPosition[_selector].facetAddress;
    }

    /// @dev Real Diamond fallback: routes any selector Added via a cut to its facet by delegatecall,
    ///      so an applied cut (e.g. `ping`) is callable through the proxy (matches diamond-lib's
    ///      `Diamond.fallback`). Without this the freshly-bound selector would have no router.
    fallback() external payable {
        address implementation = DiamondLib.selectorToFacet(msg.sig);
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}

/// @notice A trivial facet whose selector we will Add via a governed cut, to prove the cut applied.
contract DummyFacet {
    function ping() external pure returns (uint256) {
        return 7;
    }
}

/// @title GovernedDiamondCutTester
/// @notice Unit tests for the GovernedDiamondCut module.
contract GovernedDiamondCutTester is Test {
    MockGovernedDiamond internal diamond;
    DummyFacet internal dummy;
    address internal admin = address(0xA1);
    address internal stranger = address(0xBEEF);

    function setUp() public {
        diamond = new MockGovernedDiamond();
        diamond.initialize(admin);
        dummy = new DummyFacet();
    }

    function _addPingCut() internal view returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = DummyFacet.ping.selector;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(dummy), action: FacetCutAction.Add, functionSelectors: sels});
    }

    /// @notice The interface exposes exactly one function (`diamondCut`), so its interfaceId
    ///         equals that function's selector — which is the canonical EIP-2535 cut selector
    ///         0x1f931c1c, identical to IDiamondCut. This is intentional: GovernedDiamondCut
    ///         replaces the stock DiamondCutFacet at the same selector.
    function test_InterfaceIdIsCutSelector() public pure {
        assertEq(
            type(IGovernedDiamondCut).interfaceId,
            bytes4(0x1f931c1c),
            "GovernedDiamondCut iface id must be the cut selector"
        );
    }

    /// @notice The facet's `diamondCut` selector is the canonical EIP-2535 cut selector, so it
    ///         occupies the same selector slot as diamond-lib's stock `DiamondCutFacet`.
    function test_FacetSelectorIsCutSelector() public pure {
        assertEq(GovernedDiamondCut.diamondCut.selector, bytes4(0x1f931c1c), "facet selector mismatch");
    }

    function _erc7201Slot(string memory id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(id))) - 1)) & ~bytes32(uint256(0xff));
    }

    function test_StorageSlotDerivation() public pure {
        assertEq(
            GOVERNED_DIAMOND_CUT_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.GovernedDiamondCut"),
            "GovernedDiamondCut storage slot mismatch"
        );
    }

    function test_UpgradeExecutorRoleConstant() public pure {
        assertEq(UPGRADE_EXECUTOR_ROLE, keccak256("UPGRADE_EXECUTOR_ROLE"), "role constant mismatch");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            GUARDED CUT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Role is granted to the diamond itself, never to an EOA.
    function test_RoleHeldByDiamondNotAdmin() public view {
        assertTrue(diamond.hasRole(UPGRADE_EXECUTOR_ROLE, address(diamond)));
        assertFalse(diamond.hasRole(UPGRADE_EXECUTOR_ROLE, admin));
    }

    /// @notice A stranger (no role) calling diamondCut reverts with the unauthorized role error.
    function test_UnauthorizedCallerReverts() public {
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, UPGRADE_EXECUTOR_ROLE
            )
        );
        diamond.diamondCut(cuts, address(0), "");
    }

    /// @notice Even the admin (DEFAULT_ADMIN_ROLE) cannot cut — the role lives only on address(this).
    function test_AdminCannotCut() public {
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, admin, UPGRADE_EXECUTOR_ROLE
            )
        );
        diamond.diamondCut(cuts, address(0), "");
    }

    /// @notice The authorized caller (the diamond itself) applies a real cut: ping selector is bound.
    function test_AuthorizedSelfCallAppliesCut() public {
        FacetCut[] memory cuts = _addPingCut();
        // Impersonate the diamond calling its own diamondCut (this is exactly what the timelock relay
        // achieves in production: msg.sender == address(this)).
        vm.prank(address(diamond));
        diamond.diamondCut(cuts, address(0), "");
        assertEq(diamond.facetOf(DummyFacet.ping.selector), address(dummy), "ping selector not bound");
        // ping() is now callable through the diamond fallback.
        (bool ok, bytes memory ret) = address(diamond).call(abi.encodeWithSelector(DummyFacet.ping.selector));
        assertTrue(ok);
        assertEq(abi.decode(ret, (uint256)), 7);
    }

    /// @notice Emergency stop is the OUTER guard: when stopped, even the authorized caller is blocked,
    ///         and the revert is EmergencyStopActive (not the role error) — proving guard ordering.
    function test_EmergencyStopBlocksAuthorizedCut() public {
        // Make admin a guardian, then trip the stop.
        vm.prank(admin);
        diamond.addGuardian(admin);
        vm.prank(admin);
        diamond.emergencyStop("freeze upgrades");

        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(diamond));
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopActive.selector));
        diamond.diamondCut(cuts, address(0), "");
    }

    /// @notice After resume, the authorized cut succeeds again.
    function test_CutSucceedsAfterResume() public {
        vm.prank(admin);
        diamond.addGuardian(admin);
        vm.prank(admin);
        diamond.emergencyStop("freeze");
        vm.prank(admin);
        diamond.emergencyResume();

        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(diamond));
        diamond.diamondCut(cuts, address(0), "");
        assertEq(diamond.facetOf(DummyFacet.ping.selector), address(dummy));
    }

    /// @notice The UpgradeExecuted event fires on a successful cut.
    function test_UpgradeExecutedEventEmitted() public {
        FacetCut[] memory cuts = _addPingCut();
        vm.expectEmit(true, true, false, true, address(diamond));
        emit IGovernedDiamondCut.UpgradeExecuted(address(diamond), 1, address(0));
        vm.prank(address(diamond));
        diamond.diamondCut(cuts, address(0), "");
    }
}
