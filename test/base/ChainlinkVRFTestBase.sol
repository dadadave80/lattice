// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployChainlinkVRF} from "@lattice-script/base/oracles/DeployChainlinkVRF.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {ChainlinkVRF} from "@lattice/oracles/ChainlinkVRF.sol";
import {Test} from "forge-std/Test.sol";

/// @title ChainlinkVRFTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for Chainlink VRF facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployChainlinkVRF} recipe (ERC165 + AccessControl +
///         ChainlinkVRF + {ChainlinkVRFInit}) and exposes a typed `vrf` handle — so every VRF call routes
///         through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides.
///         Admin gating is enforced by the cut-in `AccessControl` facet; `supportsInterface` by `ERC165Facet`.
abstract contract ChainlinkVRFTestBase is Test, GetSelectors {
    DeployChainlinkVRF internal deployer;
    address internal diamond; // the assembled VRF diamond
    ChainlinkVRF internal vrf; // typed handle on the diamond (VRF calls dispatch through it)

    /// @notice Assembles the production Chainlink VRF diamond with `admin` as the VRF admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed VRF diamond.
    function _deployChainlinkVRF(address admin) internal returns (address diamond_) {
        deployer = new DeployChainlinkVRF();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
