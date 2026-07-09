// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";
import {ITimelockController} from "@lattice/interfaces/governance/ITimelockController.sol";

/// @title TimelockController
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/TimelockController.sol)
/// @notice A Diamond-compatible facet that schedules and executes governance actions after
///         a minimum delay. All state lives in ERC-7201 namespaced storage via
///         TimelockControllerLib; authentication uses AccessControlLib roles.
/// @dev This is a thin, stateless façade. Deploy it as a Diamond facet or inherit it
///      (together with AccessControl) in a standalone contract.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect TimelockController methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `CANCELLER_ROLE()` 0xb08e51c0
    ///      `EXECUTOR_ROLE()` 0x07bd0265
    ///      `PROPOSER_ROLE()` 0x8f61f4f5
    ///      `cancel(bytes32)` 0xc4d252f5
    ///      `execute(address,uint256,bytes,bytes32,bytes32)` 0x134008d3
    ///      `executeBatch(address[],uint256[],bytes[],bytes32,bytes32)` 0xe38335e5
    ///      `getMinDelay()` 0xf27a0c92
    ///      `getOperationState(bytes32)` 0x7958004c
    ///      `getTimestamp(bytes32)` 0xd45c4435
    ///      `hashOperation(address,uint256,bytes,bytes32,bytes32)` 0x8065657f
    ///      `hashOperationBatch(address[],uint256[],bytes[],bytes32,bytes32)` 0xb1c5f427
    ///      `isOperation(bytes32)` 0x31d50750
    ///      `isOperationDone(bytes32)` 0x2ab0f529
    ///      `isOperationPending(bytes32)` 0x584b153e
    ///      `isOperationReady(bytes32)` 0x13bc9f20
    ///      `schedule(address,uint256,bytes,bytes32,bytes32,uint256)` 0x01d5062a
    ///      `scheduleBatch(address[],uint256[],bytes[],bytes32,bytes32,uint256)` 0x8f2a0bb0
    ///      `updateDelay(uint256)` 0x64d62353
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors =
            hex"b08e51c007bd02658f61f4f5c4d252f5134008d3e38335e5f27a0c927958004cd45c44358065657fb1c5f42731d507502ab0f529584b153e13bc9f2001d5062a8f2a0bb064d62353";
    }
}
