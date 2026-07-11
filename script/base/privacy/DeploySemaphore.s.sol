// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {Semaphore} from "@lattice/privacy/Semaphore.sol";
import {SemaphoreInit} from "@lattice/privacy/SemaphoreInit.sol";

/// @title DeploySemaphore
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Semaphore diamond: `ERC165Facet` + `AccessControl` + `Semaphore` +
///         {SemaphoreInit}. The ONE source of truth for what a Semaphore diamond is, shared by production
///         (`run --broadcast`) and the facet tests (which build on {buildCuts}). `AccessControl` is part of the
///         base recipe because `setVerifier` is `DEFAULT_ADMIN_ROLE`-gated. The off-chain proof `verifier` is an
///         external dependency address (its `ISemaphoreVerifier` mock is a test fixture, not a facet).
contract DeploySemaphore is BaseDeploy {
    /// @notice Builds the Semaphore diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls `setVerifier`).
    /// @param verifier The {ISemaphoreVerifier} contract address used to check Semaphore proofs.
    /// @return cuts The facet cuts (ERC165 + AccessControl + Semaphore + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {SemaphoreInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address verifier)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new Semaphore()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new SemaphoreInit()), abi.encodeCall(SemaphoreInit.init, (admin, verifier))
        );
    }

    /// @notice Deploys a Semaphore diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The Semaphore admin (controls `setVerifier`).
    /// @param verifier The {ISemaphoreVerifier} contract address.
    /// @return semaphore The deployed Semaphore diamond address.
    function run(address admin, address verifier) external returns (address semaphore) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, verifier);
        semaphore = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
