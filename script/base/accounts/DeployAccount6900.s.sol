// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondCutFacet} from "@diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {Receive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccountInit6900} from "@lattice/accounts/erc6900/AccountInit6900.sol";
import {ERC6900AccountView} from "@lattice/accounts/erc6900/ERC6900AccountView.sol";
import {ERC6900Executor} from "@lattice/accounts/erc6900/ERC6900Executor.sol";
import {ERC6900ModuleManager} from "@lattice/accounts/erc6900/ERC6900ModuleManager.sol";
import {ERC6900Signature} from "@lattice/accounts/erc6900/ERC6900Signature.sol";
import {ERC6900Validation} from "@lattice/accounts/erc6900/ERC6900Validation.sol";

/// @title DeployAccount6900
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Canonical ERC-6900 modular-account composition (10 facets + {AccountInit6900}) — the ONE source
///         of truth shared by production deploys and the {AccountFactory6900} test blueprint. The shared
///         Diamond core (cut/loupe/erc165/access) plus the five 6900 facets (module manager, executor,
///         userOp validation, signature, account view) replace the ERC-7579 stack. Companion to
///         {DeployAccount}; see it for the broadcast-free {buildCuts} vs broadcasting {run} split.
contract DeployAccount6900 is BaseDeploy {
    /// @notice Builds the canonical ERC-6900 account facet cuts + initializer (no broadcast, no proxy deploy).
    /// @param entryPoint_ The EntryPoint the account's {AccountInit6900} seeds.
    /// @return cuts The 10 facet cuts (Add) wiring a complete ERC-6900 account.
    /// @return init The matching initializer (`init(address owner)`).
    function buildCuts(address entryPoint_) public returns (FacetCut[] memory cuts, AccountInit6900 init) {
        cuts = new FacetCut[](10);
        cuts[0] = _cut(address(new DiamondCutFacet()), "DiamondCutFacet");
        cuts[1] = _cut(address(new DiamondLoupeFacet()), "DiamondLoupeFacet");
        cuts[2] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[3] = _cut(address(new AccessControl()));
        cuts[4] = _cut(address(new ERC6900ModuleManager()));
        cuts[5] = _cut(address(new ERC6900Executor()));
        cuts[6] = _cut(address(new ERC6900Validation()));
        cuts[7] = _cut(address(new ERC6900Signature()));
        cuts[8] = _cut(address(new ERC6900AccountView()));
        cuts[9] = _cut(address(new Receive()));
        init = new AccountInit6900(entryPoint_);
    }

    /// @notice Deploys a complete ERC-6900 account diamond and initializes it for `owner`.
    /// @param entryPoint_ The EntryPoint seeded into the account.
    /// @param owner The account's initial owner.
    /// @return account The deployed account diamond address.
    function run(address entryPoint_, address owner) external returns (address account) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, AccountInit6900 init) = buildCuts(entryPoint_);
        Lattice diamond = new Lattice();
        diamond.initialize(cuts, address(init), abi.encodeCall(AccountInit6900.init, (owner)));
        vm.stopBroadcast();
        account = address(diamond);
    }
}
