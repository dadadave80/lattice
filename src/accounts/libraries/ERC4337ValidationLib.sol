// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC7579ModuleConfigLib} from "@lattice/accounts/erc7579/libraries/ERC7579ModuleConfigLib.sol";
import {AccountSignerLib} from "@lattice/accounts/libraries/AccountSignerLib.sol";
import {IERC4337Validation} from "@lattice/interfaces/accounts/IERC4337Validation.sol";
import {IAccount, PackedUserOperation} from "@lattice/interfaces/external/IAccount.sol";
import {IERC7579Validator, MODULE_TYPE_VALIDATOR} from "@lattice/interfaces/external/IERC7579.sol";
import {ECDSA} from "@lattice/utils/libraries/ECDSA.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC4337Validation")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC4337_VALIDATION_STORAGE_SLOT = 0x63f3a16063eb3400d0c49a9883f78e71c0740febe009dfe0af21003612fc2a00;

/// @dev ERC-4337 `validationData` results (low bit): success = 0, signature failure = 1. No time-range in v1.
uint256 constant SIG_VALIDATION_SUCCESS = 0;
uint256 constant SIG_VALIDATION_FAILED = 1;

/// @dev The blessed default EntryPoint (#58 item 9): ERC-4337 **v0.9** (eth-infinitism singleton, deployed
///      2025-12-22). The account stores its own EntryPoint (set at init, admin-mutable), so this is only the
///      deploy default — never hardcoded into validation. Other canonical singletons, for reference:
///      v0.7 = `0x0000000071727De22E5E9d8BAf0edAc6f37da032`,
///      v0.8 = `0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108` (native EIP-7702).
///      NOTE: v0.9 redefined `nonReentrant` as `tx.origin == msg.sender && msg.sender.code.length == 0`, so
///      `handleOps` is only callable as a top-level tx from a code-less EOA bundler — contract relayers and
///      EIP-7702-delegated EOAs (`code.length == 23`) cannot submit ops directly.
address constant DEFAULT_ENTRY_POINT = 0x433709009B8330FDa32311DF1C2AFA402eD8D009;

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
        // ERC-7579 validator routing (#58 follow-on): the top 20 bytes of the nonce select an installed
        // VALIDATOR module, which returns the packed validationData. A zero / uninstalled selector falls back
        // to the default single-owner path (the `AccountSigner`), so existing key-0 ops are unchanged.
        address validator = address(bytes20(bytes32(userOp.nonce)));
        if (validator != address(0) && ERC7579ModuleConfigLib.isInstalled(MODULE_TYPE_VALIDATOR, validator)) {
            validationData = IERC7579Validator(validator).validateUserOp(userOp, userOpHash);
        } else {
            bool ok = AccountSignerLib.isValidSignatureNow(ECDSA.toEthSignedMessageHash(userOpHash), userOp.signature);
            validationData = ok ? SIG_VALIDATION_SUCCESS : SIG_VALIDATION_FAILED;
        }
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
