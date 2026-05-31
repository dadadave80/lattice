// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";
import {ITimelockController} from "@lattice/interfaces/ITimelockController.sol";

/// @title TimelockController
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/TimelockController.sol)
/// @notice A Diamond-compatible facet that schedules and executes governance actions after
///         a minimum delay. All state lives in ERC-7201 namespaced storage via
///         TimelockControllerLib; authentication uses AccessControlLib roles.
/// @dev This is a thin, stateless façade. Deploy it as a Diamond facet or inherit it
///      (together with AccessControl) in a standalone contract.
contract TimelockController is ITimelockController {
    //*//////////////////////////////////////////////////////////////////////////
    //                              ROLE CONSTANTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc ITimelockController
    function PROPOSER_ROLE() external pure returns (bytes32) {
        return TimelockControllerLib.PROPOSER_ROLE;
    }

    /// @inheritdoc ITimelockController
    function EXECUTOR_ROLE() external pure returns (bytes32) {
        return TimelockControllerLib.EXECUTOR_ROLE;
    }

    /// @inheritdoc ITimelockController
    function CANCELLER_ROLE() external pure returns (bytes32) {
        return TimelockControllerLib.CANCELLER_ROLE;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc ITimelockController
    function isOperation(bytes32 id) public view virtual returns (bool) {
        return TimelockControllerLib.isOperation(id);
    }

    /// @inheritdoc ITimelockController
    function isOperationPending(bytes32 id) public view virtual returns (bool) {
        return TimelockControllerLib.isOperationPending(id);
    }

    /// @inheritdoc ITimelockController
    function isOperationReady(bytes32 id) public view virtual returns (bool) {
        return TimelockControllerLib.isOperationReady(id);
    }

    /// @inheritdoc ITimelockController
    function isOperationDone(bytes32 id) public view virtual returns (bool) {
        return TimelockControllerLib.isOperationDone(id);
    }

    /// @inheritdoc ITimelockController
    function getOperationState(bytes32 id) public view virtual returns (ITimelockController.OperationState) {
        return TimelockControllerLib.getOperationState(id);
    }

    /// @inheritdoc ITimelockController
    function getTimestamp(bytes32 id) public view virtual returns (uint256) {
        return TimelockControllerLib.getTimestamp(id);
    }

    /// @inheritdoc ITimelockController
    function getMinDelay() public view virtual returns (uint256) {
        return TimelockControllerLib.getMinDelay();
    }

    /// @inheritdoc ITimelockController
    function hashOperation(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt)
        public
        pure
        virtual
        returns (bytes32)
    {
        return TimelockControllerLib.hashOperation(target, value, data, predecessor, salt);
    }

    /// @inheritdoc ITimelockController
    function hashOperationBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) public pure virtual returns (bytes32) {
        return TimelockControllerLib.hashOperationBatch(targets, values, payloads, predecessor, salt);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            MUTATING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc ITimelockController
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual {
        TimelockControllerLib.schedule(target, value, data, predecessor, salt, delay);
    }

    /// @inheritdoc ITimelockController
    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public virtual {
        TimelockControllerLib.scheduleBatch(targets, values, payloads, predecessor, salt, delay);
    }

    /// @inheritdoc ITimelockController
    function cancel(bytes32 id) public virtual {
        TimelockControllerLib.cancel(id);
    }

    /// @inheritdoc ITimelockController
    function execute(address target, uint256 value, bytes calldata payload, bytes32 predecessor, bytes32 salt)
        public
        payable
        virtual
    {
        TimelockControllerLib.execute(target, value, payload, predecessor, salt);
    }

    /// @inheritdoc ITimelockController
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) public payable virtual {
        TimelockControllerLib.executeBatch(targets, values, payloads, predecessor, salt);
    }

    /// @inheritdoc ITimelockController
    function updateDelay(uint256 newDelay) public virtual {
        TimelockControllerLib.updateDelay(newDelay);
    }
}
