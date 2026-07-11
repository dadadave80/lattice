// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlInit} from "@lattice/access/AccessControlInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC20Permit} from "@lattice/tokens/ERC20/ERC20Permit.sol";
import {ERC20PermitInit} from "@lattice/tokens/ERC20/ERC20PermitInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC20Permit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a permit-enabled ERC-20 token diamond: the base {DeployERC20} recipe
///         (ERC165 + ERC20 + {ERC20Init}) plus the additive {ERC20Permit} facet (ERC-2612
///         `permit`/`nonces`/`DOMAIN_SEPARATOR`) and its {ERC20PermitInit} which seeds the EIP-712 domain + nonce
///         storage the permit digest reads. `buildCuts` is the broadcast-free primitive the permit facet test
///         reuses; `run` broadcasts. Both inits run in one initializing window via {BaseDeploy._assembleMulti}.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut (the inherited base recipe provides the
///      loupe); deploy a new diamond to change behavior. Use the ADMIN overload (`buildCuts(..., admin)` /
///      `run(..., admin)`) for an upgradeable deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployERC20Permit is BaseDeploy {
    /// @notice Builds the permit ERC-20 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name (also the EIP-712 domain name). @param symbol_ Token symbol.
    /// @return cuts The facet cuts (ERC165 + ERC20 + ERC20Permit).
    /// @return inits The initializers, run in order ({DeployERC20}'s {MultiInit} chain, then {ERC20PermitInit}).
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
        cuts[baseCuts.length] = _cut(address(new ERC20Permit()));

        inits = new address[](2);
        inits[0] = baseInit;
        inits[1] = address(new ERC20PermitInit());

        initCalldatas = new bytes[](2);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC20PermitInit.init, (name_));
    }

    /// @notice Deploys a permit ERC-20 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(string memory name_, string memory symbol_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) = buildCuts(name_, symbol_);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(string memory name_, string memory symbol_, address admin)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        (FacetCut[] memory defCuts, address[] memory defInits, bytes[] memory defCalldatas) = buildCuts(name_, symbol_);

        cuts = new FacetCut[](defCuts.length + 2);
        for (uint256 i; i < defCuts.length; ++i) {
            cuts[i] = defCuts[i];
        }
        cuts[defCuts.length] = _cut(address(new AccessControl()));
        cuts[defCuts.length + 1] = _cut(address(new AccessControlDiamondCut()));

        inits = new address[](defInits.length + 2);
        for (uint256 i; i < defInits.length; ++i) {
            inits[i] = defInits[i];
        }
        inits[defInits.length] = address(new AccessControlInit());
        inits[defInits.length + 1] = address(new DiamondIntrospectionInit());

        initCalldatas = new bytes[](defCalldatas.length + 2);
        for (uint256 i; i < defCalldatas.length; ++i) {
            initCalldatas[i] = defCalldatas[i];
        }
        initCalldatas[defCalldatas.length] = abi.encodeCall(AccessControlInit.init, (admin));
        // The base chain registered the loupe flag; the cut facet is live too — advertise both.
        initCalldatas[defCalldatas.length + 1] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(string memory name_, string memory symbol_, address admin) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, admin);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }
}
