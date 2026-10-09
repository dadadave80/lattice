// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC2309
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/interfaces/IERC2309.sol)
/// @notice ERC-2309: the ERC-721 Consecutive Transfer Extension event.
interface IERC2309 {
    /// @notice Emitted when the tokens from `fromTokenId` to `toTokenId` are transferred from `fromAddress` to
    ///         `toAddress`.
    event ConsecutiveTransfer(
        uint256 indexed fromTokenId, uint256 toTokenId, address indexed fromAddress, address indexed toAddress
    );
}

/// @title IERC721Consecutive
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721Consecutive.sol)
/// @notice Errors of the ERC-721 batch-mint extension, plus the {IERC2309} event. It declares no function, so its
///         interfaceId is `0x00000000` and nothing registers it for ERC-165.
/// @dev OpenZeppelin declares these errors on its `ERC721Consecutive` contract. Its `ERC721ForbiddenBatchBurn` is not
///      here: neither OpenZeppelin v5.6.1 nor Lattice has a batch-burn path that could raise it.
interface IERC721Consecutive is IERC2309 {
    /// @notice A batch mint ran outside the diamond's first initialization. ERC-721 lets a batch skip the per-token
    ///         `Transfer` events only during contract creation.
    error ERC721ForbiddenBatchMint();

    /// @notice A batch of `batchSize` tokens exceeds the `maxBatch` limit.
    error ERC721ExceededMaxBatchMint(uint256 batchSize, uint256 maxBatch);

    /// @notice A single-token mint ran during the first initialization of a diamond that batch mints.
    error ERC721ForbiddenMint();

    /// @notice Batch minting and ERC721Votes met on one diamond. A batch moves no voting units, so the supply
    ///         checkpoint would miss it. OpenZeppelin allows the pair; Lattice forbids it in either init order.
    error ERC721VotesForbiddenBatchMint();

    /// @notice The batch-mint initializer got `receivers` receivers but `amounts` batch sizes.
    error ERC721ConsecutiveBatchLengthMismatch(uint256 receivers, uint256 amounts);
}
