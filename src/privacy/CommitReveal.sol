// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ICommitReveal} from "@lattice/interfaces/ICommitReveal.sol";
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
}
