// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {ERC20Burnable} from "@lattice/tokens/ERC20/ERC20Burnable.sol";
import {ERC20BurnableInit} from "@lattice/tokens/ERC20/ERC20BurnableInit.sol";

/// @title DeployERC20Burnable
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a burnable ERC-20 token diamond: the base {DeployERC20} recipe
///         (ERC165 + ERC20 + {ERC20Init}) plus the additive {ERC20Burnable} facet and its {ERC20BurnableInit}.
///         `buildCuts` is the broadcast-free primitive the burnable facet test reuses; `run` broadcasts. Both
///         inits run in one initializing window via {BaseDeploy._assembleMulti}.
contract DeployERC20Burnable is BaseDeploy {
    /// @notice Builds the burnable ERC-20 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name. @param symbol_ Token symbol.
    /// @return cuts The facet cuts (ERC165 + ERC20 + ERC20Burnable).
    /// @return inits The initializers, run in order ({ERC20Init} then {ERC20BurnableInit}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory name_, string memory symbol_)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        (FacetCut[] memory baseCuts, address baseInit, bytes memory baseCalldata) =
            new DeployERC20().buildCuts(name_, symbol_);

        cuts = new FacetCut[](baseCuts.length + 1);
        for (uint256 i; i < baseCuts.length; ++i) {
            cuts[i] = baseCuts[i];
        }
        cuts[baseCuts.length] = _cut(address(new ERC20Burnable()), "ERC20Burnable");

        inits = new address[](2);
        inits[0] = baseInit;
        inits[1] = address(new ERC20BurnableInit());

        initCalldatas = new bytes[](2);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC20BurnableInit.init, ());
    }

    /// @notice Deploys a burnable ERC-20 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(string memory name_, string memory symbol_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) = buildCuts(name_, symbol_);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }
}
