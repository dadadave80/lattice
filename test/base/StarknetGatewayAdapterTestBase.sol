// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployStarknetGatewayAdapter} from "@lattice-script/base/DeployStarknetGatewayAdapter.s.sol";
import {Test} from "forge-std/Test.sol";

/// @title StarknetGatewayAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for Starknet connector facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `_deployStarknetGatewayAdapter` assembles the production
///         {DeployStarknetGatewayAdapter} recipe (ERC165 + AccessControl + StarknetGatewayAdapter +
///         {StarknetGatewayAdapterInit}) with the Starknet core + expected chain reference wired at init — so
///         every send / cancel / consume / config call routes through the diamond's `delegatecall` dispatch,
///         catching selector/storage/init bugs a mock hides. The external {MockStarknetMessaging} stays a test
///         fixture (it is NOT the facet under test). The init guards are exercised by calling
///         `_deployStarknetGatewayAdapter` with bad args inside `vm.expectRevert` (the revert bubbles up
///         through {Diamond.initialize}).
abstract contract StarknetGatewayAdapterTestBase is Test, GetSelectors {
    DeployStarknetGatewayAdapter internal deployer;

    /// @notice Assembles the production Starknet adapter diamond with `admin` as the adapter admin.
    /// @param admin                  The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param starknetCore           The Starknet core (mock in tests).
    /// @param expectedChainReference The ERC-7930 chain reference to accept (e.g. `SN_MAIN` UTF-8 bytes).
    /// @return diamond_ The deployed Starknet adapter diamond.
    function _deployStarknetGatewayAdapter(address admin, address starknetCore, bytes memory expectedChainReference)
        internal
        returns (address diamond_)
    {
        deployer = new DeployStarknetGatewayAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            deployer.buildCuts(admin, starknetCore, expectedChainReference);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
