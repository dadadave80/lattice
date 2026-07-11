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
import {RecipeGuards} from "@lattice-test/composability/RecipeGuards.sol";
import {AcrossBridgeAdapter} from "@lattice/crosschain/AcrossBridgeAdapter.sol";
import {ISuperchainETHBridgeAdapter} from "@lattice/interfaces/crosschain/ISuperchainETHBridgeAdapter.sol";

/// @title RecipeUpgradeabilityCrosschainTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Crosschain-family recipe guards: every diamond these recipes assemble must be introspectable and
///         either admin-upgradeable or immutable BY DESIGN (never silently frozen).
contract RecipeUpgradeabilityCrosschainTest is RecipeGuards {
    TestnetAsset internal asset;

    function setUp() public {
        asset = new TestnetAsset("Guard Asset", "GA");
    }

    function test_Immutable_AcrossBridgeAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployAcrossBridgeAdapter().buildCuts(address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 3);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_AcrossBridgeAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployAcrossBridgeAdapter().buildCuts(address(this), ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        assertEq(AcrossBridgeAdapter(d).spokePool(), address(this), "module init: spoke pool");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_AxelarGatewayAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployAxelarGatewayAdapter().buildCuts(ADMIN, address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_BridgeERC20() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployBridgeERC20().buildCuts(ADMIN, address(asset));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_BridgeERC7802() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployBridgeERC7802().buildCuts(ADMIN, address(asset));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_CCIPGatewayAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployCCIPGatewayAdapter().buildCuts(ADMIN, address(this), address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_CCTPBridgeAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployCCTPBridgeAdapter().buildCuts(ADMIN, address(this), address(this), address(asset));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ChainRegistry() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployChainRegistry().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_CrosschainLink() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployCrosschainLink().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_CrosschainTimelockHandler() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployCrosschainTimelockHandler().buildCuts(ADMIN, 300);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 7);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ERC7786OpenBridge() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC7786OpenBridge().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_HyperbridgeGatewayAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployHyperbridgeGatewayAdapter().buildCuts(ADMIN, address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_HyperlaneGatewayAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployHyperlaneGatewayAdapter().buildCuts(ADMIN, address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_L1ToL2CrossDomainMessengerGatewayAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployL1ToL2CrossDomainMessengerGatewayAdapter().buildCuts(ADMIN, 10, address(this), 100000);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_L2ToL2CrossDomainMessengerGatewayAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployL2ToL2CrossDomainMessengerGatewayAdapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_LayerZeroGatewayAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployLayerZeroGatewayAdapter().buildCuts(ADMIN, address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_StargateBridgeAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployStargateBridgeAdapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_StarknetGatewayAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployStarknetGatewayAdapter().buildCuts(ADMIN, address(this), bytes("SN_SEPOLIA"));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_SuperchainETHBridgeAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeploySuperchainETHBridgeAdapter().buildCuts();
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 3);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_SuperchainETHBridgeAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeploySuperchainETHBridgeAdapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        assertTrue(ERC165Facet(d).supportsInterface(type(ISuperchainETHBridgeAdapter).interfaceId), "module init flag");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_WormholeGatewayAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployWormholeGatewayAdapter().buildCuts(ADMIN, address(this), 2);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ZetaChainGatewayAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployZetaChainGatewayAdapter().buildCuts(ADMIN, address(this), 7000, address(this), 200000);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }
}
