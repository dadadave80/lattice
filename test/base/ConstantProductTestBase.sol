// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployConstantProduct} from "@lattice-script/base/amm/DeployConstantProduct.s.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {IMintableToken} from "@lattice-test/helpers/IMintableToken.sol";
import {TokenTestFacet} from "@lattice-test/helpers/TokenTestFacet.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {Test} from "forge-std/Test.sol";

/// @title ConstantProductTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Shared base for ConstantProduct AMM facet tests that exercise a REAL {Diamond} rather than a
///         flattened inheritance mock. `_deployPool` assembles the production {DeployConstantProduct} recipe
///         (ERC165 + AccessControl + ConstantProduct + {ConstantProductInit}) over two ERC-20 reserve tokens, so
///         every pool call routes through the diamond's `delegatecall` dispatch — catching selector/storage/init
///         bugs a mock hides. `_deployMintableERC20` spins up a real base ERC-20 diamond (production
///         {DeployERC20} + the test-only {TokenTestFacet} for ungated minting) to use as a pair token, mirroring
///         how the ERC-4626 wave uses a real underlying asset. `_buildPoolCuts` is exposed separately so
///         init-revert tests can target the `Diamond.initialize` call directly. Shared by
///         {ConstantProductTest} and {ConstantProductFeeOnTransferTest}.
abstract contract ConstantProductTestBase is Test, GetSelectors {
    DeployConstantProduct internal poolDeployer;
    DeployERC20 internal tokenDeployer;

    /// @notice Assembles a base ERC-20 diamond + the {TokenTestFacet} so it can be freely minted as a pair token.
    /// @param name_ Token name.
    /// @param symbol_ Token symbol.
    /// @return token_ The deployed mintable ERC-20 diamond.
    function _deployMintableERC20(string memory name_, string memory symbol_) internal returns (address token_) {
        tokenDeployer = new DeployERC20();
        (FacetCut[] memory prod, address init, bytes memory initCalldata) = tokenDeployer.buildCuts(name_, symbol_);

        FacetCut[] memory cuts = new FacetCut[](prod.length + 1);
        for (uint256 i; i < prod.length; ++i) {
            cuts[i] = prod[i];
        }
        cuts[prod.length] = FacetCut({
            facetAddress: address(new TokenTestFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("TokenTestFacet")
        });

        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        token_ = address(d);
    }

    /// @notice Builds the production ConstantProduct pool cuts + initializer (no proxy deploy). Exposed so
    ///         init-revert tests can pre-deploy a {Diamond} and target its `initialize` call under `expectRevert`.
    /// @param admin_ The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param tokenA_ One of the two pool reserve tokens.
    /// @param tokenB_ The other pool reserve token.
    function _buildPoolCuts(address admin_, address tokenA_, address tokenB_)
        internal
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        poolDeployer = new DeployConstantProduct();
        return poolDeployer.buildCuts(admin_, tokenA_, tokenB_);
    }

    /// @notice Assembles the production ConstantProduct pool diamond over (tokenA_, tokenB_) with `admin_`.
    /// @return pool_ The deployed pool diamond.
    function _deployPool(address admin_, address tokenA_, address tokenB_) internal returns (address pool_) {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = _buildPoolCuts(admin_, tokenA_, tokenB_);
        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        pool_ = address(d);
    }
}
