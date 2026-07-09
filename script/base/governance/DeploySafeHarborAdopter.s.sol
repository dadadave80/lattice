// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {SafeHarborAdopter} from "@lattice/governance/SafeHarborAdopter.sol";
import {SafeHarborAdopterInit} from "@lattice/governance/SafeHarborAdopterInit.sol";

/// @title DeploySafeHarborAdopter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a SafeHarborAdopter diamond: `ERC165Facet` + `AccessControl` +
///         `SafeHarborAdopter` + {SafeHarborAdopterInit}. The ONE source of truth for what a Safe Harbor
///         adopter diamond is, shared by production (`run --broadcast`) and the facet tests (which build on
///         {buildCuts}). `AccessControl` is part of the base recipe because every adoption/configuration
///         setter is `SAFE_HARBOR_ADMIN_ROLE`-gated (that role is administered by `DEFAULT_ADMIN_ROLE`).
contract DeploySafeHarborAdopter is BaseDeploy {
    /// @notice Builds the SafeHarborAdopter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (administers `SAFE_HARBOR_ADMIN_ROLE`).
    /// @param registry The SEAL SafeHarborRegistry for this chain (must be non-zero).
    /// @param factory The SEAL AgreementFactory for this chain (zero allowed; disables `createAndAdopt`).
    /// @return cuts The facet cuts (ERC165 + AccessControl + SafeHarborAdopter).
    /// @return init The {SafeHarborAdopterInit} initializer address.
    /// @return initCalldata The `init(admin, registry, factory)` calldata.
    function buildCuts(address admin, address registry, address factory)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new SafeHarborAdopter()));
        init = address(new SafeHarborAdopterInit());
        initCalldata = abi.encodeCall(SafeHarborAdopterInit.init, (admin, registry, factory));
    }

    /// @notice Deploys a SafeHarborAdopter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The Safe Harbor admin (root `DEFAULT_ADMIN_ROLE`).
    /// @param registry The SEAL SafeHarborRegistry for this chain.
    /// @param factory The SEAL AgreementFactory for this chain (zero allowed).
    /// @return adopter The deployed Safe Harbor adopter diamond address.
    function run(address admin, address registry, address factory) external returns (address adopter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, registry, factory);
        adopter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
