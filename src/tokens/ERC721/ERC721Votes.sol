// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721VotesLib} from "@lattice/tokens/ERC721/libraries/ERC721VotesLib.sol";

/// @title ERC721Votes
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721Votes.sol)
/// @notice Stateless Diamond facet giving ERC-721 holders ERC-5805 voting power, one unit per token. Pure delegator
///         to {ERC721VotesLib}.
/// @dev Owns only replacement selectors, so {DeployERC721Votes} cuts it with `Replace`: the unit-moving
///      `transferFrom` and both `safeTransferFrom` overloads replace the base {ERC721} ones, and the ERC-721-balance
///      `delegate`/`delegateBySig` replace the base {Votes} facet's ERC-20-balance versions. The rest of the voting
///      surface (`getVotes`, `getPastVotes`, `getPastTotalSupply`, `delegates`, `clock`, `CLOCK_MODE`) comes from
///      the {Votes} facet.
///      MUTUAL EXCLUSIONS (one ERC-721 movement override per diamond, D25):
///      - {ERC721Pausable} and {ERC721Enumerable} replace the same transfer selectors (pinned by
///        SelectorCompatibilityTest).
///      - {ERC721Burnable} and {ERC721Wrapper} mint and burn through {ERC721Lib}, which moves no voting units, so
///        neither may share a diamond with this facet (both pinned by CompositionHazardsTest). A mint, burn or
///        authorization-free transfer facet for a votes diamond calls {ERC721VotesLib} instead, never {ERC721Lib}.
///      - Batch mints ({ERC721ConsecutiveInit}) move no voting units, so the supply checkpoint would miss them;
///        either init order reverts `ERC721VotesForbiddenBatchMint` (pinned by CompositionHazardsTest).
/// @custom:lattice-version 0.5.0
/// @custom:lattice-source OpenZeppelin v5.6.1
contract ERC721Votes {
    /// @notice Transfers `tokenId` from `from` to `to` and moves its voting unit (replaces the base `transferFrom`).
    function transferFrom(address from, address to, uint256 tokenId) public virtual {
        // slither-disable-next-line arbitrary-send-erc20 ERC721VotesLib checks owner/approval first
        ERC721VotesLib.transferFrom(from, to, tokenId);
    }

    /// @notice Safely transfers `tokenId` and moves its voting unit (replaces the base `safeTransferFrom`).
    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual {
        ERC721VotesLib.safeTransferFrom(from, to, tokenId, "");
    }

    /// @notice Safely transfers `tokenId` with `data` and moves its voting unit (replaces the base
    ///         `safeTransferFrom`).
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) public virtual {
        ERC721VotesLib.safeTransferFrom(from, to, tokenId, data);
    }

    /// @notice Delegates the caller's votes to `delegatee` (replaces the base {Votes} variant).
    /// @dev Uses the caller's ERC-721 balance as voting units.
    function delegate(address delegatee) public virtual {
        ERC721VotesLib.delegate(delegatee);
    }

    /// @notice Delegates the signer's votes to `delegatee` by EIP-712 signature (replaces the base {Votes} variant).
    /// @dev Uses the signer's ERC-721 balance as voting units.
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        public
        virtual
    {
        ERC721VotesLib.delegateBySig(delegatee, nonce, expiry, v, r, s);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC721Votes methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `delegate(address)` 0x5c19a95c
    ///      `delegateBySig(address,uint256,uint256,uint8,bytes32,bytes32)` 0xc3cda520
    ///      `safeTransferFrom(address,address,uint256)` 0x42842e0e
    ///      `safeTransferFrom(address,address,uint256,bytes)` 0xb88d4fde
    ///      `transferFrom(address,address,uint256)` 0x23b872dd
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"5c19a95cc3cda52042842e0eb88d4fde23b872dd";
    }
}
