// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Init} from "@lattice/tokens/ERC20/ERC20Init.sol";

/// @title DeployERC20
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a base ERC-20 token diamond: `ERC165Facet` + `ERC20` + {ERC20Init}. The
///         ONE source of truth for what a base ERC-20 diamond is, shared by production (`run --broadcast`) and
///         the facet tests (which build on {buildCuts}, appending test-only helper facets). Extension tokens
///         extend these cuts with their additive facets (Burnable/Capped/…), keeping this the canonical base.
contract DeployERC20 is BaseDeploy {
    /// @notice Builds the base ERC-20 diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param name_ Token name.
    /// @param symbol_ Token symbol.
    /// @return cuts The facet cuts (ERC165 + ERC20).
    /// @return init The {ERC20Init} initializer address.
    /// @return initCalldata The `init(name, symbol)` calldata.
    function buildCuts(string memory name_, string memory symbol_)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](2);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new ERC20()));
        init = address(new ERC20Init());
        initCalldata = abi.encodeCall(ERC20Init.init, (name_, symbol_));
    }

    /// @notice Deploys a base ERC-20 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @return token The deployed token diamond address.
    function run(string memory name_, string memory symbol_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(name_, symbol_);
        token = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
