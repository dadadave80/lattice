// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployGovernedSafeDiamondCut} from "@lattice-script/base/governance/DeployGovernedSafeDiamondCut.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {GovernedSafeDiamondCut} from "@lattice/governance/GovernedSafeDiamondCut.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Tiny mock standing in for a Gnosis Safe (read-only surface used to validate the authority).
contract MockSafe {
    uint256 internal _threshold;
    address[] internal _owners;
    uint256 internal _nonce;

    constructor(uint256 threshold_, address[] memory owners_) {
        _threshold = threshold_;
        _owners = owners_;
    }

    function getThreshold() external view returns (uint256) {
        return _threshold;
    }

    function getOwners() external view returns (address[] memory) {
        return _owners;
    }

    function isOwner(address a) external view returns (bool) {
        for (uint256 i; i < _owners.length; ++i) {
            if (_owners[i] == a) return true;
        }
        return false;
    }

    function nonce() external view returns (uint256) {
        return _nonce;
    }
}

/// @title GovernedSafeDiamondCutTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for GovernedSafeDiamondCut facet tests that exercise a REAL {Diamond} rather than a
///         flattened inheritance mock. `setUp` assembles the production {DeployGovernedSafeDiamondCut} recipe
///         (ERC165 + DiamondLoupe + AccessControl + EmergencyStop + GovernedSafeDiamondCut +
///         {GovernedSafeDiamondCutInit}) onto a fresh `Diamond()` and exposes typed handles — so every
///         schedule / execute / cancel / role / emergency call routes through the diamond's `delegatecall`
///         dispatch, catching selector/storage/init bugs a mock hides. `loupe.facetAddress(selector)`
///         replaces the mock's hand-rolled `facetOf`; `erc165` replaces the mock's hand-rolled
///         `supportsInterface`.
abstract contract GovernedSafeDiamondCutTestBase is Test, GetSelectors {
    DeployGovernedSafeDiamondCut internal deployer;
    address internal diamond; // the assembled Safe-gated, timelocked cut diamond

    // Typed handles on the diamond (all calls dispatch through the proxy fallback).
    GovernedSafeDiamondCut internal cut; // schedule/execute/cancel / setSafe / registry / frozen / emergency
    AccessControl internal ac; // hasRole / grantRole / getRoleAdmin
    EmergencyStop internal es; // emergencyStop / emergencyResume / addGuardian / isStopped
    DiamondLoupeFacet internal loupe; // facetAddress(selector) — verify an applied cut
    ERC165Facet internal erc165; // supportsInterface(id)

    /// @notice Assembles the production governed-Safe-cut diamond and wires the typed handles.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param safe The pinned Safe authority.
    /// @param minThreshold The minimum Safe signature threshold.
    /// @param minDelay The minimum timelock delay (seconds).
    /// @return diamond_ The deployed governed-Safe-cut diamond.
    function _deployGovernedSafeDiamondCut(address admin, address safe, uint256 minThreshold, uint256 minDelay)
        internal
        returns (address diamond_)
    {
        deployer = new DeployGovernedSafeDiamondCut();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            deployer.buildCuts(admin, safe, minThreshold, minDelay);

        LatticeDiamond d = new LatticeDiamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);

        cut = GovernedSafeDiamondCut(diamond_);
        ac = AccessControl(diamond_);
        es = EmergencyStop(diamond_);
        loupe = DiamondLoupeFacet(diamond_);
        erc165 = ERC165Facet(diamond_);
    }
}
