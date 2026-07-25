// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IAccessControlDiamondCut} from "@lattice/interfaces/governance/IAccessControlDiamondCut.sol";
import {Test} from "forge-std/Test.sol";

/// @title RecipeProbeFacet
/// @notice One-selector probe a guard cuts onto a recipe diamond — calling through it proves upgradeability.
contract RecipeProbeFacet {
    function recipeProbePing() external pure returns (uint256) {
        return 42;
    }
}

/// @title RecipeGuards
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice THE anti-frozen-diamond guard harness: every deploy recipe's test asserts its assembled diamond is
///         INTROSPECTABLE (the loupe answers, the loupe flag is truthful) and either UPGRADEABLE through its
///         declared authority (admin `diamondCut` works end-to-end, strangers typed-revert, the cut flag is
///         truthful) or IMMUTABLE BY DESIGN (no `0x1f931c1c` route, cut flag false). A recipe regressing to
///         the pre-#130 frozen/un-introspectable state fails its guard by construction.
abstract contract RecipeGuards is Test {
    address internal constant ADMIN = address(0xAD);
    address internal constant UPGRADE_ADMIN = address(0xAD2);
    address internal constant STRANGER = address(0xBAD);

    /// @dev Mirrors {BaseDeploy._assemble} (BaseDeploy is a Script; tests re-implement the two-liner).
    function _assemble(FacetCut[] memory cuts, address init, bytes memory initCalldata)
        internal
        returns (address diamond)
    {
        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        diamond = address(d);
    }

    /// @dev Mirrors {BaseDeploy._assembleMulti} for recipes returning (cuts, inits[], calldatas[]).
    function _assembleMulti(FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
        internal
        returns (address diamond)
    {
        MultiInit multiInit = new MultiInit();
        diamond = _assemble(cuts, address(multiInit), abi.encodeCall(MultiInit.multiInit, (inits, initCalldatas)));
    }

    /// @notice The loupe answers on `diamond` with `expectedFacets` distinct facets, `supportsInterface` is
    ///         routed, and the IDiamondLoupe ERC-165 flag is truthfully advertised.
    function _assertIntrospectable(address diamond, uint256 expectedFacets) internal view {
        assertEq(IDiamondLoupe(diamond).facetAddresses().length, expectedFacets, "facet count");
        assertTrue(IDiamondLoupe(diamond).facetAddress(0x01ffc9a7) != address(0), "supportsInterface not routed");
        assertTrue(ERC165Facet(diamond).supportsInterface(0x48e2b093), "IDiamondLoupe flag missing");
    }

    /// @notice `admin` — and only `admin` — can `diamondCut` a live probe facet onto `diamond`, and the
    ///         upgrade authority is INSPECTABLE on-chain: `hasRole(DEFAULT_ADMIN_ROLE, admin)` answers true
    ///         through the diamond (requires the AccessControl role surface to actually be routed — a
    ///         recipe cutting the cut facet without its role surface fails here).
    function _assertAdminCanCut(address diamond, address admin) internal {
        assertTrue(IAccessControl(diamond).hasRole(bytes32(0), admin), "admin must hold DEFAULT_ADMIN_ROLE (routed)");
        RecipeProbeFacet probe = new RecipeProbeFacet();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = RecipeProbeFacet.recipeProbePing.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(probe), action: FacetCutAction.Add, functionSelectors: selectors});

        // Stranger first (leaves no state behind): typed revert on the DEFAULT_ADMIN_ROLE gate.
        vm.prank(STRANGER);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, STRANGER, bytes32(0))
        );
        IAccessControlDiamondCut(diamond).diamondCut(cuts, address(0), "");

        // The declared authority actually upgrades the diamond, and the cut flag is truthful.
        vm.prank(admin);
        IAccessControlDiamondCut(diamond).diamondCut(cuts, address(0), "");
        assertEq(RecipeProbeFacet(diamond).recipeProbePing(), 42, "probe facet not routed after the cut");
        assertTrue(ERC165Facet(diamond).supportsInterface(0x1f931c1c), "IDiamondCut flag missing");
    }

    /// @notice `diamond` is immutable BY DESIGN: no facet owns `0x1f931c1c` and the cut flag is false, while
    ///         the loupe flag stays truthfully advertised.
    function _assertImmutableByDesign(address diamond) internal view {
        assertEq(IDiamondLoupe(diamond).facetAddress(0x1f931c1c), address(0), "cut selector must not be routed");
        assertFalse(ERC165Facet(diamond).supportsInterface(0x1f931c1c), "IDiamondCut flag must be false");
        assertTrue(ERC165Facet(diamond).supportsInterface(0x48e2b093), "IDiamondLoupe flag missing");
    }
}
