// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC721} from "@lattice/tokens/ERC721/ERC721.sol";
import {ERC721Init} from "@lattice/tokens/ERC721/ERC721Init.sol";
import {ERC721URIStorage} from "@lattice/tokens/ERC721/ERC721URIStorage.sol";
import {ERC721URIStorageInit} from "@lattice/tokens/ERC721/ERC721URIStorageInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC721URIStorage
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-721 diamond with per-token URI storage (EIP-4906):
///         `ERC165Facet` + `ERC721` + `ERC721URIStorage` + `AccessControl`, seeded by {ERC721Init} +
///         {ERC721URIStorageInit} run together in one initializing window via {MultiInit}
///         (see {BaseDeploy._assembleMulti}).
/// @dev Each facet owns ONLY its own selectors (the composability principle): the base `ERC721` facet exposes the
///      ERC-721 surface, and `ERC721URIStorage` is a MIXED cut over it — it REPLACEs `tokenURI` (per-token URI
///      storage) and ADDs `setTokenURI`. `AccessControl` is included because `setTokenURI` is gated on
///      `DEFAULT_ADMIN_ROLE` (bootstrapped by {ERC721URIStorageInit}), so a production deployment can manage that
///      admin.
contract DeployERC721URIStorage is BaseDeploy {
    /// @notice Builds the URI-storage ERC-721 diamond cuts + ordered initializers (no broadcast, no proxy).
    /// @param name_ Token name. @param symbol_ Token symbol. @param admin_ The metadata admin (DEFAULT_ADMIN_ROLE).
    /// @return cuts The facet cuts (ERC165 + ERC721 + ERC721URIStorage[Add setTokenURI, Replace tokenURI] +
    ///         AccessControl + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return inits The initializer contracts ({ERC721Init}, {ERC721URIStorageInit}, then
    ///         {DiamondIntrospectionInit.initUpgradeable}), run in order via {MultiInit}.
    /// @return initCalldatas The calldata for each initializer.
    function buildCuts(string memory name_, string memory symbol_, address admin_)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        address uriFacet = address(new ERC721URIStorage());

        cuts = new FacetCut[](7);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new ERC721()));
        // `setTokenURI` is new — ADD it; `tokenURI` already exists on the base ERC-721 facet — REPLACE it.
        cuts[2] = FacetCut({facetAddress: uriFacet, action: FacetCutAction.Add, functionSelectors: _setTokenURI()});
        cuts[3] = FacetCut({facetAddress: uriFacet, action: FacetCutAction.Replace, functionSelectors: _tokenURI()});
        cuts[4] = _cut(address(new AccessControl()));
        cuts[5] = _cut(address(new DiamondLoupeFacet()));
        cuts[6] = _cut(address(new AccessControlDiamondCut()));

        inits = new address[](3);
        inits[0] = address(new ERC721Init());
        inits[1] = address(new ERC721URIStorageInit());
        inits[2] = address(new DiamondIntrospectionInit());

        initCalldatas = new bytes[](3);
        initCalldatas[0] = abi.encodeCall(ERC721Init.init, (name_, symbol_));
        initCalldatas[1] = abi.encodeCall(ERC721URIStorageInit.init, (admin_));
        initCalldatas[2] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    /// @notice The single `setTokenURI` selector ADDed by the URI-storage facet.
    function _setTokenURI() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = ERC721URIStorage.setTokenURI.selector;
    }

    /// @notice The single `tokenURI` selector the URI-storage facet REPLACEs on the base ERC-721 facet.
    function _tokenURI() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = ERC721URIStorage.tokenURI.selector;
    }

    /// @notice Deploys a URI-storage ERC-721 token diamond (broadcasting entrypoint for `forge script`).
    /// @return token The deployed token diamond address.
    function run(string memory name_, string memory symbol_, address admin_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, admin_);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }
}
