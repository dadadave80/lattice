// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ITimelockController} from "@lattice/interfaces/ITimelockController.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.TimelockController")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant TIMELOCK_CONTROLLER_STORAGE_SLOT = 0x87f5daf40fea2daee0a93658693902d7cd9e07fa1a4f16f2e8eb4a4e9d433000;

/// @dev `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant TIMELOCK_ERC165_STORAGE_LOCATION = 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0xd826478e is `type(ITimelockController).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xd826478e), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ITIMELOCKCONTROLLER_SLOT =
    0xc0a085cd59634eff50a01907a25e03eb6a55bd6279462a3ac6a99ce44b9c2f08;

/// @notice Struct for storing TimelockController state.
/// @dev Implements the storage layout for operation timestamps and the minimum delay.
/// @custom:storage-location erc7201:lattice.storage.TimelockController
struct TimelockControllerStorage {
    mapping(bytes32 id => uint256 timestamp) _timestamps;
    uint256 _minDelay;
}

/// @title TimelockController Library
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin
/// @notice A library for scheduling and executing governance actions after a minimum delay.
/// @dev Implements the OZ v5 TimelockController pattern as a stateless library with ERC-7201 storage.
///      All authentication is performed via AccessControlLib roles that are expected to reside in
///      AccessControlLib's own storage slot.
library TimelockControllerLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                               CONSTANTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Role for proposers — `keccak256("PROPOSER_ROLE")`.
    bytes32 internal constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");

    /// @dev Role for executors — `keccak256("EXECUTOR_ROLE")`.
    bytes32 internal constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    /// @dev Role for cancellers — `keccak256("CANCELLER_ROLE")`.
    bytes32 internal constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

    /// @dev Sentinel timestamp value for executed operations.
    uint256 internal constant _DONE_TIMESTAMP = 1;

    //*//////////////////////////////////////////////////////////////////////////
    //                           STORAGE ACCESSOR
    //////////////////////////////////////////////////////////////////////////*//

    function timelockControllerStorage() internal pure returns (TimelockControllerStorage storage $) {
        assembly {
            $.slot := TIMELOCK_CONTROLLER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INTERFACE REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the ITimelockController interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ITIMELOCKCONTROLLER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the TimelockController module.
    /// @param minDelay The initial minimum delay for operations.
    /// @param proposers The addresses that will be granted PROPOSER_ROLE and CANCELLER_ROLE.
    /// @param executors The addresses that will be granted EXECUTOR_ROLE.
    ///                  Pass address(0) to make execution open to everyone.
    /// @param admin The address to grant DEFAULT_ADMIN_ROLE to. If zero, no admin is set.
    /// @dev Must be called inside the preInitializer/postInitializer window.
    ///      AccessControl must already be initialized before calling this function.
    function __TimelockController_init(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);

        TimelockControllerStorage storage $ = timelockControllerStorage();
        $._minDelay = minDelay;
        emit ITimelockController.MinDelayChange(0, minDelay);

        // Grant proposers PROPOSER_ROLE + CANCELLER_ROLE
        for (uint256 i = 0; i < proposers.length; ++i) {
            AccessControlLib._grantRole(PROPOSER_ROLE, proposers[i]);
            AccessControlLib._grantRole(CANCELLER_ROLE, proposers[i]);
        }

        // Grant executors EXECUTOR_ROLE (address(0) means open execution)
        for (uint256 i = 0; i < executors.length; ++i) {
            AccessControlLib._grantRole(EXECUTOR_ROLE, executors[i]);
        }

        // Optionally grant admin the DEFAULT_ADMIN_ROLE (may have been done in AccessControl init)
        // We do NOT re-grant here; AccessControl init is responsible for setting DEFAULT_ADMIN_ROLE.
        // This avoids double-granting when used with TimelockControllerStandalone.
        (admin); // suppress unused parameter warning

        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns whether an id corresponds to a registered operation.
    function isOperation(bytes32 id) internal view returns (bool) {
        return timelockControllerStorage()._timestamps[id] != 0;
    }

    /// @notice Returns whether an operation is pending (Waiting or Ready, but not Done).
    function isOperationPending(bytes32 id) internal view returns (bool) {
        uint256 ts = timelockControllerStorage()._timestamps[id];
        return ts > _DONE_TIMESTAMP;
    }

    /// @notice Returns whether an operation is ready for execution.
    function isOperationReady(bytes32 id) internal view returns (bool) {
        uint256 ts = timelockControllerStorage()._timestamps[id];
        return ts > _DONE_TIMESTAMP && ts <= block.timestamp;
    }

    /// @notice Returns whether an operation has been executed.
    function isOperationDone(bytes32 id) internal view returns (bool) {
        return timelockControllerStorage()._timestamps[id] == _DONE_TIMESTAMP;
    }

    /// @notice Returns the state of an operation.
    function getOperationState(bytes32 id) internal view returns (ITimelockController.OperationState) {
        uint256 ts = timelockControllerStorage()._timestamps[id];
        if (ts == 0) return ITimelockController.OperationState.Unset;
        if (ts == _DONE_TIMESTAMP) return ITimelockController.OperationState.Done;
        if (ts > block.timestamp) return ITimelockController.OperationState.Waiting;
        return ITimelockController.OperationState.Ready;
    }

    /// @notice Returns the timestamp at which an operation becomes ready.
    function getTimestamp(bytes32 id) internal view returns (uint256) {
        return timelockControllerStorage()._timestamps[id];
    }

    /// @notice Returns the minimum delay for operations.
    function getMinDelay() internal view returns (uint256) {
        return timelockControllerStorage()._minDelay;
    }

    /// @notice Returns the operation id for a single-call operation.
    function hashOperation(address target, uint256 value, bytes memory data, bytes32 predecessor, bytes32 salt)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(target, value, data, predecessor, salt));
    }

    /// @notice Returns the operation id for a batch operation.
    function hashOperationBatch(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        bytes32 predecessor,
        bytes32 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(targets, values, payloads, predecessor, salt));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            MUTATING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Schedule a single-call operation.
    function schedule(
        address target,
        uint256 value,
        bytes memory data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) internal {
        AccessControlLib.checkRole(PROPOSER_ROLE);
        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        _schedule(id, delay);
        emit ITimelockController.CallScheduled(id, 0, target, value, data, predecessor, delay);
        if (salt != bytes32(0)) {
            emit ITimelockController.CallSalt(id, salt);
        }
    }

    /// @notice Schedule a batch operation.
    function scheduleBatch(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) internal {
        AccessControlLib.checkRole(PROPOSER_ROLE);
        if (targets.length != values.length || targets.length != payloads.length) {
            revert ITimelockController.TimelockInvalidOperationLength(targets.length, payloads.length, values.length);
        }
        bytes32 id = hashOperationBatch(targets, values, payloads, predecessor, salt);
        _schedule(id, delay);
        for (uint256 i = 0; i < targets.length; ++i) {
            emit ITimelockController.CallScheduled(id, i, targets[i], values[i], payloads[i], predecessor, delay);
        }
        if (salt != bytes32(0)) {
            emit ITimelockController.CallSalt(id, salt);
        }
    }

    /// @notice Cancel a pending operation.
    function cancel(bytes32 id) internal {
        AccessControlLib.checkRole(CANCELLER_ROLE);
        if (!isOperationPending(id)) {
            revert ITimelockController.TimelockUnexpectedOperationState(
                id,
                _encodeStateBitmap(ITimelockController.OperationState.Waiting)
                    | _encodeStateBitmap(ITimelockController.OperationState.Ready)
            );
        }
        timelockControllerStorage()._timestamps[id] = 0;
        emit ITimelockController.Cancelled(id);
    }

    /// @notice Execute a single-call operation.
    function execute(address target, uint256 value, bytes memory payload, bytes32 predecessor, bytes32 salt) internal {
        _onlyRoleOrOpenRole(EXECUTOR_ROLE);
        bytes32 id = hashOperation(target, value, payload, predecessor, salt);
        _beforeCall(id, predecessor);
        _executeCall(id, 0, target, value, payload);
        _afterCall(id);
    }

    /// @notice Execute a batch operation.
    function executeBatch(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        bytes32 predecessor,
        bytes32 salt
    ) internal {
        _onlyRoleOrOpenRole(EXECUTOR_ROLE);
        if (targets.length != values.length || targets.length != payloads.length) {
            revert ITimelockController.TimelockInvalidOperationLength(targets.length, payloads.length, values.length);
        }
        bytes32 id = hashOperationBatch(targets, values, payloads, predecessor, salt);
        _beforeCall(id, predecessor);
        for (uint256 i = 0; i < targets.length; ++i) {
            _executeCall(id, i, targets[i], values[i], payloads[i]);
        }
        _afterCall(id);
    }

    /// @notice Update the minimum delay.
    /// @dev Only callable from the timelock contract itself.
    function updateDelay(uint256 newDelay) internal {
        address sender = ContextLib.msgSender();
        if (sender != address(this)) {
            revert ITimelockController.TimelockUnauthorizedCaller(sender);
        }
        TimelockControllerStorage storage $ = timelockControllerStorage();
        emit ITimelockController.MinDelayChange($._minDelay, newDelay);
        $._minDelay = newDelay;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Internal function to schedule a new operation.
    function _schedule(bytes32 id, uint256 delay) internal {
        if (isOperation(id)) {
            revert ITimelockController.TimelockUnexpectedOperationState(
                id, _encodeStateBitmap(ITimelockController.OperationState.Unset)
            );
        }
        uint256 minDelay = timelockControllerStorage()._minDelay;
        if (delay < minDelay) {
            revert ITimelockController.TimelockInsufficientDelay(delay, minDelay);
        }
        timelockControllerStorage()._timestamps[id] = block.timestamp + delay;
    }

    /// @dev Check that id is ready and predecessor (if any) is done. Reverts otherwise.
    function _beforeCall(bytes32 id, bytes32 predecessor) internal view {
        if (!isOperationReady(id)) {
            revert ITimelockController.TimelockUnexpectedOperationState(
                id, _encodeStateBitmap(ITimelockController.OperationState.Ready)
            );
        }
        if (predecessor != bytes32(0) && !isOperationDone(predecessor)) {
            revert ITimelockController.TimelockUnexecutedPredecessor(predecessor);
        }
    }

    /// @dev Mark operation as done.
    function _afterCall(bytes32 id) internal {
        timelockControllerStorage()._timestamps[id] = _DONE_TIMESTAMP;
    }

    /// @dev Execute a single low-level call and emit CallExecuted. Reverts on failure.
    function _executeCall(bytes32 id, uint256 index, address target, uint256 value, bytes memory data) internal {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = target.call{value: value}(data);
        if (!success) {
            // Bubble up revert data if present
            assembly ("memory-safe") {
                let returnDataSize := returndatasize()
                if returnDataSize {
                    let ptr := mload(0x40)
                    returndatacopy(ptr, 0, returnDataSize)
                    revert(ptr, returnDataSize)
                }
                revert(0, 0)
            }
        }
        emit ITimelockController.CallExecuted(id, index, target, value, data);
    }

    /// @dev Allow access if caller has the role OR if the role is granted to address(0) (open role).
    function _onlyRoleOrOpenRole(bytes32 role) internal view {
        if (!AccessControlLib.hasRole(role, address(0))) {
            AccessControlLib.checkRole(role);
        }
    }

    /// @dev Encode a single OperationState as a single-bit bitmap for use in error reporting.
    function _encodeStateBitmap(ITimelockController.OperationState state) internal pure returns (bytes32) {
        // forge-lint: disable-next-line(incorrect-shift)
        return bytes32(1 << uint8(state));
    }
}
