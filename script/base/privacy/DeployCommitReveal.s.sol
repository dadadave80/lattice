// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {CommitReveal} from "@lattice/privacy/CommitReveal.sol";
import {CommitRevealInit} from "@lattice/privacy/CommitRevealInit.sol";

/// @title DeployCommitReveal
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a CommitReveal diamond: `ERC165Facet` + `CommitReveal` + {CommitRevealInit}.
///         The ONE source of truth for what a commit-reveal diamond is, shared by production (`run --broadcast`)
///         and the facet tests (which build on {buildCuts}). The primitive is permissionless (anyone may
///         commit/reveal their own), so there is NO `AccessControl` in the recipe.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut; deploy a new diamond to change
///      behavior. Use the ADMIN overload (`buildCuts(..., admin)` / `run(..., admin)`) for an upgradeable
///      deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployCommitReveal is BaseDeploy {
    /// @notice Builds the CommitReveal diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @return cuts The facet cuts (ERC165 + CommitReveal).
    /// @return init The {MultiInit} running {CommitRevealInit} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts() public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _coreCuts();
        (init, initCalldata) =
            _withImmutableIntrospection(address(new CommitRevealInit()), abi.encodeCall(CommitRevealInit.init, ()));
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        FacetCut[] memory base = _coreCuts();
        cuts = new FacetCut[](base.length + 2);
        for (uint256 i; i < base.length; ++i) {
            cuts[i] = base[i];
        }
        cuts[base.length] = _cut(address(new AccessControl()));
        cuts[base.length + 1] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withAdminUpgradeableIntrospection(
            address(new CommitRevealInit()), abi.encodeCall(CommitRevealInit.init, ()), admin
        );
    }

    /// @dev The shared cut set of both overloads: the module facets plus {DiamondLoupeFacet} (introspection).
    function _coreCuts() internal returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new CommitReveal()));
        cuts[2] = _cut(address(new DiamondLoupeFacet()));
    }

    /// @notice Deploys a CommitReveal diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @return commitReveal The deployed commit-reveal diamond address.
    function run() external returns (address commitReveal) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts();
        commitReveal = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(address admin) external returns (address commitReveal) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        commitReveal = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
