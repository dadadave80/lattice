// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ERC7802} from "@lattice/tokens/ERC7802/ERC7802.sol";
import {ERC7802Init} from "@lattice/tokens/ERC7802/ERC7802Init.sol";

/// @title DeployERC7802
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a crosschain-native ERC-20 (ERC-7802) diamond: the base {DeployERC20}
///         cuts (`ERC165Facet` + `ERC20`) with `AccessControl` + `ERC7802` appended, sealed by a combined
///         {ERC7802Init}. The ONE source of truth for what an ERC-7802 token diamond is, shared by production
///         (`run --broadcast`) and the facet tests (which build on {buildCuts}). `AccessControl` is part of the
///         base recipe because `crosschainMint`/`crosschainBurn` are `CROSSCHAIN_BRIDGE_ROLE`-gated.
contract DeployERC7802 is BaseDeploy {
    /// @notice Builds the ERC-7802 diamond cuts + combined initializer (no broadcast, no proxy deploy).
    /// @dev Reuses {DeployERC20.buildCuts} for the base `[ERC165, ERC20]` cuts, then appends the
    ///      `AccessControl` + `ERC7802` facets. The base `ERC20Init` is discarded in favor of the combined
    ///      {ERC7802Init}, which runs the full `__*_init` sequence in the single initializing window.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param bridge The trusted bridge granted `CROSSCHAIN_BRIDGE_ROLE`.
    /// @param name_ Token name.
    /// @param symbol_ Token symbol.
    /// @return cuts The facet cuts (ERC165 + ERC20 + AccessControl + ERC7802).
    /// @return init The {ERC7802Init} initializer address.
    /// @return initCalldata The `init(admin, bridge, name, symbol)` calldata.
    function buildCuts(address admin, address bridge, string memory name_, string memory symbol_)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        (FacetCut[] memory base,,) = new DeployERC20().buildCuts(name_, symbol_);

        cuts = new FacetCut[](base.length + 2);
        for (uint256 i; i < base.length; ++i) {
            cuts[i] = base[i];
        }
        cuts[base.length] = _cut(address(new AccessControl()), "AccessControl");
        cuts[base.length + 1] = _cut(address(new ERC7802()), "ERC7802");

        init = address(new ERC7802Init());
        initCalldata = abi.encodeCall(ERC7802Init.init, (admin, bridge, name_, symbol_));
    }

    /// @notice Deploys an ERC-7802 crosschain-native token diamond (`forge script ... --broadcast`).
    /// @return token The deployed token diamond address.
    function run(address admin, address bridge, string memory name_, string memory symbol_)
        external
        returns (address token)
    {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, bridge, name_, symbol_);
        token = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
