// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployCrosschainLink} from "@lattice-script/base/crosschain/DeployCrosschainLink.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {CrosschainLink} from "@lattice/crosschain/CrosschainLink.sol";
import {Test} from "forge-std/Test.sol";

/// @title CrosschainLinkTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for CrosschainLink facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` (in the subclass) assembles the production {DeployCrosschainLink} recipe (ERC165 +
///         AccessControl + CrosschainLink + {CrosschainLinkInit}) and exposes a typed `link` handle — so every
///         messaging call routes through the diamond's `delegatecall` dispatch, catching selector/storage/init
///         bugs a mock hides. The external ERC-7786 gateway + message-handler mocks stay test fixtures (they are
///         NOT the facet under test).
abstract contract CrosschainLinkTestBase is Test, GetSelectors {
    DeployCrosschainLink internal deployer;

    /// @notice Assembles the production CrosschainLink diamond with `admin` as the registry admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed crosschain-link diamond.
    function _deployCrosschainLink(address admin) internal returns (address diamond_) {
        deployer = new DeployCrosschainLink();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        LatticeDiamond d = new LatticeDiamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
