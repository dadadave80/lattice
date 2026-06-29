// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC5564Announcer} from "@lattice/interfaces/privacy/IERC5564Announcer.sol";
import {ERC5564AnnouncerLib} from "@lattice/privacy/libraries/ERC5564AnnouncerLib.sol";

/// @title ERC5564Announcer
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Conforms to ERC-5564 (https://eips.ethereum.org/EIPS/eip-5564)
/// @notice Stateless Diamond facet implementing the ERC-5564 stealth-address announcer.
/// @dev All logic lives in {ERC5564AnnouncerLib}. Inherit this in your Diamond to let any account
///      broadcast stealth payments via {announce}. Permissionless by design — no access control.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract ERC5564Announcer is IERC5564Announcer {
    /// @inheritdoc IERC5564Announcer
    function announce(uint256 schemeId, address stealthAddress, bytes calldata ephemeralPubKey, bytes calldata metadata)
        external
        virtual
    {
        ERC5564AnnouncerLib.announce(schemeId, stealthAddress, ephemeralPubKey, metadata);
    }
}
