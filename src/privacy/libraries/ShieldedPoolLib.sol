// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IShieldedPool, IShieldedWithdrawVerifier} from "@lattice/interfaces/IShieldedPool.sol";
import {IncrementalMerkleTreeLib} from "@lattice/privacy/libraries/IncrementalMerkleTreeLib.sol";
import {NullifierRegistryLib} from "@lattice/privacy/libraries/NullifierRegistryLib.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ShieldedPool")) - 1)) & ~bytes32(uint256(0xff))`.
///      Verify with: `cast index-erc7201 "lattice.storage.ShieldedPool"`.
bytes32 constant SHIELDED_POOL_STORAGE_SLOT = 0xa961220e87963afb8adc0f7621a90ce1922bf3bb438109c43cc7dacbc8e06600;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant SHIELDED_POOL_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x8f5cc2c7 is `type(IShieldedPool).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x8f5cc2c7), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ISHIELDEDPOOL_SLOT = 0x584247a1f67e966ee8f18e29a93dbcead963401775336064ffc8d6a343c2a4df;

/// @notice A shielded pool's storage.
/// @dev APPEND-ONLY: new fields may only be added at the end.
struct ShieldedPool {
    IncrementalMerkleTreeLib.Tree commitments; // Poseidon LeanIMT of deposit commitments (+ root history)
    NullifierRegistryLib.Registry nullifiers; // spent withdrawal nullifier hashes
    address token; // the escrowed ERC-20
    uint256 denomination; // fixed deposit / withdraw amount
    address verifier; // the withdraw-circuit verifier
    bool exists;
}

/// @notice ERC-7201 namespaced storage for the ShieldedPool module.
/// @dev APPEND-ONLY: new fields may only be added at the end to preserve the upgrade-safe layout.
/// @custom:storage-location erc7201:lattice.storage.ShieldedPool
struct ShieldedPoolStorage {
    /// @dev pool id (1-based) => pool.
    mapping(uint256 poolId => ShieldedPool pool) _pools;
    /// @dev number of pools created.
    uint256 _poolCount;
}

