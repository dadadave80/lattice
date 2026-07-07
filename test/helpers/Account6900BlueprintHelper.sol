// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployAccount6900} from "@lattice-script/base/access/DeployAccount6900.s.sol";
import {AccountInit6900} from "@lattice/accounts/erc6900/AccountInit6900.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Test-side handle on the canonical ERC-6900 modular-account blueprint. Delegates to the shared
///         {DeployAccount6900} deploy script so test setup and production deploys build the SAME facet set
///         from one definition. Kept as a thin `Test` mixin so {AccountFactory6900} tests keep calling
///         `_accountBlueprint6900` and keep their `Test` cheatcode base (previously via `GetSelectors`).
abstract contract Account6900BlueprintHelper is Test {
    /// @param entryPoint_ The EntryPoint the account's {AccountInit6900} seeds.
    /// @return cuts The facet cuts (Add) wiring a complete ERC-6900 account.
    /// @return init The matching initializer (`init(address owner)`).
    function _accountBlueprint6900(address entryPoint_)
        internal
        returns (FacetCut[] memory cuts, AccountInit6900 init)
    {
        return new DeployAccount6900().buildCuts(entryPoint_);
    }
}
