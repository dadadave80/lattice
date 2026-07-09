// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {ERC20Capped} from "@lattice/tokens/ERC20/ERC20Capped.sol";
import {ERC20CappedInit} from "@lattice/tokens/ERC20/ERC20CappedInit.sol";

/// @title DeployERC20Capped
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a capped-supply ERC-20 token diamond: the base {DeployERC20} recipe
///         (ERC165 + ERC20 + {ERC20Init}) plus the additive {ERC20Capped} facet (exposing `cap()`) and its
///         {ERC20CappedInit} seeding the cap. Cap enforcement lives in {ERC20CappedLib._checkCap}; the base
///         {ERC20Capped} facet keeps minting internal (app-specific), so callers wire their own gated mint.
///         Both inits run in one initializing window via {BaseDeploy._assembleMulti}.
contract DeployERC20Capped is BaseDeploy {
    /// @notice Builds the capped ERC-20 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name. @param symbol_ Token symbol. @param cap_ The supply cap (must be non-zero).
    /// @return cuts The facet cuts (ERC165 + ERC20 + ERC20Capped).
    /// @return inits The initializers, run in order ({ERC20Init} then {ERC20CappedInit}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory name_, string memory symbol_, uint256 cap_)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        (FacetCut[] memory baseCuts, address baseInit, bytes memory baseCalldata) =
            new DeployERC20().buildCuts(name_, symbol_);

        cuts = new FacetCut[](baseCuts.length + 1);
        for (uint256 i; i < baseCuts.length; ++i) {
            cuts[i] = baseCuts[i];
        }
        cuts[baseCuts.length] = _cut(address(new ERC20Capped()));

        inits = new address[](2);
        inits[0] = baseInit;
        inits[1] = address(new ERC20CappedInit());

        initCalldatas = new bytes[](2);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC20CappedInit.init, (cap_));
    }

    /// @notice Deploys a capped ERC-20 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(string memory name_, string memory symbol_, uint256 cap_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) = buildCuts(name_, symbol_, cap_);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }
}
