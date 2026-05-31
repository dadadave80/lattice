// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IEIP712
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/EIP712.sol)
/// @notice Interface for EIP-712 typed structured data hashing and signing,
///         including ERC-5267 domain discovery.
interface IEIP712 {
    /// @dev Thrown when the provided name is invalid (empty).
    error EIP712InvalidName();

    /// @dev Thrown when the provided version is invalid (empty).
    error EIP712InvalidVersion();

    /// @notice Returns the fields and values that describe the domain separator used for signing.
    /// @dev Implements ERC-5267.
    /// @return fields A bitmask where bit i indicates that field i is active in the domain.
    ///         Bit 0 = name, bit 1 = version, bit 2 = chainId, bit 3 = verifyingContract, bit 4 = salt.
    /// @return name The user-readable name of the signing domain.
    /// @return version The current major version of the signing domain.
    /// @return chainId The EIP-155 chain ID.
    /// @return verifyingContract The address of the contract that will verify the signature.
    /// @return salt An optional disambiguating salt.
    /// @return extensions An array of EIP-7702 extensions (empty for this implementation).
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );
}
