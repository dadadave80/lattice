// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC7802 — crosschain token mint/burn interface
/// @author Vendored minimal subset of OpenZeppelin Contracts v5.6.1
///         (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/interfaces/draft-IERC7802.sol).
///         Upstream is MIT and inherits IERC165; only the mint/burn ABI that {BridgeERC7802} calls is
///         re-declared here. Vendored subset — do not add an openzeppelin-contracts dependency.
/// @notice The crosschain mint/burn surface an ERC-7802 token exposes to a trusted bridge.
interface IERC7802 {
    /// @notice Emitted when a crosschain transfer mints tokens.
    event CrosschainMint(address indexed to, uint256 amount, address indexed sender);

    /// @notice Emitted when a crosschain transfer burns tokens.
    event CrosschainBurn(address indexed from, uint256 amount, address indexed sender);

    /// @notice Mint tokens through a crosschain transfer.
    function crosschainMint(address _to, uint256 _amount) external;

    /// @notice Burn tokens through a crosschain transfer.
    function crosschainBurn(address _from, uint256 _amount) external;
}
