// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAgentRole} from "@lattice/interfaces/tokens/erc3643/IAgentRole.sol";
import {ERC3643AgentRoleLib} from "@lattice/tokens/ERC3643/libraries/ERC3643AgentRoleLib.sol";

/// @title ERC3643AgentRole
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Owner-managed standard agents. Ownership transfer retains current memberships.
/// @custom:lattice-source ERC-3643 CC0 standard
/// @custom:lattice-requires OwnableFacet convention agent-administration;
/// @custom:lattice-family none
/// @custom:lattice-owns none;
/// @custom:lattice-touches lattice.storage.AccessControl;
/// @custom:lattice-touches transient:lattice.storage.ERC3643Execution;
/// @custom:lattice-seam none;
/// @custom:lattice-init ERC3643Init
contract ERC3643AgentRole is IAgentRole {
    function addAgent(address agent) external {
        ERC3643AgentRoleLib.addAgent(agent);
    }

    function removeAgent(address agent) external {
        ERC3643AgentRoleLib.removeAgent(agent);
    }

    function isAgent(address agent) external view returns (bool) {
        return ERC3643AgentRoleLib.isAgent(agent);
    }

    function exportSelectors() external pure returns (bytes memory) {
        return hex"84e798421ffbb06497a6278e";
    }
}
