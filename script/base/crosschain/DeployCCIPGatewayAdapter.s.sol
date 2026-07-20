// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {Receive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {CCIPGatewayAdapter} from "@lattice/crosschain/chainlink/CCIPGatewayAdapter.sol";
import {CCIPGatewayAdapterInit} from "@lattice/crosschain/chainlink/CCIPGatewayAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployCCIPGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Chainlink CCIP gateway-adapter diamond: `ERC165Facet` + `AccessControl` +
///         `CCIPGatewayAdapter` + {CCIPGatewayAdapterInit}. The ONE source of truth for what a CCIP adapter diamond
///         is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because every chain-selector / remote-gateway / destination /
///         fee-token setter is `DEFAULT_ADMIN_ROLE`-gated. The CCIP router and fee token are wired at init time.
contract DeployCCIPGatewayAdapter is BaseDeploy {
    /// @notice Builds the CCIP adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param router The CCIP router the adapter dispatches to and accepts deliveries from.
    /// @param feeToken The initial CCIP fee token (`address(0)` = native gas).
    /// @return cuts The facet cuts (ERC165 + AccessControl + CCIPGatewayAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {CCIPGatewayAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address router, address feeToken)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](6);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new CCIPGatewayAdapter()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        cuts[5] = _cut(address(new Receive()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new CCIPGatewayAdapterInit()),
            abi.encodeCall(CCIPGatewayAdapterInit.init, (admin, router, feeToken))
        );
    }

    /// @notice Deploys a CCIP adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The adapter admin.
    /// @param router The CCIP router.
    /// @param feeToken The initial CCIP fee token (`address(0)` = native gas).
    /// @return adapter The deployed CCIP adapter diamond address.
    function run(address admin, address router, address feeToken) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, router, feeToken);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
