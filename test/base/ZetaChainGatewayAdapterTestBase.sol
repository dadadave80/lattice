// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployZetaChainGatewayAdapter} from "@lattice-script/base/crosschain/DeployZetaChainGatewayAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {ZetaChainGatewayAdapter} from "@lattice/crosschain/ZetaChainGatewayAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title ZetaChainGatewayAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ZetaChain `GatewayEVM` gateway-adapter facet tests that exercise a REAL {Diamond} rather than a
///         flattened inheritance mock. `setUp` assembles the production {DeployZetaChainGatewayAdapter} recipe
///         (ERC165 + AccessControl + ZetaChainGatewayAdapter + {ZetaChainGatewayAdapterInit}) and exposes a typed
///         `adapter` handle — so every send / receive / config call routes through the diamond's `delegatecall`
///         dispatch, catching selector/storage/init bugs a mock hides. The `GatewayEVM` is a DEPLOYED contract, so
///         the test passes a `MockGatewayEVM` address as the ctor arg (NOT etched at a predeploy).
abstract contract ZetaChainGatewayAdapterTestBase is Test, GetSelectors {
    DeployZetaChainGatewayAdapter internal deployer;
    address internal diamond; // the assembled ZetaChain adapter diamond
    ZetaChainGatewayAdapter internal adapter; // typed handle (all calls dispatch through it)

    /// @notice Assembles the production ZetaChain adapter diamond.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param gateway The ZetaChain `GatewayEVM` (mock in tests).
    /// @param hubChainId The hub chainId.
    /// @param hubRemoteApp The trusted ZEVM universal app (hub).
    /// @param defaultOnRevertGasLimit The default revert gas limit.
    /// @return diamond_ The deployed ZetaChain adapter diamond.
    function _deployZetaChainGatewayAdapter(
        address admin,
        address gateway,
        uint256 hubChainId,
        address hubRemoteApp,
        uint256 defaultOnRevertGasLimit
    ) internal returns (address diamond_) {
        deployer = new DeployZetaChainGatewayAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            deployer.buildCuts(admin, gateway, hubChainId, hubRemoteApp, defaultOnRevertGasLimit);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
