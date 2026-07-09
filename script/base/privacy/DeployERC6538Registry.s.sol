// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
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
contract DeployERC6538Registry is BaseDeploy {
    /// @notice Builds the ERC-6538 registry diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @return cuts The facet cuts (ERC165 + EIP712 + ERC6538Registry).
    /// @return init The {ERC6538RegistryInit} initializer address.
    /// @return initCalldata The `init()` calldata.
    function buildCuts() public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new EIP712()));
        cuts[2] = _cut(address(new ERC6538Registry()));
        init = address(new ERC6538RegistryInit());
        initCalldata = abi.encodeCall(ERC6538RegistryInit.init, ());
    }

    /// @notice Deploys an ERC-6538 registry diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @return registry The deployed registry diamond address.
    function run() external returns (address registry) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts();
        registry = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
