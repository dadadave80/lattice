// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployRateLimiter} from "@lattice-script/base/security/DeployRateLimiter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {RateLimiter} from "@lattice/security/RateLimiter.sol";
import {Test} from "forge-std/Test.sol";

/// @title RateLimiterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for RateLimiter facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployRateLimiter} recipe (ERC165 + AccessControl + RateLimiter
///         + the recipe-local init) and exposes a typed `limiter` handle — so every rate-limit call routes through the
///         diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. No test-only
///         helper facet is needed: the tests drive the public facet functions (`configure` is admin-gated in the
///         lib, `consume`/`getConfig`/`getAvailable` are permissionless).
abstract contract RateLimiterTestBase is Test, GetSelectors {
    DeployRateLimiter internal deployer;
    address internal diamond; // the assembled rate-limiter diamond
    RateLimiter internal limiter; // typed handle on the diamond (rate-limit calls dispatch through it)

    /// @notice Assembles the production RateLimiter diamond with `admin` as the rate-limit admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed rate-limiter diamond.
    function _deployRateLimiter(address admin) internal returns (address diamond_) {
        deployer = new DeployRateLimiter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        LatticeDiamond d = new LatticeDiamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
