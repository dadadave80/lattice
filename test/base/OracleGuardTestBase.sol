// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployChainlinkAdapter} from "@lattice-script/base/oracles/DeployChainlinkAdapter.s.sol";
import {DeployOracleGuard} from "@lattice-script/base/oracles/DeployOracleGuard.s.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {OracleGuardInit} from "@lattice/oracles/OracleGuardInit.sol";
import {Test} from "forge-std/Test.sol";

/// @title OracleGuardTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for OracleGuard tests over REAL diamonds: the production {DeployOracleGuard} recipe for a standalone
///         guard diamond, the production {DeployChainlinkAdapter} recipe for the adapter it reads, and a co-cut
///         diamond holding both facets so the guard reads its own diamond.
abstract contract OracleGuardTestBase is Test {
    /// @notice Assembles the production OracleGuard diamond with `admin` as the guard admin.
    function _deployOracleGuard(address admin) internal returns (address diamond_) {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = new DeployOracleGuard().buildCuts(admin);
        diamond_ = _initialize(cuts, init, initCalldata);
    }

    /// @notice Assembles the production Chainlink adapter diamond with `admin` as the feed-registry admin.
    function _deployChainlinkAdapter(address admin) internal returns (address diamond_) {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            new DeployChainlinkAdapter().buildCuts(admin);
        diamond_ = _initialize(cuts, init, initCalldata);
    }

    /// @notice Assembles the Chainlink adapter recipe with the OracleGuard facet cut alongside it, running the
    ///         shipped {OracleGuardInit} after the adapter recipe's init.
    function _deployCoCutChainlinkGuard(address admin) internal returns (address diamond_) {
        (FacetCut[] memory adapterCuts, address adapterInit, bytes memory adapterCalldata) =
            new DeployChainlinkAdapter().buildCuts(admin);
        (FacetCut[] memory guardCuts,,) = new DeployOracleGuard().buildCuts(admin);

        FacetCut[] memory cuts = new FacetCut[](adapterCuts.length + 1);
        for (uint256 i; i < adapterCuts.length; ++i) {
            cuts[i] = adapterCuts[i];
        }
        cuts[adapterCuts.length] = guardCuts[2]; // the OracleGuard facet

        address[] memory inits = new address[](2);
        inits[0] = adapterInit;
        inits[1] = address(new OracleGuardInit());
        bytes[] memory calldatas = new bytes[](2);
        calldatas[0] = adapterCalldata;
        calldatas[1] = abi.encodeCall(OracleGuardInit.init, ());
        diamond_ = _initialize(cuts, address(new MultiInit()), abi.encodeCall(MultiInit.multiInit, (inits, calldatas)));
    }

    function _initialize(FacetCut[] memory cuts, address init, bytes memory initCalldata)
        private
        returns (address diamond_)
    {
        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
