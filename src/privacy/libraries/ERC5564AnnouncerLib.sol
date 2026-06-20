// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IERC5564Announcer} from "@lattice/interfaces/IERC5564Announcer.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC5564ANNOUNCER_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x4d1f9583 is `type(IERC5564Announcer).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x4d1f9583), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC5564ANNOUNCER_SLOT = 0xa57260aa5166ddbfa7edd847f707bbf0762a8707401140e29b2073d6dfc88e2e;

/// @title ERC5564AnnouncerLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Conforms to ERC-5564 (https://eips.ethereum.org/EIPS/eip-5564)
/// @notice Library implementing the ERC-5564 stealth-address announcer.
/// @dev Stateless apart from one ERC-165 flag — `announce` only emits {IERC5564Announcer.Announcement}.
library ERC5564AnnouncerLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the ERC5564Announcer module.
    /// @dev Must be called inside a pre/postInitializer block. Registers IERC5564Announcer for ERC-165.
    function __ERC5564Announcer_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IERC5564Announcer interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC5564ANNOUNCER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ANNOUNCEMENT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Emits an {IERC5564Announcer.Announcement}; `caller` is forced to `msg.sender`.
    /// @param schemeId        The stealth-address scheme id.
    /// @param stealthAddress  The destination stealth address.
    /// @param ephemeralPubKey The sender's ephemeral public key.
    /// @param metadata        Scheme-specific metadata.
    function announce(uint256 schemeId, address stealthAddress, bytes calldata ephemeralPubKey, bytes calldata metadata)
        internal
    {
        emit IERC5564Announcer.Announcement(schemeId, stealthAddress, msg.sender, ephemeralPubKey, metadata);
    }
}
