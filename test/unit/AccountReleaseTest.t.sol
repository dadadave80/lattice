// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Selectors} from "@diamond-test/helpers/Selectors.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployAccount} from "@lattice-script/base/accounts/DeployAccount.s.sol";
import {DeployAccount6900} from "@lattice-script/base/accounts/DeployAccount6900.s.sol";
import {DeployRelease} from "@lattice-script/deploy/DeployRelease.s.sol";
import {AccountReleaseInventory} from "@lattice-script/lib/AccountReleaseInventory.sol";
import {ArachnidDeployer} from "@lattice-script/lib/ArachnidDeployer.sol";
import {FacetInventory} from "@lattice-script/lib/FacetInventory.sol";
import {ArachnidProxy} from "@lattice-test/helpers/ArachnidProxy.sol";
import {LatticeVersion} from "@lattice/LatticeVersion.sol";
import {AccountInit6900} from "@lattice/accounts/erc6900/AccountInit6900.sol";
import {AccountFactory} from "@lattice/accounts/erc7579/AccountFactory.sol";
import {AccountInit} from "@lattice/accounts/erc7579/AccountInit.sol";
import {ERC4337_VALIDATION_STORAGE_SLOT} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {ILatticeRegistry} from "@lattice/interfaces/ILatticeRegistry.sol";
import {IAccountFactory} from "@lattice/interfaces/accounts/IAccountFactory.sol";
import {IERC8153} from "@lattice/interfaces/external/ercs/IERC8153.sol";
import {Test} from "forge-std/Test.sol";

