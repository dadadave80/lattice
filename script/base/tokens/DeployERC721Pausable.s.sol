// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {DeployERC721} from "@lattice-script/base/tokens/DeployERC721.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {ERC721PausableInit} from "@lattice/tokens/ERC721/ERC721PausableInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC721Pausable
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a pausable ERC-721 token diamond: the base {DeployERC721} recipe
///         (ERC165 + ERC721 + {ERC721Init}), the {Pausable} facet (admin-gated `pause()`/`unpause()`), and the
///         {ERC721Pausable} facet, which REPLACES the base `transferFrom` and both `safeTransferFrom` overloads with
///         pause-gated variants. {ERC721PausableInit} registers IPausable and grants `admin` the DEFAULT_ADMIN_ROLE.
///         All inits run in one initializing window via {BaseDeploy._assembleMulti}.
/// @dev Admin-only: the pause authority must exist, so there is no immutable overload. The pause gates only the
///      three replaced selectors; {ERC721Burnable} or {ERC721Wrapper} cut next to it still burn and wrap while paused.
///      The `ERC721Pausable` facet is the release facet from {BaseDeploy._facet}; the other cuts and the inits
///      still deploy fresh until every recipe moves to release contracts (#195).
contract DeployERC721Pausable is BaseDeploy {
    /// @notice Builds the pausable ERC-721 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name. @param symbol_ Token symbol. @param admin The pause/unpause and upgrade authority.
    /// @return cuts The facet cuts (ERC165 + ERC721 + DiamondLoupeFacet [base] + Pausable [Add] + ERC721Pausable
    ///         [Replace] + AccessControl + AccessControlDiamondCut).
    /// @return inits The initializers, run in order ({DeployERC721}'s {MultiInit} chain, {ERC721PausableInit}, then
    ///         {DiamondIntrospectionInit.initUpgradeable}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory name_, string memory symbol_, address admin)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        (FacetCut[] memory baseCuts, address baseInit, bytes memory baseCalldata) =
            new DeployERC721().buildCuts(name_, symbol_);

        cuts = new FacetCut[](baseCuts.length + 4);
        for (uint256 i; i < baseCuts.length; ++i) {
            cuts[i] = baseCuts[i];
        }
        // Additive pause/unpause/paused control.
        cuts[baseCuts.length] = _cut(address(new Pausable()));
        // Override the base transferFrom/safeTransferFrom with pause-gated variants.
        cuts[baseCuts.length + 1] = _replace(_facet("ERC721Pausable"));
        // The pause/upgrade authority must be inspectable and rotatable on-chain: cut the role surface too.
        cuts[baseCuts.length + 2] = _cut(address(new AccessControl()));
        cuts[baseCuts.length + 3] = _cut(address(new AccessControlDiamondCut()));

        inits = new address[](3);
        inits[0] = baseInit;
        inits[1] = address(new ERC721PausableInit());
        inits[2] = address(new DiamondIntrospectionInit());

        initCalldatas = new bytes[](3);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC721PausableInit.init, (admin));
        // The base chain registered the loupe flag; the cut facet is live too — advertise both.
        initCalldatas[2] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    /// @notice Deploys a pausable ERC-721 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(string memory name_, string memory symbol_, address admin) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, admin);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }
}
