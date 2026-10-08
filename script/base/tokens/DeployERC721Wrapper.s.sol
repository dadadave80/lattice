// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {DeployERC721} from "@lattice-script/base/tokens/DeployERC721.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlInit} from "@lattice/access/AccessControlInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC721Wrapper} from "@lattice/tokens/ERC721/ERC721Wrapper.sol";
import {ERC721WrapperInit} from "@lattice/tokens/ERC721/ERC721WrapperInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC721Wrapper
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a wrapper ERC-721 token diamond that wraps an existing `underlying_` ERC-721
///         id for id: the base {DeployERC721} recipe (ERC165 + ERC721 + {ERC721Init}) plus the additive
///         {ERC721Wrapper} facet (`depositFor`, `withdrawTo`, `onERC721Received`, `underlying`).
///         {ERC721WrapperInit} records the underlying. Both inits run in one initializing window via
///         {BaseDeploy._assembleMulti}.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut (the inherited base recipe provides the
///      loupe); deploy a new diamond to change behavior. Use the ADMIN overload (`buildCuts(..., admin)` /
///      `run(..., admin)`) for an upgradeable deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployERC721Wrapper is BaseDeploy {
    /// @notice Builds the wrapper ERC-721 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name. @param symbol_ Token symbol. @param underlying_ The wrapped ERC-721 collection.
    /// @return cuts The facet cuts (ERC165 + ERC721 + DiamondLoupeFacet + ERC721Wrapper).
    /// @return inits The initializers, run in order ({DeployERC721}'s {MultiInit} chain, then {ERC721WrapperInit}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory name_, string memory symbol_, address underlying_)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        (FacetCut[] memory baseCuts, address baseInit, bytes memory baseCalldata) =
            new DeployERC721().buildCuts(name_, symbol_);

        cuts = new FacetCut[](baseCuts.length + 1);
        for (uint256 i; i < baseCuts.length; ++i) {
            cuts[i] = baseCuts[i];
        }
        cuts[baseCuts.length] = _cut(address(new ERC721Wrapper()));

        inits = new address[](2);
        inits[0] = baseInit;
        inits[1] = address(new ERC721WrapperInit());

        initCalldatas = new bytes[](2);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC721WrapperInit.init, (underlying_));
    }

    /// @notice Deploys a wrapper ERC-721 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(string memory name_, string memory symbol_, address underlying_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, underlying_);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(string memory name_, string memory symbol_, address underlying_, address admin)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        (FacetCut[] memory defCuts, address[] memory defInits, bytes[] memory defCalldatas) =
            buildCuts(name_, symbol_, underlying_);

        cuts = new FacetCut[](defCuts.length + 2);
        for (uint256 i; i < defCuts.length; ++i) {
            cuts[i] = defCuts[i];
        }
        cuts[defCuts.length] = _cut(address(new AccessControl()));
        cuts[defCuts.length + 1] = _cut(address(new AccessControlDiamondCut()));

        inits = new address[](defInits.length + 2);
        for (uint256 i; i < defInits.length; ++i) {
            inits[i] = defInits[i];
        }
        inits[defInits.length] = address(new AccessControlInit());
        inits[defInits.length + 1] = address(new DiamondIntrospectionInit());

        initCalldatas = new bytes[](defCalldatas.length + 2);
        for (uint256 i; i < defCalldatas.length; ++i) {
            initCalldatas[i] = defCalldatas[i];
        }
        initCalldatas[defCalldatas.length] = abi.encodeCall(AccessControlInit.init, (admin));
        // The base chain registered the loupe flag; the cut facet is live too — advertise both.
        initCalldatas[defCalldatas.length + 1] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(string memory name_, string memory symbol_, address underlying_, address admin)
        external
        returns (address token)
    {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, underlying_, admin);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }
}
