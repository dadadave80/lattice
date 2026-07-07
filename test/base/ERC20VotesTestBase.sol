// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20Votes} from "@lattice-script/base/DeployERC20Votes.s.sol";
import {ERC20VotesTestFacet} from "@lattice-test/helpers/ERC20VotesTestFacet.sol";
import {Test} from "forge-std/Test.sol";

/// @title ERC20VotesTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for {ERC20Votes} facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `_deployERC20Votes` assembles the production {DeployERC20Votes} recipe (ERC165 + ERC20 +
///         ERC20Votes[Replace transfer/transferFrom + Add votes surface] + AccessControl, seeded by {ERC20Init}
///         and {ERC20VotesInit}) and appends the test-only {ERC20VotesTestFacet} exposing the checkpoint/cap
///         `mint`/`burn` and the `nonces`/`DOMAIN_SEPARATOR` reads — so every delegation, checkpoint, and
///         `delegateBySig` call routes through the diamond's `delegatecall` dispatch, running every initializer in
///         one window via {MultiInit} (the same composition {BaseDeploy._assembleMulti} performs in production).
abstract contract ERC20VotesTestBase is Test, GetSelectors {
    DeployERC20Votes internal deployer;
    address internal diamond; // the assembled votes ERC-20 token diamond

    /// @notice Assembles the production votes ERC-20 diamond + the test helper facet.
    /// @param name_ Token name (also the EIP-712 domain name). @param symbol_ Token symbol.
    /// @param admin The address granted DEFAULT_ADMIN_ROLE.
    /// @return diamond_ The deployed votes token diamond.
    function _deployERC20Votes(string memory name_, string memory symbol_, address admin)
        internal
        returns (address diamond_)
    {
        deployer = new DeployERC20Votes();
        (FacetCut[] memory prod, address[] memory inits, bytes[] memory initCalldatas) =
            deployer.buildCuts(name_, symbol_, admin);

        FacetCut[] memory cuts = new FacetCut[](prod.length + 1);
        for (uint256 i; i < prod.length; ++i) {
            cuts[i] = prod[i];
        }
        cuts[prod.length] = FacetCut({
            facetAddress: address(new ERC20VotesTestFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("ERC20VotesTestFacet")
        });

        MultiInit multiInit = new MultiInit();
        Diamond d = new Diamond();
        d.initialize(cuts, address(multiInit), abi.encodeCall(MultiInit.multiInit, (inits, initCalldatas)));
        diamond_ = address(d);
    }
}
