// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {
    L1ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice/crosschain/L1ToL2CrossDomainMessengerGatewayAdapter.sol";
import {
    L1ToL2CrossDomainMessengerGatewayAdapterInit
} from "@lattice/crosschain/L1ToL2CrossDomainMessengerGatewayAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployL1ToL2CrossDomainMessengerGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a canonical OP Stack L1<->L2 `CrossDomainMessenger` gateway-adapter diamond:
///         `ERC165Facet` + `AccessControl` + `L1ToL2CrossDomainMessengerGatewayAdapter` +
///         {L1ToL2CrossDomainMessengerGatewayAdapterInit}. The ONE source of truth for what such an adapter
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because the counterpart/min-gas setters are
///         `DEFAULT_ADMIN_ROLE`-gated. Unlike the CCIP/LayerZero recipes there is no endpoint/router arg — the
///         messenger is the fixed predeploy constant.
contract DeployL1ToL2CrossDomainMessengerGatewayAdapter is BaseDeploy {
    /// @notice Builds the adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin              The address granted `DEFAULT_ADMIN_ROLE` (controls the setters).
    /// @param counterpartChainId The paired-domain chain id.
    /// @param counterpartAdapter The sibling adapter on the paired domain (must be non-zero).
    /// @param minGasLimit        The `minGasLimit` the messenger relays outbound messages with.
    /// @return cuts The facet cuts (ERC165 + AccessControl + L1ToL2CrossDomainMessengerGatewayAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {L1ToL2CrossDomainMessengerGatewayAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, uint256 counterpartChainId, address counterpartAdapter, uint32 minGasLimit)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new L1ToL2CrossDomainMessengerGatewayAdapter()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new L1ToL2CrossDomainMessengerGatewayAdapterInit()),
            abi.encodeCall(
                L1ToL2CrossDomainMessengerGatewayAdapterInit.init,
                (admin, counterpartChainId, counterpartAdapter, minGasLimit)
            )
        );
    }

    /// @notice Deploys the adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin              The adapter admin.
    /// @param counterpartChainId The paired-domain chain id.
    /// @param counterpartAdapter The sibling adapter on the paired domain.
    /// @param minGasLimit        The `minGasLimit` the messenger relays outbound messages with.
    /// @return adapter The deployed adapter diamond address.
    function run(address admin, uint256 counterpartChainId, address counterpartAdapter, uint32 minGasLimit)
        external
        returns (address adapter)
    {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            buildCuts(admin, counterpartChainId, counterpartAdapter, minGasLimit);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
