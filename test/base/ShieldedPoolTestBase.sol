// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployShieldedPool} from "@lattice-script/base/privacy/DeployShieldedPool.s.sol";
import {ShieldedPool} from "@lattice/privacy/ShieldedPool.sol";
import {Test} from "forge-std/Test.sol";

/// @title ShieldedPoolTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ShieldedPool facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployShieldedPool} recipe (ERC165 + AccessControl +
///         ShieldedPool + {ShieldedPoolInit}) and exposes a typed `pool` handle — so every deposit/withdraw call
///         routes through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides.
///         The pool's ERC-20 token and Groth16 withdraw verifier stay external test fixtures (they are NOT the
///         facet under test).
abstract contract ShieldedPoolTestBase is Test, GetSelectors {
    DeployShieldedPool internal deployer;
    address internal diamond; // the assembled shielded-pool diamond
    ShieldedPool internal pool; // typed handle on the diamond (deposit/withdraw calls dispatch through it)

    /// @notice Assembles the production ShieldedPool diamond with `admin` as the pool admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls `createPool`).
    /// @return diamond_ The deployed shielded-pool diamond.
    function _deployShieldedPool(address admin) internal returns (address diamond_) {
        deployer = new DeployShieldedPool();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
