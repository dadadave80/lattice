// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC4337ValidationLib} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {SessionKeyLib} from "@lattice/accounts/libraries/SessionKeyLib.sol";
import {SignerECDSALib} from "@lattice/accounts/libraries/SignerECDSALib.sol";
import {IERC7821Executor} from "@lattice/interfaces/IERC7821Executor.sol";
import {Call} from "@lattice/interfaces/external/IERC7821.sol";
import {ECDSA} from "@lattice/utils/libraries/ECDSA.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev ERC-165 map slot for `IERC7821` (`type(IERC7821).interfaceId == 0x39922547`, the XOR of
///      `execute(bytes32,bytes)` ^ `supportsExecutionMode(bytes32)`; ERC-7821 defines no canonical id).
///      `keccak256(abi.encode(bytes4(0x39922547), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC7821_SLOT = 0x78c1401e50bfb6276de93dc8c11adfbefc06555e8af1f7964bc4c850cbbd171c;

/// @dev ERC-7821 mode ids. First byte `0x01` = batch; bytes [6:10) `0x78210001` mark the opData variant.
///      Only the first 10 bytes are significant (`_MODE_HEAD_MASK`); the trailing modePayload is ignored.
bytes32 constant _MODE_HEAD_MASK = 0xffffffffffffffffffff00000000000000000000000000000000000000000000;
bytes32 constant _BATCH_HEAD = 0x0100000000000000000000000000000000000000000000000000000000000000;
bytes32 constant _BATCH_OPDATA_HEAD = 0x0100000000007821000100000000000000000000000000000000000000000000;

/// @dev EIP-712 type hash for a relayer-submitted (signed-opData) batch authorization.
///      `keccak256("Execute(bytes32 mode,bytes32 callsHash,uint256 nonce)")`.
bytes32 constant EXECUTE_TYPEHASH = 0xb63526befbf5b966e64c36954eb12c5d09096e0b0a8a06e90bd0c857b842ebcb;

/// @title ERC7821ExecutorLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Logic for the ERC-7821 minimal batch executor facet. Stateless: authorization is derived from the
///         caller (self / configured EntryPoint / `DEFAULT_ADMIN_ROLE`) and the calls run from the account.
/// @dev Authorization is either direct (caller is self / EntryPoint / `DEFAULT_ADMIN_ROLE`) or, for the opData
///      mode, an EIP-712 `Execute` envelope `abi.encode(nonce, signature)` signed by the owner (full authority)
///      or by a registered, in-policy session key (see {SessionKeyLib}) — letting a relayer submit a batch
///      authorized off-chain, replay-protected via the shared {NoncesLib}. A failing inner call bubbles its
///      revert data.
library ERC7821ExecutorLib {
    /// @notice Registers the `IERC7821` ERC-165 id.
    function __ERC7821Executor_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for `IERC7821`.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC7821_SLOT, true)
        }
    }

    /// @notice Whether `mode` is a supported batch execution mode (with or without opData).
    function supportsExecutionMode(bytes32 mode) internal pure returns (bool) {
        bytes32 head = mode & _MODE_HEAD_MASK;
        return head == _BATCH_HEAD || head == _BATCH_OPDATA_HEAD;
    }

    /// @notice Executes a batch of calls per `mode`. Reverts {UnsupportedExecutionMode} on an unknown mode and
    ///         {UnauthorizedExecutor} if the caller is not self / the EntryPoint / an admin.
    function execute(bytes32 mode, bytes calldata executionData) internal {
        bytes32 head = mode & _MODE_HEAD_MASK;
        bool hasOpData;
        if (head == _BATCH_OPDATA_HEAD) hasOpData = true;
        else if (head != _BATCH_HEAD) revert IERC7821Executor.UnsupportedExecutionMode(mode);

        Call[] memory calls;
        bytes memory opData;
        if (hasOpData) (calls, opData) = abi.decode(executionData, (Call[], bytes));
        else calls = abi.decode(executionData, (Call[]));

        // Direct caller (self / EntryPoint / admin), or a signed opData envelope (owner or session key).
        if (!_isDirectlyAuthorized()) {
            if (!hasOpData || opData.length == 0) revert IERC7821Executor.UnauthorizedExecutor(msg.sender);
            _verifySignedOpData(mode, calls, opData);
        }

        uint256 n = calls.length;
        for (uint256 i; i < n; ++i) {
            Call memory c = calls[i];
            (bool ok, bytes memory ret) = c.target.call{value: c.value}(c.data);
            if (!ok) {
                assembly ("memory-safe") {
                    revert(add(ret, 0x20), mload(ret))
                }
            }
        }
        emit IERC7821Executor.BatchExecuted(mode, n);
    }

    /// @notice True if the caller is the account itself, the configured EntryPoint, or an admin.
    function _isDirectlyAuthorized() private view returns (bool) {
        return msg.sender == address(this) || msg.sender == ERC4337ValidationLib.entryPoint()
            || AccessControlLib.hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice Verifies a nonce-protected EIP-712 `Execute` authorization for this batch, then consumes the
    ///         account nonce. The owner signature grants full authority; otherwise the recovered ECDSA signer
    ///         must be a registered session key whose policy permits every call (see {SessionKeyLib}). Reverts
    ///         {UnauthorizedExecutor} on a bad signature, the session-key errors on a policy/validity failure,
    ///         and `InvalidAccountNonce` on replay / wrong nonce.
    function _verifySignedOpData(bytes32 mode, Call[] memory calls, bytes memory opData) private {
        (uint256 nonce, bytes memory signature) = abi.decode(opData, (uint256, bytes));
        bytes32 digest = EIP712Lib.hashTypedDataV4(
            keccak256(abi.encode(EXECUTE_TYPEHASH, mode, keccak256(abi.encode(calls)), nonce))
        );

        if (!SignerECDSALib.isValidSignatureNow(digest, signature)) {
            (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
            if (err != ECDSA.RecoverError.NoError) revert IERC7821Executor.UnauthorizedExecutor(msg.sender);
            SessionKeyLib.authorizeBatch(signer, calls);
        }
        NoncesLib.useCheckedNonce(address(this), nonce);
    }
}