/// @title AccountReleaseTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
contract AccountReleaseTest is Test, DeployRelease {
    function setUp() public {
        vm.etch(ArachnidProxy.PROXY, ArachnidProxy.RUNTIME);
    }

    function test_AllCanonicalAccountPairsHavePredictedFactoriesAndAttestedInits() public {
        ReleaseOutput memory out = this.release(LatticeVersion.VERSION, address(this));
        AccountReleaseInventory.Entry[] memory entries = AccountReleaseInventory.inventory();
        assertEq(out.accountInits.length, entries.length);
        assertEq(out.accountFactories.length, entries.length);
        for (uint256 i; i < entries.length; ++i) {
            AccountReleaseInventory.Entry memory entry = entries[i];
            address init = out.accountInits[i];
            address factory = out.accountFactories[i];
            assertEq(
                init,
                ArachnidDeployer.predict(
                    facetSalt(entry.initializer, LatticeVersion.VERSION),
                    keccak256(abi.encodePacked(vm.getCode(entry.initializerArtifact), abi.encode(entry.entryPoint)))
                )
            );
            assertEq(AccountInit(init).ENTRY_POINT(), entry.entryPoint);
            FacetCut[] memory cuts = _canonicalCuts(entry.modular, out.facets);
            assertEq(
                factory,
                ArachnidDeployer.predict(
                    facetSalt(entry.factory, LatticeVersion.VERSION),
                    keccak256(abi.encodePacked(vm.getCode(entry.factoryArtifact), abi.encode(cuts, init)))
                )
            );
            assertEq(IAccountFactory(factory).accountInit(), init);
            assertEq(ILatticeRegistry(out.registry).resolve(init.codehash), init);
            assertEq(ILatticeRegistry(out.registry).resolve(factory.codehash), address(0));
            address owner = address(uint160(0xA1100 + i));
            address predicted = IAccountFactory(factory).getAddress(owner, bytes32(i));
            address account = IAccountFactory(factory).createAccount(owner, bytes32(i));
            assertEq(account, predicted);
            assertEq(account.codehash, keccak256(vm.getDeployedCode(entry.proxyArtifact)));
            assertEq(address(uint160(uint256(vm.load(account, ERC4337_VALIDATION_STORAGE_SLOT)))), entry.entryPoint);
            for (uint256 k; k < cuts.length; ++k) {
                for (uint256 s; s < cuts[k].functionSelectors.length; ++s) {
                    assertEq(IDiamondLoupe(account).facetAddress(cuts[k].functionSelectors[s]), cuts[k].facetAddress);
                }
            }
            assertEq(IDiamondLoupe(account).facetAddress(IERC8153.exportSelectors.selector), address(0));
            assertEq(IAccountFactory(factory).createAccount(owner, bytes32(i)), account);
        }
    }

    function test_RecipesReuseTheReleasedCanonicalInitsAndFactories() public {
        ReleaseOutput memory out = this.release(LatticeVersion.VERSION, address(this));
        AccountReleaseInventory.Entry[] memory entries = AccountReleaseInventory.inventory();
        DeployAccount recipe = new DeployAccount();
        DeployAccount6900 modularRecipe = new DeployAccount6900();
        for (uint256 i; i < entries.length; ++i) {
            FacetCut[] memory cuts;
            address init;
            address factory;
            if (entries[i].modular) {
                AccountInit6900 typedInit;
                (cuts, typedInit) = modularRecipe.buildCuts(entries[i].entryPoint);
                init = address(typedInit);
                factory = address(modularRecipe.buildFactory(entries[i].entryPoint));
            } else {
                AccountInit typedInit;
                (cuts, typedInit) = recipe.buildCuts(entries[i].entryPoint);
                init = address(typedInit);
                factory = address(recipe.buildFactory(entries[i].entryPoint));
            }
            assertEq(init, out.accountInits[i]);
            assertEq(factory, out.accountFactories[i]);
            assertEq(abi.encode(cuts), abi.encode(_canonicalCuts(entries[i].modular, out.facets)));
        }
    }

    function test_NonOwnerReleaseStillCompletesAndResumeReusesAllAccountPairs() public {
        ReleaseOutput memory first = this.release("99.0.0", address(0xBEEF));
        ReleaseOutput memory second = this.release("99.0.0", address(0xBEEF));
        assertEq(abi.encode(first.accountInits), abi.encode(second.accountInits));
        assertEq(abi.encode(first.accountFactories), abi.encode(second.accountFactories));
        for (uint256 i; i < first.accountFactories.length; ++i) {
            assertGt(first.accountFactories[i].code.length, 0);
            assertEq(ILatticeRegistry(first.registry).resolve(first.accountInits[i].codehash), first.accountInits[i]);
        }
    }

    function test_CustomEntryPointsRemainExplicitAndContentBound() public {
        DeployAccount recipe = new DeployAccount();
        address first = address(recipe.buildFactory(address(0xE117)));
        address second = address(recipe.buildFactory(address(0xE118)));
        assertTrue(first != second);
        assertEq(address(recipe.buildFactory(address(0xE117))), first);
        assertEq(AccountInit(IAccountFactory(first).accountInit()).ENTRY_POINT(), address(0xE117));
        assertEq(AccountReleaseInventory.describe(false, address(0xE117)).entryPointVersion, "custom");
        AccountReleaseInventory.Entry[] memory entries = AccountReleaseInventory.inventory();
        for (uint256 i; i < entries.length; ++i) {
            assertTrue(entries[i].entryPoint != address(0xE117));
        }
    }

    function test_RuntimeCodehashDoesNotIdentifyAFactoryBlueprint() public {
        ReleaseOutput memory out = this.release(LatticeVersion.VERSION, address(this));
        FacetCut[] memory full = _canonicalCuts(false, out.facets);
        // Receive is optional for a custom account. Both blueprints are usable, with different ETH behavior.
        FacetCut[] memory withoutReceive = new FacetCut[](full.length - 1);
        for (uint256 i; i < withoutReceive.length; ++i) {
            withoutReceive[i] = full[i];
        }
        AccountFactory other = new AccountFactory(withoutReceive, out.accountInits[0]);
        address canonical = out.accountFactories[0];
        assertEq(address(other).codehash, canonical.codehash, "runtime omits the stored blueprint");
        address expectedAccount = IAccountFactory(canonical).createAccount(address(this), bytes32(0));
        address otherAccount = other.createAccount(address(this), bytes32(0));
        assertTrue(expectedAccount != otherAccount);
        assertEq(expectedAccount.codehash, otherAccount.codehash);
        assertTrue(IDiamondLoupe(expectedAccount).facetAddress(bytes4(0)) != address(0));
        assertEq(IDiamondLoupe(otherAccount).facetAddress(bytes4(0)), address(0));
        ILatticeRegistry registry = ILatticeRegistry(out.registry);
        assertEq(registry.resolve(canonical.codehash), address(0), "factory identity requires full constructor state");
        // Anyone may attest another same-codehash factory. Release selection must still use the exact manifest.
        registry.attest(address(other));
        assertEq(registry.resolve(canonical.codehash), address(other));
        ReleaseOutput memory resumed = this.release(LatticeVersion.VERSION, address(this));
        assertEq(resumed.accountFactories[0], canonical);
        assertEq(registry.resolve(canonical.codehash), address(other));
    }

    function test_CanonicalRunBindsOwnerAndSaltAndCanResumeAcrossScriptInstances() public {
        address ep = AccountReleaseInventory.inventory()[2].entryPoint;
        bytes32 salt = keccak256("account recipe salt");
        address first = new DeployAccount().run(ep, address(0xA11CE), salt);
        assertEq(new DeployAccount().run(ep, address(0xA11CE), salt), first);
        assertTrue(new DeployAccount().run(ep, address(0xA11CE), bytes32(uint256(salt) + 1)) != first);
        assertTrue(new DeployAccount().run(ep, address(0xB0B), salt) != first);
        address modular = new DeployAccount6900().run(ep, address(0xA11CE), salt);
        assertTrue(modular != first);
        assertEq(new DeployAccount6900().run(ep, address(0xA11CE), salt), modular);
    }

    function test_ReleaseVersionAndBlueprintBothBindFactoryIdentity() public {
        ReleaseOutput memory first = this.release("99.0.0", address(this));
        ReleaseOutput memory second = this.release("99.0.1", address(this));
        AccountReleaseInventory.Entry memory entry = AccountReleaseInventory.inventory()[0];
        assertTrue(first.accountInits[0] != second.accountInits[0]);
        assertTrue(first.accountFactories[0] != second.accountFactories[0]);
        FacetCut[] memory cuts = _canonicalCuts(entry.modular, first.facets);
        bytes32 original =
            keccak256(abi.encodePacked(vm.getCode(entry.factoryArtifact), abi.encode(cuts, first.accountInits[0])));
        cuts[0].facetAddress = cuts[1].facetAddress;
        bytes32 changed =
            keccak256(abi.encodePacked(vm.getCode(entry.factoryArtifact), abi.encode(cuts, first.accountInits[0])));
        assertTrue(original != changed);
        assertTrue(
            ArachnidDeployer.predict(facetSalt(entry.factory, "99.0.0"), original)
                != ArachnidDeployer.predict(facetSalt(entry.factory, "99.0.0"), changed)
        );
    }

    function test_LocalNoProxyProfileStillCreatesSpecializedAccounts() public {
        vm.etch(ArachnidProxy.PROXY, "");
        DeployAccount recipe = new DeployAccount();
        IAccountFactory factory = recipe.buildFactory(address(0xE117));
        address account = factory.createAccount(address(this), bytes32(0));
        assertEq(
            account.codehash, keccak256(vm.getDeployedCode("src/accounts/erc7579/AccountDiamond.sol:AccountDiamond"))
        );
        assertEq(AccountInit(factory.accountInit()).ENTRY_POINT(), address(0xE117));
        IAccountFactory other = new DeployAccount6900().buildFactory(address(0xE117));
        address modular = other.createAccount(address(this), bytes32(0));
        assertEq(
            modular.codehash,
            keccak256(vm.getDeployedCode("src/accounts/erc6900/ModularAccount6900.sol:ModularAccount6900"))
        );
    }

    function _canonicalCuts(bool modular, address[] memory facets) private view returns (FacetCut[] memory cuts) {
        string[] memory wanted = AccountReleaseInventory.facetNames(modular);
        (string[] memory names,) = FacetInventory.inventory();
        cuts = new FacetCut[](wanted.length);
        for (uint256 i; i < wanted.length; ++i) {
            bool found;
            for (uint256 k; k < names.length; ++k) {
                if (keccak256(bytes(wanted[i])) != keccak256(bytes(names[k]))) continue;
                cuts[i].facetAddress = facets[k];
                cuts[i].functionSelectors = Selectors.decode(IERC8153(facets[k]).exportSelectors());
                found = true;
                break;
            }
            assertTrue(found, "account blueprint facet absent from release inventory");
        }
    }
}
