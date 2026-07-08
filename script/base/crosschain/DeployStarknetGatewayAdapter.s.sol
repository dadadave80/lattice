// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {StarknetGatewayAdapter} from "@lattice/crosschain/StarknetGatewayAdapter.sol";
import {StarknetGatewayAdapterInit} from "@lattice/crosschain/StarknetGatewayAdapterInit.sol";

/// @title DeployStarknetGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Starknet L1 <-> L2 connector diamond (Ethereum L1 only): `ERC165Facet`
///         + `AccessControl` + `StarknetGatewayAdapter` + {StarknetGatewayAdapterInit}. The ONE source of truth
///         for what a Starknet adapter diamond is, shared by production (`run --broadcast`) and the facet tests
///         (which build on {buildCuts}). `AccessControl` is part of the base recipe because the L2 handler /
///         trusted-sender setters are `DEFAULT_ADMIN_ROLE`-gated. The Starknet core and expected chain
///         reference are wired at init; L2 targets (+ their `l1_handler` selectors) and trusted L2 senders are
///         registered by the admin AFTER deploy (verify them).
contract DeployStarknetGatewayAdapter is BaseDeploy {
    /// @notice Builds the Starknet adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin                  The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param starknetCore           The Starknet core (`StarknetMessaging`) contract on this chain.
    /// @param expectedChainReference The ERC-7930 chain reference to accept (e.g. `SN_MAIN` UTF-8 bytes).
    /// @return cuts         The facet cuts (ERC165 + AccessControl + StarknetGatewayAdapter).
    /// @return init         The {StarknetGatewayAdapterInit} initializer address.
    /// @return initCalldata The `init(admin, starknetCore, expectedChainReference)` calldata.
    function buildCuts(address admin, address starknetCore, bytes memory expectedChainReference)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new StarknetGatewayAdapter()));
        init = address(new StarknetGatewayAdapterInit());
        initCalldata = abi.encodeCall(StarknetGatewayAdapterInit.init, (admin, starknetCore, expectedChainReference));
    }

    /// @notice Deploys a Starknet adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin                  The adapter admin.
    /// @param starknetCore           The Starknet core (`StarknetMessaging`) contract on this chain.
    /// @param expectedChainReference The ERC-7930 chain reference to accept (e.g. `SN_MAIN` UTF-8 bytes).
    /// @return adapter The deployed Starknet adapter diamond address.
    function run(address admin, address starknetCore, bytes memory expectedChainReference)
        external
        returns (address adapter)
    {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            buildCuts(admin, starknetCore, expectedChainReference);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
