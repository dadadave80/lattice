// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC1155URIStorageLib} from "@lattice/tokens/ERC1155/libraries/ERC1155URIStorageLib.sol";

/// @title ERC1155URIStorageInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ERC-1155 per-token URI storage extension. Registers IERC1155URIStorage
///         via ERC-165 and seeds the metadata admin who may call the facet's admin-gated `setURI`/`setBaseURI`.
///         Composed alongside {ERC1155Init} in a single initializing window via {MultiInit} (see
///         {BaseDeploy._assembleMulti}); it must NOT open its own pre/postInitializer.
/// @dev The setters on the {ERC1155URIStorage} facet are gated on `DEFAULT_ADMIN_ROLE`, so seeding that admin is
///      intrinsic to deploying a usable per-token-URI token — hence AccessControl is bootstrapped here.
/// @custom:lattice-kind bundle
contract ERC1155URIStorageInit {
    /// @custom:lattice-initializes ERC1155URIStorage;
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence ERC1155URIStorage;AccessControl;
    /// @custom:lattice-param admin_ authority;
    /// @custom:lattice-registers-interfaces
    function init(address admin_) external {
        ERC1155URIStorageLib.__ERC1155URIStorage_init();
        AccessControlLib.__AccessControl_init(admin_);
    }
}
