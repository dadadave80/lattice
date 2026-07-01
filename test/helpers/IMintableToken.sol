// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IMintableToken
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only handle for an underlying-asset ERC-20 diamond assembled from the production
///         {DeployERC20} recipe plus the {TokenTestFacet} (which supplies the ungated `mint`). Vault facet
///         tests need a mintable ERC-20 to seed depositor balances; typing the underlying diamond as this
///         combined interface lets a test call `mint`/`approve`/`transfer`/`balanceOf` through the real
///         diamond dispatch. Never shipped — a test fixture only.
interface IMintableToken {
    function mint(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
}
