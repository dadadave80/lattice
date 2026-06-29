// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IERC7802} from "@lattice/interfaces/external/IERC7802.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev 0x33331994 is `type(IERC7802).interfaceId` — the canonical ERC-7802 id (matches the standard;
///      the vendored {IERC7802} intentionally omits IERC165 so the derived id equals the canonical one).
/// `keccak256(abi.encode(bytes4(0x33331994), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC7802_SLOT = 0x8874437f0039021364a4853ff7e826b818ba7233f378ea008f000746be5d784a;

/// @dev Role authorized to crosschain-mint/burn. Granted to the trusted token bridge(s) (e.g. the host
///      Diamond of a {BridgeERC7802} facet). A holder can mint to, and burn from, ANY account — this is
///      the privileged ERC-7802 bridge operation, so grant it only to a vetted bridge.
bytes32 constant CROSSCHAIN_BRIDGE_ROLE = keccak256("CROSSCHAIN_BRIDGE_ROLE");

/// @title ERC7802Lib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Implements ERC-7802 (https://eips.ethereum.org/EIPS/eip-7802) over {ERC20Lib}.
/// @notice ERC-7802 crosschain mint/burn extension for the Lattice ERC-20. Adds no own storage (reuses the
///         ERC20 balances + the shared AccessControl roles); gives a {BridgeERC7802} a native token to bridge.
library ERC7802Lib {
    /// @notice Registers the IERC7802 ERC-165 interface. Must be called inside a pre/postInitializer block.
    function __ERC7802_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for IERC7802 (canonical id 0x33331994).
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC7802_SLOT, true)
        }
    }

    /// @notice Mint `amount` to `to` on this (destination) chain. Caller must hold CROSSCHAIN_BRIDGE_ROLE.
    function crosschainMint(address to, uint256 amount) internal {
        AccessControlLib.checkRole(CROSSCHAIN_BRIDGE_ROLE);
        ERC20Lib._mint(to, amount);
        emit IERC7802.CrosschainMint(to, amount, msg.sender);
    }

    /// @notice Burn `amount` from `from` on this (source) chain. Caller must hold CROSSCHAIN_BRIDGE_ROLE.
    /// @dev Privileged burn — no allowance is consumed (the bridge is trusted, per ERC-7802).
    function crosschainBurn(address from, uint256 amount) internal {
        AccessControlLib.checkRole(CROSSCHAIN_BRIDGE_ROLE);
        ERC20Lib._burn(from, amount);
        emit IERC7802.CrosschainBurn(from, amount, msg.sender);
    }
}
