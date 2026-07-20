// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC1271 — Standard signature validation for contracts
/// @author Vendored from OpenZeppelin Contracts `contracts/interfaces/IERC1271.sol` (MIT). Vendored subset —
///         do not add an openzeppelin-contracts dependency.
/// @notice ERC-1271: lets a contract declare a signature valid. dapps (permits, Seaport, Permit2) call this.
interface IERC1271 {
    /// @notice Returns `0x1626ba7e` when `signature` is a valid signature over `hash` for this contract.
    /// @dev The magic value is `bytes4(keccak256("isValidSignature(bytes32,bytes)"))`. Any other return
    ///      (or a revert) means invalid.
    /// @param hash The hash of the signed data.
    /// @param signature The signature bytes (opaque; format is account-defined).
    /// @return magicValue `0x1626ba7e` if valid, any other value otherwise.
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue);
}
