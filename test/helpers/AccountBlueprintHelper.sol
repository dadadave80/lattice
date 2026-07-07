// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployAccount} from "@lattice-script/base/access/DeployAccount.s.sol";
import {AccountInit} from "@lattice/accounts/erc7579/AccountInit.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Test-side handle on the canonical single-owner ERC-4337 account blueprint. Delegates to the
///         shared {DeployAccount} deploy script so test setup and production deploys build the SAME facet
///         set from one definition (see the Deployment section of the Solidity standards). Kept as a thin
///         `Test` mixin so the factory / 7702 / EntryPoint integration tests keep calling `_accountBlueprint`
///         and keep their `Test` cheatcode base (previously inherited transitively via `GetSelectors`).
abstract contract AccountBlueprintHelper is Test {
    /// @param entryPoint_ The EntryPoint the account's {AccountInit} seeds.
    /// @return cuts The facet cuts (Add) wiring a complete account.
    /// @return init The matching initializer (`init(address)` / `init7702()`).
    function _accountBlueprint(address entryPoint_) internal returns (FacetCut[] memory cuts, AccountInit init) {
        return new DeployAccount().buildCuts(entryPoint_);
    }
}
