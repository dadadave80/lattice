// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721VotesInit} from "@lattice/tokens/ERC721/ERC721VotesInit.sol";
import {ERC721ConsecutiveLib} from "@lattice/tokens/ERC721/libraries/ERC721ConsecutiveLib.sol";
import {ERC721Lib} from "@lattice/tokens/ERC721/libraries/ERC721Lib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @title ERC721SingleMintInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only init that single-mints through {ERC721Lib._mint} inside the window it runs in. In a
///         batch-minting diamond's first initialization neither order is safe: after {ERC721ConsecutiveInit} the
///         mint reverts `ERC721ForbiddenMint`, and before it a batch covering the id counts the token twice.
contract ERC721SingleMintInit {
    function init(address to, uint256 tokenId) external {
        ERC721Lib._mint(to, tokenId);
    }
}

/// @title ERC721BatchWithoutInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only app init that batch mints without {ERC721ConsecutiveLib.__ERC721Consecutive_init}. It must
///         revert `ERC721ForbiddenBatchMint` even inside the first initialization, or the batch would start at id 0
///         with the single-mint ban, the Enumerable and Votes guards and the first-id setting all off.
contract ERC721BatchWithoutInit {
    function init(address to, uint96 batchSize) external {
        ERC721ConsecutiveLib._mintConsecutive(to, batchSize);
    }
}

/// @title ERC721ConsecutiveReinit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only `_init` for an upgrade cut: opens a version-2 reinitializer window, the one an upgrade cut runs
///         in, and mints there. A batch must revert `ERC721ForbiddenBatchMint`; a single mint must succeed.
contract ERC721ConsecutiveReinit {
    function batch(address to, uint96 batchSize) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preReinitializer(s, 2);
        ERC721ConsecutiveLib._mintConsecutive(to, batchSize);
        InitializableLib.postReinitializer(s, 2);
    }

    /// @dev Runs `votesInit` ({ERC721VotesInit}) in the version-2 window, as an upgrade cut that adds votes would.
    function votes(address votesInit, string calldata name_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preReinitializer(s, 2);
        (bool ok, bytes memory ret) = votesInit.delegatecall(abi.encodeCall(ERC721VotesInit.init, (name_)));
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 0x20), mload(ret))
            }
        }
        InitializableLib.postReinitializer(s, 2);
    }

    function single(address to, uint256 tokenId) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preReinitializer(s, 2);
        ERC721Lib._mint(to, tokenId);
        InitializableLib.postReinitializer(s, 2);
    }
}
