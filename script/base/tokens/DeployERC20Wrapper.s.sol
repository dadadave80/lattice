// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlInit} from "@lattice/access/AccessControlInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC20Wrapper} from "@lattice/tokens/ERC20/ERC20Wrapper.sol";
import {ERC20WrapperInit} from "@lattice/tokens/ERC20/ERC20WrapperInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC20Wrapper
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a wrapper ERC-20 token diamond that wraps an existing `underlying_` ERC-20
///         1:1: the base {DeployERC20} recipe (ERC165 + ERC20 + {ERC20Init}) plus the {ERC20Wrapper} facet. The
///         wrapper facet is a MIXED cut — its `decimals()` REPLACES the base ERC-20 `decimals()` (to mirror the
///         underlying), while `underlying`/`depositFor`/`withdrawTo` are ADDED. {ERC20WrapperInit} records the
///         underlying. Both inits run in one initializing window via {BaseDeploy._assembleMulti}.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut (the inherited base recipe provides the
///      loupe); deploy a new diamond to change behavior. Use the ADMIN overload (`buildCuts(..., admin)` /
///      `run(..., admin)`) for an upgradeable deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployERC20Wrapper is BaseDeploy {
    /// @notice Builds the wrapper ERC-20 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name. @param symbol_ Token symbol. @param underlying_ The wrapped ERC-20 token.
    /// @return cuts The facet cuts (ERC165 + ERC20 + ERC20Wrapper[Replace decimals] + ERC20Wrapper[Add rest]).
    /// @return inits The initializers, run in order ({DeployERC20}'s {MultiInit} chain, then {ERC20WrapperInit}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory name_, string memory symbol_, address underlying_)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        (FacetCut[] memory baseCuts, address baseInit, bytes memory baseCalldata) =
            new DeployERC20().buildCuts(name_, symbol_);

        address wrapperFacet = address(new ERC20Wrapper());

        // `decimals()` already exists on the base ERC-20 facet — replace it to mirror the underlying.
        bytes4[] memory replaceSelectors = new bytes4[](1);
        replaceSelectors[0] = ERC20Wrapper.decimals.selector;

        // The remaining wrapper selectors are new — add them.
        bytes4[] memory addSelectors = new bytes4[](3);
        addSelectors[0] = ERC20Wrapper.underlying.selector;
        addSelectors[1] = ERC20Wrapper.depositFor.selector;
        addSelectors[2] = ERC20Wrapper.withdrawTo.selector;

        cuts = new FacetCut[](baseCuts.length + 2);
        for (uint256 i; i < baseCuts.length; ++i) {
            cuts[i] = baseCuts[i];
        }
        cuts[baseCuts.length] =
            FacetCut({facetAddress: wrapperFacet, action: FacetCutAction.Add, functionSelectors: addSelectors});
        cuts[baseCuts.length + 1] =
            FacetCut({facetAddress: wrapperFacet, action: FacetCutAction.Replace, functionSelectors: replaceSelectors});

        inits = new address[](2);
        inits[0] = baseInit;
        inits[1] = address(new ERC20WrapperInit());

        initCalldatas = new bytes[](2);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC20WrapperInit.init, (underlying_));
    }

    /// @notice Deploys a wrapper ERC-20 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
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
