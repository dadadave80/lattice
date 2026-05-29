// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC20Permit
/// @notice Interface for ERC-2612 permit-based approvals (EIP-20 + EIP-712 signed approvals).
interface IERC20Permit {
    /// @dev The signature's deadline has expired.
    error ERC2612ExpiredSignature(uint256 deadline);

    /// @dev The recovered signer does not match the expected owner.
    error ERC2612InvalidSigner(address signer, address owner);

    /// @notice Sets `value` as the allowance of `spender` over `owner`'s tokens,
    ///         given a signed approval.
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /// @notice Returns the current nonce for `owner` (for use in permit signatures).
    function nonces(address owner) external view returns (uint256);

    /// @notice Returns the domain separator used in the encoding of permit signatures.
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
