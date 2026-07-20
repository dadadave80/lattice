// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {ERC20Pausable} from "@lattice/tokens/ERC20/ERC20Pausable.sol";
import {ERC20PausableInit} from "@lattice/tokens/ERC20/ERC20PausableInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC20Pausable
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a pausable ERC-20 token diamond: the base {DeployERC20} recipe
///         (ERC165 + ERC20 + {ERC20Init}), the {Pausable} facet (admin-gated `pause()`/`unpause()`), and the
///         {ERC20Pausable} facet which REPLACES the base `transfer`/`transferFrom` with pause-gated variants.
///         {ERC20PausableInit} registers IPausable (ERC-165) and grants `admin` the DEFAULT_ADMIN_ROLE. Both
///         inits run in one initializing window via {BaseDeploy._assembleMulti}.
contract DeployERC20Pausable is BaseDeploy {
    /// @notice Builds the pausable ERC-20 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name. @param symbol_ Token symbol. @param admin The pause/unpause authority.
    /// @return cuts The facet cuts (ERC165 + ERC20 + DiamondLoupeFacet [base] + Pausable [Add] + ERC20Pausable [Replace] + AccessControl + AccessControlDiamondCut).
    /// @return inits The initializers, run in order ({DeployERC20}'s {MultiInit} chain, {ERC20PausableInit}, then {DiamondIntrospectionInit.initUpgradeable}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory name_, string memory symbol_, address admin)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        (FacetCut[] memory baseCuts, address baseInit, bytes memory baseCalldata) =
            new DeployERC20().buildCuts(name_, symbol_);

        cuts = new FacetCut[](baseCuts.length + 4);
        for (uint256 i; i < baseCuts.length; ++i) {
            cuts[i] = baseCuts[i];
        }
        // Additive pause/unpause/paused control.
        cuts[baseCuts.length] = _cut(address(new Pausable()));
        // Override the base transfer/transferFrom with pause-gated variants.
        cuts[baseCuts.length + 1] = _replace(address(new ERC20Pausable()));
        // The pause/upgrade authority must be inspectable and rotatable on-chain: cut the role surface too.
        cuts[baseCuts.length + 2] = _cut(address(new AccessControl()));
        cuts[baseCuts.length + 3] = _cut(address(new AccessControlDiamondCut()));

        inits = new address[](3);
        inits[0] = baseInit;
        inits[1] = address(new ERC20PausableInit());
        inits[2] = address(new DiamondIntrospectionInit());

        initCalldatas = new bytes[](3);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC20PausableInit.init, (admin));
        // The base chain registered the loupe flag; the cut facet is live too — advertise both.
        initCalldatas[2] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    /// @notice Deploys a pausable ERC-20 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(string memory name_, string memory symbol_, address admin) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, admin);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }
}
