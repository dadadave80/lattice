// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployENSSubnameIssuer} from "@lattice-script/base/ens/DeployENSSubnameIssuer.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {ENSSubnameIssuer} from "@lattice/ens/ENSSubnameIssuer.sol";
import {Test} from "forge-std/Test.sol";

/// @title ENSSubnameIssuerTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ENS subname-issuer facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` assembles the production {DeployENSSubnameIssuer} recipe (ERC165 +
///         AccessControl + ENSSubnameIssuer + {ENSSubnameIssuerInit}) with the external NameWrapper wired at init,
///         and exposes a typed `subnameIssuer` handle — so `issueSubname` forwards `setSubnodeRecord` through the
///         diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. Role gating is
///         enforced by the cut-in `AccessControl` facet. The external `MockNameWrapper` stays a test fixture (it
///         is NOT the facet under test).
abstract contract ENSSubnameIssuerTestBase is Test, GetSelectors {
    DeployENSSubnameIssuer internal deployer;
    address internal diamond; // the assembled ENS subname-issuer diamond
    ENSSubnameIssuer internal subnameIssuer; // typed handle on the diamond (issuance dispatches through it)

    /// @notice Assembles the production ENS subname-issuer diamond with `admin` as the role admin and `wrapper`
    ///         wired.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param wrapper The external ENS NameWrapper the facet forwards `setSubnodeRecord` to.
    /// @return diamond_ The deployed ENS subname-issuer diamond.
    function _deployENSSubnameIssuer(address admin, address wrapper) internal returns (address diamond_) {
        deployer = new DeployENSSubnameIssuer();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, wrapper);

        LatticeDiamond d = new LatticeDiamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
