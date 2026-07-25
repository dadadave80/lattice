// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeploySafeHarborAdopter} from "@lattice-script/base/governance/DeploySafeHarborAdopter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {SafeHarborAdopter} from "@lattice/governance/SafeHarborAdopter.sol";
import {Test} from "forge-std/Test.sol";

/// @title SafeHarborAdopterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for SafeHarborAdopter facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` assembles the production {DeploySafeHarborAdopter} recipe (ERC165 +
///         AccessControl + SafeHarborAdopter + {SafeHarborAdopterInit}) onto a fresh `Diamond` and exposes a
///         typed `adopter` handle — so every adoption/configuration call routes through the diamond's
///         `delegatecall` dispatch (with `msg.sender == diamond` toward the SEAL registry), catching
///         selector/storage/init bugs a mock hides. No test-only helper facet is needed: the tests drive the
///         public, admin-gated facet functions. `_buildCuts` is exposed so tests can assert init-time reverts.
abstract contract SafeHarborAdopterTestBase is Test, GetSelectors {
    DeploySafeHarborAdopter internal deployer;

    /// @notice Builds the production SafeHarborAdopter cuts + initializer without assembling a diamond, so a
    ///         test can drive `Diamond.initialize` directly and assert an init-time revert.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param registry The SEAL SafeHarborRegistry (zero to trigger the init revert path).
    /// @param factory The SEAL AgreementFactory (zero allowed).
    function _buildCuts(address admin, address registry, address factory)
        internal
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        deployer = new DeploySafeHarborAdopter();
        (cuts, init, initCalldata) = deployer.buildCuts(admin, registry, factory);
    }

    /// @notice Assembles the production SafeHarborAdopter diamond with `admin` as root admin and the SEAL
    ///         registry + factory wired at init.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param registry The SEAL SafeHarborRegistry for this chain (must be non-zero).
    /// @param factory The SEAL AgreementFactory for this chain (zero allowed).
    /// @return diamond_ The deployed Safe Harbor adopter diamond.
    function _deploySafeHarborAdopter(address admin, address registry, address factory)
        internal
        returns (address diamond_)
    {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = _buildCuts(admin, registry, factory);

        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
