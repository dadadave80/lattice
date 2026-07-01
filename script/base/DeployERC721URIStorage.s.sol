// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ERC721Init} from "@lattice/tokens/ERC721/ERC721Init.sol";
import {ERC721URIStorage} from "@lattice/tokens/ERC721/ERC721URIStorage.sol";
import {ERC721URIStorageInit} from "@lattice/tokens/ERC721/ERC721URIStorageInit.sol";

/// @title DeployERC721URIStorage
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-721 diamond with per-token URI storage (EIP-4906):
///         `ERC165Facet` + `ERC721URIStorage` + `AccessControl`, seeded by {ERC721Init} + {ERC721URIStorageInit}
///         run together in one initializing window via {MultiInit} (see {BaseDeploy._assembleMulti}).
/// @dev The {ERC721URIStorage} facet INHERITS {ERC721} — its ABI already exposes every base ERC-721 selector
///      plus the `tokenURI` override and `setTokenURI`. Cutting it as the SOLE token facet (rather than
///      appending it on top of a base `ERC721` cut) is what keeps the diamond selector-conflict-free: an
///      "additive" append would collide on `name`/`ownerOf`/… which the extension re-declares via inheritance.
///      `AccessControl` is included because `setTokenURI` is gated on `DEFAULT_ADMIN_ROLE` (bootstrapped by
///      {ERC721URIStorageInit}), so a production deployment can manage that admin.
contract DeployERC721URIStorage is BaseDeploy {
    /// @notice Builds the URI-storage ERC-721 diamond cuts + ordered initializers (no broadcast, no proxy).
    /// @param name_ Token name. @param symbol_ Token symbol. @param admin_ The metadata admin (DEFAULT_ADMIN_ROLE).
    /// @return cuts The facet cuts (ERC165 + ERC721URIStorage + AccessControl).
    /// @return inits The initializer contracts, run in order via {MultiInit}.
    /// @return initCalldatas The calldata for each initializer.
    function buildCuts(string memory name_, string memory symbol_, address admin_)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new ERC721URIStorage()), "ERC721URIStorage");
        cuts[2] = _cut(address(new AccessControl()), "AccessControl");

        inits = new address[](2);
        inits[0] = address(new ERC721Init());
        inits[1] = address(new ERC721URIStorageInit());

        initCalldatas = new bytes[](2);
        initCalldatas[0] = abi.encodeCall(ERC721Init.init, (name_, symbol_));
        initCalldatas[1] = abi.encodeCall(ERC721URIStorageInit.init, (admin_));
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
