// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC7821ExecutorLib} from "@lattice/accounts/libraries/ERC7821ExecutorLib.sol";
import {IERC7821} from "@lattice/interfaces/external/IERC7821.sol";

/// @title ERC7821Executor
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice ERC-7821 minimal batch executor facet. Executes a batch of calls from the account, authorized for
///         the account itself, the configured ERC-4337 EntryPoint, or a `DEFAULT_ADMIN_ROLE` holder.
/// @dev Stateless delegator — logic lives in {ERC7821ExecutorLib}. Following the ERC-7821 reference, execution
///      is gated by authorization only (no reentrancy lock, which would block legitimate self-re-entrant
///      flows). An unauthorized caller may still execute a batch the owner signed off-chain via the opData
///      envelope (replay-protected by the account nonce).
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source ERC-7821
contract ERC7821Executor is IERC7821 {
    /// @inheritdoc IERC7821
    function execute(bytes32 mode, bytes calldata executionData) external payable virtual {
        ERC7821ExecutorLib.execute(mode, executionData);
    }

    /// @inheritdoc IERC7821
    function supportsExecutionMode(bytes32 mode) external view virtual returns (bool result) {
        return ERC7821ExecutorLib.supportsExecutionMode(mode);
    }
}
