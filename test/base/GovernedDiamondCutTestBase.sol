// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployGovernedDiamondCut} from "@lattice-script/base/governance/DeployGovernedDiamondCut.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {GovernedDiamondCut} from "@lattice/governance/GovernedDiamondCut.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";
import {Test} from "forge-std/Test.sol";

/// @title GovernedDiamondCutTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for GovernedDiamondCut facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` assembles the production {DeployGovernedDiamondCut} recipe (ERC165 +
///         DiamondLoupe + AccessControl + EmergencyStop + GovernedDiamondCut + {GovernedDiamondCutInit}) onto
///         a fresh `Diamond()` and exposes typed handles — so every cut / role / emergency call routes
///         through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides.
///         `loupe.facetAddress(selector)` replaces the mock's hand-rolled `facetOf`; `erc165` replaces the
///         mock's hand-rolled `supportsInterface`.
abstract contract GovernedDiamondCutTestBase is Test, GetSelectors {
    DeployGovernedDiamondCut internal deployer;
    address internal diamond; // the assembled governed-cut diamond

    // Typed handles on the diamond (all calls dispatch through the proxy fallback).
    GovernedDiamondCut internal cut; // diamondCut / registry / frozen / emergency surface
    AccessControl internal ac; // hasRole / grantRole / getRoleAdmin
    EmergencyStop internal es; // emergencyStop / emergencyResume / addGuardian / isStopped
    DiamondLoupeFacet internal loupe; // facetAddress(selector) — verify an applied cut
    ERC165Facet internal erc165; // supportsInterface(id)

    /// @notice Assembles the production governed-cut diamond with `admin` as the role/guardian admin and
    ///         wires the typed handles.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed governed-cut diamond.
    function _deployGovernedDiamondCut(address admin) internal returns (address diamond_) {
        deployer = new DeployGovernedDiamondCut();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);

        cut = GovernedDiamondCut(diamond_);
        ac = AccessControl(diamond_);
        es = EmergencyStop(diamond_);
        loupe = DiamondLoupeFacet(diamond_);
        erc165 = ERC165Facet(diamond_);
    }
}
