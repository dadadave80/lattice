// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IERC6538Registry} from "@lattice/interfaces/IERC6538Registry.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {SignatureChecker} from "@lattice/utils/libraries/SignatureChecker.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC6538Registry")) - 1)) & ~bytes32(uint256(0xff))`.
///      Verify with: `cast index-erc7201 "lattice.storage.ERC6538Registry"`.
bytes32 constant ERC6538REGISTRY_STORAGE_SLOT = 0x77e72c5973ed8cfb58126100bfd525d25949aa328155f37334e51548cdc80100;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC6538REGISTRY_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x7b1f57cb is `type(IERC6538Registry).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x7b1f57cb), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC6538REGISTRY_SLOT = 0xba3bf91c60e936a8bb7a4c2729c74c6ef842a655f3dff9707765ac926778cd2e;

/// @dev EIP-712 typehash for an on-behalf registration entry. Byte-identical to the canonical ERC-6538
///      reference (`Erc6538RegistryEntry`) so wallets that implement ERC-6538 signing produce
///      compatible signatures against this diamond's domain.
bytes32 constant ERC6538REGISTRY_ENTRY_TYPE_HASH =
    keccak256("Erc6538RegistryEntry(uint256 schemeId,bytes stealthMetaAddress,uint256 nonce)");

/// @notice ERC-7201 namespaced storage for the ERC6538Registry module.
/// @dev APPEND-ONLY: new fields may only be added at the end to preserve the upgrade-safe layout.
/// @custom:storage-location erc7201:lattice.storage.ERC6538Registry
struct ERC6538RegistryStorage {
    /// @dev registrant address => schemeId => stealth meta-address.
    mapping(address registrant => mapping(uint256 schemeId => bytes stealthMetaAddress)) _stealthMetaAddresses;
    /// @dev registrant address => next nonce for {registerKeysOnBehalf} (registry-local, not the
    ///      diamond-wide Nonces module — matches the canonical ERC-6538 per-registry nonce semantics).
    mapping(address registrant => uint256 nonce) _nonces;
}

/// @title ERC6538RegistryLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Conforms to ERC-6538 (https://eips.ethereum.org/EIPS/eip-6538)
/// @notice Library implementing the ERC-6538 stealth meta-address registry.
/// @dev Reuses the shared EIP712 module for the domain separator + typed-data hashing, and
///      {SignatureChecker} for ECDSA + ERC-1271 verification — mirroring the canonical reference's
///      `registerKeysOnBehalf` exactly. The nonce is registry-local (this module's own storage), so
///      `nonceOf` is independent of any token permit / vote-delegation nonce in the same diamond.
///      The EIP-712 domain is the host diamond's shared domain; initialize EIP712 with name
///      "ERC6538Registry" / version "1.0" for canonical ERC-6538 signer compatibility.
library ERC6538RegistryLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function erc6538RegistryStorage() internal pure returns (ERC6538RegistryStorage storage $) {
        assembly {
            $.slot := ERC6538REGISTRY_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the ERC6538Registry module.
    /// @dev Must be called inside a pre/postInitializer block. Registers IERC6538Registry for ERC-165.
    ///      EIP712 must be initialized separately (the registry reuses its domain for hashing).
    function __ERC6538Registry_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IERC6538Registry interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC6538REGISTRY_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the caller's stealth meta-address for `schemeId` (last-write-wins).
    /// @param schemeId           The stealth-address scheme id.
    /// @param stealthMetaAddress The caller's stealth meta-address bytes.
    function registerKeys(uint256 schemeId, bytes calldata stealthMetaAddress) internal {
        erc6538RegistryStorage()._stealthMetaAddresses[msg.sender][schemeId] = stealthMetaAddress;
        emit IERC6538Registry.StealthMetaAddressSet(msg.sender, schemeId, stealthMetaAddress);
    }

    /// @notice Registers `registrant`'s stealth meta-address from an EIP-712 signature.
    /// @dev Consumes the registrant's nonce BEFORE verifying, so a failed verification reverts the
    ///      whole call and rolls the consumed nonce back (no griefing). Supports EOA + ERC-1271 signers.
    /// @param registrant         The account authorizing the registration.
    /// @param schemeId           The stealth-address scheme id.
    /// @param signature          The registrant's EIP-712 signature.
    /// @param stealthMetaAddress The stealth meta-address bytes to store.
    function registerKeysOnBehalf(
        address registrant,
        uint256 schemeId,
        bytes calldata signature,
        bytes calldata stealthMetaAddress
    ) internal {
        ERC6538RegistryStorage storage $ = erc6538RegistryStorage();

        uint256 nonce;
        unchecked {
            nonce = $._nonces[registrant]++;
        }

        bytes32 structHash =
            keccak256(abi.encode(ERC6538REGISTRY_ENTRY_TYPE_HASH, schemeId, keccak256(stealthMetaAddress), nonce));
        bytes32 digest = EIP712Lib.hashTypedDataV4(structHash);

        if (!SignatureChecker.isValidSignatureNow(registrant, digest, signature)) {
            revert IERC6538Registry.ERC6538Registry__InvalidSignature();
        }

        $._stealthMetaAddresses[registrant][schemeId] = stealthMetaAddress;
        emit IERC6538Registry.StealthMetaAddressSet(registrant, schemeId, stealthMetaAddress);
    }

    /// @notice Advances the caller's nonce, invalidating outstanding on-behalf signatures.
    function incrementNonce() internal {
        ERC6538RegistryStorage storage $ = erc6538RegistryStorage();
        uint256 newNonce;
        unchecked {
            newNonce = ++$._nonces[msg.sender];
        }
        emit IERC6538Registry.NonceIncremented(msg.sender, newNonce);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the stealth meta-address registered by `registrant` for `schemeId`.
    /// @param registrant The account to query.
    /// @param schemeId   The stealth-address scheme id.
    /// @return The registered stealth meta-address bytes (empty if unset).
    function stealthMetaAddressOf(address registrant, uint256 schemeId) internal view returns (bytes memory) {
        return erc6538RegistryStorage()._stealthMetaAddresses[registrant][schemeId];
    }

    /// @notice Returns the current on-behalf-registration nonce for `registrant`.
    /// @param registrant The account to query.
    /// @return The current nonce.
    function nonceOf(address registrant) internal view returns (uint256) {
        return erc6538RegistryStorage()._nonces[registrant];
    }

    /// @notice Returns the EIP-712 type hash used in {registerKeysOnBehalf}.
    function entryTypeHash() internal pure returns (bytes32) {
        return ERC6538REGISTRY_ENTRY_TYPE_HASH;
    }
}
