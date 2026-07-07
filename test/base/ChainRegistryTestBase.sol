// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployChainRegistry} from "@lattice-script/base/DeployChainRegistry.s.sol";
import {ChainRegistry} from "@lattice/crosschain/ChainRegistry.sol";
import {Test} from "forge-std/Test.sol";

/// @title ChainRegistryTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for chain-registry facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `_deployChainRegistry` assembles the production {DeployChainRegistry} recipe
///         (ERC165 + AccessControl + ChainRegistry + {ChainRegistryInit}) — so every registry read/write and
///         the `addEvmChain` fan-out route through the diamond's `delegatecall` dispatch, catching
///         selector/storage/init bugs a mock hides.
abstract contract ChainRegistryTestBase is Test, GetSelectors {
    DeployChainRegistry internal deployer;

    /// @notice Assembles the production chain-registry diamond with `admin` as the registry admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed chain-registry diamond.
    function _deployChainRegistry(address admin) internal returns (address diamond_) {
        deployer = new DeployChainRegistry();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
