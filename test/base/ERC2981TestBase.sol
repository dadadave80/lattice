// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC2981} from "@lattice-script/base/DeployERC2981.s.sol";
import {ERC2981} from "@lattice/tokens/ERC2981/ERC2981.sol";
import {Test} from "forge-std/Test.sol";

/// @title ERC2981TestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ERC-2981 facet tests that exercise a REAL {Diamond} rather than a flattened inheritance mock.
///         `setUp` assembles the production {DeployERC2981} recipe (ERC165 + AccessControl + ERC2981 +
///         {ERC2981Init}) and exposes a typed `royalty` handle — so every royalty call routes through the
///         diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. No test-only
///         helper facet is needed: the tests drive the public, admin-gated setters (not the raw internal ones).
abstract contract ERC2981TestBase is Test, GetSelectors {
    DeployERC2981 internal deployer;
    address internal diamond; // the assembled royalty diamond
    ERC2981 internal royalty; // typed handle on the diamond (royalty calls dispatch through it)

    /// @notice Assembles the production ERC-2981 diamond with `admin` as the royalty admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed royalty diamond.
    function _deployERC2981(address admin) internal returns (address diamond_) {
        deployer = new DeployERC2981();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
