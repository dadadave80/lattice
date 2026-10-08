// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC1155} from "@lattice/tokens/ERC1155/ERC1155.sol";
import {ERC1155Init} from "@lattice/tokens/ERC1155/ERC1155Init.sol";
import {ERC1155URIStorage} from "@lattice/tokens/ERC1155/ERC1155URIStorage.sol";
import {ERC1155URIStorageInit} from "@lattice/tokens/ERC1155/ERC1155URIStorageInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC1155URIStorage
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-1155 diamond with per-token URI storage: `ERC165Facet` + `ERC1155` +
///         `ERC1155URIStorage` + `AccessControl`, seeded by {ERC1155Init} + {ERC1155URIStorageInit} run together
///         in one initializing window via {MultiInit} (see {BaseDeploy._assembleMulti}).
/// @dev Each facet owns ONLY its own selectors (the composability principle): the base `ERC1155` facet exposes the
///      ERC-1155 surface, and `ERC1155URIStorage` is a MIXED cut over it — it REPLACEs `uri(uint256)` (per-token
///      URI storage) and ADDs `setURI`/`setBaseURI`. `AccessControl` is included because both setters are gated
///      on `DEFAULT_ADMIN_ROLE` (bootstrapped by {ERC1155URIStorageInit}), so a production deployment can manage
///      that admin; `AccessControlDiamondCut` lets the same admin upgrade the diamond.
///      The `ERC1155URIStorage` facet is the release facet from {BaseDeploy._facet}; the other cuts and the inits
///      still deploy fresh until every recipe moves to release contracts (#195).
contract DeployERC1155URIStorage is BaseDeploy {
    /// @notice Builds the URI-storage ERC-1155 diamond cuts + ordered initializers (no broadcast, no proxy).
    /// @param uri_ The ERC-1155 URI template, served for ids without a per-token URI.
    /// @param admin_ The metadata admin (DEFAULT_ADMIN_ROLE).
    /// @return cuts The facet cuts (ERC165 + ERC1155 + ERC1155URIStorage[Add setters, Replace uri] +
    ///         AccessControl + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return inits The initializer contracts ({ERC1155Init}, {ERC1155URIStorageInit}, then
    ///         {DiamondIntrospectionInit.initUpgradeable}), run in order via {MultiInit}.
    /// @return initCalldatas The calldata for each initializer.
    function buildCuts(string memory uri_, address admin_)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        address uriFacet = _facet("ERC1155URIStorage");

        cuts = new FacetCut[](7);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new ERC1155()));
        // `setURI`/`setBaseURI` are new — ADD them; `uri` already exists on the base ERC-1155 facet — REPLACE it.
        cuts[2] = FacetCut({facetAddress: uriFacet, action: FacetCutAction.Add, functionSelectors: _setters()});
        cuts[3] = FacetCut({facetAddress: uriFacet, action: FacetCutAction.Replace, functionSelectors: _uri()});
        cuts[4] = _cut(address(new AccessControl()));
        cuts[5] = _cut(address(new DiamondLoupeFacet()));
        cuts[6] = _cut(address(new AccessControlDiamondCut()));

        inits = new address[](3);
        inits[0] = address(new ERC1155Init());
        inits[1] = address(new ERC1155URIStorageInit());
        inits[2] = address(new DiamondIntrospectionInit());

        initCalldatas = new bytes[](3);
        initCalldatas[0] = abi.encodeCall(ERC1155Init.init, (uri_));
        initCalldatas[1] = abi.encodeCall(ERC1155URIStorageInit.init, (admin_));
        initCalldatas[2] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    /// @notice The `setURI` and `setBaseURI` selectors ADDed by the URI-storage facet.
    function _setters() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = ERC1155URIStorage.setURI.selector;
        s[1] = ERC1155URIStorage.setBaseURI.selector;
    }

    /// @notice The single `uri` selector the URI-storage facet REPLACEs on the base ERC-1155 facet.
    function _uri() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = ERC1155URIStorage.uri.selector;
    }

    /// @notice Deploys a URI-storage ERC-1155 token diamond (broadcasting entrypoint for `forge script`).
    /// @return token The deployed token diamond address.
    function run(string memory uri_, address admin_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) = buildCuts(uri_, admin_);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }
}
