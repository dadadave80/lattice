// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC1155Burnable} from "@lattice/interfaces/tokens/IERC1155Burnable.sol";
import {ERC1155PausableLib} from "@lattice/tokens/ERC1155/libraries/ERC1155PausableLib.sol";

/// @title ERC1155Pausable
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC1155/extensions/ERC1155Pausable.sol)
/// @notice Stateless Diamond facet — ERC-1155 whose transfers and burns revert while the diamond is paused.
/// @dev Owns ONLY its own selectors: pause-gated `safeTransferFrom`/`safeBatchTransferFrom`, which REPLACE the
///      base {ERC1155} variants, and pause-gated `burn`/`burnBatch` with {ERC1155Burnable}'s signatures and
///      authorization. Under decision D25(a) on #234 the base {ERC1155Lib} has no hook, so every movement the pause
///      must stop is served here. That makes this facet MUTUALLY EXCLUSIVE with {ERC1155Burnable} and
///      {ERC1155Supply}, which export the same `burn`/`burnBatch` selectors: cut exactly one of the three. Mints
///      come from an app-specific facet, which must mint through {ERC1155PausableLib._mint}/
///      {ERC1155PausableLib._mintBatch}. To pause a token that cannot be burned, cut this facet without its
///      `burn`/`burnBatch` selectors. Reuses the shared {PausableLib} state (no new storage or ERC-165 id); the
///      diamond also cuts the {Pausable} facet for the admin-gated `pause()`/`unpause()`, as
///      {DeployERC1155Pausable} does. See {ERC1155PausableLib} for every difference from OpenZeppelin v5.6.1.
/// @custom:lattice-version 0.5.0
/// @custom:lattice-source OpenZeppelin v5.6.1
contract ERC1155Pausable is IERC1155Burnable {
    /// @notice Transfers `value` of token `id` from `from` to `to`, reverting with {IPausable-EnforcedPause} while
    ///         paused (replaces the base `safeTransferFrom`).
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data) public virtual {
        ERC1155PausableLib.safeTransferFrom(from, to, id, value, data);
    }

    /// @notice Batch transfers tokens, reverting with {IPausable-EnforcedPause} while paused (replaces the base
    ///         `safeBatchTransferFrom`).
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) public virtual {
        ERC1155PausableLib.safeBatchTransferFrom(from, to, ids, values, data);
    }

    /// @notice Destroys `value` tokens of type `id` from `account`, reverting with {IPausable-EnforcedPause} while
    ///         paused.
    /// @dev The caller must be `account` or an operator approved by `account`.
    function burn(address account, uint256 id, uint256 value) public virtual {
        ERC1155PausableLib.burn(account, id, value);
    }

    /// @notice Batched version of {burn}.
    /// @dev The caller must be `account` or an operator approved by `account`.
    function burnBatch(address account, uint256[] calldata ids, uint256[] calldata values) public virtual {
        ERC1155PausableLib.burnBatch(account, ids, values);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC1155Pausable methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `burn(address,uint256,uint256)` 0xf5298aca
    ///      `burnBatch(address,uint256[],uint256[])` 0x6b20c454
    ///      `safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)` 0x2eb2c2d6
    ///      `safeTransferFrom(address,address,uint256,uint256,bytes)` 0xf242432a
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"f5298aca6b20c4542eb2c2d6f242432a";
    }
}
