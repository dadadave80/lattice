// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HederaResponseCodes} from "@lattice/interfaces/external/hedera/HederaResponseCodes.sol";
import {IHederaAccountService} from "@lattice/interfaces/external/hedera/IHederaAccountService.sol";

/// @title MockHederaAccountService
/// @notice `vm.etch`-able stand-in for the HAS system contract at 0x16a. A 65-byte blob is verified for real
///         (ecrecover against `account`, modelling an ECDSA-keyed Hedera account whose EVM alias IS the
///         recovered address); a 64-byte ED25519 blob is answered from a fixture table (ED25519 has no EVM
///         precompile); ANY other length REVERTS, exactly like the network's `INVALID_TRANSACTION_BODY`.
/// @dev Must not rely on constructor state: an etched contract starts with empty storage. Two reverts live
///      here and between them they prove {HASSignatureVerifierLib} never propagates a system-contract revert
///      into the signer seam: the length revert carries a 4-byte custom error, which the wrapper's
///      returndata-length guard alone already rejects, while the opt-in {forceRevert} variant carries an
///      `Error(string)` payload far longer than 32 bytes, so only the failed-call flag can reject that one.
///      `isAuthorizedRaw` returns a BARE `bool` (not a response code + bool) and `isAuthorized` returns
///      `(int64, bool)`, matching the vendored {IHederaAccountService} ABI. Both are `view` so the library's
///      `staticcall` succeeds.
contract MockHederaAccountService is IHederaAccountService {
    /// @dev The long-reason revert {forceRevert} arms, sized so the returndata clears 32 bytes.
    string constant FRAME_HALTED = "MockHederaAccountService: the system contract halted this frame";

    /// @notice ED25519 fixtures: `keccak256(account, messageHash, signature)` => authorized.
    mapping(bytes32 fixture => bool authorized) public ed25519Fixtures;

    /// @notice `isAuthorized` fixtures: `keccak256(account, message, signatureMap)` => authorized.
    mapping(bytes32 fixture => bool authorized) public signatureMapFixtures;

    /// @notice Armed by {forceRevert}: `isAuthorizedRaw` halts its frame instead of answering.
    bool public forcedRevert;

    /// @notice The signature blob is neither 65 bytes (ECDSA) nor 64 bytes (ED25519).
    error InvalidTransactionBody();

    /// @notice Arm (`on`) or disarm the frame-failure injector for `isAuthorizedRaw`.
    /// @dev Off by default, and sticky rather than one-shot — the revert rolls back any self-disarm.
    function forceRevert(bool on) external {
        forcedRevert = on;
    }

    /// @notice Seeds the ED25519 answer for one (account, messageHash, signature) triple.
    function setEd25519Authorized(address account, bytes32 hash, bytes calldata sig, bool ok) external {
        ed25519Fixtures[keccak256(abi.encode(account, hash, sig))] = ok;
    }

    /// @notice Seeds the protobuf-`SignatureMap` answer for one (account, message, signatureMap) triple.
    function setAuthorized(address account, bytes calldata message, bytes calldata signatureMap, bool ok) external {
        signatureMapFixtures[keccak256(abi.encode(account, message, signatureMap))] = ok;
    }

    /// @inheritdoc IHederaAccountService
    function isAuthorizedRaw(address account, bytes memory messageHash, bytes memory signature)
        external
        view
        returns (bool authorized)
    {
        require(!forcedRevert, FRAME_HALTED);
        bytes32 hash = abi.decode(messageHash, (bytes32)); // the caller always packs exactly 32 bytes
        if (signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            assembly ("memory-safe") {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }
            return ecrecover(hash, v, r, s) == account;
        }
        if (signature.length == 64) return ed25519Fixtures[keccak256(abi.encode(account, hash, signature))];
        revert InvalidTransactionBody();
    }

    /// @inheritdoc IHederaAccountService
    function isAuthorized(address account, bytes memory message, bytes memory signature)
        external
        view
        returns (int64 responseCode, bool authorized)
    {
        return (HederaResponseCodes.SUCCESS, signatureMapFixtures[keccak256(abi.encode(account, message, signature))]);
    }
}
