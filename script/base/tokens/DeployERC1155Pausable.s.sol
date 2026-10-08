// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {DeployERC1155} from "@lattice-script/base/tokens/DeployERC1155.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {ERC1155BurnableInit} from "@lattice/tokens/ERC1155/ERC1155BurnableInit.sol";
import {ERC1155Pausable} from "@lattice/tokens/ERC1155/ERC1155Pausable.sol";
import {ERC1155PausableInit} from "@lattice/tokens/ERC1155/ERC1155PausableInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC1155Pausable
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a pausable, burnable ERC-1155 token diamond: the base {DeployERC1155} recipe
///         (ERC165 + ERC1155 + {ERC1155Init}), the {Pausable} facet (admin-gated `pause()`/`unpause()`), and the
///         {ERC1155Pausable} facet as a mixed cut — it REPLACES the base `safeTransferFrom`/`safeBatchTransferFrom`
///         with pause-gated variants and ADDS pause-gated `burn`/`burnBatch`. {ERC1155PausableInit} registers
///         IPausable and grants `admin` the DEFAULT_ADMIN_ROLE; {ERC1155BurnableInit} registers IERC1155Burnable,
///         since the burns are live. All inits run in one initializing window via {BaseDeploy._assembleMulti}.
/// @dev Upgradeable: `AccessControl` makes the pause authority inspectable and rotatable, and
///      `AccessControlDiamondCut` lets the same admin `diamondCut`. Under decision D25(a) on #234,
///      {ERC1155Pausable} is mutually exclusive with {ERC1155Burnable} and {ERC1155Supply}: do not add either here.
///      The recipe cuts no mint; the app's mint facet must call {ERC1155PausableLib._mint}/
///      {ERC1155PausableLib._mintBatch}, or mints ignore the pause. The `ERC1155Pausable` facet is the release
///      facet from {BaseDeploy._facet}; the other cuts and the inits still deploy fresh until every recipe moves to
///      release contracts (#195).
contract DeployERC1155Pausable is BaseDeploy {
    /// @notice Builds the pausable ERC-1155 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param uri_ Token URI template. @param admin The pause/unpause and upgrade authority.
    /// @return cuts The facet cuts (ERC165 + ERC1155 + DiamondLoupeFacet [base] + Pausable [Add] +
    ///         ERC1155Pausable [Replace transfers, Add burns] + AccessControl + AccessControlDiamondCut).
    /// @return inits The initializers, run in order ({DeployERC1155}'s {MultiInit} chain, {ERC1155PausableInit},
    ///         {ERC1155BurnableInit}, then {DiamondIntrospectionInit.initUpgradeable}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory uri_, address admin)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        (FacetCut[] memory baseCuts, address baseInit, bytes memory baseCalldata) = new DeployERC1155().buildCuts(uri_);
        address pausableFacet = _facet("ERC1155Pausable");

        cuts = new FacetCut[](baseCuts.length + 5);
        for (uint256 i; i < baseCuts.length; ++i) {
            cuts[i] = baseCuts[i];
        }
        // Additive pause/unpause/paused control.
        cuts[baseCuts.length] = _cut(address(new Pausable()));
        // The transfers already exist on the base ERC-1155 facet — REPLACE them; the burns are new — ADD them.
        cuts[baseCuts.length + 1] =
            FacetCut({facetAddress: pausableFacet, action: FacetCutAction.Replace, functionSelectors: _transfers()});
        cuts[baseCuts.length + 2] =
            FacetCut({facetAddress: pausableFacet, action: FacetCutAction.Add, functionSelectors: _burns()});
        // The pause/upgrade authority must be inspectable and rotatable on-chain: cut the role surface too.
        cuts[baseCuts.length + 3] = _cut(address(new AccessControl()));
        cuts[baseCuts.length + 4] = _cut(address(new AccessControlDiamondCut()));

        inits = new address[](4);
        inits[0] = baseInit;
        inits[1] = address(new ERC1155PausableInit());
        inits[2] = address(new ERC1155BurnableInit());
        inits[3] = address(new DiamondIntrospectionInit());

        initCalldatas = new bytes[](4);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC1155PausableInit.init, (admin));
        initCalldatas[2] = abi.encodeCall(ERC1155BurnableInit.init, ());
        // The base chain registered the loupe flag; the cut facet is live too — advertise both.
        initCalldatas[3] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    /// @notice The `safeTransferFrom`/`safeBatchTransferFrom` selectors the pausable facet REPLACEs on the base.
    function _transfers() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = ERC1155Pausable.safeTransferFrom.selector;
        s[1] = ERC1155Pausable.safeBatchTransferFrom.selector;
    }

    /// @notice The `burn`/`burnBatch` selectors the pausable facet ADDs.
    function _burns() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = ERC1155Pausable.burn.selector;
        s[1] = ERC1155Pausable.burnBatch.selector;
    }

    /// @notice Deploys a pausable ERC-1155 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(string memory uri_, address admin) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) = buildCuts(uri_, admin);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }
}
