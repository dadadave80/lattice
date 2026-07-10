// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20Crosschain} from "@lattice-script/base/tokens/DeployERC20Crosschain.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {TokenTestFacet} from "@lattice-test/helpers/TokenTestFacet.sol";
import {Test} from "forge-std/Test.sol";

/// @title ERC20CrosschainTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for self-bridging ERC-20 facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` (in the subclass) assembles the production {DeployERC20Crosschain} recipe
///         (ERC165 + ERC20 + AccessControl + CrosschainLink + ERC20Crosschain + {ERC20CrosschainInit}) and
///         appends a test-only {TokenTestFacet} so an initial supply can be seeded — while every crosschain
///         send/receive still routes through the diamond's `delegatecall` dispatch, catching selector/storage/
///         init bugs a mock hides.
abstract contract ERC20CrosschainTestBase is Test, GetSelectors {
    DeployERC20Crosschain internal deployer;
    address internal diamond; // the assembled self-bridging ERC-20 diamond
    TokenTestFacet internal helper; // typed handle for test-only supply seeding

    /// @notice Builds the test-only {TokenTestFacet} cut appended on top of the production recipe.
    function _helperCut() internal returns (FacetCut memory) {
        return FacetCut({
            facetAddress: address(new TokenTestFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("TokenTestFacet")
        });
    }

    /// @notice Assembles the production self-bridging ERC-20 diamond + the test helper facet.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param name_ Token name. @param symbol_ Token symbol.
    /// @return diamond_ The deployed token diamond.
    function _deployERC20Crosschain(address admin, string memory name_, string memory symbol_)
        internal
        returns (address diamond_)
    {
        deployer = new DeployERC20Crosschain();
        (FacetCut[] memory prod, address init, bytes memory initCalldata) = deployer.buildCuts(admin, name_, symbol_);

        FacetCut[] memory cuts = new FacetCut[](prod.length + 1);
        for (uint256 i; i < prod.length; ++i) {
            cuts[i] = prod[i];
        }
        cuts[prod.length] = _helperCut();

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
        helper = TokenTestFacet(diamond_);
    }
}
