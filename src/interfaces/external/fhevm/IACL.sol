// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IACL
/// @author Vendored minimal subset of Zama FHEVM (https://github.com/zama-ai/fhevm).
///         Upstream license: BSD-3-Clause-Clear.
/// @notice The calls {FHEVMLib} makes on the FHEVM (Fully Homomorphic Encryption Virtual Machine) host's access
///         control list (ACL), which records which accounts may use each ciphertext handle.
interface IACL {
    /// @notice Persistently allows `account` to use `handle`. The caller must itself be allowed on `handle`.
    function allow(bytes32 handle, address account) external;

    /// @notice Allows `account` to use `handle` for the current transaction only.
    function allowTransient(bytes32 handle, address account) external;

    /// @notice Marks every handle in `handlesList` as publicly decryptable.
    function allowForDecryption(bytes32[] memory handlesList) external;

    /// @notice Whether `account` may use `handle`, through a transient or a persistent grant.
    function isAllowed(bytes32 handle, address account) external view returns (bool);
}
