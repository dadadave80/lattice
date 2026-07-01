// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC721URIStorageLib} from "@lattice/tokens/ERC721/libraries/ERC721URIStorageLib.sol";

/// @title ERC721URIStorageInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ERC-721 per-token URI storage extension (EIP-4906). Registers the
///         ERC-4906 interface via ERC-165 and seeds the metadata admin who may call the facet's admin-gated
///         `setTokenURI`. Composed alongside {ERC721Init} in a single initializing window via {MultiInit}
///         (see {BaseDeploy._assembleMulti}) — it must NOT open its own pre/postInitializer; the
///         `__ERC721URIStorage_init` / `__AccessControl_init` guards pass because the window is already open.
/// @dev `setTokenURI` on the {ERC721URIStorage} facet is gated on `DEFAULT_ADMIN_ROLE`, so seeding that admin
///      is intrinsic to deploying a usable per-token-URI token — hence AccessControl is bootstrapped here.
contract ERC721URIStorageInit {
    function init(address admin_) external {
        ERC721URIStorageLib.__ERC721URIStorage_init();
        AccessControlLib.__AccessControl_init(admin_);
    }
}
