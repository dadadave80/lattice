// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib} from "@diamond/libraries/DiamondLib.sol";
import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC6900SignatureLib} from "@lattice/accounts/erc6900/libraries/ERC6900SignatureLib.sol";
import {ERC4337ValidationLib} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {IERC6900Account, IERC6900AccountView} from "@lattice/interfaces/external/IERC6900.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";

/// @title AccountInit6900
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an ERC-6900 modular Diamond account. Delegatecalled by the proxy's
///         `diamondCut` during {Diamond.initialize} (so `address(this)` is the account), it seeds the admin, the
///         EIP-712 domain (for ERC-7739 signature binding), the trusted EntryPoint, and the account's ERC-165
///         interface ids.
/// @dev Unlike the single-owner ERC-7579 `AccountInit` (which self-administers and bootstraps via `AccountSigner`),
///      the ERC-6900 account has no default signer — its authority lives in installed VALIDATION modules. Config
///      (install/uninstall) is admin-gated in {ERC6900ModuleManagerLib}, so admin is granted to the `owner` EOA,
///      which installs the account's validation(s) to make it usable (the counterfactual-userOp bootstrap — an
///      initial validation carried in `initCode` — is wired in the reference-modules + e2e work). The EntryPoint
///      is fixed per factory deployment (immutable, read from this contract's own code even under delegatecall),
///      and is shared with the executor's privileged-caller bypass and the `validateUserOp` path
///      ({ERC4337ValidationLib}).
contract AccountInit6900 {
    /// @notice The EntryPoint every account from this blueprint trusts to call `validateUserOp`.
    address public immutable ENTRY_POINT;

    constructor(address entryPoint_) {
        ENTRY_POINT = entryPoint_;
    }

    /// @notice Runs the account module initializers. MUST be invoked via `diamondCut`'s `_init` delegatecall.
    /// @param owner The account's admin — the authority that installs/uninstalls validations and executions.
    function init(address owner) external {
        // The account is its OWN Ownable owner: diamond-lib's DiamondCutFacet gates on this slot, so the
        // only upgrade path is a validated self-call through the account's execution surface (which the
        // admin `owner` drives) — never a raw external cut. Without this the cut facet was a decoy: the
        // owner slot stayed zero and `diamondCut` reverted `Unauthorized()` forever.
        OwnableLib.initializeOwner(address(this));
        // Advertise the cut + loupe interfaces the blueprint actually routes (IDiamondCut + IDiamondLoupe).
        DiamondLib.registerInterface();
        AccessControlLib.__AccessControl_init(owner);
        EIP712Lib.__EIP712_init("Lattice Modular Account", "1");
        ERC4337ValidationLib.__ERC4337Validation_init(ENTRY_POINT);
        ERC6900SignatureLib.__ERC6900Signature_init();
        ERC165Lib.erc165Storage().supportedInterfaces[type(IERC6900Account).interfaceId] = true;
        ERC165Lib.erc165Storage().supportedInterfaces[type(IERC6900AccountView).interfaceId] = true;
    }
}
