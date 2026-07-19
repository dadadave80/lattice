// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {TimelockController} from "@lattice/governance/TimelockController.sol";
import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @title TimelockControllerStandalone
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/TimelockController.sol)
/// @notice Non-Diamond deployable variant. Inherits all logic from {TimelockController} and
///         {AccessControl}; runs the pre/init/post initializer dance in the constructor.
/// @dev Consumers who need a Diamond-proxy deployment should use {TimelockController} as a
///      facet and call initializers separately.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract TimelockControllerStandalone is TimelockController, AccessControl {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(TimelockController, AccessControl)
        returns (bytes memory)
    {}

    /// @param minDelay The initial minimum delay for operations.
    /// @param proposers The addresses to grant PROPOSER_ROLE + CANCELLER_ROLE.
    /// @param executors The addresses to grant EXECUTOR_ROLE.
    ///                  Pass address(0) in the array to allow open execution.
    /// @param admin The address to grant DEFAULT_ADMIN_ROLE to.
    ///              Pass address(0) to leave administration to the timelock itself only.
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin) {
        bytes32 s = InitializableLib.initializableSlot();
        s = InitializableLib.preInitializer(s);
        // Only grant DEFAULT_ADMIN_ROLE to a non-zero admin; a zero admin means
        // "self-administered only" — address(this) receives the role unconditionally
        // inside __TimelockController_init.
        if (admin != address(0)) {
            AccessControlLib.__AccessControl_init(admin);
        } else {
            // Still satisfy AccessControl's checkInitializing requirement and register interface
            // without granting the role to address(0).
            AccessControlLib.registerInterface();
        }
        TimelockControllerLib.__TimelockController_init(minDelay, proposers, executors, admin);
        InitializableLib.postInitializer(s);
    }

    /// @notice Accept ETH so the timelock can hold and forward value during executions.
    receive() external payable {}

    //*//////////////////////////////////////////////////////////////////////////
    //                          NFT RECEIVER HOOKS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Allows the timelock to receive ERC-721 tokens via safeTransferFrom.
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /// @notice Allows the timelock to receive single ERC-1155 tokens via safeTransferFrom.
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /// @notice Allows the timelock to receive batch ERC-1155 tokens via safeBatchTransferFrom.
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }
}
