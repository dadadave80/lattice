// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IERC2981} from "@lattice/interfaces/IERC2981.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC2981")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC2981_STORAGE_SLOT = 0xf01000cac811e850d05bb5588943b621fb762a575809c98a87e3540df4e97a00;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC2981_ERC165_STORAGE_LOCATION = 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x2a55205a is `type(IERC2981).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x2a55205a), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC2981_SLOT = 0x0b6e5f3aef2b5db6c8b7f9a90550b00e1bcf3efa09341feda1a90dabdea92899;

/// @notice Royalty information for a receiver.
struct RoyaltyInfo {
    address receiver;
    uint96 royaltyFraction;
}

/// @notice Storage struct for ERC-2981 module.
/// @custom:storage-location erc7201:lattice.storage.ERC2981
struct ERC2981Storage {
    RoyaltyInfo _defaultRoyaltyInfo;
    mapping(uint256 tokenId => RoyaltyInfo) _tokenRoyaltyInfo;
}

/// @title ERC2981Lib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/common/ERC2981.sol)
/// @notice Library implementing the ERC-2981 NFT Royalty Standard.
/// @dev Mirrors OpenZeppelin v5 ERC2981 logic. All state lives in an ERC-7201 slot.
library ERC2981Lib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function erc2981Storage() internal pure returns (ERC2981Storage storage $) {
        assembly {
            $.slot := ERC2981_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the ERC-2981 module and registers the interface.
    /// @dev Must be called inside a pre/postInitializer block.
    function __ERC2981_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IERC2981 interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC2981_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the royalty denominator (basis points: 10_000).
    function _feeDenominator() internal pure returns (uint96) {
        return 10_000;
    }

    /// @notice Returns royalty information for a given token sale.
    /// @dev Uses token-specific royalty if set, otherwise falls back to default.
    function royaltyInfo(uint256 tokenId, uint256 salePrice) internal view returns (address, uint256) {
        ERC2981Storage storage $ = erc2981Storage();
        RoyaltyInfo memory royalty = $._tokenRoyaltyInfo[tokenId];

        if (royalty.receiver == address(0)) {
            royalty = $._defaultRoyaltyInfo;
        }

        uint256 royaltyAmount = (salePrice * royalty.royaltyFraction) / _feeDenominator();
        return (royalty.receiver, royaltyAmount);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          MUTATIONS (AUTH-CHECKED)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets the default royalty receiver and fraction. Admin-only.
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /// @notice Deletes the default royalty configuration. Admin-only.
    function deleteDefaultRoyalty() internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _deleteDefaultRoyalty();
    }

    /// @notice Sets a per-token royalty override. Admin-only.
    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }

    /// @notice Removes the per-token royalty override, falling back to default. Admin-only.
    function resetTokenRoyalty(uint256 tokenId) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _resetTokenRoyalty(tokenId);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets the default royalty receiver and fraction. Reverts if invalid.
    function _setDefaultRoyalty(address receiver, uint96 feeNumerator) internal {
        uint96 denominator = _feeDenominator();
        if (feeNumerator > denominator) {
            revert IERC2981.ERC2981InvalidDefaultRoyalty(feeNumerator, denominator);
        }
        if (receiver == address(0)) {
            revert IERC2981.ERC2981InvalidDefaultRoyaltyReceiver(address(0));
        }
        ERC2981Storage storage $ = erc2981Storage();
        $._defaultRoyaltyInfo = RoyaltyInfo(receiver, feeNumerator);
    }

    /// @notice Deletes the default royalty configuration.
    function _deleteDefaultRoyalty() internal {
        delete erc2981Storage()._defaultRoyaltyInfo;
    }

    /// @notice Sets a per-token royalty override. Reverts if invalid.
    function _setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) internal {
        uint96 denominator = _feeDenominator();
        if (feeNumerator > denominator) {
            revert IERC2981.ERC2981InvalidTokenRoyalty(tokenId, feeNumerator, denominator);
        }
        if (receiver == address(0)) {
            revert IERC2981.ERC2981InvalidTokenRoyaltyReceiver(tokenId, address(0));
        }
        erc2981Storage()._tokenRoyaltyInfo[tokenId] = RoyaltyInfo(receiver, feeNumerator);
    }

    /// @notice Removes the per-token royalty override, falling back to default.
    function _resetTokenRoyalty(uint256 tokenId) internal {
        delete erc2981Storage()._tokenRoyaltyInfo[tokenId];
    }
}
