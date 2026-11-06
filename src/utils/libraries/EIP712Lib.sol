// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib} from "@diamond/libraries/DiamondLib.sol";
import {IEIP712} from "@lattice/interfaces/utils/IEIP712.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {ShortString, ShortStrings} from "@lattice/utils/libraries/ShortStrings.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.EIP712")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant EIP712_STORAGE_SLOT = 0x20a66479672b0fb14805a3bad8d1d6c2fa26c98d9118036fcaf73a0900bc5a00;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant EIP712_ERC165_STORAGE_LOCATION = 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x84b0196e is `type(IEIP712).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x84b0196e), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IEIP712_SLOT = 0xce8419fc9d1331d080c55682cb17490a04c7d4f800e9d81986c2db7a5e912f84;

/// @dev EIP-712 type hash for the domain struct.
bytes32 constant EIP712_DOMAIN_TYPE_HASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

/// @notice Storage struct for EIP-712 module.
/// @custom:storage-location erc7201:lattice.storage.EIP712
struct EIP712Storage {
    bytes32 _cachedDomainSeparator;
    uint256 _cachedChainId;
    address _cachedThis;
    bytes32 _hashedName;
    bytes32 _hashedVersion;
    ShortString _name;
    ShortString _version;
    string _nameFallback;
    string _versionFallback;
}

/// @title EIP712Lib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/EIP712.sol)
/// @notice Library implementing EIP-712 typed structured data hashing.
///         Supports ERC-5267 domain discovery and caches the domain separator
///         for the current chain ID + contract address to save gas.
library EIP712Lib {
    using ShortStrings for *;

    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function eip712Storage() internal pure returns (EIP712Storage storage $) {
        assembly {
            $.slot := EIP712_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the EIP-712 module with the given name and version.
    /// @dev Must be called inside a pre/postInitializer block.
    ///      Caches the domain separator, chain ID, and contract address.
    ///      Rejects a conflicting domain; identical configuration preserves the existing domain/cache.
    ///      Registers IEIP712 only when its discovery view is routed in this diamond.
    /// @param name The human-readable name of the signing domain.
    /// @param version The version of the signing domain.
    function __EIP712_init(string memory name, string memory version) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);

        EIP712Storage storage $ = eip712Storage();

        // Validate name and version
        if (bytes(name).length == 0) revert IEIP712.EIP712InvalidName();
        if (bytes(version).length == 0) revert IEIP712.EIP712InvalidVersion();

        bytes32 hashedName = keccak256(bytes(name));
        bytes32 hashedVersion = keccak256(bytes(version));
        if ($._hashedName != bytes32(0) || $._hashedVersion != bytes32(0)) {
            if ($._hashedName != hashedName || $._hashedVersion != hashedVersion) {
                revert IEIP712.EIP712ConflictingDomain();
            }
        } else {
            $._name = ShortStrings.toShortStringWithFallback(name, $._nameFallback);
            $._version = ShortStrings.toShortStringWithFallback(version, $._versionFallback);
            $._hashedName = hashedName;
            $._hashedVersion = hashedVersion;
            $._cachedChainId = block.chainid;
            $._cachedThis = address(this);
            $._cachedDomainSeparator = _buildDomainSeparator(hashedName, hashedVersion);
        }

        if (DiamondLib.selectorToFacet(DiamondLib.diamondStorage(), IEIP712.eip712Domain.selector) != address(0)) {
            registerInterface();
        } else {
            // Repair false-positive flags left by initializers predating routed-view registration.
            assembly ("memory-safe") {
                sstore(ERC165_MAP_IEIP712_SLOT, false)
            }
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IEIP712 interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IEIP712_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            DOMAIN SEPARATOR
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the EIP-712 domain separator.
    /// @dev Returns the cached value if chain ID and this address match; otherwise recomputes.
    /// @return The current domain separator.
    function domainSeparatorV4() internal view returns (bytes32) {
        EIP712Storage storage $ = eip712Storage();
        if (block.chainid == $._cachedChainId && address(this) == $._cachedThis) {
            return $._cachedDomainSeparator;
        }
        return _buildDomainSeparator($._hashedName, $._hashedVersion);
    }

    /// @notice Returns the hash of an EIP-712 typed data message.
    /// @dev Prefixes the struct hash with the EIP-712 domain separator.
    /// @param structHash The hash of the typed data struct.
    /// @return The final digest: keccak256("\x19\x01" + domainSeparator + structHash).
    function hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparatorV4(), structHash));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-5267 VIEW
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the ERC-5267 domain descriptor.
    /// @return fields Active field bitmask (0x0f = name, version, chainId, verifyingContract).
    /// @return name The signing domain name.
    /// @return version The signing domain version.
    /// @return chainId The current chain ID.
    /// @return verifyingContract This contract's address.
    /// @return salt Empty (not used).
    /// @return extensions Empty array.
    function eip712Domain()
        internal
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        EIP712Storage storage $ = eip712Storage();
        return (
            hex"0f", // fields: name (bit0) + version (bit1) + chainId (bit2) + verifyingContract (bit3)
            ShortStrings.toStringWithFallback($._name, $._nameFallback),
            ShortStrings.toStringWithFallback($._version, $._versionFallback),
            block.chainid,
            address(this),
            bytes32(0),
            new uint256[](0)
        );
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Builds the EIP-712 domain separator from hashed name and version.
    function _buildDomainSeparator(bytes32 hashedName, bytes32 hashedVersion) private view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPE_HASH, hashedName, hashedVersion, block.chainid, address(this)));
    }
}
