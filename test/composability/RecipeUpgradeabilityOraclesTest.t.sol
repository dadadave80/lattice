// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// AUTO-STRUCTURED guard suite — one test per deploy recipe (see RecipeGuards).
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {TestnetAsset} from "@lattice-script/base/defi/DeployGovernedVaultENS.s.sol";
import {DeployAPI3Adapter} from "@lattice-script/base/oracles/DeployAPI3Adapter.s.sol";
import {DeployAPI3QRNGAdapter} from "@lattice-script/base/oracles/DeployAPI3QRNGAdapter.s.sol";
import {DeployBandAdapter} from "@lattice-script/base/oracles/DeployBandAdapter.s.sol";
import {DeployChainlinkAdapter} from "@lattice-script/base/oracles/DeployChainlinkAdapter.s.sol";
import {DeployChainlinkAutomationAdapter} from "@lattice-script/base/oracles/DeployChainlinkAutomationAdapter.s.sol";
import {DeployChainlinkCREAdapter} from "@lattice-script/base/oracles/DeployChainlinkCREAdapter.s.sol";
import {DeployChainlinkVRF} from "@lattice-script/base/oracles/DeployChainlinkVRF.s.sol";
import {DeployChronicleAdapter} from "@lattice-script/base/oracles/DeployChronicleAdapter.s.sol";
import {DeployDIAAdapter} from "@lattice-script/base/oracles/DeployDIAAdapter.s.sol";
import {DeployGelatoAutomateAdapter} from "@lattice-script/base/oracles/DeployGelatoAutomateAdapter.s.sol";
import {DeployGelatoVRFAdapter} from "@lattice-script/base/oracles/DeployGelatoVRFAdapter.s.sol";
import {DeployPythAdapter} from "@lattice-script/base/oracles/DeployPythAdapter.s.sol";
import {DeployPythEntropyAdapter} from "@lattice-script/base/oracles/DeployPythEntropyAdapter.s.sol";
import {DeployRedStoneAdapter} from "@lattice-script/base/oracles/DeployRedStoneAdapter.s.sol";
import {DeployTWAPOracle} from "@lattice-script/base/oracles/DeployTWAPOracle.s.sol";
import {DeployTellorAdapter} from "@lattice-script/base/oracles/DeployTellorAdapter.s.sol";
import {RecipeGuards} from "@lattice-test/composability/RecipeGuards.sol";

/// @title RecipeUpgradeabilityOraclesTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Oracles-family recipe guards: every diamond these recipes assemble must be introspectable and
///         either admin-upgradeable or immutable BY DESIGN (never silently frozen).
contract RecipeUpgradeabilityOraclesTest is RecipeGuards {
    TestnetAsset internal asset;

    function setUp() public {
        asset = new TestnetAsset("Guard Asset", "GA");
    }

    function test_Upgradeable_API3Adapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployAPI3Adapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_API3QRNGAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployAPI3QRNGAdapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_BandAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployBandAdapter().buildCuts(ADMIN, address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ChainlinkAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployChainlinkAdapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ChainlinkAutomationAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployChainlinkAutomationAdapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ChainlinkCREAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployChainlinkCREAdapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ChainlinkVRF() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployChainlinkVRF().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ChronicleAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployChronicleAdapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_DIAAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployDIAAdapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_GelatoAutomateAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployGelatoAutomateAdapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_GelatoVRFAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployGelatoVRFAdapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_PythAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployPythAdapter().buildCuts(ADMIN, address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_PythEntropyAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployPythEntropyAdapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_RedStoneAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployRedStoneAdapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_TellorAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployTellorAdapter().buildCuts(ADMIN, address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_TWAPOracle() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployTWAPOracle().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }
}
