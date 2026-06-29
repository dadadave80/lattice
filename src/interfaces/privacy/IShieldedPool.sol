// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IShieldedWithdrawVerifier
/// @notice The verifier a shielded pool calls to check a withdrawal proof. A consumer deploys a Groth16
///         verifier for their audited withdraw circuit (whose 5 public signals are, in order,
///         `[root, nullifierHash, recipient, relayer, fee]`) and registers its address on the pool.
interface IShieldedWithdrawVerifier {
    /// @param a Groth16 proof point A.
    /// @param b Groth16 proof point B.
    /// @param c Groth16 proof point C.
    /// @param input The public signals `[root, nullifierHash, recipient, relayer, fee]`.
    /// @return True iff the proof is valid.
    function verifyProof(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[5] calldata input
    ) external view returns (bool);
}

/// @title IShieldedPool
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice External interface for fixed-denomination shielded (private) ERC-20 transfers. A depositor
///         inserts a commitment into a Poseidon incremental Merkle tree; later, anyone holding the
///         secret withdraws to an arbitrary recipient by proving, in zero knowledge, that their
///         commitment is in the tree — without revealing which — and publishing a one-time nullifier
///         hash that blocks double-spends.
/// @dev Tornado-style. The pool provides the on-chain mechanics (commitment tree + nullifier set +
///      fixed-denomination ERC-20 escrow); the WITHDRAW CIRCUIT + its verifier are supplied by the
///      consumer (set per pool), so the cryptography is wrapped, not hand-rolled. The circuit's 5 public
///      signals MUST be `[root, nullifierHash, recipient, relayer, fee]`; the commitment is
///      `Poseidon(nullifier, secret)`, the tree is the shared Poseidon LeanIMT, and `nullifierHash`
///      blocks reuse. SECURITY: this module escrows funds and must be deployed with an AUDITED circuit +
///      verifier and an honest trusted setup before any mainnet-with-funds use.
interface IShieldedPool {
    /// @notice A Groth16 withdrawal proof.
    struct WithdrawProof {
        uint256[2] a;
        uint256[2][2] b;
        uint256[2] c;
    }

    /// @dev Thrown when the pool id does not exist.
    error ShieldedPoolDoesNotExist();
    /// @dev Thrown when creating a pool with a zero token, zero verifier, or zero denomination.
    error ShieldedPoolInvalidConfig();
    /// @dev Thrown when the withdrawal root is not a known recent root of the pool.
    error ShieldedPoolUnknownRoot();
    /// @dev Thrown when the nullifier hash has already been spent.
    error ShieldedPoolNullifierAlreadySpent();
    /// @dev Thrown when the relayer fee exceeds the pool denomination.
    error ShieldedPoolFeeExceedsDenomination();
    /// @dev Thrown when the withdrawal proof does not verify.
    error ShieldedPoolInvalidProof();
    /// @dev Thrown when an ERC-20 transfer / transferFrom fails.
    /// @param token The token whose transfer failed.
    error ShieldedPoolTransferFailed(address token);

    /// @dev Emitted when a pool is created.
    event PoolCreated(uint256 indexed poolId, address indexed token, uint256 denomination, address indexed verifier);

    /// @dev Emitted on a deposit.
    /// @param poolId The pool.
    /// @param commitment The inserted commitment.
    /// @param leafIndex The commitment's leaf index.
    /// @param merkleRoot The new tree root.
    event Deposit(uint256 indexed poolId, uint256 indexed commitment, uint256 leafIndex, uint256 merkleRoot);

    /// @dev Emitted on a withdrawal.
    event Withdrawal(
        uint256 indexed poolId, uint256 indexed nullifierHash, address indexed recipient, address relayer, uint256 fee
    );

    /// @notice Creates a fixed-denomination shielded pool. Gated on the default admin role.
    /// @param token The ERC-20 token escrowed.
    /// @param denomination The fixed deposit/withdraw amount.
    /// @param verifier The withdraw-circuit verifier (see {IShieldedWithdrawVerifier}).
    /// @return poolId The new pool id (1-based).
    function createPool(address token, uint256 denomination, address verifier) external returns (uint256 poolId);

    /// @notice Deposits one `denomination` and inserts `commitment = Poseidon(nullifier, secret)`.
    /// @dev Pulls `denomination` of the pool token from `msg.sender` (requires prior approval).
    /// @param poolId The pool.
    /// @param commitment The commitment to insert.
    function deposit(uint256 poolId, uint256 commitment) external;

    /// @notice Withdraws `denomination - fee` to `recipient` and `fee` to `relayer`, against a proof.
    /// @param poolId The pool.
    /// @param proof The Groth16 withdrawal proof.
    /// @param root A known recent Merkle root the proof was built against.
    /// @param nullifierHash The one-time spend tag (blocks double-spends).
    /// @param recipient The withdrawal recipient.
    /// @param relayer The relayer paid `fee` (may be the recipient; `fee` may be 0).
    /// @param fee The relayer fee, `<= denomination`.
    function withdraw(
        uint256 poolId,
        WithdrawProof calldata proof,
        uint256 root,
        uint256 nullifierHash,
        address recipient,
        address relayer,
        uint256 fee
    ) external;

    /// @notice Returns the number of pools created.
    function poolCount() external view returns (uint256);

    /// @notice Returns pool config + state: token, denomination, verifier, current root, leaf count.
    function getPool(uint256 poolId)
        external
        view
        returns (address token, uint256 denomination, address verifier, uint256 merkleRoot, uint256 numLeaves);

    /// @notice Returns whether `nullifierHash` has been spent in `poolId`.
    function isSpent(uint256 poolId, uint256 nullifierHash) external view returns (bool);

    /// @notice Returns whether `root` is a known recent root of `poolId`.
    function isKnownRoot(uint256 poolId, uint256 root) external view returns (bool);
}
