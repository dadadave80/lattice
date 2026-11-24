// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {euint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";
import {FHEVMLib} from "@lattice/privacy/libraries/FHEVMLib.sol";
import {ERC7984Lib} from "@lattice/tokens/ERC7984/libraries/ERC7984Lib.sol";

/// @title ERC7984TestFacet
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only facet cut next to the ERC-7984 (confidential fungible token) facet: a plaintext mint to seed
///         balances, and a self-call relay that makes the diamond call itself. Never shipped.
contract ERC7984TestFacet {
    /// @notice Mints a trivially encrypted `amount` to `to` through {ERC7984Lib._mint}.
    function mint(address to, uint64 amount) external returns (euint64) {
        return ERC7984Lib._mint(to, FHEVMLib.asEuint64(amount));
    }

    /// @notice Calls the diamond with `data` as the diamond itself, bubbling any revert unchanged.
    function selfCall(bytes calldata data) external returns (bytes memory result) {
        bool ok;
        (ok, result) = address(this).call(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(result, 0x20), mload(result))
            }
        }
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Chunks:
    ///      `mint(address,uint64)` 0x2893c5b0
    ///      `selfCall(bytes)` 0xa4a107ad
    function exportSelectors() external pure returns (bytes memory selectors) {
        selectors = hex"2893c5b0a4a107ad";
    }
}
