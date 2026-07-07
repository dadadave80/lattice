// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {ERC1155} from "@lattice/tokens/ERC1155/ERC1155.sol";
import {ERC1155Init} from "@lattice/tokens/ERC1155/ERC1155Init.sol";

/// @title DeployERC1155
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a base ERC-1155 token diamond: `ERC165Facet` + `ERC1155` + {ERC1155Init}.
///         The ONE source of truth for what a base ERC-1155 diamond is, shared by production (`run --broadcast`)
///         and the facet tests (which build on {buildCuts}, appending test-only helper facets). Extension tokens
///         extend these cuts with their additive facets, keeping this the canonical base.
contract DeployERC1155 is BaseDeploy {
    /// @notice Builds the base ERC-1155 diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param uri_ Token URI template.
    /// @return cuts The facet cuts (ERC165 + ERC1155).
    /// @return init The {ERC1155Init} initializer address.
    /// @return initCalldata The `init(uri)` calldata.
    function buildCuts(string memory uri_)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](2);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new ERC1155()), "ERC1155");
        init = address(new ERC1155Init());
        initCalldata = abi.encodeCall(ERC1155Init.init, (uri_));
    }

    /// @notice Deploys a base ERC-1155 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @return token The deployed token diamond address.
    function run(string memory uri_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(uri_);
        token = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
