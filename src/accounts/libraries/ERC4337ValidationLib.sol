// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {AccountSignerLib} from "@lattice/accounts/libraries/AccountSignerLib.sol";
import {IERC4337Validation} from "@lattice/interfaces/IERC4337Validation.sol";
import {IAccount, PackedUserOperation} from "@lattice/interfaces/external/IAccount.sol";
import {ECDSA} from "@lattice/utils/libraries/ECDSA.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC4337Validation")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC4337_VALIDATION_STORAGE_SLOT = 0x63f3a16063eb3400d0c49a9883f78e71c0740febe009dfe0af21003612fc2a00;

/// @dev ERC-4337 `validationData` results (low bit): success = 0, signature failure = 1. No time-range in v1.
uint256 constant SIG_VALIDATION_SUCCESS = 0;
uint256 constant SIG_VALIDATION_FAILED = 1;

/// @notice ERC-7201 namespaced storage for the ERC-4337 validation facet.
/// @custom:storage-location erc7201:lattice.storage.ERC4337Validation
struct ERC4337ValidationStorage {
    /// @notice The EntryPoint trusted to call `validateUserOp`. APPEND-ONLY.
    address _entryPoint;
}

/// @title ERC4337ValidationLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Logic + ERC-7201 storage for the ERC-4337 validation facet. `validateUserOp` is gated to the
///         configured EntryPoint, validates the user op signature against the `AccountSigner` owner, and pays
///         the EntryPoint its prefund.
/// @dev The user op signature is checked over the EIP-191 (`personal_sign`) digest of `userOpHash`
///      (SimpleAccount convention), routed through `AccountSignerLib` so the owner may be an EOA or an
///      ERC-1271 contract. Per ERC-4337, a signature mismatch returns `SIG_VALIDATION_FAILED` (1) rather than
///      reverting; only an unauthorized caller reverts. No `validUntil`/`validAfter` time-range in v1.
library ERC4337ValidationLib {
    function erc4337ValidationStorage() internal pure returns (ERC4337ValidationStorage storage $) {
        assembly {
            $.slot := ERC4337_VALIDATION_STORAGE_SLOT
        }
    }

    /// @notice Seeds the trusted EntryPoint during diamond initialization.
    function __ERC4337Validation_init(address entryPoint_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        _setEntryPoint(entryPoint_);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function entryPoint() internal view returns (address) {
        return erc4337ValidationStorage()._entryPoint;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets the trusted EntryPoint. Admin only.
    function setEntryPoint(address entryPoint_) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _setEntryPoint(entryPoint_);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 VALIDATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice ERC-4337 account validation. Only the EntryPoint may call.
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        internal
        returns (uint256 validationData)
    {
        if (msg.sender != erc4337ValidationStorage()._entryPoint) {
            revert IERC4337Validation.NotFromEntryPoint(msg.sender);
        }
        bool ok = AccountSignerLib.isValidSignatureNow(ECDSA.toEthSignedMessageHash(userOpHash), userOp.signature);
        validationData = ok ? SIG_VALIDATION_SUCCESS : SIG_VALIDATION_FAILED;
        _payPrefund(missingAccountFunds);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    function _setEntryPoint(address entryPoint_) private {
        if (entryPoint_ == address(0)) revert IERC4337Validation.InvalidEntryPoint();
        erc4337ValidationStorage()._entryPoint = entryPoint_;
        emit IERC4337Validation.EntryPointSet(entryPoint_);
    }

    /// @notice Pays the EntryPoint (`msg.sender`) its prefund. Result is intentionally ignored: per ERC-4337
    ///         the EntryPoint validates its own balance change, and reverting here would block validation.
    function _payPrefund(uint256 missingAccountFunds) private {
        if (missingAccountFunds != 0) {
            assembly ("memory-safe") {
                pop(call(gas(), caller(), missingAccountFunds, 0x00, 0x00, 0x00, 0x00))
            }
        }
    }
}
