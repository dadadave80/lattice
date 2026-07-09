// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAccount — ERC-4337 account interface + PackedUserOperation (v0.7+)
/// @author Vendored from OpenZeppelin Contracts `contracts/interfaces/draft-IERC4337.sol` (MIT) and the
///         ERC-4337 reference (eth-infinitism/account-abstraction). Re-authored to the standard ABI to avoid
///         a GPL dependency. Vendored subset — do not add an account-abstraction dependency.
/// @notice The account-side surface a smart account exposes to the ERC-4337 EntryPoint. `PackedUserOperation`
///         is the v0.7/v0.8 packed struct (NOT ABI-compatible with the v0.6 `UserOperation`).
/// @dev Canonical EntryPoints (the trusted `msg.sender` of `validateUserOp`): v0.7
///      `0x0000000071727De22E5E9d8BAf0edAc6f37da032`, v0.8 `0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108`
///      (native EIP-7702), v0.9 `0x433709009B8330FDa32311DF1C2AFA402eD8D009`. Which one is canonical is a
///      deployment choice — the account stores its EntryPoint rather than hardcoding it.

/// @dev The packed ERC-4337 v0.7+ user operation.
///      `accountGasLimits = verificationGasLimit (high 128) || callGasLimit (low 128)`.
///      `gasFees = maxPriorityFeePerGas (high 128) || maxFeePerGas (low 128)`.
struct PackedUserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;
    uint256 preVerificationGas;
    bytes32 gasFees;
    bytes paymasterAndData;
    bytes signature;
}

/// @dev ERC-4337 account interface.
interface IAccount {
    /// @notice Validates a user operation on behalf of the EntryPoint.
    /// @dev MUST be gated to `msg.sender == entryPoint`. MUST NOT revert on a signature mismatch — instead
    ///      return `validationData` with the low bit set (`SIG_VALIDATION_FAILED == 1`). If `missingAccountFunds`
    ///      is non-zero, the account MUST transfer at least that much to the EntryPoint (`msg.sender`).
    /// @param userOp The packed user operation.
    /// @param userOpHash The EntryPoint-computed hash the signature is over (already domain-bound).
    /// @param missingAccountFunds The prefund the account owes the EntryPoint for this op.
    /// @return validationData Packed `authorizer(160) || validUntil(48) || validAfter(48)`; `0` = valid,
    ///         `1` = signature failure.
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        returns (uint256 validationData);
}
