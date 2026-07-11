// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AcrossBridgeAdapter} from "@lattice/crosschain/AcrossBridgeAdapter.sol";
import {AcrossBridgeAdapterInit} from "@lattice/crosschain/AcrossBridgeAdapterInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployAcrossBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an Across v3 token-bridge diamond: `ERC165Facet` + `AcrossBridgeAdapter`
///         + {AcrossBridgeAdapterInit}. The ONE source of truth for what an Across adapter diamond is, shared
///         by production (`run --broadcast`) and the facet tests (which build on {buildCuts}). Unlike the CCTP
///         recipe there is NO `AccessControl` cut: the adapter has no admin surface (the SpokePool is wired
///         once at init and Across chain ids are passed raw by callers — no domain table to manage). The
///         reentrancy guard is seeded inside {AcrossBridgeAdapterInit} (storage-only, no facet cut needed).
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut; deploy a new diamond to change
///      behavior. Use the ADMIN overload (`buildCuts(..., admin)` / `run(..., admin)`) for an upgradeable
///      deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployAcrossBridgeAdapter is BaseDeploy {
    /// @notice Builds the Across adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param spokePool The LOCAL chain's canonical Across v3 SpokePool.
    /// @return cuts         The facet cuts (ERC165 + AcrossBridgeAdapter).
    /// @return init         The {MultiInit} running {AcrossBridgeAdapterInit} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address spokePool)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _coreCuts();
        (init, initCalldata) = _withImmutableIntrospection(
            address(new AcrossBridgeAdapterInit()), abi.encodeCall(AcrossBridgeAdapterInit.init, (spokePool))
        );
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(address spokePool, address admin)
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
            address(new AcrossBridgeAdapterInit()), abi.encodeCall(AcrossBridgeAdapterInit.init, (spokePool)), admin
        );
    }

    /// @dev The shared cut set of both overloads: the module facets plus {DiamondLoupeFacet} (introspection).
    function _coreCuts() internal returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AcrossBridgeAdapter()));
        cuts[2] = _cut(address(new DiamondLoupeFacet()));
    }

    /// @notice Deploys an Across adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param spokePool The LOCAL chain's canonical Across v3 SpokePool.
    /// @return adapter The deployed Across adapter diamond address.
    function run(address spokePool) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(spokePool);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(address spokePool, address admin) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(spokePool, admin);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
