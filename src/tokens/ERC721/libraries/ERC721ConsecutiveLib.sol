// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165_MAP_IVOTES_SLOT} from "@lattice/governance/libraries/VotesLib.sol";
import {IERC721} from "@lattice/interfaces/tokens/IERC721.sol";
import {IERC2309, IERC721Consecutive} from "@lattice/interfaces/tokens/IERC721Consecutive.sol";
import {IERC721Enumerable} from "@lattice/interfaces/tokens/IERC721Enumerable.sol";
import {ERC165_MAP_IERC721ENUMERABLE_SLOT} from "@lattice/tokens/ERC721/libraries/ERC721EnumerableLib.sol";
import {ERC721Lib} from "@lattice/tokens/ERC721/libraries/ERC721Lib.sol";
import {Checkpoints} from "@lattice/utils/libraries/Checkpoints.sol";
import {InitializableLib, InvalidInitialization} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC721Consecutive")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC721CONSECUTIVE_STORAGE_SLOT = 0xa366fb2bdee137bc7f716776578183d1280f09a256650bb770031cb75d936000;

/// @notice Storage struct for the ERC-721 batch-mint extension.
/// @dev The first three fields share one slot, so the base library's range check costs a single SLOAD.
/// @custom:storage-location erc7201:lattice.storage.ERC721Consecutive
struct ERC721ConsecutiveStorage {
    uint96 _firstConsecutiveId;
    uint96 _nextConsecutiveId;
    bool _enabled;
    Checkpoints.Trace160 _sequentialOwnership;
    mapping(uint256 bucket => uint256) _sequentialBurn;
}

