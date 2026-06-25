// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ISignerECDSA} from "@lattice/interfaces/ISignerECDSA.sol";
import {SignatureChecker} from "@lattice/utils/libraries/SignatureChecker.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.SignerECDSA")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant SIGNER_ECDSA_STORAGE_SLOT = 0xaf273bb17bfc30760e1328e155348f6f93ceff3d7bff7b90236de96aa1fbbe00;

/// @notice ERC-7201 namespaced storage for the single-owner ECDSA signer.
/// @custom:storage-location erc7201:lattice.storage.SignerECDSA
struct SignerECDSAStorage {
    /// @notice The address whose signatures this account accepts (EOA or ERC-1271 contract). APPEND-ONLY.
    address _owner;
}

/// @title SignerECDSALib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Logic + ERC-7201 storage for the single-owner ECDSA signer that backs both ERC-4337
///         `validateUserOp` and ERC-1271 `isValidSignature`.
/// @dev `isValidSignatureNow` is the signer seam consumed by the validation/1271 facets. It routes through
///      the repo's `SignatureChecker`, so the owner may be an EOA (ECDSA, malleability-rejecting) or an
///      ERC-1271 contract. Owner changes are admin-gated; the init seeds the owner once.
library SignerECDSALib {
    function signerECDSAStorage() internal pure returns (SignerECDSAStorage storage $) {
        assembly {
            $.slot := SIGNER_ECDSA_STORAGE_SLOT
        }
    }

    /// @notice Seeds the signing owner during diamond initialization.
    function __SignerECDSA_init(address owner_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        _setOwner(owner_);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function owner() internal view returns (address) {
        return signerECDSAStorage()._owner;
    }

    /// @notice True if `signature` is a valid signature over `hash` for the configured owner.
    function isValidSignatureNow(bytes32 hash, bytes memory signature) internal view returns (bool) {
        return SignatureChecker.isValidSignatureNow(signerECDSAStorage()._owner, hash, signature);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets the signing owner. Admin only.
    function setOwner(address newOwner) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _setOwner(newOwner);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    function _setOwner(address newOwner) private {
        if (newOwner == address(0)) revert ISignerECDSA.InvalidOwner();
        SignerECDSAStorage storage $ = signerECDSAStorage();
        emit ISignerECDSA.OwnerSet($._owner, newOwner);
        $._owner = newOwner;
    }
}
