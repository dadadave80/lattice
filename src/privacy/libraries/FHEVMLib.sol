// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ebool, euint64, externalEuint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";
import {IACL} from "@lattice/interfaces/external/fhevm/IACL.sol";
import {IFHEVMExecutor} from "@lattice/interfaces/external/fhevm/IFHEVMExecutor.sol";
import {IKMSVerifier} from "@lattice/interfaces/external/fhevm/IKMSVerifier.sol";

/// @notice Addresses of the three host contracts of a Fully Homomorphic Encryption Virtual Machine (FHEVM)
///         coprocessor deployment, in the field order of Zama's own configuration struct.
/// @dev Carries no storage-location annotation: it is only the layout of the shared coprocessor slot,
///      {FHEVMLib.CONFIG_SLOT}.
struct CoprocessorConfig {
    address acl;
    address executor;
    address kmsVerifier;
}

/// @title FHEVMLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Zama FHEVM (https://github.com/zama-ai/fhevm) and OpenZeppelin Confidential Contracts FHESafeMath (https://github.com/OpenZeppelin/openzeppelin-confidential-contracts)
/// @notice Thin host library for confidential (FHEVM) tokens: the coprocessor configuration, the host members
///         a token needs, with the names and host calldata of Zama's `FHE` library 0.13.4, and the two
///         `FHESafeMath` helpers of OpenZeppelin Confidential Contracts 0.5.3.
/// @dev An uninitialized (zero) handle passed as an operand or as a granted value is replaced by a trivially
///      encrypted zero of its type, as in `FHE`; {isAllowed} passes it through unchanged. An initialized
///      handle is type-checked by the executor wherever `FHE` checks it.
library FHEVMLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                                 CONFIGURATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Zama's coprocessor configuration slot, `keccak256(abi.encode(uint256(keccak256("confidential.storage.config")) - 1)) & ~bytes32(uint256(0xff))`.
    ///      Sharing it keeps Zama's `FHE` library reading the addresses written here.
    bytes32 internal constant CONFIG_SLOT = 0x9e7b61f58c47dc699ac88507c4f5bb9f121c03808c5676a8078fe583e4649700;

    /// @notice The chain has no pinned coprocessor deployment.
    error FHEVMUnsupportedChain(uint256 chainId);

    /// @notice The slot already holds a coprocessor configuration that differs from this chain's pinned one.
    error FHEVMConflictingCoprocessor(address acl, address executor, address kmsVerifier);

    /// @dev Binds the coprocessor configuration to {CONFIG_SLOT}.
    function config() internal pure returns (CoprocessorConfig storage $) {
        bytes32 slot = CONFIG_SLOT;
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    /// @notice The pinned coprocessor addresses for `chainId`: Ethereum mainnet (1), Sepolia (11155111) and the
    ///         local test chain (31337). Chain 31337 is for local tests only.
    function hostsFor(uint256 chainId) internal pure returns (CoprocessorConfig memory) {
        if (chainId == 1) {
            return CoprocessorConfig({
                acl: 0xcA2E8f1F656CD25C01F05d0b243Ab1ecd4a8ffb6,
                executor: 0xD82385dADa1ae3E969447f20A3164F6213100e75,
                kmsVerifier: 0x77627828a55156b04Ac0DC0eb30467f1a552BB03
            });
        }
        if (chainId == 11155111) {
            return CoprocessorConfig({
                acl: 0xf0Ffdc93b7E186bC2f8CB3dAA75D86d1930A433D,
                executor: 0x92C920834Ec8941d2C77D188936E1f7A6f49c127,
                kmsVerifier: 0xbE0E383937d564D7FF0BC3b46c51f0bF8d5C311A
            });
        }
        if (chainId == 31337) {
            return CoprocessorConfig({
                acl: 0x50157CFfD6bBFA2DECe204a89ec419c23ef5755D,
                executor: 0xe3a9105a3a932253A70F126eb1E3b589C643dD24,
                kmsVerifier: 0x901F8942346f7AB3a01F6D7613119Bca447Bb030
            });
        }
        revert FHEVMUnsupportedChain(chainId);
    }

    /// @notice Writes the pinned configuration for `block.chainid` into {CONFIG_SLOT}.
    /// @dev An empty slot is written; an identical stored configuration is left untouched; anything else
    ///      reverts with {FHEVMConflictingCoprocessor} carrying the stored values.
    function setCoprocessorForChain() internal {
        CoprocessorConfig memory pinned = hostsFor(block.chainid);
        CoprocessorConfig storage $ = config();
        (address acl, address executor, address kmsVerifier) = ($.acl, $.executor, $.kmsVerifier);
        if (acl == address(0) && executor == address(0) && kmsVerifier == address(0)) {
            $.acl = pinned.acl;
            $.executor = pinned.executor;
            $.kmsVerifier = pinned.kmsVerifier;
        } else if (acl != pinned.acl || executor != pinned.executor || kmsVerifier != pinned.kmsVerifier) {
            revert FHEVMConflictingCoprocessor(acl, executor, kmsVerifier);
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  HOST MEMBERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Executor type ordinal of an encrypted boolean (`FheType.Bool`).
    uint8 internal constant TYPE_BOOL = 0;

    /// @dev Executor type ordinal of an encrypted 64-bit unsigned integer (`FheType.Uint64`).
    uint8 internal constant TYPE_UINT64 = 5;

    /// @notice An empty-proof external handle is not allowed to the caller.
    error SenderNotAllowedToUseHandle(bytes32 handle, address sender);

    /// @notice The Key Management Service (KMS) verifier rejected a public decryption proof.
    error InvalidKMSSignatures();

    /// @notice A public decryption of `handlesList` to `abiEncodedCleartexts` passed {checkSignatures}.
    event PublicDecryptionVerified(bytes32[] handlesList, bytes abiEncodedCleartexts);

    /// @notice Whether `v` is a non-zero handle.
    function isInitialized(euint64 v) internal pure returns (bool) {
        return euint64.unwrap(v) != 0;
    }

    /// @notice Whether `v` is a non-zero handle.
    function isInitialized(ebool v) internal pure returns (bool) {
        return ebool.unwrap(v) != 0;
    }

    /// @notice Trivially encrypts `value` as an `euint64`.
    function asEuint64(uint64 value) internal returns (euint64) {
        return euint64.wrap(IFHEVMExecutor(config().executor).trivialEncrypt(uint256(value), TYPE_UINT64));
    }

    /// @notice Trivially encrypts `value` as an `ebool`.
    function asEbool(bool value) internal returns (ebool) {
        return ebool.wrap(IFHEVMExecutor(config().executor).trivialEncrypt(value ? 1 : 0, TYPE_BOOL));
    }

    /// @notice Converts an external handle to an `euint64`.
    /// @dev With a proof, the executor verifies it for `msg.sender` and the result is transiently allowed to
    ///      `msg.sender`. With an empty proof, a zero handle becomes an encrypted zero and any other handle must
    ///      already be allowed to `msg.sender`, else {SenderNotAllowedToUseHandle}, and be an `euint64`.
    function fromExternal(externalEuint64 inputHandle, bytes memory inputProof) internal returns (euint64) {
        bytes32 handle = externalEuint64.unwrap(inputHandle);
        if (inputProof.length != 0) {
            CoprocessorConfig storage $ = config();
            bytes32 result = IFHEVMExecutor($.executor).verifyInput(handle, msg.sender, inputProof, TYPE_UINT64);
            IACL($.acl).allowTransient(result, msg.sender);
            return euint64.wrap(result);
        }
        if (handle == 0) {
            return asEuint64(0);
        }
        if (!IACL(config().acl).isAllowed(handle, msg.sender)) revert SenderNotAllowedToUseHandle(handle, msg.sender);
        IFHEVMExecutor(config().executor).checkHandleType(handle, TYPE_UINT64);
        return euint64.wrap(handle);
    }

    /// @notice Encrypted `a + b`, wrapping on overflow.
    function add(euint64 a, euint64 b) internal returns (euint64) {
        a = _validated(a);
        if (!isInitialized(b)) b = asEuint64(0);
        return euint64.wrap(IFHEVMExecutor(config().executor).fheAdd(euint64.unwrap(a), euint64.unwrap(b), 0x00));
    }

    /// @notice Encrypted `a - b`, wrapping on underflow.
    function sub(euint64 a, euint64 b) internal returns (euint64) {
        a = _validated(a);
        if (!isInitialized(b)) b = asEuint64(0);
        return euint64.wrap(IFHEVMExecutor(config().executor).fheSub(euint64.unwrap(a), euint64.unwrap(b), 0x00));
    }

    /// @notice Encrypted `a >= b`.
    function ge(euint64 a, euint64 b) internal returns (ebool) {
        a = _validated(a);
        if (!isInitialized(b)) b = asEuint64(0);
        return ebool.wrap(IFHEVMExecutor(config().executor).fheGe(euint64.unwrap(a), euint64.unwrap(b), 0x00));
    }

    /// @notice Encrypted `a == b` against the plaintext `b`.
    function eq(euint64 a, uint64 b) internal returns (ebool) {
        a = _validated(a);
        return ebool.wrap(IFHEVMExecutor(config().executor).fheEq(euint64.unwrap(a), bytes32(uint256(b)), 0x01));
    }

    /// @notice Encrypted `control ? a : b`. An uninitialized `control` is an encrypted `false`.
    function select(ebool control, euint64 a, euint64 b) internal returns (euint64) {
        if (!isInitialized(control)) control = asEbool(false);
        a = _validated(a);
        if (!isInitialized(b)) b = asEuint64(0);
        return euint64.wrap(
            IFHEVMExecutor(config().executor).fheIfThenElse(ebool.unwrap(control), euint64.unwrap(a), euint64.unwrap(b))
        );
    }

    /// @notice Whether `account` may use `value`. An initialized `value` must be an `euint64`.
    function isAllowed(euint64 value, address account) internal view returns (bool) {
        bytes32 handle = euint64.unwrap(value);
        if (handle != 0) IFHEVMExecutor(config().executor).checkHandleType(handle, TYPE_UINT64);
        return IACL(config().acl).isAllowed(handle, account);
    }

    /// @notice Whether `account` may use `value`. An initialized `value` must be an `ebool`.
    function isAllowed(ebool value, address account) internal view returns (bool) {
        bytes32 handle = ebool.unwrap(value);
        if (handle != 0) IFHEVMExecutor(config().executor).checkHandleType(handle, TYPE_BOOL);
        return IACL(config().acl).isAllowed(handle, account);
    }

    /// @notice Persistently allows `account` to use `value`; returns the granted handle.
    function allow(euint64 value, address account) internal returns (euint64) {
        value = _validated(value);
        IACL(config().acl).allow(euint64.unwrap(value), account);
        return value;
    }

    /// @notice Persistently allows this contract to use `value`; returns the granted handle.
    function allowThis(euint64 value) internal returns (euint64) {
        value = _validated(value);
        IACL(config().acl).allow(euint64.unwrap(value), address(this));
        return value;
    }

    /// @notice Allows `account` to use `value` for this transaction; returns the granted handle.
    function allowTransient(euint64 value, address account) internal returns (euint64) {
        value = _validated(value);
        IACL(config().acl).allowTransient(euint64.unwrap(value), account);
        return value;
    }

    /// @notice Marks `value` as publicly decryptable; returns the marked handle.
    function makePubliclyDecryptable(euint64 value) internal returns (euint64) {
        value = _validated(value);
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = euint64.unwrap(value);
        IACL(config().acl).allowForDecryption(handles);
        return value;
    }

    /// @notice Verifies a KMS public decryption proof of `handlesList` to `abiEncodedCleartexts`.
    /// @dev Reverts {InvalidKMSSignatures} when the verifier returns `false`; a proof signed for another digest
    ///      reverts in the verifier with `KMSInvalidSigner(address)`, bubbled unchanged.
    function checkSignatures(
        bytes32[] memory handlesList,
        bytes memory abiEncodedCleartexts,
        bytes memory decryptionProof
    ) internal {
        bool isVerified = IKMSVerifier(config().kmsVerifier)
            .verifyDecryptionEIP712KMSSignatures(handlesList, abiEncodedCleartexts, decryptionProof);
        if (!isVerified) revert InvalidKMSSignatures();
        emit PublicDecryptionVerified(handlesList, abiEncodedCleartexts);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   SAFE MATH
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Tries `oldValue + delta`: `success` is whether it did not overflow, and `updated` is the sum on
    ///         success or `oldValue` otherwise. An uninitialized `oldValue` returns `(true, delta)`.
    function tryIncrease(euint64 oldValue, euint64 delta) internal returns (ebool success, euint64 updated) {
        if (!isInitialized(oldValue)) {
            return (asEbool(true), delta);
        }
        euint64 newValue = add(oldValue, delta);
        success = ge(newValue, oldValue);
        updated = select(success, newValue, oldValue);
    }

    /// @notice Tries `oldValue - delta`: `success` is whether it did not underflow, and `updated` is the
    ///         difference on success or `oldValue` otherwise. An uninitialized `oldValue` returns
    ///         `(true, oldValue)` when `delta` is uninitialized too, else `(delta == 0, asEuint64(0))`.
    function tryDecrease(euint64 oldValue, euint64 delta) internal returns (ebool success, euint64 updated) {
        if (!isInitialized(oldValue)) {
            if (!isInitialized(delta)) {
                return (asEbool(true), oldValue);
            }
            return (eq(delta, 0), asEuint64(0));
        }
        success = ge(oldValue, delta);
        updated = select(success, sub(oldValue, delta), oldValue);
    }

    /// @dev `value` itself after the executor type-checks it as an `euint64`, or an encrypted zero if it is
    ///      uninitialized.
    function _validated(euint64 value) private returns (euint64) {
        if (!isInitialized(value)) return asEuint64(0);
        IFHEVMExecutor(config().executor).checkHandleType(euint64.unwrap(value), TYPE_UINT64);
        return value;
    }
}
