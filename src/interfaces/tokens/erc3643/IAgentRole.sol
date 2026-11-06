// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IAgentRole
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice ERC-3643 owner-managed agents. Membership is independent of ownership transfer.
interface IAgentRole {
    event AgentAdded(address indexed agent);
    event AgentRemoved(address indexed agent);
    error ERC3643UnauthorizedAgent(address account);
    error ERC3643InvalidAgent(address account);
    function addAgent(address agent) external;
    function removeAgent(address agent) external;
    function isAgent(address agent) external view returns (bool);
}
