// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {ERC20Wrapper} from "@lattice/tokens/ERC20/ERC20Wrapper.sol";
import {ERC20WrapperInit} from "@lattice/tokens/ERC20/ERC20WrapperInit.sol";

/// @title DeployERC20Wrapper
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a wrapper ERC-20 token diamond that wraps an existing `underlying_` ERC-20
///         1:1: the base {DeployERC20} recipe (ERC165 + ERC20 + {ERC20Init}) plus the {ERC20Wrapper} facet. The
///         wrapper facet is a MIXED cut — its `decimals()` REPLACES the base ERC-20 `decimals()` (to mirror the
///         underlying), while `underlying`/`depositFor`/`withdrawTo` are ADDED. {ERC20WrapperInit} records the
///         underlying. Both inits run in one initializing window via {BaseDeploy._assembleMulti}.
contract DeployERC20Wrapper is BaseDeploy {
    /// @notice Builds the wrapper ERC-20 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name. @param symbol_ Token symbol. @param underlying_ The wrapped ERC-20 token.
    /// @return cuts The facet cuts (ERC165 + ERC20 + ERC20Wrapper[Replace decimals] + ERC20Wrapper[Add rest]).
    /// @return inits The initializers, run in order ({ERC20Init} then {ERC20WrapperInit}).
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
}
