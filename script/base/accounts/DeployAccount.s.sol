// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {AccountDeployBase} from "@lattice-script/base/accounts/AccountDeployBase.s.sol";
import {AccountReleaseInventory} from "@lattice-script/lib/AccountReleaseInventory.sol";
import {LatticeVersion} from "@lattice/LatticeVersion.sol";
import {AccountInit} from "@lattice/accounts/erc7579/AccountInit.sol";
import {DEFAULT_ENTRY_POINT} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {IAccountFactory} from "@lattice/interfaces/accounts/IAccountFactory.sol";

/// @title DeployAccount
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Canonical single-owner ERC-4337/7579 account recipe. The shared release blueprint fixes its facet set;
///         the EntryPoint-specific factory creates and initializes the specialized fallback proxy atomically.
/// @dev Canonical EntryPoints reuse the release's constructor-bound init/factory identities. Other EntryPoints
///      use an explicit custom identity whose initcode still binds the EntryPoint and ordered blueprint.
contract DeployAccount is AccountDeployBase {
    /// @notice Build released facet cuts and the constructor-bound initializer, without creating an account.
    /// @param entryPoint_ Trusted ERC-4337 EntryPoint; chain availability is a deployment precondition.
    function buildCuts(address entryPoint_) public returns (FacetCut[] memory cuts, AccountInit init) {
        cuts = _accountCuts(false, LatticeVersion.VERSION);
        init = AccountInit(_accountInit(AccountReleaseInventory.describe(false, entryPoint_), LatticeVersion.VERSION));
    }

    /// @notice Resolve or deploy the specialized account factory for this exact EntryPoint and blueprint.
    function buildFactory(address entryPoint_) public returns (IAccountFactory factory) {
        (,, address at) = _accountRelease(AccountReleaseInventory.describe(false, entryPoint_), LatticeVersion.VERSION);
        factory = IAccountFactory(at);
    }

    /// @notice Create an account, or return the existing account for the same owner and LATTICE_SALT.
    function run(address entryPoint_, address owner) external returns (address account) {
        return _run(entryPoint_, owner, vm.envOr("LATTICE_SALT", bytes32(0)));
    }

    /// @notice Explicit-salt deployment, with the same idempotent semantics as the account factory.
    function run(address entryPoint_, address owner, bytes32 salt) external returns (address account) {
        return _run(entryPoint_, owner, salt);
    }

    /// @notice Use the repository's default EntryPoint (v0.9).
    function run(address owner) external returns (address account) {
        return _run(DEFAULT_ENTRY_POINT, owner, vm.envOr("LATTICE_SALT", bytes32(0)));
    }

    function _run(address entryPoint_, address owner, bytes32 salt) private returns (address account) {
        vm.startBroadcast();
        account = buildFactory(entryPoint_).createAccount(owner, salt);
        vm.stopBroadcast();
    }
}
