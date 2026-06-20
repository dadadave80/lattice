// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC5564Announcer
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Conforms to ERC-5564 (https://eips.ethereum.org/EIPS/eip-5564)
/// @notice External interface for the ERC-5564 stealth-address announcer: a permissionless event
///         emitter that lets a sender publish the data a stealth-payment recipient needs to detect
///         and spend a payment, without revealing the recipient on-chain.
/// @dev The announcer is stateless — `announce` only emits {Announcement}. Any account may call it;
///      there is no access control or validation, matching the canonical ERC-5564 contract.
interface IERC5564Announcer {
    /// @dev Emitted on every announcement. Indexers watch this to discover stealth payments.
    /// @param schemeId        The stealth-address scheme id (1 == SECP256k1 with view tags).
    /// @param stealthAddress  The destination stealth address the funds were sent to.
    /// @param caller          The account that emitted the announcement (`msg.sender`), set by the contract.
    /// @param ephemeralPubKey The sender's ephemeral public key, used by the recipient to derive the shared secret.
    /// @param metadata        Scheme-specific metadata; for scheme 1, byte[0] is the view tag.
    event Announcement(
        uint256 indexed schemeId,
        address indexed stealthAddress,
        address indexed caller,
        bytes ephemeralPubKey,
        bytes metadata
    );

    /// @notice Emits an {Announcement} broadcasting a stealth payment.
    /// @dev Permissionless and stateless; `caller` in the event is forced to `msg.sender`.
    /// @param schemeId        The stealth-address scheme id (1 == SECP256k1 with view tags).
    /// @param stealthAddress  The destination stealth address.
    /// @param ephemeralPubKey The sender's ephemeral public key.
    /// @param metadata        Scheme-specific metadata (view tag + optional transfer hints for scheme 1).
    function announce(uint256 schemeId, address stealthAddress, bytes calldata ephemeralPubKey, bytes calldata metadata)
        external;
}
