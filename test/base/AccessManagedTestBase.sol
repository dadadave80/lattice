// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployAccessManaged} from "@lattice-script/base/access/DeployAccessManaged.s.sol";
import {DeployAccessManager} from "@lattice-script/base/access/DeployAccessManager.s.sol";
import {AccessManagedTestFacet} from "@lattice-test/helpers/AccessManagedTestFacet.sol";
import {AccessManaged} from "@lattice/access/AccessManaged.sol";
import {AccessManager} from "@lattice/access/AccessManager.sol";
import {Test} from "forge-std/Test.sol";

/// @title AccessManagedTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for AccessManaged facet tests that exercise a REAL {Diamond} pair rather than flattened mocks:
///         a production {DeployAccessManager} authority diamond and a production {DeployAccessManaged} managed
///         diamond pointed at it (with a test-only {AccessManagedTestFacet} appended so the managed target has a
///         gated `restrictedFn`). Every authority + managed call routes through diamond `delegatecall` dispatch,
///         so the full authorization round-trip (direct `canCall`, and matured `schedule`/`execute`) is proven.
abstract contract AccessManagedTestBase is Test, GetSelectors {
    DeployAccessManager internal managerDeployer;
    DeployAccessManaged internal managedDeployer;

    address internal authority; // the AccessManager authority diamond
    AccessManager internal mgr; // typed handle on the authority
    address internal diamond; // the managed diamond
    AccessManaged internal managed; // typed handle on the managed diamond
    AccessManagedTestFacet internal managedHelper; // typed handle for the test-only restrictedFn

    /// @notice Assembles a production AccessManager authority diamond with `admin` as the initial admin.
    /// @param admin The address granted the initial `ADMIN_ROLE`.
    /// @return authority_ The deployed authority diamond.
    function _deployAuthority(address admin) internal returns (address authority_) {
        managerDeployer = new DeployAccessManager();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = managerDeployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        authority_ = address(d);
    }

    /// @notice Builds the managed diamond cuts + initializer (production recipe + the test-only helper facet),
    ///         WITHOUT assembling — so a test can drive `new Diamond().initialize(...)` under `vm.expectRevert`
    ///         for the invalid-authority init paths.
    /// @param authority_ The AccessManager authority the managed contract will point at.
    function _managedCuts(address authority_)
        internal
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        managedDeployer = new DeployAccessManaged();
        (FacetCut[] memory prod, address init_, bytes memory cd) = managedDeployer.buildCuts(authority_);

        cuts = new FacetCut[](prod.length + 1);
        for (uint256 i; i < prod.length; ++i) {
            cuts[i] = prod[i];
        }
        cuts[prod.length] = FacetCut({
            facetAddress: address(new AccessManagedTestFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("AccessManagedTestFacet")
        });
        init = init_;
        initCalldata = cd;
    }

    /// @notice Assembles the production managed diamond (+ helper facet) pointed at `authority_`.
    /// @param authority_ The AccessManager authority.
    /// @return diamond_ The deployed managed diamond.
    function _deployManaged(address authority_) internal returns (address diamond_) {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = _managedCuts(authority_);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
