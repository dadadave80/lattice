// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAgentRole} from "@lattice/interfaces/tokens/erc3643/IAgentRole.sol";
import {ERC3643ExecutionLib} from "@lattice/tokens/ERC3643/libraries/ERC3643ExecutionLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @dev `keccak256("lattice.role.ERC3643Agent")`; membership survives ownership transfer.
bytes32 constant ERC3643_AGENT_ROLE = 0x4c550038b786c0bec2ada1b6ba9e8a312fd8adb96f1666a54683074813bef6b6;
/// @dev 0x0cba0fa8 is `type(IAgentRole).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x0cba0fa8), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IAGENTROLE_SLOT = 0x5e0e61fcfafd9757a5e1c80a17dd186de8f76529f91d051782b2ee9d958f98cf;

/// @title ERC3643AgentRoleLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice ERC-173 owner-managed agents, reusing role bookkeeping without advertising AccessControl.
/// @dev Does not call __AccessControl_init, seed DEFAULT_ADMIN_ROLE, or expose a grantRole bypass.
library ERC3643AgentRoleLib {
    function __ERC3643AgentRole_init(address[] memory agents) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
        for (uint256 i; i < agents.length; ++i) {
            _addAgent(agents[i]);
        }
    }

    function registerInterface() internal {
        assembly ("memory-safe") { sstore(ERC165_MAP_IAGENTROLE_SLOT, true) }
    }

    function addAgent(address agent) internal {
        ERC3643ExecutionLib.enter();
        OwnableLib.checkOwner();
        _addAgent(agent);
        ERC3643ExecutionLib.exit();
    }

    function _addAgent(address agent) internal {
        if (agent == address(0)) revert IAgentRole.ERC3643InvalidAgent(agent);
        if (AccessControlLib._grantRole(ERC3643_AGENT_ROLE, agent)) emit IAgentRole.AgentAdded(agent);
    }

    function removeAgent(address agent) internal {
        ERC3643ExecutionLib.enter();
        OwnableLib.checkOwner();
        if (agent == address(0)) revert IAgentRole.ERC3643InvalidAgent(agent);
        if (AccessControlLib._revokeRole(ERC3643_AGENT_ROLE, agent)) emit IAgentRole.AgentRemoved(agent);
        ERC3643ExecutionLib.exit();
    }

    function isAgent(address account) internal view returns (bool) {
        return AccessControlLib.hasRole(ERC3643_AGENT_ROLE, account);
    }

    function checkAgent() internal view {
        if (!isAgent(msg.sender)) revert IAgentRole.ERC3643UnauthorizedAgent(msg.sender);
    }
}
