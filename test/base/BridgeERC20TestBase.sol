// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployBridgeERC20} from "@lattice-script/base/crosschain/DeployBridgeERC20.s.sol";
import {Test} from "forge-std/Test.sol";

/// @title BridgeERC20TestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for BridgeERC20 facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `_deployBridgeERC20` assembles the production {DeployBridgeERC20} recipe (ERC165 + AccessControl
///         + CrosschainLink + BridgeERC20 + {BridgeERC20Init}) — so every bridge call routes through the diamond's
///         `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. The external ERC-7786
///         gateway + ERC-20 token mocks stay test fixtures (they are NOT the facet under test). The zero-token
///         init guard is exercised by calling `_deployBridgeERC20(admin, address(0))` inside `vm.expectRevert`
///         (the `BridgeZeroToken` revert bubbles up through {Diamond.initialize}).
abstract contract BridgeERC20TestBase is Test, GetSelectors {
    DeployBridgeERC20 internal deployer;

    /// @notice Assembles the production BridgeERC20 diamond over `token` with `admin` as the registry admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param token The bridged ERC-20 token.
    /// @return diamond_ The deployed bridge diamond.
    function _deployBridgeERC20(address admin, address token) internal returns (address diamond_) {
        deployer = new DeployBridgeERC20();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, token);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
