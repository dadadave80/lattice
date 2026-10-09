// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {DeployERC721} from "@lattice-script/base/tokens/DeployERC721.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlInit} from "@lattice/access/AccessControlInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC721Enumerable} from "@lattice/tokens/ERC721/ERC721Enumerable.sol";
import {ERC721EnumerableInit} from "@lattice/tokens/ERC721/ERC721EnumerableInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC721Enumerable
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an enumerable ERC-721 token diamond: the base {DeployERC721} recipe
///         (ERC165 + ERC721 + {ERC721Init}) plus the {ERC721Enumerable} facet, which ADDS `totalSupply`,
///         `tokenByIndex` and `tokenOfOwnerByIndex` and REPLACES the base `transferFrom` and both `safeTransferFrom`
///         overloads with enumeration-aware versions. {ERC721EnumerableInit} registers IERC721Enumerable. All inits
///         run in one initializing window via {BaseDeploy._assembleMulti}.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut (the inherited base recipe provides the
///      loupe); deploy a new diamond to change behavior. Use the ADMIN overload (`buildCuts(..., admin)` /
///      `run(..., admin)`) for an upgradeable deployment gated on `DEFAULT_ADMIN_ROLE`.
///      Mint and burn are app-specific: a minting facet calls {ERC721EnumerableLib._mint}/{_burn}, never
///      {ERC721Lib}'s. Do not add {ERC721Burnable}, {ERC721Wrapper}, {ERC721Pausable} or {ERC721Votes} to this
///      diamond (see {ERC721Enumerable}); an {ERC721ConsecutiveInit} batch reverts.
///      The `ERC721Enumerable` facet is the release facet from {BaseDeploy._facet}; the base recipe's cuts, the
///      admin-overload cuts and the inits still deploy fresh until every recipe moves to release contracts (#195).
contract DeployERC721Enumerable is BaseDeploy {
    /// @notice Builds the enumerable ERC-721 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name. @param symbol_ Token symbol.
    /// @return cuts The facet cuts (ERC165 + ERC721 + DiamondLoupeFacet + ERC721Enumerable [Add views, Replace
    ///         transferFrom/safeTransferFrom]).
    /// @return inits The initializers, run in order ({DeployERC721}'s {MultiInit} chain, then
    ///         {ERC721EnumerableInit}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory name_, string memory symbol_)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        (FacetCut[] memory baseCuts, address baseInit, bytes memory baseCalldata) =
            new DeployERC721().buildCuts(name_, symbol_);

        address facet = _facet("ERC721Enumerable");
        // The base ERC-721 already routes these three; replace them so every transfer updates the lists.
        bytes4[] memory movement = new bytes4[](3);
        movement[0] = ERC721Enumerable.transferFrom.selector;
        movement[1] = bytes4(keccak256("safeTransferFrom(address,address,uint256)"));
        movement[2] = bytes4(keccak256("safeTransferFrom(address,address,uint256,bytes)"));

        cuts = new FacetCut[](baseCuts.length + 2);
        for (uint256 i; i < baseCuts.length; ++i) {
            cuts[i] = baseCuts[i];
        }
        // The three enumeration views are new.
        cuts[baseCuts.length] = _cutExcept(facet, movement);
        cuts[baseCuts.length + 1] =
            FacetCut({facetAddress: facet, action: FacetCutAction.Replace, functionSelectors: movement});

        inits = new address[](2);
        inits[0] = baseInit;
        inits[1] = address(new ERC721EnumerableInit());

        initCalldatas = new bytes[](2);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC721EnumerableInit.init, ());
    }

    /// @notice Deploys an enumerable ERC-721 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(string memory name_, string memory symbol_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) = buildCuts(name_, symbol_);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(string memory name_, string memory symbol_, address admin)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        (FacetCut[] memory defCuts, address[] memory defInits, bytes[] memory defCalldatas) = buildCuts(name_, symbol_);

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
    function run(string memory name_, string memory symbol_, address admin) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, admin);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }
}
