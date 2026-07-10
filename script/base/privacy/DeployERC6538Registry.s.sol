// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC6538Registry} from "@lattice/privacy/ERC6538Registry.sol";
import {ERC6538RegistryInit} from "@lattice/privacy/ERC6538RegistryInit.sol";
import {EIP712} from "@lattice/utils/EIP712.sol";

/// @title DeployERC6538Registry
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-6538 stealth meta-address registry diamond: `ERC165Facet` +
///         `EIP712` + `ERC6538Registry` + {ERC6538RegistryInit}. The ONE source of truth for what a registry
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         Each facet owns ONLY its own selectors (the composability principle): the standalone `EIP712` facet
///         provides the ERC-5267 `eip712Domain()` entry point, and `ERC6538Registry` provides the registry
///         surface. The init seeds the EIP-712 domain.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut; deploy a new diamond to change
///      behavior. Use the ADMIN overload (`buildCuts(..., admin)` / `run(..., admin)`) for an upgradeable
///      deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployERC6538Registry is BaseDeploy {
    /// @notice Builds the ERC-6538 registry diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @return cuts The facet cuts (ERC165 + EIP712 + ERC6538Registry).
    /// @return init The {MultiInit} running {ERC6538RegistryInit} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts() public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _coreCuts();
        (init, initCalldata) = _withImmutableIntrospection(
            address(new ERC6538RegistryInit()), abi.encodeCall(ERC6538RegistryInit.init, ())
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
            address(new ERC6538RegistryInit()), abi.encodeCall(ERC6538RegistryInit.init, ()), admin
        );
    }

    /// @dev The shared cut set of both overloads: the module facets plus {DiamondLoupeFacet} (introspection).
    function _coreCuts() internal returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](4);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new EIP712()));
        cuts[2] = _cut(address(new ERC6538Registry()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
    }

    /// @notice Deploys an ERC-6538 registry diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @return registry The deployed registry diamond address.
    function run() external returns (address registry) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts();
        registry = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(address admin) external returns (address registry) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        registry = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
