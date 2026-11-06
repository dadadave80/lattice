// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// AUTO-STRUCTURED guard suite — one test per deploy recipe (see RecipeGuards).
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployAcrossBridgeAdapter} from "@lattice-script/base/crosschain/DeployAcrossBridgeAdapter.s.sol";
import {DeployAxelarGatewayAdapter} from "@lattice-script/base/crosschain/DeployAxelarGatewayAdapter.s.sol";
import {DeployBridgeERC20} from "@lattice-script/base/crosschain/DeployBridgeERC20.s.sol";
import {DeployBridgeERC7802} from "@lattice-script/base/crosschain/DeployBridgeERC7802.s.sol";
import {DeployCCIPGatewayAdapter} from "@lattice-script/base/crosschain/DeployCCIPGatewayAdapter.s.sol";
import {DeployCCTPBridgeAdapter} from "@lattice-script/base/crosschain/DeployCCTPBridgeAdapter.s.sol";
import {DeployChainRegistry} from "@lattice-script/base/crosschain/DeployChainRegistry.s.sol";
import {DeployCrosschainLink} from "@lattice-script/base/crosschain/DeployCrosschainLink.s.sol";
import {DeployCrosschainTimelockHandler} from "@lattice-script/base/crosschain/DeployCrosschainTimelockHandler.s.sol";
import {DeployERC7786OpenBridge} from "@lattice-script/base/crosschain/DeployERC7786OpenBridge.s.sol";
import {DeployHyperbridgeGatewayAdapter} from "@lattice-script/base/crosschain/DeployHyperbridgeGatewayAdapter.s.sol";
import {DeployHyperlaneGatewayAdapter} from "@lattice-script/base/crosschain/DeployHyperlaneGatewayAdapter.s.sol";
import {
    DeployL1ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice-script/base/crosschain/DeployL1ToL2CrossDomainMessengerGatewayAdapter.s.sol";
import {
    DeployL2ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice-script/base/crosschain/DeployL2ToL2CrossDomainMessengerGatewayAdapter.s.sol";
import {DeployLayerZeroGatewayAdapter} from "@lattice-script/base/crosschain/DeployLayerZeroGatewayAdapter.s.sol";
import {DeployStargateBridgeAdapter} from "@lattice-script/base/crosschain/DeployStargateBridgeAdapter.s.sol";
import {DeployStarknetGatewayAdapter} from "@lattice-script/base/crosschain/DeployStarknetGatewayAdapter.s.sol";
import {DeploySuperchainETHBridgeAdapter} from "@lattice-script/base/crosschain/DeploySuperchainETHBridgeAdapter.s.sol";
import {DeployWormholeGatewayAdapter} from "@lattice-script/base/crosschain/DeployWormholeGatewayAdapter.s.sol";
import {DeployZetaChainGatewayAdapter} from "@lattice-script/base/crosschain/DeployZetaChainGatewayAdapter.s.sol";
import {TestnetAsset} from "@lattice-script/base/defi/DeployGovernedVaultENS.s.sol";
import {RecipeConsistencyGuards} from "@lattice-test/composability/RecipeConsistencyGuards.sol";
import {AcrossBridgeAdapter} from "@lattice/crosschain/across/AcrossBridgeAdapter.sol";
import {ISuperchainETHBridgeAdapter} from "@lattice/interfaces/crosschain/ISuperchainETHBridgeAdapter.sol";

/// @title RecipeUpgradeabilityCrosschainTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Crosschain-family recipe guards: every diamond these recipes assemble must be introspectable and
///         either admin-upgradeable or immutable BY DESIGN (never silently frozen).
contract RecipeUpgradeabilityCrosschainTest is RecipeConsistencyGuards {
    TestnetAsset internal asset;

    function setUp() public {
        asset = new TestnetAsset("Guard Asset", "GA");
    }

    function test_Immutable_AcrossBridgeAdapter() public {
        _expectRecipe(new DeployAcrossBridgeAdapter().recipeSpec(), 0, "DeployAcrossBridgeAdapter");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployAcrossBridgeAdapter().buildCuts(address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 3);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_AcrossBridgeAdapter() public {
        _expectRecipe(new DeployAcrossBridgeAdapter().recipeSpec(), 1, "DeployAcrossBridgeAdapter");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployAcrossBridgeAdapter().buildCuts(address(this), ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        assertEq(AcrossBridgeAdapter(d).spokePool(), address(this), "module init: spoke pool");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_AxelarGatewayAdapter() public {
        _expectRecipe(new DeployAxelarGatewayAdapter().recipeSpec(), 0, "DeployAxelarGatewayAdapter");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployAxelarGatewayAdapter().buildCuts(ADMIN, address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_BridgeERC20() public {
        _expectRecipe(new DeployBridgeERC20().recipeSpec(), 0, "DeployBridgeERC20");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployBridgeERC20().buildCuts(ADMIN, address(asset));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_BridgeERC7802() public {
        _expectRecipe(new DeployBridgeERC7802().recipeSpec(), 0, "DeployBridgeERC7802");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployBridgeERC7802().buildCuts(ADMIN, address(asset));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_CCIPGatewayAdapter() public {
        _expectRecipe(new DeployCCIPGatewayAdapter().recipeSpec(), 0, "DeployCCIPGatewayAdapter");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployCCIPGatewayAdapter().buildCuts(ADMIN, address(this), address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_CCTPBridgeAdapter() public {
        _expectRecipe(new DeployCCTPBridgeAdapter().recipeSpec(), 0, "DeployCCTPBridgeAdapter");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployCCTPBridgeAdapter().buildCuts(ADMIN, address(this), address(this), address(asset));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ChainRegistry() public {
        _expectRecipe(new DeployChainRegistry().recipeSpec(), 0, "DeployChainRegistry");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployChainRegistry().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_CrosschainLink() public {
        _expectRecipe(new DeployCrosschainLink().recipeSpec(), 0, "DeployCrosschainLink");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployCrosschainLink().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_CrosschainTimelockHandler() public {
        _expectRecipe(new DeployCrosschainTimelockHandler().recipeSpec(), 0, "DeployCrosschainTimelockHandler");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployCrosschainTimelockHandler().buildCuts(ADMIN, 300);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 8);
        _assertBareEth(d, true);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ERC7786OpenBridge() public {
        _expectRecipe(new DeployERC7786OpenBridge().recipeSpec(), 0, "DeployERC7786OpenBridge");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC7786OpenBridge().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_HyperbridgeGatewayAdapter() public {
        _expectRecipe(new DeployHyperbridgeGatewayAdapter().recipeSpec(), 0, "DeployHyperbridgeGatewayAdapter");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployHyperbridgeGatewayAdapter().buildCuts(ADMIN, address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_HyperlaneGatewayAdapter() public {
        _expectRecipe(new DeployHyperlaneGatewayAdapter().recipeSpec(), 0, "DeployHyperlaneGatewayAdapter");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployHyperlaneGatewayAdapter().buildCuts(ADMIN, address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_L1ToL2CrossDomainMessengerGatewayAdapter() public {
        _expectRecipe(
            new DeployL1ToL2CrossDomainMessengerGatewayAdapter().recipeSpec(),
            0,
            "DeployL1ToL2CrossDomainMessengerGatewayAdapter"
        );
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployL1ToL2CrossDomainMessengerGatewayAdapter().buildCuts(ADMIN, 10, address(this), 100000);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_L2ToL2CrossDomainMessengerGatewayAdapter() public {
        _expectRecipe(
            new DeployL2ToL2CrossDomainMessengerGatewayAdapter().recipeSpec(),
            0,
            "DeployL2ToL2CrossDomainMessengerGatewayAdapter"
        );
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployL2ToL2CrossDomainMessengerGatewayAdapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_LayerZeroGatewayAdapter() public {
        _expectRecipe(new DeployLayerZeroGatewayAdapter().recipeSpec(), 0, "DeployLayerZeroGatewayAdapter");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployLayerZeroGatewayAdapter().buildCuts(ADMIN, address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_StargateBridgeAdapter() public {
        _expectRecipe(new DeployStargateBridgeAdapter().recipeSpec(), 0, "DeployStargateBridgeAdapter");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployStargateBridgeAdapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_StarknetGatewayAdapter() public {
        _expectRecipe(new DeployStarknetGatewayAdapter().recipeSpec(), 0, "DeployStarknetGatewayAdapter");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployStarknetGatewayAdapter().buildCuts(ADMIN, address(this), bytes("SN_SEPOLIA"));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_SuperchainETHBridgeAdapter() public {
        _expectRecipe(new DeploySuperchainETHBridgeAdapter().recipeSpec(), 0, "DeploySuperchainETHBridgeAdapter");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeploySuperchainETHBridgeAdapter().buildCuts();
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 3);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_SuperchainETHBridgeAdapter() public {
        _expectRecipe(new DeploySuperchainETHBridgeAdapter().recipeSpec(), 1, "DeploySuperchainETHBridgeAdapter");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeploySuperchainETHBridgeAdapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        assertTrue(ERC165Facet(d).supportsInterface(type(ISuperchainETHBridgeAdapter).interfaceId), "module init flag");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_WormholeGatewayAdapter() public {
        _expectRecipe(new DeployWormholeGatewayAdapter().recipeSpec(), 0, "DeployWormholeGatewayAdapter");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployWormholeGatewayAdapter().buildCuts(ADMIN, address(this), 2);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ZetaChainGatewayAdapter() public {
        _expectRecipe(new DeployZetaChainGatewayAdapter().recipeSpec(), 0, "DeployZetaChainGatewayAdapter");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployZetaChainGatewayAdapter().buildCuts(ADMIN, address(this), 7000, address(this), 200000);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }
}