/// @title ERC721ConsecutiveLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721Consecutive.sol)
/// @notice ERC-2309 batch minting for ERC-721, allowed only while the diamond runs its first initialization. A batch
///         records one ownership checkpoint and emits one {IERC2309.ConsecutiveTransfer} instead of a `Transfer` per
///         token.
/// @dev No facet and no selector: {ERC721ConsecutiveInit} mints the batches, and {ERC721Lib} reads the state below.
///      {ERC721Lib._ownerOf} falls back to {_sequentialOwnerOf} for an id with no stored owner, and
///      {ERC721Lib._update} calls {_checkSingleMint} on a mint and {_recordBurn} on a burn. Every transfer, mint or
///      burn path, base or extension, reaches those calls, so a batch-minted token moves like any other.
///      Differences from OpenZeppelin v5.6.1:
///      - OpenZeppelin allows a batch only while `address(this).code.length == 0`, i.e. in the constructor. A Lattice
///        diamond has code before {Lattice.initialize} runs, so the window here is the diamond's first
///        initialization: the initializing flag set and the initialized version 1. A `reinitializer` upgrade cut runs
///        at version 2 or later and cannot batch mint, which matches OpenZeppelin's "not in subsequent upgrades".
///        {LatticeFactory} creates and initializes a diamond in one transaction, so on that path the window is the
///        creation transaction.
///      - OpenZeppelin forbids single mints during construction through an `_update` override. Here the ban starts
///        when {__ERC721Consecutive_init} runs, so a single mint in an init that runs earlier in the same window is
///        not caught, and a batch covering its id counts that token twice. Never single-mint during a
///        batch-minting diamond's first initialization, in any init order: mint after {Lattice.initialize}
///        returns.
///      - `_firstConsecutiveId` and `_maxBatchSize` are virtual upstream. Here the first id is an init argument and
///        the batch limit is the constant {MAX_BATCH_SIZE} (OpenZeppelin's default, 5000).
///      - Batches end at id `2**96 - 2`: the stored next id must fit in a uint96. OpenZeppelin's last batch may end at
///        `2**96 - 1`.
///      - {ERC721Enumerable} cannot share a diamond with batch mints, as upstream: {_mintConsecutive} reverts
///        {IERC721Enumerable.ERC721EnumerableForbiddenBatchMint} when IERC721Enumerable is registered, and
///        {ERC721EnumerableLib.__ERC721Enumerable_init} reverts with it once this extension is initialized.
///      - OpenZeppelin's ERC721Votes moves batch-minted voting units through `_increaseBalance`. {ERC721VotesLib}
///        cannot see a batch, so the supply checkpoint would miss it. {_mintConsecutive} reverts
///        {IERC721Consecutive.ERC721VotesForbiddenBatchMint} when IVotes is registered, and {ERC721VotesInit}
///        reverts with it once this extension is initialized, so either order fails, upgrade cuts included.
library ERC721ConsecutiveLib {
    /// @notice The largest batch {_mintConsecutive} accepts, OpenZeppelin's default. Off-chain indexers record one
    ///         entry per token and may reject larger batches.
    uint96 internal constant MAX_BATCH_SIZE = 5000;

    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function erc721ConsecutiveStorage() internal pure returns (ERC721ConsecutiveStorage storage $) {
        assembly {
            $.slot := ERC721CONSECUTIVE_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Enables batch minting from `firstConsecutiveId`, and from now until the window closes forbids single
    ///         mints. A single mint earlier in the same window is not caught; never single-mint in this window.
    /// @dev Reverts {IERC721Consecutive.ERC721ForbiddenBatchMint} outside the diamond's first initialization, and
    ///      {InvalidInitialization} when called twice. Registers no ERC-165 id: the extension adds no function.
    function __ERC721Consecutive_init(uint96 firstConsecutiveId) internal {
        if (!_isFirstInitialization()) revert IERC721Consecutive.ERC721ForbiddenBatchMint();
        ERC721ConsecutiveStorage storage $ = erc721ConsecutiveStorage();
        if ($._enabled) revert InvalidInitialization();
        $._firstConsecutiveId = firstConsecutiveId;
        $._nextConsecutiveId = firstConsecutiveId;
        $._enabled = true;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               BATCH MINTING
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Mints `batchSize` consecutive tokens to `to` and returns the first id. A `batchSize` of 0 mints nothing
    ///         and returns the next id to be minted.
    /// @dev Emits {IERC2309.ConsecutiveTransfer}, not `Transfer`, and calls no `onERC721Received`. Reverts
    ///      {IERC721Consecutive.ERC721ForbiddenBatchMint} outside the first initialization or before
    ///      {__ERC721Consecutive_init}, {IERC721.ERC721InvalidReceiver} for a zero `to`,
    ///      {IERC721Consecutive.ERC721ExceededMaxBatchMint} above {MAX_BATCH_SIZE},
    ///      {IERC721Enumerable.ERC721EnumerableForbiddenBatchMint} on an enumerable diamond, and
    ///      {IERC721Consecutive.ERC721VotesForbiddenBatchMint} on a votes diamond.
    function _mintConsecutive(address to, uint96 batchSize) internal returns (uint96 next) {
        ERC721ConsecutiveStorage storage $ = erc721ConsecutiveStorage();
        next = $._nextConsecutiveId;

        if (batchSize > 0) {
            if (!$._enabled || !_isFirstInitialization()) revert IERC721Consecutive.ERC721ForbiddenBatchMint();
            if (to == address(0)) revert IERC721.ERC721InvalidReceiver(address(0));
            if (batchSize > MAX_BATCH_SIZE) {
                revert IERC721Consecutive.ERC721ExceededMaxBatchMint(batchSize, MAX_BATCH_SIZE);
            }
            if (_registered(ERC165_MAP_IERC721ENUMERABLE_SLOT)) {
                revert IERC721Enumerable.ERC721EnumerableForbiddenBatchMint();
            }
            if (_registered(ERC165_MAP_IVOTES_SLOT)) revert IERC721Consecutive.ERC721VotesForbiddenBatchMint();

            uint96 last = next + batchSize - 1;
            Checkpoints.push($._sequentialOwnership, last, uint160(to));
            $._nextConsecutiveId = last + 1;
            ERC721Lib._increaseBalance(to, batchSize);

            emit IERC2309.ConsecutiveTransfer(next, last, address(0), to);
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         BASE-LIBRARY CALLBACKS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The batch owner of `tokenId`, or zero when it is outside every batch or was burned.
    /// @dev {ERC721Lib._ownerOf} calls this only when `_owners[tokenId]` is zero, so a transferred batch token is
    ///      answered from `_owners` first. Off a batch-minting diamond the range is empty and this costs one SLOAD.
    function _sequentialOwnerOf(uint256 tokenId) internal view returns (address) {
        ERC721ConsecutiveStorage storage $ = erc721ConsecutiveStorage();
        if (tokenId < $._firstConsecutiveId || tokenId >= $._nextConsecutiveId) return address(0);
        if (_isBurned($, tokenId)) return address(0);
        // `tokenId < _nextConsecutiveId`, a uint96, so the cast is safe.
        return address(Checkpoints.lowerLookup($._sequentialOwnership, uint96(tokenId)));
    }

    /// @notice Reverts {IERC721Consecutive.ERC721ForbiddenMint} for a single mint during the first initialization of
    ///         a diamond that batch mints. {ERC721Lib._update} calls it on every mint.
    function _checkSingleMint() internal view {
        if (erc721ConsecutiveStorage()._enabled && _isFirstInitialization()) {
            revert IERC721Consecutive.ERC721ForbiddenMint();
        }
    }

    /// @notice Marks a burned batch id so {_sequentialOwnerOf} stops resolving it. {ERC721Lib._update} calls it on
    ///         every burn of an existing token.
    /// @dev The burned token may have left its batch owner before the burn. `_owners` then cleared to zero, and only
    ///      this bit stops the batch checkpoint from answering again.
    function _recordBurn(uint256 tokenId) internal {
        ERC721ConsecutiveStorage storage $ = erc721ConsecutiveStorage();
        if (tokenId < $._firstConsecutiveId || tokenId >= $._nextConsecutiveId) return;
        $._sequentialBurn[tokenId >> 8] |= 1 << (tokenId & 0xff);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Whether the diamond is in its first initialization: the initializing flag set at version 1.
    function _isFirstInitialization() private view returns (bool) {
        bytes32 s = InitializableLib.initializableSlot();
        return InitializableLib.isInitializing(s) && InitializableLib.getInitializedVersion(s) == 1;
    }

    /// @dev Whether the ERC-165 map entry at `mapSlot` is set. On an ERC-721 diamond, IVotes is registered only by
    ///      {ERC721VotesInit}.
    function _registered(bytes32 mapSlot) private view returns (bool registered) {
        assembly ("memory-safe") {
            registered := iszero(iszero(sload(mapSlot)))
        }
    }

    function _isBurned(ERC721ConsecutiveStorage storage $, uint256 tokenId) private view returns (bool) {
        return ($._sequentialBurn[tokenId >> 8] & (1 << (tokenId & 0xff))) != 0;
    }
}
