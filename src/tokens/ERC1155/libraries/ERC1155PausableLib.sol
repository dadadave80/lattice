// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC1155} from "@lattice/interfaces/tokens/IERC1155.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {ERC1155Lib} from "@lattice/tokens/ERC1155/libraries/ERC1155Lib.sol";

/// @title ERC1155PausableLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC1155/extensions/ERC1155Pausable.sol)
/// @notice Library implementing ERC-1155 transfers, mints and burns that revert with {IPausable-EnforcedPause}
///         while the shared {PausableLib} state is paused. Adds no own storage and no ERC-165 id.
/// @dev OpenZeppelin v5.6.1 puts `whenNotPaused` on `_update`. Lattice's base {ERC1155Lib} has no hook (decision
///      D25(a) on #234), so this library carries its own transfer, mint and burn paths and checks the pause in
///      {_updateWithAcceptanceCheck}, right before {ERC1155Lib._update}. The authorization and zero-address checks
///      therefore still run first while paused, and the pause check runs before the array-length check, as in
///      OpenZeppelin. Differences from OpenZeppelin v5.6.1:
///      - Only movements that go through this library are gated. A facet that moves tokens through {ERC1155Lib}
///        directly ignores the pause: the base {ERC1155} transfers (which {ERC1155Pausable} replaces),
///        {ERC1155Burnable}'s and {ERC1155Supply}'s burns, and any mint facet that does not call {_mint}/{_mintBatch}.
///      - Burns are exported by the {ERC1155Pausable} facet (OpenZeppelin's live in `ERC1155Burnable`).
///      - `pause`/`unpause` come from the separately cut {Pausable} facet, gated on `DEFAULT_ADMIN_ROLE`.
library ERC1155PausableLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                           PAUSE-GATED OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice {ERC1155Lib.safeTransferFrom}, reverting while paused.
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes memory data) internal {
        ERC1155Lib._checkAuthorized(msg.sender, from);
        _checkTransferAddresses(from, to);
        _updateWithAcceptanceCheck(
            from, to, ERC1155Lib._asSingletonArray(id), ERC1155Lib._asSingletonArray(value), data, false
        );
    }

    /// @notice {ERC1155Lib.safeBatchTransferFrom}, reverting while paused.
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) internal {
        ERC1155Lib._checkAuthorized(msg.sender, from);
        _checkTransferAddresses(from, to);
        _updateWithAcceptanceCheck(from, to, ids, values, data, true);
    }

    /// @notice {ERC1155BurnableLib.burn}, reverting while paused.
    function burn(address account, uint256 id, uint256 value) internal {
        ERC1155Lib._checkAuthorized(msg.sender, account);
        _burn(account, id, value);
    }

    /// @notice {ERC1155BurnableLib.burnBatch}, reverting while paused.
    function burnBatch(address account, uint256[] memory ids, uint256[] memory values) internal {
        ERC1155Lib._checkAuthorized(msg.sender, account);
        _burnBatch(account, ids, values);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         PAUSE-GATED INTERNALS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice {ERC1155Lib._mint}, reverting while paused. A mint facet on a pausable diamond must call this.
    function _mint(address to, uint256 id, uint256 value, bytes memory data) internal {
        if (to == address(0)) revert IERC1155.ERC1155InvalidReceiver(address(0));
        _updateWithAcceptanceCheck(
            address(0), to, ERC1155Lib._asSingletonArray(id), ERC1155Lib._asSingletonArray(value), data, false
        );
    }

    /// @notice {ERC1155Lib._mintBatch}, reverting while paused.
    function _mintBatch(address to, uint256[] memory ids, uint256[] memory values, bytes memory data) internal {
        if (to == address(0)) revert IERC1155.ERC1155InvalidReceiver(address(0));
        _updateWithAcceptanceCheck(address(0), to, ids, values, data, true);
    }

    /// @notice {ERC1155Lib._burn}, reverting while paused.
    function _burn(address from, uint256 id, uint256 value) internal {
        if (from == address(0)) revert IERC1155.ERC1155InvalidSender(address(0));
        _updateWithAcceptanceCheck(
            from, address(0), ERC1155Lib._asSingletonArray(id), ERC1155Lib._asSingletonArray(value), "", false
        );
    }

    /// @notice {ERC1155Lib._burnBatch}, reverting while paused.
    function _burnBatch(address from, uint256[] memory ids, uint256[] memory values) internal {
        if (from == address(0)) revert IERC1155.ERC1155InvalidSender(address(0));
        _updateWithAcceptanceCheck(from, address(0), ids, values, "", true);
    }

    /// @notice Reverts with {IPausable-EnforcedPause} while paused, then runs
    ///         {ERC1155Lib._updateWithAcceptanceCheck}: the port of OpenZeppelin's `whenNotPaused` on `_update`.
    function _updateWithAcceptanceCheck(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data,
        bool batch
    ) internal {
        PausableLib.checkNotPaused();
        ERC1155Lib._updateWithAcceptanceCheck(from, to, ids, values, data, batch);
    }

    /// @dev The zero-address checks of {ERC1155Lib._safeTransferFrom}, in its order.
    function _checkTransferAddresses(address from, address to) private pure {
        if (to == address(0)) revert IERC1155.ERC1155InvalidReceiver(address(0));
        if (from == address(0)) revert IERC1155.ERC1155InvalidSender(address(0));
    }
}
