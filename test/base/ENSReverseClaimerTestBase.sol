// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployENSReverseClaimer} from "@lattice-script/base/DeployENSReverseClaimer.s.sol";
import {ENSReverseClaimer} from "@lattice/ens/ENSReverseClaimer.sol";
import {Test} from "forge-std/Test.sol";

/// @title ENSReverseClaimerTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ENS reverse-claimer facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` assembles the production {DeployENSReverseClaimer} recipe (ERC165 +
///         AccessControl + ENSReverseClaimer + {ENSReverseClaimerInit}) with the external reverse registrar wired
///         at init, and exposes a typed `claimer` handle — so `setEnsName` forwards `setName` to the registrar AS
///         the diamond (msg.sender == diamond) through the `delegatecall` dispatch, catching selector/storage/init
///         bugs a mock hides. Role gating is enforced by the cut-in `AccessControl` facet. The external
///         `MockReverseRegistrar` stays a test fixture (it is NOT the facet under test).
abstract contract ENSReverseClaimerTestBase is Test, GetSelectors {
    DeployENSReverseClaimer internal deployer;
    address internal diamond; // the assembled ENS reverse-claimer diamond
    ENSReverseClaimer internal claimer; // typed handle on the diamond (claims dispatch through it)

    /// @notice Assembles the production ENS reverse-claimer diamond with `admin` as the role admin and `registrar`
    ///         wired.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param registrar The external ENS reverse registrar the facet forwards `setName` to.
    /// @return diamond_ The deployed ENS reverse-claimer diamond.
    function _deployENSReverseClaimer(address admin, address registrar) internal returns (address diamond_) {
        deployer = new DeployENSReverseClaimer();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, registrar);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
