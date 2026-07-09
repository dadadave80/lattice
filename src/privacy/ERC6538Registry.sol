// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC6538Registry} from "@lattice/interfaces/privacy/IERC6538Registry.sol";
import {ERC6538RegistryLib} from "@lattice/privacy/libraries/ERC6538RegistryLib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";

/// @title ERC6538Registry
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ScopeLift (https://github.com/ScopeLift/stealth-address-erc-contracts)
/// @author Conforms to ERC-6538 (https://eips.ethereum.org/EIPS/eip-6538)
/// @notice Stateless Diamond facet implementing the ERC-6538 stealth meta-address registry.
/// @dev All logic lives in {ERC6538RegistryLib}. Owns ONLY the registry selectors. It does NOT inherit the
///      {EIP712} facet — doing so would re-export `eip712Domain()` and collide with the standalone {EIP712}
///      facet in a Diamond. ERC-5267 domain discovery comes from a separately-cut {EIP712} facet;
///      {DeployERC6538Registry} composes both. The EIP-712 domain (name "ERC6538Registry" / version "1.0")
///      and the registry must be initialized in the diamond initializer.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract ERC6538Registry is IERC6538Registry {
    /// @inheritdoc IERC6538Registry
    function registerKeys(uint256 schemeId, bytes calldata stealthMetaAddress) external virtual {
        ERC6538RegistryLib.registerKeys(schemeId, stealthMetaAddress);
    }

    /// @inheritdoc IERC6538Registry
    function registerKeysOnBehalf(
        address registrant,
        uint256 schemeId,
        bytes calldata signature,
        bytes calldata stealthMetaAddress
    ) external virtual {
        ERC6538RegistryLib.registerKeysOnBehalf(registrant, schemeId, signature, stealthMetaAddress);
    }

    /// @inheritdoc IERC6538Registry
    function incrementNonce() external virtual {
        ERC6538RegistryLib.incrementNonce();
    }

    /// @inheritdoc IERC6538Registry
    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return EIP712Lib.domainSeparatorV4();
    }

    /// @inheritdoc IERC6538Registry
    function stealthMetaAddressOf(address registrant, uint256 schemeId) external view virtual returns (bytes memory) {
        return ERC6538RegistryLib.stealthMetaAddressOf(registrant, schemeId);
    }

    /// @inheritdoc IERC6538Registry
    function ERC6538REGISTRY_ENTRY_TYPE_HASH() external view virtual returns (bytes32) {
        return ERC6538RegistryLib.entryTypeHash();
    }

    /// @inheritdoc IERC6538Registry
    function nonceOf(address registrant) external view virtual returns (uint256) {
        return ERC6538RegistryLib.nonceOf(registrant);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC6538Registry methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `DOMAIN_SEPARATOR()` 0x3644e515
    ///      `ERC6538REGISTRY_ENTRY_TYPE_HASH()` 0xfe04b106
    ///      `incrementNonce()` 0x627cdcb9
    ///      `nonceOf(address)` 0xed2a2d64
    ///      `registerKeys(uint256,bytes)` 0x042c7aa3
    ///      `registerKeysOnBehalf(address,uint256,bytes,bytes)` 0x428d3d0b
    ///      `stealthMetaAddressOf(address,uint256)` 0x7aa8b5ad
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"3644e515fe04b106627cdcb9ed2a2d64042c7aa3428d3d0b7aa8b5ad";
    }
}
