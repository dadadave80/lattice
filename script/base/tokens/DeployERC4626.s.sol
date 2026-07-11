// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC4626} from "@lattice/tokens/ERC4626/ERC4626.sol";
import {ERC4626Init} from "@lattice/tokens/ERC4626/ERC4626Init.sol";

/// @title DeployERC4626
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-4626 tokenized-vault diamond: `ERC165Facet` + `ERC20` + `ERC4626` +
///         {ERC4626Init}. The vault's shares ARE an ERC-20 token, so the base `ERC20` facet is cut for the share
///         surface and the `ERC4626` facet is a MIXED cut over it — its `decimals()` REPLACES the base ERC-20
///         `decimals()` (to add the virtual-share offset), while the vault surface (`asset`/`totalAssets`/
///         convert*/preview*/max*/deposit/mint/withdraw/redeem) is ADDED. Each facet owns ONLY its own selectors
///         (the composability principle) over one shared storage layout. The ONE source of truth for what a base
///         vault diamond is, shared by production (`run --broadcast`) and the facet tests (which build on
///         {buildCuts}, appending test-only helper facets / a mintable underlying asset).
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut; deploy a new diamond to change
///      behavior. Use the ADMIN overload (`buildCuts(..., admin)` / `run(..., admin)`) for an upgradeable
///      deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployERC4626 is BaseDeploy {
    /// @notice Builds the ERC-4626 vault diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param asset_ The underlying ERC-20 asset the vault holds.
    /// @param name_ Vault share token name.
    /// @param symbol_ Vault share token symbol.
    /// @param decimalsOffset_ Virtual-share decimals offset for inflation-attack mitigation (usually 0).
    /// @return cuts The facet cuts (ERC165 + ERC20 + ERC4626[Add vault surface] + ERC4626[Replace decimals]).
    /// @return init The {MultiInit} running {ERC4626Init} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address asset_, string memory name_, string memory symbol_, uint8 decimalsOffset_)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _coreCuts();
        (init, initCalldata) = _withImmutableIntrospection(
            address(new ERC4626Init()), abi.encodeCall(ERC4626Init.init, (asset_, name_, symbol_, decimalsOffset_))
        );
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(address asset_, string memory name_, string memory symbol_, uint8 decimalsOffset_, address admin)
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
            address(new ERC4626Init()),
            abi.encodeCall(ERC4626Init.init, (asset_, name_, symbol_, decimalsOffset_)),
            admin
        );
    }

    /// @dev The shared cut set of both overloads: the vault facets plus {DiamondLoupeFacet} (introspection).
    function _coreCuts() internal returns (FacetCut[] memory cuts) {
        address vaultFacet = address(new ERC4626());

        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new ERC20()));
        cuts[2] = FacetCut({facetAddress: vaultFacet, action: FacetCutAction.Add, functionSelectors: _vaultSurface()});
        // `decimals()` already exists on the base ERC-20 facet — replace it with the share-offset variant.
        cuts[3] = FacetCut({facetAddress: vaultFacet, action: FacetCutAction.Replace, functionSelectors: _decimals()});
        cuts[4] = _cut(address(new DiamondLoupeFacet()));
    }

    /// @notice The ERC-4626 vault selectors that are NEW relative to the base ERC-20 facet (an `Add` cut).
    function _vaultSurface() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](16);
        s[0] = ERC4626.asset.selector;
        s[1] = ERC4626.totalAssets.selector;
        s[2] = ERC4626.convertToShares.selector;
        s[3] = ERC4626.convertToAssets.selector;
        s[4] = ERC4626.maxDeposit.selector;
        s[5] = ERC4626.maxMint.selector;
        s[6] = ERC4626.maxWithdraw.selector;
        s[7] = ERC4626.maxRedeem.selector;
        s[8] = ERC4626.previewDeposit.selector;
        s[9] = ERC4626.previewMint.selector;
        s[10] = ERC4626.previewWithdraw.selector;
        s[11] = ERC4626.previewRedeem.selector;
        s[12] = ERC4626.deposit.selector;
        s[13] = ERC4626.mint.selector;
        s[14] = ERC4626.withdraw.selector;
        s[15] = ERC4626.redeem.selector;
    }

    /// @notice The single `decimals()` selector the ERC-4626 facet REPLACEs on the base ERC-20 facet.
    function _decimals() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = ERC4626.decimals.selector;
    }

    /// @notice Deploys an ERC-4626 vault diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @return vault The deployed vault diamond address.
    function run(address asset_, string memory name_, string memory symbol_, uint8 decimalsOffset_)
        external
        returns (address vault)
    {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            buildCuts(asset_, name_, symbol_, decimalsOffset_);
        vault = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(address asset_, string memory name_, string memory symbol_, uint8 decimalsOffset_, address admin)
        external
        returns (address vault)
    {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            buildCuts(asset_, name_, symbol_, decimalsOffset_, admin);
        vault = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
