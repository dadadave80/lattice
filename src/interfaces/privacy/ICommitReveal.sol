// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ICommitReveal
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice External interface for a generic commit–reveal primitive: hide a value behind a hash, then
///         reveal it later. A building block for sealed-bid auctions, commit–reveal voting, and MEV
///         mitigation. No ZK / circuits — plain keccak256 hashing.
/// @dev A commitment is `keccak256(abi.encode(committer, data, salt))`, binding the committer's address
///      into the hash. {reveal} recomputes the hash from `msg.sender`, so ONLY the bound committer can
///      reveal a given commitment — front-running the {commit} transaction does not let anyone else
///      reveal it. Each commitment can be revealed at most once. Commit and reveal should be in
///      different blocks for the hiding to be meaningful (the application enforces any timing using
///      {Commitment.committedAt}).
interface ICommitReveal {
    /// @notice Per-commitment record.
    /// @param committer   The account that submitted the {commit} transaction. Informational only —
    ///                    reveal authorization comes from the committer's address being bound into the
    ///                    commitment hash, NOT from this field (do not gate {reveal} on it).
    /// @param committedAt The block timestamp at which it was committed (0 == never committed).
    /// @param revealed    Whether it has been revealed.
    struct Commitment {
        address committer;
        uint64 committedAt;
        bool revealed;
    }

    /// @dev Thrown when committing the zero hash.
    error CommitRevealZeroCommitment();

    /// @dev Thrown when committing a hash that is already committed.
    /// @param commitment The already-committed hash.
    error CommitRevealAlreadyCommitted(bytes32 commitment);

    /// @dev Thrown when revealing a commitment that was never committed (or wrong data/salt/sender).
    /// @param commitment The recomputed hash that has no commitment.
    error CommitRevealNotCommitted(bytes32 commitment);

    /// @dev Thrown when revealing an already-revealed commitment.
    /// @param commitment The already-revealed hash.
    error CommitRevealAlreadyRevealed(bytes32 commitment);

    /// @dev Emitted on {commit}.
    /// @param commitment  The committed hash.
    /// @param committer   The account that committed.
    /// @param committedAt The commit block timestamp.
    event Committed(bytes32 indexed commitment, address indexed committer, uint64 committedAt);

    /// @dev Emitted on {reveal}, publishing the revealed data.
    /// @param commitment The revealed hash.
    /// @param committer  The account that revealed (the address bound into the hash).
    /// @param data       The revealed data.
    /// @param salt       The blinding salt.
    event Revealed(bytes32 indexed commitment, address indexed committer, bytes data, bytes32 salt);

    /// @notice Records a commitment hash. The hash should be `computeCommitment(msg.sender, data, salt)`.
    /// @param commitment The commitment hash to record.
    function commit(bytes32 commitment) external;

    /// @notice Reveals `data` + `salt` for a commitment previously made by `msg.sender`.
    /// @dev Recomputes `keccak256(abi.encode(msg.sender, data, salt))` and marks that commitment revealed.
    /// @param data The committed data.
    /// @param salt The blinding salt used in the commitment.
    function reveal(bytes calldata data, bytes32 salt) external;

    /// @notice Returns the record for `commitment`.
    /// @param commitment The commitment hash to query.
    /// @return The commitment record (zero `committedAt` if never committed).
    function commitmentInfo(bytes32 commitment) external view returns (Commitment memory);

    /// @notice Returns whether `commitment` has been revealed.
    /// @param commitment The commitment hash to query.
    function isRevealed(bytes32 commitment) external view returns (bool);

    /// @notice Computes the commitment hash for `(committer, data, salt)`.
    /// @dev `keccak256(abi.encode(committer, data, salt))`. Use off-chain (or in a consuming contract)
    ///      to build the {commit} hash consistently with {reveal}.
    /// @param committer The address to bind into the commitment.
    /// @param data The data to commit.
    /// @param salt The blinding salt.
    /// @return The commitment hash.
    function computeCommitment(address committer, bytes calldata data, bytes32 salt) external pure returns (bytes32);
}
