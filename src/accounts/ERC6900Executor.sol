// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC6900ExecutorLib} from "@lattice/accounts/libraries/ERC6900ExecutorLib.sol";
import {Call} from "@lattice/interfaces/external/IERC6900.sol";

/// @title ERC6900Executor
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice ERC-6900 execution facet: the native `execute` / `executeBatch` (validation-gated, exec-hook-wrapped
///         calls to arbitrary targets) and the explicit-auth `executeWithRuntimeValidation`. Together with the
///         `ModularAccount6900` fallback (which dispatches installed execution-module selectors) this completes
///         the ERC-6900 execution surface of `IERC6900Account`.
/// @dev Stateless delegator — logic lives in {ERC6900ExecutorLib}; it reads the registries owned by
///      {ERC6900ModuleManagerLib}. Part of the ERC-6900 account blueprint (alternative to the ERC-7579 stack).
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source ERC-6900
contract ERC6900Executor {
    /// @notice Executes a single call to `target` with `value`, gated by the caller's runtime validation.
    function execute(address target, uint256 value, bytes calldata data)
        external
        payable
        virtual
        returns (bytes memory)
    {
        return ERC6900ExecutorLib.execute(target, value, data);
    }

    /// @notice Executes a batch of calls atomically (any sub-call revert reverts all).
    function executeBatch(Call[] calldata calls) external payable virtual returns (bytes[] memory) {
        return ERC6900ExecutorLib.executeBatch(calls);
    }

    /// @notice Runs the validation function named by `authorization` then self-dispatches `data`.
    function executeWithRuntimeValidation(bytes calldata data, bytes calldata authorization)
        external
        payable
        virtual
        returns (bytes memory)
    {
        return ERC6900ExecutorLib.executeWithRuntimeValidation(data, authorization);
    }
}
