// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC2981} from "@lattice/tokens/ERC2981/ERC2981.sol";
import {ERC2981Init} from "@lattice/tokens/ERC2981/ERC2981Init.sol";
import {ERC721} from "@lattice/tokens/ERC721/ERC721.sol";
import {ERC721Init} from "@lattice/tokens/ERC721/ERC721Init.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC721Royalty
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-721 token with ERC-2981 royalties (the OpenZeppelin `ERC721Royalty`
///         equivalent): `ERC165Facet` + `ERC721` + `ERC2981` + `AccessControl`, seeded by {ERC721Init} and
///         {ERC2981Init} in one initializing window via {MultiInit} (see {BaseDeploy._assembleMulti}).
/// @dev OpenZeppelin v5.6.1's `ERC721Royalty` only merges `supportsInterface`, which the shared ERC-165 map does
///      here, and v5 no longer clears royalties on burn, so the two facets need no seam: every selector is
///      ADDed. `AccessControl` is included because every royalty setter is gated on `DEFAULT_ADMIN_ROLE`, which
///      {ERC2981Init} grants to `admin_`; `AccessControlDiamondCut` lets that admin upgrade the diamond, as in
///      {DeployERC2981} and {DeployERC721URIStorage}.
contract DeployERC721Royalty is BaseDeploy {
    /// @notice Builds the royalty ERC-721 diamond cuts + ordered initializers (no broadcast, no proxy).
    /// @param name_ Token name. @param symbol_ Token symbol. @param admin_ The royalty admin (DEFAULT_ADMIN_ROLE).
    /// @return cuts The facet cuts (ERC165 + ERC721 + ERC2981 + AccessControl + DiamondLoupeFacet +
    ///         AccessControlDiamondCut).
    /// @return inits The initializer contracts ({ERC721Init}, {ERC2981Init}, then
    ///         {DiamondIntrospectionInit.initUpgradeable}), run in order via {MultiInit}.
    /// @return initCalldatas The calldata for each initializer.
    function buildCuts(string memory name_, string memory symbol_, address admin_)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        cuts = new FacetCut[](6);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new ERC721()));
        cuts[2] = _cut(address(new ERC2981()));
        cuts[3] = _cut(address(new AccessControl()));
        cuts[4] = _cut(address(new DiamondLoupeFacet()));
        cuts[5] = _cut(address(new AccessControlDiamondCut()));

        inits = new address[](3);
        inits[0] = address(new ERC721Init());
        inits[1] = address(new ERC2981Init());
        inits[2] = address(new DiamondIntrospectionInit());

        initCalldatas = new bytes[](3);
        initCalldatas[0] = abi.encodeCall(ERC721Init.init, (name_, symbol_));
        initCalldatas[1] = abi.encodeCall(ERC2981Init.init, (admin_));
        initCalldatas[2] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    /// @notice Deploys a royalty ERC-721 token diamond (broadcasting entrypoint for `forge script`).
    /// @return token The deployed token diamond address.
    function run(string memory name_, string memory symbol_, address admin_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, admin_);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }
}
