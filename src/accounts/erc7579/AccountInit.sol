// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib} from "@diamond/libraries/DiamondLib.sol";
import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC7821ExecutorLib} from "@lattice/accounts/erc7579/libraries/ERC7821ExecutorLib.sol";
import {AccountSignerLib} from "@lattice/accounts/libraries/AccountSignerLib.sol";
import {ERC1271SignatureLib} from "@lattice/accounts/libraries/ERC1271SignatureLib.sol";
import {ERC4337ValidationLib} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";

/// @title AccountInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a single-owner ERC-4337 Diamond account. Delegatecalled by the proxy's
///         `diamondCut` during {Diamond.initialize} (so `address(this)` is the account), it seeds the owner,
///         the trusted EntryPoint, and registers the account interfaces.
/// @dev The EntryPoint is fixed per factory deployment (immutable, read from this contract's own code even
///      under delegatecall). The account administers itself — `DEFAULT_ADMIN_ROLE` is granted to the account
///      address, AND the account is its own diamond-lib Ownable owner (the {DiamondCutFacet} gate), so
///      owner/EntryPoint/module changes AND upgrades flow through the validated execution path (a self-call
///      via the ERC-7821 executor / EntryPoint), never a raw external admin. Without the `initializeOwner`
///      step the blueprint's cut facet was a decoy: the owner slot stayed zero and `diamondCut` reverted
///      `Unauthorized()` for every caller, freezing the account forever. `init` is safe to expose: each
///      `__*_init` asserts the initializing window, so a direct call (outside a `diamondCut`) reverts.
contract AccountInit {
    /// @notice The EntryPoint every account from this blueprint trusts to call `validateUserOp`.
    address public immutable ENTRY_POINT;

    constructor(address entryPoint_) {
        ENTRY_POINT = entryPoint_;
    }

    /// @notice Runs the account module initializers. MUST be invoked via `diamondCut`'s `_init` delegatecall.
    /// @param owner The account's initial ECDSA signing owner.
    function init(address owner) external {
        _init(owner);
    }

    /// @notice EIP-7702 onboarding (#58 item 7): identical to {init} but the owner is the account itself — i.e.
    ///         the delegated EOA, whose own key is the signer. Taking no owner argument keeps the `0x7702`
    ///         initCode uniform for every EOA. Runs against the EOA's own storage via its 7702 delegate code.
    /// @dev SECURITY — onboarding MUST be atomic. The bare {Diamond} `initialize` that delegatecalls this is
    ///      ungated, so the 7702 authorization MUST be bundled into the SAME transaction as the first UserOp
    ///      (the standard 4337+7702 flow: the auth in the `handleOps` tx's `authorization_list`). Then
    ///      delegation + init run in one tx and cannot be front-run. Applying the delegation in a SEPARATE,
    ///      earlier tx and leaving the account uninitialized opens a window where anyone can initialize it with
    ///      a hostile blueprint. Integrators who cannot guarantee atomicity should delegate to
    ///      {Account7702Diamond} instead, whose signed onboarding closes that window on-chain.
    function init7702() external {
        _init(address(this));
    }

    function _init(address owner) private {
        // The account is its OWN Ownable owner: diamond-lib's DiamondCutFacet gates on this slot, so the
        // only upgrade path is a validated self-call (executor / EntryPoint) — never an external EOA.
        OwnableLib.initializeOwner(address(this));
        // Advertise the cut + loupe interfaces the blueprint actually routes (IDiamondCut + IDiamondLoupe).
        DiamondLib.registerInterface();
        AccessControlLib.__AccessControl_init(address(this));
        AccountSignerLib.__AccountSigner_init(owner);
        ERC4337ValidationLib.__ERC4337Validation_init(ENTRY_POINT);
        ERC1271SignatureLib.__ERC1271Signature_init();
        ERC7821ExecutorLib.__ERC7821Executor_init();
    }
}
