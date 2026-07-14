// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {PrivateVoting} from "@lattice/privacy/PrivateVoting.sol";
import {PrivateVotingInit} from "@lattice/privacy/PrivateVotingInit.sol";
import {Semaphore} from "@lattice/privacy/Semaphore.sol";

/// @title DeployPrivateVoting
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an anonymous-voting diamond: `ERC165Facet` + `Semaphore` + `PrivateVoting`
///         + {PrivateVotingInit}. The ONE source of truth for what a private-voting diamond is, shared by
///         production (`run --broadcast`) and the facet tests (which build on {buildCuts}). PrivateVoting layers
///         1p1v tallying on top of the `Semaphore` membership facet, so BOTH facets are cut in. Poll and group
///         admin are per-group (set by `createGroup`), so there is NO `AccessControl` in the recipe. The off-chain
///         proof `verifier` is an external dependency address (its `ISemaphoreVerifier` mock is a test fixture).
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut; deploy a new diamond to change
///      behavior. Use the ADMIN overload (`buildCuts(..., admin)` / `run(..., admin)`) for an upgradeable
///      deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployPrivateVoting is BaseDeploy {
    /// @notice Builds the PrivateVoting diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param verifier The {ISemaphoreVerifier} contract address used to check the anonymous vote proofs.
    /// @return cuts The facet cuts (ERC165 + Semaphore + PrivateVoting).
    /// @return init The {MultiInit} running {PrivateVotingInit} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address verifier)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _coreCuts();
        (init, initCalldata) = _withImmutableIntrospection(
            address(new PrivateVotingInit()), abi.encodeCall(PrivateVotingInit.init, (verifier))
        );
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(address verifier, address admin)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        FacetCut[] memory base = _coreCuts();
        cuts = new FacetCut[](base.length + 2);
        for (uint256 i; i < base.length; ++i) {
            cuts[i] = base[i];
        }
        cuts[base.length] = _cut(address(new AccessControl()));
        cuts[base.length + 1] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withAdminUpgradeableIntrospection(
            address(new PrivateVotingInit()), abi.encodeCall(PrivateVotingInit.init, (verifier)), admin
        );
    }

    /// @dev The shared cut set of both overloads: the module facets plus {DiamondLoupeFacet} (introspection).
    function _coreCuts() internal returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](4);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new Semaphore()));
        cuts[2] = _cut(address(new PrivateVoting()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
    }

    /// @notice Deploys a PrivateVoting diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param verifier The {ISemaphoreVerifier} contract address.
    /// @return voting The deployed private-voting diamond address.
    function run(address verifier) external returns (address voting) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(verifier);
        voting = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(address verifier, address admin) external returns (address voting) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(verifier, admin);
        voting = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
