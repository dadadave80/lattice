// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployAccount} from "@lattice-script/base/accounts/DeployAccount.s.sol";
import {AccountInit} from "@lattice/accounts/erc7579/AccountInit.sol";
import {Test} from "forge-std/Test.sol";

/// @title Base
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Shared test base that builds the system through the SAME deploy code production uses — the
///         `BaseTest`-using-scripts pattern from the Solidity standards' Deployment section, and the token
///         analog of diamond-lib's {DeployedDiamondState}. `setUp` composes a default single-owner account
///         diamond from the canonical {DeployAccount} blueprint (so test setup can never drift from the
///         deploy path). Subclasses override `entryPoint`/`owner`, or the whole `setUp`, as needed; new
///         system-level tests should extend this instead of re-assembling facet cuts by hand.
abstract contract Base is Test {
    DeployAccount internal deployAccount;
    address internal account; // the assembled single-owner account diamond
    address internal owner = address(this);
    address internal entryPoint = address(0xE117); // placeholder; override for EntryPoint-dependent tests

    function setUp() public virtual {
        deployAccount = new DeployAccount();
        (FacetCut[] memory cuts, AccountInit init) = deployAccount.buildCuts(entryPoint);
        Diamond diamond = new Diamond();
        diamond.initialize(cuts, address(init), abi.encodeCall(AccountInit.init, (owner)));
        account = address(diamond);
    }
}
