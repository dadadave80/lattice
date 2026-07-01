// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployENSResolver} from "@lattice-script/base/DeployENSResolver.s.sol";
import {ENSResolver} from "@lattice/ens/ENSResolver.sol";
import {Test} from "forge-std/Test.sol";

/// @title ENSResolverTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ENS resolver facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployENSResolver} recipe (ERC165 + AccessControl + ENSResolver
///         + {ENSResolverInit}) with the external ENS registry wired at init, and exposes a typed `resolverFacet`
///         handle — so every forward-resolution read routes through the diamond's `delegatecall` dispatch,
///         catching selector/storage/init bugs a mock hides. Role gating is enforced by the cut-in `AccessControl`
///         facet. The external `MockENS`/`MockAddrResolver` stay test fixtures (they are NOT the facet under test).
abstract contract ENSResolverTestBase is Test, GetSelectors {
    DeployENSResolver internal deployer;
    address internal diamond; // the assembled ENS resolver diamond
    ENSResolver internal resolverFacet; // typed handle on the diamond (resolution dispatches through it)

    /// @notice Assembles the production ENS resolver diamond with `admin` as the role admin and `registry` wired.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param registry The external ENS registry the facet reads resolvers from.
    /// @return diamond_ The deployed ENS resolver diamond.
    function _deployENSResolver(address admin, address registry) internal returns (address diamond_) {
        deployer = new DeployENSResolver();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, registry);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
