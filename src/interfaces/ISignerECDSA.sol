// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ISignerECDSA
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Admin/read surface of the `SignerECDSA` facet — the single-owner ECDSA signer that backs both
///         ERC-4337 `validateUserOp` and ERC-1271 `isValidSignature`.
/// @dev The owner may be an EOA or a contract (ERC-1271), since validation goes through the repo's
///      `SignatureChecker`. Replaces a constructor with admin-gated `setOwner`.
interface ISignerECDSA {
    /// @notice Emitted when the signing owner changes.
    event OwnerSet(address indexed previousOwner, address indexed newOwner);

    /// @notice The new owner is the zero address.
    error InvalidOwner();

    /// @notice The address whose signatures this account accepts.
    function owner() external view returns (address);

    /// @notice Sets the signing owner. Admin only.
    function setOwner(address newOwner) external;
}
