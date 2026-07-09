// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

// IERC6551 — Token-bound account interfaces. Re-authored to the ERC-6551 standard ABI (reference:
// erc6551/reference, MIT). Vendored subset — do not add an external dependency.
// Interface ids: IERC6551Account = 0x6faff5f1, IERC6551Executable = 0x51945447. The `isValidSigner` success
// magic value is its own selector, 0x523e3260.

/// @dev ERC-6551 account introspection + signer validation.
interface IERC6551Account {
    /// @notice The account must be able to receive native value.
    receive() external payable;

    /// @notice Returns the magic value `0x523e3260` if `signer` is authorized to act for the account in
    ///         `context`, else `bytes4(0)`.
    function isValidSigner(address signer, bytes calldata context) external view returns (bytes4 magicValue);

    /// @notice A value that changes every time the account state changes (e.g. after each execution).
    function state() external view returns (uint256);

    /// @notice The token that owns this account: `(chainId, tokenContract, tokenId)`.
    function token() external view returns (uint256 chainId, address tokenContract, uint256 tokenId);
}

/// @dev ERC-6551 execution surface.
interface IERC6551Executable {
    /// @notice Executes a low-level operation if the caller is a valid signer. `operation` 0 = CALL.
    function execute(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        payable
        returns (bytes memory);
}
