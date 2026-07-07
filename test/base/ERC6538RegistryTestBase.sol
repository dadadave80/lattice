// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC6538Registry} from "@lattice-script/base/privacy/DeployERC6538Registry.s.sol";
import {ERC6538Registry} from "@lattice/privacy/ERC6538Registry.sol";
import {Test} from "forge-std/Test.sol";

/// @title ERC6538RegistryTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ERC-6538 registry facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` assembles the production {DeployERC6538Registry} recipe (ERC165 +
///         ERC6538Registry + {ERC6538RegistryInit}) and exposes a typed `registry` handle — so every registration
///         and the EIP-712 `registerKeysOnBehalf` signature path route through the diamond's `delegatecall`
///         dispatch, catching selector/storage/init bugs a mock hides. The registry facet `is EIP712`, so its ABI
///         already carries `eip712Domain()`; NO separate EIP712 facet is cut (that would collide on selectors).
abstract contract ERC6538RegistryTestBase is Test, GetSelectors {
    DeployERC6538Registry internal deployer;
    address internal diamond; // the assembled registry diamond
    ERC6538Registry internal registry; // typed handle on the diamond (registrations dispatch through it)

    /// @notice Assembles the production ERC-6538 registry diamond.
    /// @return diamond_ The deployed registry diamond.
    function _deployERC6538Registry() internal returns (address diamond_) {
        deployer = new DeployERC6538Registry();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts();

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
