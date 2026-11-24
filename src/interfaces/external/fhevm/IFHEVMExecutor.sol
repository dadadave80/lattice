// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IFHEVMExecutor
/// @author Vendored minimal subset of Zama FHEVM (https://github.com/zama-ai/fhevm).
///         Upstream license: BSD-3-Clause-Clear.
/// @notice The calls {FHEVMLib} makes on the FHEVM (Fully Homomorphic Encryption Virtual Machine) host's
///         executor, which derives result handles for encrypted operations.
/// @dev `scalarByte` is `0x00` when `rhs` is a handle and `0x01` when it is a plaintext. Types are the
///      upstream `FheType` ordinals (`0` boolean, `5` 64-bit unsigned integer).
interface IFHEVMExecutor {
    /// @notice The executor's caller is not allowed on an operand handle.
    error ACLNotAllowed(bytes32 handle, address account);

    /// @notice A handle's encoded type does not match the expected type.
    error InvalidType();

    function fheAdd(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) external returns (bytes32);

    function fheSub(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) external returns (bytes32);

    function fheGe(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) external returns (bytes32);

    function fheEq(bytes32 lhs, bytes32 rhs, bytes1 scalarByte) external returns (bytes32);

    function fheIfThenElse(bytes32 control, bytes32 ifTrue, bytes32 ifFalse) external returns (bytes32);

    /// @notice Encrypts the plaintext `ct` as a handle of type `toType`, without a proof.
    function trivialEncrypt(uint256 ct, uint8 toType) external returns (bytes32);

    /// @notice Verifies an input proof for `inputHandle` bound to `callerAddress` and returns the usable handle.
    function verifyInput(bytes32 inputHandle, address callerAddress, bytes memory inputProof, uint8 inputType)
        external
        returns (bytes32);

    /// @notice Reverts with {InvalidType} if the initialized `handle` is not of `expectedType`.
    function checkHandleType(bytes32 handle, uint8 expectedType) external view;
}
