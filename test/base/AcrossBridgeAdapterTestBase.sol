// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployAcrossBridgeAdapter} from "@lattice-script/base/crosschain/DeployAcrossBridgeAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {Test} from "forge-std/Test.sol";

/// @title AcrossBridgeAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for Across token-bridge adapter facet tests that exercise a REAL {Diamond} rather than a
///         flattened inheritance mock. `_deployAcrossBridgeAdapter` assembles the production
///         {DeployAcrossBridgeAdapter} recipe (ERC165 + AcrossBridgeAdapter + {AcrossBridgeAdapterInit}) with
///         the local SpokePool wired at init — so every deposit / handle call routes through the diamond's
///         `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. The external
///         `MockSpokePool` stays a test fixture (it is NOT the facet under test). The zero-address init guard
///         is exercised by calling `buildCuts` with a zero SpokePool inside `vm.expectRevert` (the
///         `AcrossZeroAddress` revert bubbles up through {Diamond.initialize}).
abstract contract AcrossBridgeAdapterTestBase is Test, GetSelectors {
    DeployAcrossBridgeAdapter internal deployer;

    /// @notice Assembles the production Across adapter diamond wired to `spokePool`.
    /// @param spokePool The local Across v3 SpokePool (mock in tests).
    /// @return diamond_ The deployed Across adapter diamond.
    function _deployAcrossBridgeAdapter(address spokePool) internal returns (address diamond_) {
        deployer = new DeployAcrossBridgeAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(spokePool);

        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
