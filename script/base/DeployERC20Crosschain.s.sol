// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {DeployERC20} from "@lattice-script/base/DeployERC20.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {CrosschainLink} from "@lattice/crosschain/CrosschainLink.sol";
import {ERC20Crosschain} from "@lattice/tokens/ERC20/ERC20Crosschain.sol";
import {ERC20CrosschainInit} from "@lattice/tokens/ERC20/ERC20CrosschainInit.sol";

/// @title DeployERC20Crosschain
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a self-bridging ERC-20 diamond: the base {DeployERC20} cuts
///         (`ERC165Facet` + `ERC20`) with `AccessControl` + `CrosschainLink` + `ERC20Crosschain` appended,
///         sealed by a combined {ERC20CrosschainInit}. The ONE source of truth for what a self-bridging ERC-20
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because the crosschain-link setters are admin-gated.
contract DeployERC20Crosschain is BaseDeploy {
    /// @notice Builds the self-bridging ERC-20 diamond cuts + combined initializer (no broadcast, no deploy).
    /// @dev Reuses {DeployERC20.buildCuts} for the base `[ERC165, ERC20]` cuts, then appends the
    ///      `AccessControl` + `CrosschainLink` + `ERC20Crosschain` facets. The base `ERC20Init` is discarded in
    ///      favor of the combined {ERC20CrosschainInit}, which runs the full `__*_init` sequence in the single
    ///      initializing window.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param name_ Token name.
    /// @param symbol_ Token symbol.
    /// @return cuts The facet cuts (ERC165 + ERC20 + AccessControl + CrosschainLink + ERC20Crosschain).
    /// @return init The {ERC20CrosschainInit} initializer address.
    /// @return initCalldata The `init(admin, name, symbol)` calldata.
    function buildCuts(address admin, string memory name_, string memory symbol_)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        (FacetCut[] memory base,,) = new DeployERC20().buildCuts(name_, symbol_);

        cuts = new FacetCut[](base.length + 3);
        for (uint256 i; i < base.length; ++i) {
            cuts[i] = base[i];
        }
        cuts[base.length] = _cut(address(new AccessControl()), "AccessControl");
        cuts[base.length + 1] = _cut(address(new CrosschainLink()), "CrosschainLink");
        cuts[base.length + 2] = _cut(address(new ERC20Crosschain()), "ERC20Crosschain");

        init = address(new ERC20CrosschainInit());
        initCalldata = abi.encodeCall(ERC20CrosschainInit.init, (admin, name_, symbol_));
    }

    /// @notice Deploys a self-bridging ERC-20 token diamond (`forge script ... --broadcast`).
    /// @return token The deployed token diamond address.
    function run(address admin, string memory name_, string memory symbol_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, name_, symbol_);
        token = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
