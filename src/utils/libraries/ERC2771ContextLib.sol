// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IERC2771Context} from "@lattice/interfaces/IERC2771Context.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC2771Context")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC2771_CONTEXT_STORAGE_SLOT = 0x8bfb6e7879de3cfcf53864e2a6757677ffa9fceefb124ac2a4e28b6fac171500;

/// @dev 0xf0ffe65a is `type(IERC2771Context).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xf0ffe65a), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC2771CONTEXT_SLOT = 0x0397519133c7f71c66962d7c0c1ca2679c0037f00141c5e2808db9f02a0831ec;

/// @custom:storage-location erc7201:lattice.storage.ERC2771Context
struct ERC2771ContextStorage {
    address _trustedForwarder;
}

/// @title ERC2771ContextLib
/// @notice Library implementing ERC-2771 meta-transaction context support.
///         Allows a trusted forwarder to relay calls on behalf of the original signer.
/// @dev The `msgSender()` and `msgData()` functions are utilities for consumers who want
///      meta-tx support. They are parallel utilities — not replacements for ContextLib.msgSender()
///      in other Lattice modules.
library ERC2771ContextLib {
    function erc2771ContextStorage() internal pure returns (ERC2771ContextStorage storage $) {
        assembly {
            $.slot := ERC2771_CONTEXT_STORAGE_SLOT
        }
    }

    /// @notice Initializes the ERC2771Context module.
    /// @param initialForwarder The initial trusted forwarder address (zero address disables forwarding).
    /// @dev Must be called between preInitializer / postInitializer. Emits TrustedForwarderUpdated
    ///      and registers the IERC2771Context interface.
    function __ERC2771Context_init(address initialForwarder) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        erc2771ContextStorage()._trustedForwarder = initialForwarder;
        emit IERC2771Context.TrustedForwarderUpdated(initialForwarder);
        registerInterface();
    }

    /// @notice Registers the IERC2771Context interface for ERC-165 discovery.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC2771CONTEXT_SLOT, true)
        }
    }

    // ---- Reads ----

    /// @notice Returns the current trusted forwarder address.
    function trustedForwarder() internal view returns (address) {
        return erc2771ContextStorage()._trustedForwarder;
    }

    /// @notice Returns whether the given address is the trusted forwarder.
    function isTrustedForwarder(address forwarder) internal view returns (bool) {
        return erc2771ContextStorage()._trustedForwarder == forwarder;
    }

    /// @notice Returns the effective sender of the call.
    /// @dev If msg.sender is the trusted forwarder and msg.data has at least 20 bytes,
    ///      reads the original sender from the last 20 bytes of calldata.
    ///      Otherwise returns msg.sender directly.
    function msgSender() internal view returns (address sender) {
        if (msg.sender == erc2771ContextStorage()._trustedForwarder && msg.data.length >= 20) {
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            sender = msg.sender;
        }
    }

    /// @notice Returns the effective calldata of the call.
    /// @dev If the call was forwarded by the trusted forwarder, strips the last 20 bytes
    ///      (the appended original sender). Otherwise returns msg.data as-is.
    function msgData() internal view returns (bytes calldata) {
        if (msg.sender == erc2771ContextStorage()._trustedForwarder && msg.data.length >= 20) {
            return msg.data[:msg.data.length - 20];
        } else {
            return msg.data;
        }
    }

    // ---- Mutations ----

    /// @notice Sets the trusted forwarder address.
    /// @param forwarder The new trusted forwarder (zero address disables forwarding).
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE. Emits TrustedForwarderUpdated.
    function setTrustedForwarder(address forwarder) internal {
        AccessControlLib.checkRole(bytes32(0));
        erc2771ContextStorage()._trustedForwarder = forwarder;
        emit IERC2771Context.TrustedForwarderUpdated(forwarder);
    }
}
