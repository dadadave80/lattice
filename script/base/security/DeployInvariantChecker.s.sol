// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {InvariantChecker} from "@lattice/security/InvariantChecker.sol";
import {InvariantCheckerLib} from "@lattice/security/libraries/InvariantCheckerLib.sol";

/// @notice Recipe-local init: seeds AccessControl and registers IInvariantChecker. Composed inline —
///         `InvariantCheckerLib.__InvariantChecker_init()` is callable from any init, so no standalone production
///         init artifact exists. MUST be invoked via the diamond's `initialize` `_init` delegatecall.
contract InvariantCheckerRecipeInit {
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls invariant registration).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        InvariantCheckerLib.__InvariantChecker_init();
    }
}

/// @title DeployInvariantChecker
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an InvariantChecker diamond: `ERC165Facet` + `AccessControl` +
///         `InvariantChecker` + a recipe-local init. The ONE source of truth for what an invariant-checking
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because `registerInvariant`/`unregisterInvariant` are
///         `DEFAULT_ADMIN_ROLE`-gated.
contract DeployInvariantChecker is BaseDeploy {
    /// @notice Builds the InvariantChecker diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls invariant registration).
    /// @return cuts The facet cuts (ERC165 + AccessControl + InvariantChecker + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {InvariantCheckerRecipeInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new InvariantChecker()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new InvariantCheckerRecipeInit()), abi.encodeCall(InvariantCheckerRecipeInit.init, (admin))
        );
    }

    /// @notice Deploys an InvariantChecker diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The invariant-registration admin.
    /// @return checker The deployed invariant-checker diamond address.
    function run(address admin) external returns (address checker) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        checker = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
