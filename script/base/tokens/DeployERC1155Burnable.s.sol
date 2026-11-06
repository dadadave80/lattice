// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC1155} from "@lattice-script/base/tokens/DeployERC1155.s.sol";
import {TokenDeployBase} from "@lattice-script/base/tokens/TokenDeployBase.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlInit} from "@lattice/access/AccessControlInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC1155BurnableInit} from "@lattice/tokens/ERC1155/ERC1155BurnableInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC1155Burnable
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a burnable ERC-1155 token diamond: the base {DeployERC1155} recipe
///         (ERC165 + ERC1155 + {ERC1155Init}) plus the additive {ERC1155Burnable} facet and its
///         {ERC1155BurnableInit}. `buildCuts` is the broadcast-free primitive the burnable facet test reuses; `run`
///         broadcasts. Both inits run in one initializing window via {BaseDeploy._assembleMulti}.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut (the inherited base recipe provides the
///      loupe); deploy a new diamond to change behavior. Use the ADMIN overload (`buildCuts(..., admin)` /
///      `run(..., admin)`) for an upgradeable deployment gated on `DEFAULT_ADMIN_ROLE`.
///      All inventory facets and initializers use the shared release helpers.
contract DeployERC1155Burnable is TokenDeployBase {
    /// @notice Builds the burnable ERC-1155 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param uri_ Token URI template.
    /// @return cuts The facet cuts (ERC165 + ERC1155 + DiamondLoupeFacet + ERC1155Burnable).
    /// @return inits The initializers, run in order ({DeployERC1155}'s {MultiInit} chain, then
    ///         {ERC1155BurnableInit}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory uri_)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        (FacetCut[] memory baseCuts, address baseInit, bytes memory baseCalldata) = _erc1155Base(uri_);

        cuts = new FacetCut[](baseCuts.length + 1);
        for (uint256 i; i < baseCuts.length; ++i) {
            cuts[i] = baseCuts[i];
        }
        cuts[baseCuts.length] = _cut(_facet("ERC1155Burnable"));

        inits = new address[](2);
        inits[0] = baseInit;
        inits[1] = _init("ERC1155BurnableInit");

        initCalldatas = new bytes[](2);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC1155BurnableInit.init, ());
    }

    /// @notice Deploys a burnable ERC-1155 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(string memory uri_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) = buildCuts(uri_);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(string memory uri_, address admin)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        (FacetCut[] memory defCuts, address[] memory defInits, bytes[] memory defCalldatas) = buildCuts(uri_);

        cuts = new FacetCut[](defCuts.length + 2);
        for (uint256 i; i < defCuts.length; ++i) {
            cuts[i] = defCuts[i];
        }
        cuts[defCuts.length] = _cut(_facet("AccessControl"));
        cuts[defCuts.length + 1] = _cut(_facet("AccessControlDiamondCut"));

        inits = new address[](defInits.length + 2);
        for (uint256 i; i < defInits.length; ++i) {
            inits[i] = defInits[i];
        }
        inits[defInits.length] = _init("AccessControlInit");
        inits[defInits.length + 1] = _init("DiamondIntrospectionInit");

        initCalldatas = new bytes[](defCalldatas.length + 2);
        for (uint256 i; i < defCalldatas.length; ++i) {
            initCalldatas[i] = defCalldatas[i];
        }
        initCalldatas[defCalldatas.length] = abi.encodeCall(AccessControlInit.init, (admin));
        // The base chain registered the loupe flag; the cut facet is live too — advertise both.
        initCalldatas[defCalldatas.length + 1] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(string memory uri_, address admin) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) = buildCuts(uri_, admin);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }
}
