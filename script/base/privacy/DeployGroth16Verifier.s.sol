// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {Groth16Verifier} from "@lattice/privacy/Groth16Verifier.sol";
import {Groth16VerifierInit} from "@lattice/privacy/Groth16VerifierInit.sol";

/// @title DeployGroth16Verifier
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Groth16 verifier diamond: `ERC165Facet` + `Groth16Verifier` +
///         {Groth16VerifierInit}. The ONE source of truth for what a Groth16 verifier diamond is, shared by
///         production (`run --broadcast`) and the facet tests (which build on {buildCuts}). The verifier is a
///         stateless, permissionless primitive, so there is NO `AccessControl` in the recipe.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut; deploy a new diamond to change
///      behavior. Use the ADMIN overload (`buildCuts(..., admin)` / `run(..., admin)`) for an upgradeable
///      deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployGroth16Verifier is BaseDeploy {
    /// @notice Builds the Groth16 verifier diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @return cuts The facet cuts (ERC165 + Groth16Verifier).
    /// @return init The {MultiInit} running {Groth16VerifierInit} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts() public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _coreCuts();
        (init, initCalldata) = _withImmutableIntrospection(
            address(new Groth16VerifierInit()), abi.encodeCall(Groth16VerifierInit.init, ())
        );
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
            address(new Groth16VerifierInit()), abi.encodeCall(Groth16VerifierInit.init, ()), admin
        );
    }

    /// @dev The shared cut set of both overloads: the module facets plus {DiamondLoupeFacet} (introspection).
    function _coreCuts() internal returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new Groth16Verifier()));
        cuts[2] = _cut(address(new DiamondLoupeFacet()));
    }

    /// @notice Deploys a Groth16 verifier diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @return verifier The deployed Groth16 verifier diamond address.
    function run() external returns (address verifier) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts();
        verifier = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(address admin) external returns (address verifier) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        verifier = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
