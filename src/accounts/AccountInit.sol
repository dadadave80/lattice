// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AccountSignerLib} from "@lattice/accounts/libraries/AccountSignerLib.sol";
import {ERC1271SignatureLib} from "@lattice/accounts/libraries/ERC1271SignatureLib.sol";
import {ERC4337ValidationLib} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {ERC7821ExecutorLib} from "@lattice/accounts/libraries/ERC7821ExecutorLib.sol";

/// @title AccountInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a single-owner ERC-4337 Diamond account. Delegatecalled by the proxy's
///         `diamondCut` during {Diamond.initialize} (so `address(this)` is the account), it seeds the owner,
///         the trusted EntryPoint, and registers the account interfaces.
/// @dev The EntryPoint is fixed per factory deployment (immutable, read from this contract's own code even
///      under delegatecall). The account administers itself — `DEFAULT_ADMIN_ROLE` is granted to the account
///      address, so owner/EntryPoint/module changes flow through the validated execution path, never a raw
///      external admin. `init` is safe to expose: each `__*_init` asserts the initializing window, so a direct
///      call (outside a `diamondCut`) reverts.
contract AccountInit {
    /// @notice The EntryPoint every account from this blueprint trusts to call `validateUserOp`.
    address public immutable ENTRY_POINT;

    constructor(address entryPoint_) {
        ENTRY_POINT = entryPoint_;
    }

    /// @notice Runs the account module initializers. MUST be invoked via `diamondCut`'s `_init` delegatecall.
    /// @param owner The account's initial ECDSA signing owner.
    function init(address owner) external {
        AccessControlLib.__AccessControl_init(address(this));
        AccountSignerLib.__AccountSigner_init(owner);
        ERC4337ValidationLib.__ERC4337Validation_init(ENTRY_POINT);
        ERC1271SignatureLib.__ERC1271Signature_init();
        ERC7821ExecutorLib.__ERC7821Executor_init();
    }
}
