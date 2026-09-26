// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {Receive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {HTSAdapter} from "@lattice/tokens/hedera/HTSAdapter.sol";
import {HTSAdapterInit} from "@lattice/tokens/hedera/HTSAdapterInit.sol";

/// @title DeployHTSAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Hedera Token Service diamond: `ERC165Facet` + `AccessControl` +
///         `HTSAdapter` + {HTSAdapterInit}. The ONE source of truth for what an HTS diamond is, shared by
///         production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because every association, creation and treasury
///         mutator is role-gated (`HTS_MANAGER_ROLE` / `HTS_OPERATOR_ROLE`). `Receive` is part of it because
///         the diamond is the treasury AND the auto-renew account of every token it creates, so it must be
///         able to hold HBAR — a plain transfer is how it gets funded for the auto-renewal the network
///         charges it and for the creation fees it forwards as `msg.value`.
contract DeployHTSAdapter is BaseDeploy {
    /// @notice Builds the HTS diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`, `HTS_MANAGER_ROLE` and `HTS_OPERATOR_ROLE`.
    /// @return cuts The facet cuts (ERC165 + AccessControl + HTSAdapter + DiamondLoupeFacet +
    ///         AccessControlDiamondCut + Receive).
    /// @return init The {MultiInit} running {HTSAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](6);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new HTSAdapter()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        cuts[5] = _cut(address(new Receive()));
        (init, initCalldata) =
            _withUpgradeableIntrospection(address(new HTSAdapterInit()), abi.encodeCall(HTSAdapterInit.init, (admin)));
    }

    /// @notice Deploys an HTS diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The HTS manager / operator admin.
    /// @return hts The deployed HTS diamond address.
    function run(address admin) external returns (address hts) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        hts = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
