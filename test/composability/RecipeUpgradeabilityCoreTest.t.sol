// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployAccount} from "@lattice-script/base/accounts/DeployAccount.s.sol";
import {DeployAccount6900} from "@lattice-script/base/accounts/DeployAccount6900.s.sol";
import {DeployGovernedVault} from "@lattice-script/base/defi/DeployGovernedVault.s.sol";
import {DeployGovernedVaultENS, TestnetAsset} from "@lattice-script/base/defi/DeployGovernedVaultENS.s.sol";
import {DeployGovernedDiamondCut} from "@lattice-script/base/governance/DeployGovernedDiamondCut.s.sol";
import {DeployGovernedSafeDiamondCut} from "@lattice-script/base/governance/DeployGovernedSafeDiamondCut.s.sol";
import {DeploySafeDiamondCut} from "@lattice-script/base/governance/DeploySafeDiamondCut.s.sol";
import {MockSafe} from "@lattice-test/base/SafeDiamondCutTestBase.sol";
import {RecipeConsistencyGuards} from "@lattice-test/composability/RecipeConsistencyGuards.sol";
import {AccountFactory6900} from "@lattice/accounts/erc6900/AccountFactory6900.sol";
import {AccountInit6900} from "@lattice/accounts/erc6900/AccountInit6900.sol";
import {AccountFactory} from "@lattice/accounts/erc7579/AccountFactory.sol";
import {AccountInit} from "@lattice/accounts/erc7579/AccountInit.sol";
import {GovernedVaultENSParams} from "@lattice/defi/GovernedVaultENSInit.sol";
import {GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {IReverseRegistrar} from "@lattice/interfaces/external/ens/IReverseRegistrar.sol";

/// @title GuardReverseRegistrar
/// @notice Minimal reverse registrar accepting any setName (ENS-vault guard fixture).
contract GuardReverseRegistrar is IReverseRegistrar {
    function claim(address) external pure returns (bytes32) {
        return bytes32(0);
    }

    function setName(string memory) external {}
}

/// @title RecipeUpgradeabilityCoreTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Introspection guards for the recipes whose upgrade paths are covered by their own dedicated
///         suites (accounts, governance cut variants, self-governed vaults): the loupe must answer with the
///         expected facet census on every one of them.
contract RecipeUpgradeabilityCoreTest is RecipeConsistencyGuards {
    address internal entryPoint = address(0xE117);

    function _mockSafe() internal returns (address) {
        address[] memory owners = new address[](1);
        owners[0] = ADMIN;
        return address(new MockSafe(1, owners));
    }

    function test_Introspectable_Account() public {
        _expectRecipe(new DeployAccount().recipeSpec(), 0, "DeployAccount");
        (FacetCut[] memory cuts, AccountInit init) = new DeployAccount().buildCuts(entryPoint);
        _assertReleasedAccount(false, entryPoint, cuts, address(init));
        _assertAccountRecipe(cuts, false);
        address d = new AccountFactory(cuts, address(init)).createAccount(address(this), bytes32(0));
        _assertIntrospectable(d, 9);
        _assertBareEth(d, true);
    }

    function test_Introspectable_Account6900() public {
        _expectRecipe(new DeployAccount6900().recipeSpec(), 0, "DeployAccount6900");
        (FacetCut[] memory cuts, AccountInit6900 init) = new DeployAccount6900().buildCuts(entryPoint);
        _assertReleasedAccount(true, entryPoint, cuts, address(init));
        _assertAccountRecipe(cuts, true);
        address d = new AccountFactory6900(cuts, address(init)).createAccount(address(this), bytes32(0));
        _assertIntrospectable(d, 10);
        _assertBareEth(d, true);
    }

    function test_Introspectable_GovernedDiamondCut() public {
        _expectRecipe(new DeployGovernedDiamondCut().recipeSpec(), 0, "DeployGovernedDiamondCut");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployGovernedDiamondCut().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
    }

    function test_Introspectable_SafeDiamondCut() public {
        _expectRecipe(new DeploySafeDiamondCut().recipeSpec(), 0, "DeploySafeDiamondCut");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeploySafeDiamondCut().buildCuts(ADMIN, _mockSafe(), 1);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
    }

    function test_Introspectable_GovernedSafeDiamondCut() public {
        _expectRecipe(new DeployGovernedSafeDiamondCut().recipeSpec(), 0, "DeployGovernedSafeDiamondCut");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployGovernedSafeDiamondCut().buildCuts(ADMIN, _mockSafe(), 1, 300);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
    }

    function _vaultParams() internal returns (GovernedVaultParams memory p) {
        p.asset = address(new TestnetAsset("Guard Asset", "GA"));
        p.name = "Guard Vault Share";
        p.symbol = "gGV";
        p.minDelay = 300;
        p.votingDelay = 60;
        p.votingPeriod = 600;
        p.quorumNumerator = 4;
    }

    function test_Introspectable_GovernedVault() public {
        vm.warp(1_000_000);
        _expectRecipe(new DeployGovernedVault().recipeSpec(), 0, "DeployGovernedVault");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployGovernedVault().buildCuts(_vaultParams());
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 14);
        _assertBareEth(d, true);
    }

    function test_Introspectable_GovernedVaultENS() public {
        vm.warp(1_000_000);
        GovernedVaultENSParams memory p;
        p.vault = _vaultParams();
        p.reverseRegistrar = address(new GuardReverseRegistrar());
        p.ensName = "guard.lattice.eth";
        _expectRecipe(new DeployGovernedVaultENS().recipeSpec(), 1, "DeployGovernedVaultENS");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployGovernedVaultENS().buildCutsWithENS(p);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 15);
        _assertBareEth(d, true);
    }

    function test_Introspectable_GovernedVaultENSInheritedBase() public {
        vm.warp(1_000_000);
        _expectRecipe(new DeployGovernedVaultENS().recipeSpec(), 0, "DeployGovernedVaultENS");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployGovernedVaultENS().buildCuts(_vaultParams());
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 14);
        _assertBareEth(d, true);
    }
}
