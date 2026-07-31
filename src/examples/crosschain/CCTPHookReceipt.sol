// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {CCTPHookReceiptRenderer} from "@lattice/examples/crosschain/libraries/CCTPHookReceiptRenderer.sol";
import {ICCTPHookReceiver} from "@lattice/interfaces/crosschain/ICCTPHookReceiver.sol";
import {IERC721} from "@lattice/interfaces/tokens/IERC721.sol";
import {ERC721} from "@lattice/tokens/ERC721/ERC721.sol";
import {ERC721Lib} from "@lattice/tokens/ERC721/libraries/ERC721Lib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @title CCTPHookReceipt
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Uniswap v4 Periphery (https://github.com/Uniswap/v4-periphery)
/// @notice Position-style ERC-721 proof that Circle CCTP v2 delivered USDC through a Lattice hook.
/// @dev The receipt never custodies or controls USDC. Only the immutable CCTPHookExecutor may mint, and every
///      recorded transfer fact comes from the Circle-attested callback. The attacker-controlled payload is ignored.
///      The NFT is transferable, but `originalRecipient` remains the account that received the USDC.
contract CCTPHookReceipt is ERC721, ICCTPHookReceiver {
    struct Receipt {
        uint32 sourceDomain;
        bytes32 sender;
        address originalRecipient;
        uint256 amount;
        uint64 recordedAt;
    }

    address public immutable executor;
    uint256 public nextTokenId = 1;
    mapping(uint256 tokenId => Receipt receipt_) private _receipts;

    event ReceiptMinted(
        uint256 indexed tokenId,
        address indexed originalRecipient,
        uint32 indexed sourceDomain,
        bytes32 sender,
        uint256 amount,
        uint64 recordedAt
    );

    error CCTPHookReceipt__ZeroExecutor();
    error CCTPHookReceipt__NotExecutor();
    error CCTPHookReceipt__InvalidRecipient(bytes32 mintRecipient);

    constructor(address executor_) {
        if (executor_ == address(0)) revert CCTPHookReceipt__ZeroExecutor();
        executor = executor_;

        bytes32 slot = InitializableLib.preInitializer();
        ERC721Lib.__ERC721_init("Lattice CCTP Receipt", "LCR");
        InitializableLib.postInitializer(slot);
    }

    /// @notice Query ERC-165 support registered by the standalone ERC-721 initialization.
    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }

    /// @notice Return the immutable delivery facts for an existing receipt.
    function receipt(uint256 tokenId) external view returns (Receipt memory) {
        ERC721Lib.ownerOf(tokenId);
        return _receipts[tokenId];
    }

    /// @inheritdoc ICCTPHookReceiver
    function onCCTPHook(uint32 sourceDomain, bytes32 sender, bytes32 mintRecipient, uint256 amount, bytes calldata)
        external
    {
        if (msg.sender != executor) revert CCTPHookReceipt__NotExecutor();

        uint256 recipientWord = uint256(mintRecipient);
        if (recipientWord == 0 || recipientWord > type(uint160).max) {
            revert CCTPHookReceipt__InvalidRecipient(mintRecipient);
        }
        address originalRecipient = address(uint160(recipientWord));

        uint256 tokenId = nextTokenId++;
        uint64 recordedAt = uint64(block.timestamp);
        _receipts[tokenId] = Receipt({
            sourceDomain: sourceDomain,
            sender: sender,
            originalRecipient: originalRecipient,
            amount: amount,
            recordedAt: recordedAt
        });
        // Deliberately not `_safeMint`: receipt delivery must not depend on a contract recipient callback.
        ERC721Lib._mint(originalRecipient, tokenId);
        emit ReceiptMinted(tokenId, originalRecipient, sourceDomain, sender, amount, recordedAt);
    }

    /// @inheritdoc IERC721
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        ERC721Lib.ownerOf(tokenId);
        Receipt memory r = _receipts[tokenId];
        return CCTPHookReceiptRenderer.tokenURI(
            CCTPHookReceiptRenderer.RenderParams({
                tokenId: tokenId,
                sourceDomain: r.sourceDomain,
                sender: r.sender,
                originalRecipient: r.originalRecipient,
                amount: r.amount,
                recordedAt: r.recordedAt,
                destinationChainId: block.chainid
            })
        );
    }
}
