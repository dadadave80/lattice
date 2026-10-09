// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC721Consecutive} from "@lattice/interfaces/tokens/IERC721Consecutive.sol";
import {ERC721ConsecutiveLib} from "@lattice/tokens/ERC721/libraries/ERC721ConsecutiveLib.sol";

/// @title ERC721ConsecutiveInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for ERC-2309 batch minting: enables the extension from `firstId`, then mints
///         `amounts[i]` consecutive tokens to `receivers[i]` for each `i`, emitting one `ConsecutiveTransfer` per
///         non-empty batch. Delegatecalled by {Lattice.initialize} (through {MultiInit}) inside the diamond's first
///         initialization, after the base {ERC721Init}; it must NOT open its own pre/postInitializer. Never
///         single-mint in that window: after this init the mint reverts `ERC721ForbiddenMint`, and before it a batch
///         covering the id counts the token twice. Mint after `initialize` returns (see {ERC721ConsecutiveLib}).
contract ERC721ConsecutiveInit {
    function init(uint96 firstId, address[] calldata receivers, uint96[] calldata amounts) external {
        if (receivers.length != amounts.length) {
            revert IERC721Consecutive.ERC721ConsecutiveBatchLengthMismatch(receivers.length, amounts.length);
        }
        ERC721ConsecutiveLib.__ERC721Consecutive_init(firstId);
        for (uint256 i; i < receivers.length; ++i) {
            ERC721ConsecutiveLib._mintConsecutive(receivers[i], amounts[i]);
        }
    }
}
