// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccountSignerLib} from "@lattice/accounts/libraries/AccountSignerLib.sol";
import {ERC7739Lib} from "@lattice/accounts/libraries/ERC7739Lib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev ERC-165 map slot for `IERC1271` (`isValidSignature(bytes32,bytes)` => `type(IERC1271).interfaceId
///      == 0x1626ba7e`). `keccak256(abi.encode(bytes4(0x1626ba7e), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC1271_SLOT = 0x13edcf2102dbcbe8afc6b8b590ac545a2ed12e9a15726b4c8ab7a3fb938ab3b7;

/// @dev ERC-1271 magic value for a valid signature; any other value is invalid.
bytes4 constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
bytes4 constant ERC1271_INVALID = 0xffffffff;

/// @dev ERC-7739 support sentinel: `isValidSignature(ERC7739_SENTINEL_HASH, "")` returns this iff the account
///      implements ERC-7739 defensive rehashing. The hash is the byte pair `0x7739` repeated 16 times.
bytes4 constant ERC7739_SUPPORT = 0x77390001;
bytes32 constant ERC7739_SENTINEL_HASH = 0x7739773977397739773977397739773977397739773977397739773977397739;

/// @title ERC1271SignatureLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/draft-ERC7739Utils.sol)
/// @notice Logic for the ERC-1271 contract-signature facet. Stateless — delegates verification to the
///         configured owner via {AccountSignerLib}.
/// @dev Implements ERC-7739: `isValidSignature` accepts only a nested `TypedDataSign` (EIP-712) or
///      `PersonalSign` envelope bound to this account's EIP-712 domain, so a signature is never valid for a
///      different account that shares the owner key. A plain signature over the raw `hash` is rejected. The
///      hashing is delegated to {ERC7739Lib} (ported from audited OZ/Solady), composed over {EIP712Lib}.
library ERC1271SignatureLib {
    /// @notice Registers the `IERC1271` ERC-165 id so dapps can discover contract-signature support.
    function __ERC1271Signature_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for `IERC1271`.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC1271_SLOT, true)
        }
    }

    /// @notice ERC-7739 `isValidSignature`. Returns `0x1626ba7e` for a valid nested `TypedDataSign` /
    ///         `PersonalSign` signature, `0x77390001` for the support-detection probe, else `0xffffffff`.
    function isValidSignature(bytes32 hash, bytes calldata signature) internal view returns (bytes4) {
        if (_isValidNestedTypedDataSignature(hash, signature) || _isValidNestedPersonalSignSignature(hash, signature)) {
            return ERC1271_MAGIC_VALUE;
        }
        if (hash == ERC7739_SENTINEL_HASH && signature.length == 0) return ERC7739_SUPPORT;
        return ERC1271_INVALID;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice `personal_sign` path: the owner must have signed `hash` wrapped in this account's domain.
    function _isValidNestedPersonalSignSignature(bytes32 hash, bytes calldata signature) private view returns (bool) {
        return AccountSignerLib.isValidSignatureNow(
            EIP712Lib.hashTypedDataV4(ERC7739Lib.personalSignStructHash(hash)), signature
        );
    }

    /// @notice `eth_signTypedData` path: the outer `hash` must equal the app's typed-data hash, and the owner
    ///         must have signed the `TypedDataSign` struct (contents + this account's domain) under the app's
    ///         separator. The inner signature, app separator, contents hash, and descriptor are read from the
    ///         appended wire envelope.
    function _isValidNestedTypedDataSignature(bytes32 hash, bytes calldata encodedSignature)
        private
        view
        returns (bool)
    {
        (bytes calldata signature, bytes32 appSeparator, bytes32 contentsHash, string calldata contentsDescr) =
            ERC7739Lib.decodeTypedDataSig(encodedSignature);

        (, string memory name, string memory version, uint256 chainId, address verifyingContract, bytes32 salt,) =
            EIP712Lib.eip712Domain();

        return hash == _toTypedDataHash(appSeparator, contentsHash) && bytes(contentsDescr).length != 0
            && AccountSignerLib.isValidSignatureNow(
            _toTypedDataHash(
            appSeparator,
            ERC7739Lib.typedDataSignStructHash(
            contentsDescr,
            contentsHash,
            abi.encode(keccak256(bytes(name)), keccak256(bytes(version)), chainId, verifyingContract, salt)
        )
        ),
            signature
        );
    }

    /// @dev `keccak256("\x19\x01" || separator || structHash)`. Used here with the APP's separator;
    ///      `EIP712Lib.hashTypedDataV4` wraps with THIS account's separator (the PersonalSign path).
    function _toTypedDataHash(bytes32 separator, bytes32 structHash) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(hex"1901", separator, structHash));
    }
}
