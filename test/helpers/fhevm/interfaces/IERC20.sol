// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

/// @dev Local copy rather than an OpenZeppelin import: this file reaches every consumer's
/// compile graph through the test base, and Foundry remappings are project-global.
interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}