/// @title ShieldedPoolLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library implementing fixed-denomination shielded (private) ERC-20 transfers (Tornado-style):
///         deposits insert `Poseidon(nullifier, secret)` commitments into a Poseidon LeanIMT; withdrawals
///         prove membership in zero knowledge and burn a one-time nullifier hash to an arbitrary recipient.
/// @dev Three-layer pattern: this library holds the logic + namespaced storage; the stateless
///      {ShieldedPool} facet forwards to it. The on-chain mechanics are wrapped from the shared
///      {IncrementalMerkleTreeLib} (Poseidon LeanIMT + recent-root ring) and {NullifierRegistryLib};
///      the withdraw circuit + verifier are consumer-supplied per pool. Withdrawals follow strict CEI:
///      the nullifier is spent BEFORE any token transfer, so a reentrant token cannot replay a spend.
library ShieldedPoolLib {
    using IncrementalMerkleTreeLib for IncrementalMerkleTreeLib.Tree;
    using NullifierRegistryLib for NullifierRegistryLib.Registry;

    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function shieldedPoolStorage() internal pure returns (ShieldedPoolStorage storage $) {
        assembly {
            $.slot := SHIELDED_POOL_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the ShieldedPool module.
    /// @dev Must be called inside a pre/postInitializer block. Registers IShieldedPool for ERC-165.
    function __ShieldedPool_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    /// @notice Registers support for the IShieldedPool interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ISHIELDEDPOOL_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  POOLS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Creates a fixed-denomination shielded pool. Gated on the default admin role.
    function createPool(address token, uint256 denomination, address verifier) internal returns (uint256 poolId) {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (token == address(0) || verifier == address(0) || denomination == 0) {
            revert IShieldedPool.ShieldedPoolInvalidConfig();
        }
        ShieldedPoolStorage storage $ = shieldedPoolStorage();
        poolId = ++$._poolCount;
        ShieldedPool storage p = $._pools[poolId];
        p.token = token;
        p.denomination = denomination;
        p.verifier = verifier;
        p.exists = true;
        emit IShieldedPool.PoolCreated(poolId, token, denomination, verifier);
    }

    /// @notice Deposits one denomination and inserts `commitment`.
    /// @dev Pulls `denomination` from `msg.sender` first, then inserts the leaf. Guarded against
    ///      reentrancy (the diamond-wide guard also blocks cross-entry reentry into {withdraw}).
    function deposit(uint256 poolId, uint256 commitment) internal {
        ReentrancyGuardLib.nonReentrantBefore();
        ShieldedPool storage p = shieldedPoolStorage()._pools[poolId];
        if (!p.exists) revert IShieldedPool.ShieldedPoolDoesNotExist();

        _safeTransferFrom(p.token, msg.sender, address(this), p.denomination);

        uint256 leafIndex = p.commitments.size();
        uint256 root = p.commitments.insert(commitment); // reverts on zero / duplicate / >= field
        emit IShieldedPool.Deposit(poolId, commitment, leafIndex, root);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Withdraws `denomination - fee` to `recipient` and `fee` to `relayer` against a proof.
    /// @dev Strict CEI: verify → spend nullifier → transfer. The proof's 5 public signals are
    ///      `[root, nullifierHash, recipient, relayer, fee]`, binding the destination + fee.
    function withdraw(
        uint256 poolId,
        IShieldedPool.WithdrawProof calldata proof,
        uint256 root,
        uint256 nullifierHash,
        address recipient,
        address relayer,
        uint256 fee
    ) internal {
        ReentrancyGuardLib.nonReentrantBefore();
        ShieldedPool storage p = shieldedPoolStorage()._pools[poolId];
        if (!p.exists) revert IShieldedPool.ShieldedPoolDoesNotExist();
        if (fee > p.denomination) revert IShieldedPool.ShieldedPoolFeeExceedsDenomination();
        if (!p.commitments.isKnownRoot(root)) revert IShieldedPool.ShieldedPoolUnknownRoot();
        if (p.nullifiers.isSpent(nullifierHash)) revert IShieldedPool.ShieldedPoolNullifierAlreadySpent();

        uint256[5] memory input = [root, nullifierHash, uint256(uint160(recipient)), uint256(uint160(relayer)), fee];
        if (!IShieldedWithdrawVerifier(p.verifier).verifyProof(proof.a, proof.b, proof.c, input)) {
            revert IShieldedPool.ShieldedPoolInvalidProof();
        }

        // Effects before interactions: burn the nullifier so a reentrant token cannot replay it.
        p.nullifiers.spend(nullifierHash);

        address token = p.token;
        unchecked {
            _safeTransfer(token, recipient, p.denomination - fee);
        }
        if (fee != 0) _safeTransfer(token, relayer, fee);

        emit IShieldedPool.Withdrawal(poolId, nullifierHash, recipient, relayer, fee);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 GETTERS
    //////////////////////////////////////////////////////////////////////////*//

    function poolCount() internal view returns (uint256) {
        return shieldedPoolStorage()._poolCount;
    }

    function getPool(uint256 poolId)
        internal
        view
        returns (address token, uint256 denomination, address verifier, uint256 merkleRoot, uint256 numLeaves)
    {
        ShieldedPool storage p = shieldedPoolStorage()._pools[poolId];
        if (!p.exists) revert IShieldedPool.ShieldedPoolDoesNotExist();
        return (p.token, p.denomination, p.verifier, p.commitments.root(), p.commitments.size());
    }

    function isSpent(uint256 poolId, uint256 nullifierHash) internal view returns (bool) {
        return shieldedPoolStorage()._pools[poolId].nullifiers.isSpent(nullifierHash);
    }

    function isKnownRoot(uint256 poolId, uint256 root) internal view returns (bool) {
        return shieldedPoolStorage()._pools[poolId].commitments.isKnownRoot(root);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            SAFE ERC-20 HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev `transferFrom` tolerating non-standard (no-return) ERC-20s; reverts on explicit failure.
    function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, amount)); // transferFrom(address,address,uint256)
        if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) {
            revert IShieldedPool.ShieldedPoolTransferFailed(token);
        }
    }

    /// @dev `transfer` tolerating non-standard (no-return) ERC-20s; reverts on explicit failure.
    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(0xa9059cbb, to, amount)); // transfer(address,uint256)
        if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) {
            revert IShieldedPool.ShieldedPoolTransferFailed(token);
        }
    }
}
