// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IHASSignatureVerifier
/// @author Modified from hiero-ledger/hiero-contracts (https://github.com/hiero-ledger/hiero-contracts)
/// @notice Interface for the HASSignatureVerifier Diamond facet — native Hedera account signature checks
///         (HIP-632) through the Hedera Account Service system contract, so ED25519-keyed Hedera accounts
///         (and ECDSA accounts after key rotation) can sign for a Lattice smart account or module.
/// @dev Both reads never revert on a bad signature: a system-contract revert (malformed input, key list on
///      the raw path, insufficient gas) is reported as `false`, matching the {AccountSigner} seam contract.
interface IHASSignatureVerifier {
    /// @notice True if `signature` (65 bytes ECDSA or 64 bytes ED25519) is valid over `messageHash` for the
    ///         simple key of Hedera `account` (an EVM alias or long-zero `0x000…<accountNum>` address).
    function isAuthorizedRaw(address account, bytes32 messageHash, bytes calldata signature)
        external
        view
        returns (bool authorized);

    /// @notice True if the protobuf `signatureMap` satisfies `account`'s full key structure (key lists and
    ///         threshold keys included) over the raw `message`.
    function isAuthorized(address account, bytes calldata message, bytes calldata signatureMap)
        external
        view
        returns (bool authorized);
}
