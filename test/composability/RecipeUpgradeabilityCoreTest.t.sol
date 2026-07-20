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
import {RecipeGuards} from "@lattice-test/composability/RecipeGuards.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {AccountInit6900} from "@lattice/accounts/erc6900/AccountInit6900.sol";
import {AccountInit} from "@lattice/accounts/erc7579/AccountInit.sol";
import {GovernedVaultENSParams} from "@lattice/defi/GovernedVaultENSInit.sol";
import {GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {IReverseRegistrar} from "@lattice/interfaces/external/ens/IReverseRegistrar.sol";

/// @title GuardReverseRegistrar
/// @notice Minimal reverse registrar accepting any setName (ENS-vault guard fixture).
contract GuardReverseRegistrar is IReverseRegistrar {
    function setName(string memory) external {}
}

/// @title RecipeUpgradeabilityCoreTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Introspection guards for the recipes whose upgrade paths are covered by their own dedicated
///         suites (accounts, governance cut variants, self-governed vaults): the loupe must answer with the
///         expected facet census on every one of them.
contract RecipeUpgradeabilityCoreTest is RecipeGuards {
    address internal entryPoint = address(0xE117);

    function _mockSafe() internal returns (address) {
        address[] memory owners = new address[](1);
        owners[0] = ADMIN;
        return address(new MockSafe(1, owners));
    }

    function test_Introspectable_Account() public {
        (FacetCut[] memory cuts, AccountInit init) = new DeployAccount().buildCuts(entryPoint);
        LatticeDiamond d = new LatticeDiamond();
        d.initialize(cuts, address(init), abi.encodeCall(AccountInit.init, (address(this))));
        _assertIntrospectable(address(d), 9);
    }

    function test_Introspectable_Account6900() public {
        (FacetCut[] memory cuts, AccountInit6900 init) = new DeployAccount6900().buildCuts(entryPoint);
        LatticeDiamond d = new LatticeDiamond();
        d.initialize(cuts, address(init), abi.encodeCall(AccountInit6900.init, (address(this))));
        _assertIntrospectable(address(d), 10);
    }

    function test_Introspectable_GovernedDiamondCut() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployGovernedDiamondCut().buildCuts(ADMIN);
        _assertIntrospectable(_assemble(cuts, init, cd), 6);
    }

    function test_Introspectable_SafeDiamondCut() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeploySafeDiamondCut().buildCuts(ADMIN, _mockSafe(), 1);
        _assertIntrospectable(_assemble(cuts, init, cd), 6);
    }

    function test_Introspectable_GovernedSafeDiamondCut() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployGovernedSafeDiamondCut().buildCuts(ADMIN, _mockSafe(), 1, 300);
        _assertIntrospectable(_assemble(cuts, init, cd), 6);
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
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployGovernedVault().buildCuts(_vaultParams());
        _assertIntrospectable(_assemble(cuts, init, cd), 14);
    }

    function test_Introspectable_GovernedVaultENS() public {
        vm.warp(1_000_000);
        GovernedVaultENSParams memory p;
        p.vault = _vaultParams();
        p.reverseRegistrar = address(new GuardReverseRegistrar());
        p.ensName = "guard.lattice.eth";
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployGovernedVaultENS().buildCutsWithENS(p);
        _assertIntrospectable(_assemble(cuts, init, cd), 15);
    }
}
