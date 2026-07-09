// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC6538Registry
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ScopeLift (https://github.com/ScopeLift/stealth-address-erc-contracts)
/// @author Conforms to ERC-6538 (https://eips.ethereum.org/EIPS/eip-6538)
/// @notice External interface for the ERC-6538 stealth meta-address registry: an on-chain mapping
///         from a registrant address to the stealth meta-address others use to pay them privately.
/// @dev The function and event ABIs match the canonical ERC-6538 reference exactly (address-keyed
///      registrant, `Erc6538RegistryEntry` EIP-712 entry, `ERC6538Registry__InvalidSignature` error)
///      so ERC-6538 indexers and wallets interoperate. Registrants may set their own keys
///      ({registerKeys}) or authorize a relayer with an EIP-712 signature ({registerKeysOnBehalf},
///      ERC-1271-aware, replay-protected by a per-registrant nonce).
///      CONFORMANCE CAVEAT: as a Diamond facet the EIP-712 domain's `verifyingContract` is the host
///      diamond (not a fixed singleton), so relayers/wallets MUST read the live domain via
///      {DOMAIN_SEPARATOR} / ERC-5267 `eip712Domain()` rather than assuming a canonical address. An
///      on-behalf signature does not expire; a signer cancels an outstanding one with {incrementNonce}.
interface IERC6538Registry {
    /// @dev Thrown when the signature passed to {registerKeysOnBehalf} is not valid for `registrant`.
    error ERC6538Registry__InvalidSignature();

    /// @dev Emitted when a registrant sets or overwrites their stealth meta-address for a scheme.
    /// @param registrant         The account whose stealth meta-address was set.
    /// @param schemeId           The stealth-address scheme id (1 == SECP256k1 with view tags).
    /// @param stealthMetaAddress The registered stealth meta-address bytes.
    event StealthMetaAddressSet(address indexed registrant, uint256 indexed schemeId, bytes stealthMetaAddress);

    /// @dev Emitted when a registrant advances their nonce, invalidating outstanding signatures.
    /// @param registrant The account whose nonce advanced.
    /// @param newNonce   The nonce value after incrementing.
    event NonceIncremented(address indexed registrant, uint256 newNonce);

    /// @notice Sets the caller's stealth meta-address for `schemeId` (last-write-wins).
    /// @param schemeId           The stealth-address scheme id.
    /// @param stealthMetaAddress The caller's stealth meta-address bytes.
    function registerKeys(uint256 schemeId, bytes calldata stealthMetaAddress) external;

    /// @notice Sets `registrant`'s stealth meta-address using an EIP-712 signature from `registrant`.
    /// @dev Verifies via ECDSA or ERC-1271 over the `Erc6538RegistryEntry` typed data bound to the
    ///      registrant's current nonce; the nonce is consumed so the signature is single-use.
    /// @param registrant         The account authorizing the registration.
    /// @param schemeId           The stealth-address scheme id.
    /// @param signature          The registrant's EIP-712 signature (EOA or ERC-1271).
    /// @param stealthMetaAddress The stealth meta-address bytes to store.
    function registerKeysOnBehalf(
        address registrant,
        uint256 schemeId,
        bytes calldata signature,
        bytes calldata stealthMetaAddress
    ) external;

    /// @notice Advances the caller's nonce by one, invalidating any outstanding on-behalf signatures.
    function incrementNonce() external;

    /// @notice Returns the EIP-712 domain separator used for {registerKeysOnBehalf} signatures.
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice Returns the stealth meta-address registered by `registrant` for `schemeId`.
    /// @param registrant The account to query.
    /// @param schemeId   The stealth-address scheme id.
    /// @return The registered stealth meta-address bytes (empty if never registered).
    function stealthMetaAddressOf(address registrant, uint256 schemeId) external view returns (bytes memory);

    /// @notice Returns the EIP-712 type hash used in {registerKeysOnBehalf}.
    function ERC6538REGISTRY_ENTRY_TYPE_HASH() external view returns (bytes32);

    /// @notice Returns the current on-behalf-registration nonce for `registrant`.
    /// @param registrant The account to query.
    /// @return The current nonce.
    function nonceOf(address registrant) external view returns (uint256);
}
