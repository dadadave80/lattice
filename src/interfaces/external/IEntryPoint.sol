// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

// Vendored minimal subset of the ERC-4337 EntryPoint (v0.7+) surface needed to submit and hash user
// operations from tests/tooling. Re-authored to the standard ABI to avoid a GPL account-abstraction
// dependency. `PackedUserOperation` is reused from the vendored IAccount. Do NOT add an account-abstraction
// dependency — extend this subset instead.

import {PackedUserOperation} from "@lattice/interfaces/external/IAccount.sol";

/// @title IEntryPoint — minimal ERC-4337 EntryPoint surface (v0.7/v0.8/v0.9 share this ABI)
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice The bundler/relayer-facing entrypoint that validates and executes user operations. Lattice
///         accounts trust ONE configured EntryPoint as the caller of `validateUserOp` (stored per account).
interface IEntryPoint {
    /// @notice Executes a batch of user operations, refunding gas to `beneficiary`.
    function handleOps(PackedUserOperation[] calldata ops, address payable beneficiary) external;

    /// @notice The next valid nonce for `sender` under the 192-bit `key` (sequential within a key).
    function getNonce(address sender, uint192 key) external view returns (uint256 nonce);

    /// @notice The EntryPoint-computed hash a user operation's signature must commit to.
    function getUserOpHash(PackedUserOperation calldata userOp) external view returns (bytes32);

    /// @notice Deposits ETH on behalf of `account` to prefund its future operations.
    function depositTo(address account) external payable;

    /// @notice The deposited balance available to `account` for prefunding.
    function balanceOf(address account) external view returns (uint256);
}
