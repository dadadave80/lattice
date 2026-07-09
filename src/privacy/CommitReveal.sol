// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ICommitReveal} from "@lattice/interfaces/privacy/ICommitReveal.sol";
import {CommitRevealLib} from "@lattice/privacy/libraries/CommitRevealLib.sol";

/// @title CommitReveal
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Stateless Diamond facet implementing a generic commit–reveal primitive — a building block
///         for sealed-bid auctions, commit–reveal voting, and MEV mitigation. No ZK / circuits.
/// @dev All logic lives in {CommitRevealLib}. Permissionless: anyone may commit and reveal their own.
///      The commitment binds the committer's address, so reveal is front-run-proof.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract CommitReveal is ICommitReveal {
    /// @inheritdoc ICommitReveal
    function commit(bytes32 commitment) external virtual {
        CommitRevealLib.commit(commitment);
    }

    /// @inheritdoc ICommitReveal
    function reveal(bytes calldata data, bytes32 salt) external virtual {
        CommitRevealLib.reveal(data, salt);
    }

    /// @inheritdoc ICommitReveal
    function commitmentInfo(bytes32 commitment) external view virtual returns (Commitment memory) {
        return CommitRevealLib.commitmentInfo(commitment);
    }

    /// @inheritdoc ICommitReveal
    function isRevealed(bytes32 commitment) external view virtual returns (bool) {
        return CommitRevealLib.isRevealed(commitment);
    }

    /// @inheritdoc ICommitReveal
    function computeCommitment(address committer, bytes calldata data, bytes32 salt)
        external
        pure
        virtual
        returns (bytes32)
    {
        return CommitRevealLib.computeCommitment(committer, data, salt);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect CommitReveal methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `commit(bytes32)` 0xf14fcbc8
    ///      `commitmentInfo(bytes32)` 0xfa3f7e8c
    ///      `computeCommitment(address,bytes,bytes32)` 0xc15f7d29
    ///      `isRevealed(bytes32)` 0xd321c77a
    ///      `reveal(bytes,bytes32)` 0xfa7fe7a0
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"f14fcbc8fa3f7e8cc15f7d29d321c77afa7fe7a0";
    }
}
