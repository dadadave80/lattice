// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {ERC3643Init} from "@lattice/tokens/ERC3643/ERC3643Init.sol";
import {ERC3643Params} from "@lattice/tokens/ERC3643/ERC3643Params.sol";

/// @title DeployERC3643
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice The reviewed immutable ERC-3643 composition, initialized atomically by LatticeFactory.
/// @dev No cut, arbitrary execution, delegatecall, permit, vote/vault or other accounting facet is installed.
///      The canonical initializer checks all runtime hashes and exact required selector routes. External
///      storage must pre-bind the predicted registry/token address; external compliance must be pre-bound
///      or genuinely authorize the token to bind it. No custom initializer or approved-hash list is accepted.
contract DeployERC3643 is BaseDeploy {
    function buildCuts(ERC3643Params memory config)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        string[10] memory names = [
            "ERC165Facet",
            "OwnableFacet",
            "DiamondLoupeFacet",
            "ERC3643",
            "ERC3643AgentRole",
            "ERC3643IdentityRegistry",
            "ERC3643IdentityRegistryStorage",
            "ERC3643TrustedIssuersRegistry",
            "ERC3643ClaimTopicsRegistry",
            "ERC3643Compliance"
        ];
        cuts = new FacetCut[](names.length + (config.temporaryApproval ? 1 : 0));
        for (uint256 i; i < names.length; ++i) {
            cuts[i] = _cut(_facet(names[i]));
        }
        if (config.temporaryApproval) cuts[names.length] = _cut(_facet("ERC20TemporaryApproval"));
        init = _init("ERC3643Init");
        initCalldata = abi.encodeCall(ERC3643Init.init, (config));
    }

    function run(ERC3643Params memory config) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory data) = buildCuts(config);
        token = _assemble(cuts, init, data);
        vm.stopBroadcast();
    }
}
