// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC2771ContextLib} from "@lattice/utils/libraries/ERC2771ContextLib.sol";
import {IERC2771Context} from "@lattice/interfaces/IERC2771Context.sol";

/// @title ERC2771Context
/// @notice Diamond facet exposing ERC-2771 trusted forwarder management.
/// @dev Thin delegator to ERC2771ContextLib. All logic lives in the library.
contract ERC2771Context is IERC2771Context {
    /// @inheritdoc IERC2771Context
    function isTrustedForwarder(address forwarder) external view virtual override returns (bool) {
        return ERC2771ContextLib.isTrustedForwarder(forwarder);
    }

    /// @inheritdoc IERC2771Context
    function trustedForwarder() external view virtual override returns (address) {
        return ERC2771ContextLib.trustedForwarder();
    }

    /// @inheritdoc IERC2771Context
    function setTrustedForwarder(address forwarder) external virtual override {
        ERC2771ContextLib.setTrustedForwarder(forwarder);
    }
}
