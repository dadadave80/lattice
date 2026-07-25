// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployBridgeERC7802} from "@lattice-script/base/crosschain/DeployBridgeERC7802.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {Test} from "forge-std/Test.sol";

/// @title BridgeERC7802TestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for BridgeERC7802 facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `_deployBridgeERC7802` assembles the production {DeployBridgeERC7802} recipe (ERC165 +
///         AccessControl + CrosschainLink + BridgeERC7802 + {BridgeERC7802Init}) — so every bridge call routes
///         through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. The
///         external ERC-7786 gateway + ERC-7802 token mocks stay test fixtures (they are NOT the facet under
///         test). The zero-token init guard is exercised by calling `_deployBridgeERC7802(admin, address(0))`
///         inside `vm.expectRevert` (the `BridgeZeroToken` revert bubbles up through {Diamond.initialize}).
abstract contract BridgeERC7802TestBase is Test, GetSelectors {
    DeployBridgeERC7802 internal deployer;

    /// @notice Assembles the production BridgeERC7802 diamond over `token` with `admin` as the registry admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param token The bridged ERC-7802 token.
    /// @return diamond_ The deployed bridge diamond.
    function _deployBridgeERC7802(address admin, address token) internal returns (address diamond_) {
        deployer = new DeployBridgeERC7802();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, token);

        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
