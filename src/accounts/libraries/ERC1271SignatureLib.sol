// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {SignerECDSALib} from "@lattice/accounts/libraries/SignerECDSALib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev ERC-165 map slot for `IERC1271` (`isValidSignature(bytes32,bytes)` => `type(IERC1271).interfaceId
///      == 0x1626ba7e`). `keccak256(abi.encode(bytes4(0x1626ba7e), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC1271_SLOT = 0x13edcf2102dbcbe8afc6b8b590ac545a2ed12e9a15726b4c8ab7a3fb938ab3b7;

/// @dev ERC-1271 magic value for a valid signature; any other value is invalid.
bytes4 constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
bytes4 constant ERC1271_INVALID = 0xffffffff;

/// @title ERC1271SignatureLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Logic for the ERC-1271 contract-signature facet. Stateless — delegates verification to the
///         configured owner via {SignerECDSALib}.
/// @dev v1 verifies the owner's signature over the raw `hash`. ERC-7739 defensive rehashing (binding the
///      signature to this account's EIP-712 domain to stop cross-account replay when an owner controls
///      multiple accounts) is a planned hardening — it should compose the audited Solady `ERC1271` /
///      OZ `ERC7739Utils` algorithm rather than be hand-rolled, so it is intentionally deferred here.
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

    /// @notice Returns `0x1626ba7e` iff `signature` is a valid signature over `hash` for the owner.
    function isValidSignature(bytes32 hash, bytes memory signature) internal view returns (bytes4) {
        return SignerECDSALib.isValidSignatureNow(hash, signature) ? ERC1271_MAGIC_VALUE : ERC1271_INVALID;
    }
}
