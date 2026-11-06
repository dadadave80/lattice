// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    ERC3643RegistryTestBase,
    RegistryIdentityMock,
    RegistryIssuerMock
} from "@lattice-test/helpers/ERC3643RegistryTestHelpers.sol";
import {IClaimTopicsRegistry} from "@lattice/interfaces/tokens/erc3643/IClaimTopicsRegistry.sol";
import {ICompliance} from "@lattice/interfaces/tokens/erc3643/ICompliance.sol";
import {IIdentityRegistry} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistry.sol";
import {IIdentityRegistryStorage} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistryStorage.sol";
import {ITrustedIssuersRegistry} from "@lattice/interfaces/tokens/erc3643/ITrustedIssuersRegistry.sol";

contract ERC3643RegistryEventsTest is ERC3643RegistryTestBase {
    address diamond;
    RegistryIdentityMock investor;
    RegistryIssuerMock issuer;
    address alice = address(0xA11CE);

    function setUp() public {
        diamond = _deployRegistry(address(0));
        investor = new RegistryIdentityMock();
        issuer = new RegistryIssuerMock();
    }

    function test_TopicEventsPreserveIndexedTopic() public {
        vm.expectEmit(true, false, false, true, diamond);
        emit IClaimTopicsRegistry.ClaimTopicAdded(7);
        IClaimTopicsRegistry(diamond).addClaimTopic(7);
        vm.expectEmit(true, false, false, true, diamond);
        emit IClaimTopicsRegistry.ClaimTopicRemoved(7);
        IClaimTopicsRegistry(diamond).removeClaimTopic(7);
    }

    function test_IssuerEventsPreserveIndexedIssuerAndTopicSet() public {
        vm.expectEmit(true, false, false, true, diamond);
        emit ITrustedIssuersRegistry.TrustedIssuerAdded(issuer, _topics(7));
        ITrustedIssuersRegistry(diamond).addTrustedIssuer(issuer, _topics(7));
        vm.expectEmit(true, false, false, true, diamond);
        emit ITrustedIssuersRegistry.ClaimTopicsUpdated(issuer, _topics(9));
        ITrustedIssuersRegistry(diamond).updateIssuerClaimTopics(issuer, _topics(9));
        vm.expectEmit(true, false, false, true, diamond);
        emit ITrustedIssuersRegistry.TrustedIssuerRemoved(issuer);
        ITrustedIssuersRegistry(diamond).removeTrustedIssuer(issuer);
    }

    function test_IdentityAndStorageMutationEventsPreserveAllIndexedValues() public {
        vm.expectEmit(true, true, false, true, diamond);
        emit IIdentityRegistryStorage.IdentityStored(alice, investor);
        vm.expectEmit(true, true, false, true, diamond);
        emit IIdentityRegistry.IdentityRegistered(alice, investor);
        IIdentityRegistry(diamond).registerIdentity(alice, investor, 840);
        RegistryIdentityMock next = new RegistryIdentityMock();
        next.setManagement(alice, true);
        vm.expectEmit(true, true, false, true, diamond);
        emit IIdentityRegistryStorage.IdentityModified(investor, next);
        vm.expectEmit(true, true, false, true, diamond);
        emit IIdentityRegistry.IdentityUpdated(investor, next);
        IIdentityRegistry(diamond).updateIdentity(alice, next);
        vm.expectEmit(true, true, false, true, diamond);
        emit IIdentityRegistryStorage.CountryModified(alice, 826);
        vm.expectEmit(true, true, false, true, diamond);
        emit IIdentityRegistry.CountryUpdated(alice, 826);
        IIdentityRegistry(diamond).updateCountry(alice, 826);
        vm.expectEmit(true, true, false, true, diamond);
        emit IIdentityRegistryStorage.IdentityUnstored(alice, next);
        vm.expectEmit(true, true, false, true, diamond);
        emit IIdentityRegistry.IdentityRemoved(alice, next);
        IIdentityRegistry(diamond).deleteIdentity(alice);
    }

    function test_RegistryDependencyEventsPreserveIndexedEndpoint() public {
        vm.expectEmit(true, false, false, true, diamond);
        emit IIdentityRegistry.IdentityStorageSet(diamond);
        IIdentityRegistry(diamond).setIdentityRegistryStorage(diamond);
        vm.expectEmit(true, false, false, true, diamond);
        emit IIdentityRegistry.TrustedIssuersRegistrySet(diamond);
        IIdentityRegistry(diamond).setTrustedIssuersRegistry(diamond);
        vm.expectEmit(true, false, false, true, diamond);
        emit IIdentityRegistry.ClaimTopicsRegistrySet(diamond);
        IIdentityRegistry(diamond).setClaimTopicsRegistry(diamond);
    }

    function test_StorageBindingEventsPreserveIndexedRegistry() public {
        vm.expectEmit(true, false, false, true, diamond);
        emit IIdentityRegistryStorage.IdentityRegistryBound(alice);
        IIdentityRegistryStorage(diamond).bindIdentityRegistry(alice);
        vm.expectEmit(true, false, false, true, diamond);
        emit IIdentityRegistryStorage.IdentityRegistryUnbound(alice);
        IIdentityRegistryStorage(diamond).unbindIdentityRegistry(alice);
    }

    function test_ComplianceBindingEventsKeepTokenInDataAsStandard() public {
        vm.expectEmit(false, false, false, true, diamond);
        emit ICompliance.TokenUnbound(diamond);
        ICompliance(diamond).unbindToken(diamond);
        vm.expectEmit(false, false, false, true, diamond);
        emit ICompliance.TokenBound(alice);
        ICompliance(diamond).bindToken(alice);
    }
}
