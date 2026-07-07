// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {ERC20Pausable} from "@lattice/tokens/ERC20/ERC20Pausable.sol";
import {ERC20PausableInit} from "@lattice/tokens/ERC20/ERC20PausableInit.sol";

/// @title DeployERC20Pausable
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a pausable ERC-20 token diamond: the base {DeployERC20} recipe
///         (ERC165 + ERC20 + {ERC20Init}), the {Pausable} facet (admin-gated `pause()`/`unpause()`), and the
///         {ERC20Pausable} facet which REPLACES the base `transfer`/`transferFrom` with pause-gated variants.
///         {ERC20PausableInit} seeds the shared Pausable state and grants `admin` the DEFAULT_ADMIN_ROLE. Both
///         inits run in one initializing window via {BaseDeploy._assembleMulti}.
contract DeployERC20Pausable is BaseDeploy {
    /// @notice Builds the pausable ERC-20 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name. @param symbol_ Token symbol. @param admin The pause/unpause authority.
    /// @return cuts The facet cuts (ERC165 + ERC20 + Pausable [Add] + ERC20Pausable [Replace]).
    /// @return inits The initializers, run in order ({ERC20Init} then {ERC20PausableInit}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory name_, string memory symbol_, address admin)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        (FacetCut[] memory baseCuts, address baseInit, bytes memory baseCalldata) =
            new DeployERC20().buildCuts(name_, symbol_);

        cuts = new FacetCut[](baseCuts.length + 2);
        for (uint256 i; i < baseCuts.length; ++i) {
            cuts[i] = baseCuts[i];
        }
        // Additive pause/unpause/paused control.
        cuts[baseCuts.length] = _cut(address(new Pausable()), "Pausable");
        // Override the base transfer/transferFrom with pause-gated variants.
        cuts[baseCuts.length + 1] = _replace(address(new ERC20Pausable()), "ERC20Pausable");

        inits = new address[](2);
        inits[0] = baseInit;
        inits[1] = address(new ERC20PausableInit());

        initCalldatas = new bytes[](2);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC20PausableInit.init, (admin));
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
