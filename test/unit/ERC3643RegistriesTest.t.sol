// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {OwnableFacet} from "@diamond/facets/OwnableFacet.sol";
import {
    ERC3643RegistryTestBase,
    RegistryExecutionProbe,
    RegistryIdentityMock,
    RegistryIssuerMock
} from "@lattice-test/helpers/ERC3643RegistryTestHelpers.sol";
import {IERC3643ClaimIssuer} from "@lattice/interfaces/external/erc3643/IERC3643ClaimIssuer.sol";
import {IERC3643Identity} from "@lattice/interfaces/external/erc3643/IERC3643Identity.sol";
import {IAgentRole} from "@lattice/interfaces/tokens/erc3643/IAgentRole.sol";
import {IClaimTopicsRegistry} from "@lattice/interfaces/tokens/erc3643/IClaimTopicsRegistry.sol";
import {IIdentityRegistry} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistry.sol";
import {IIdentityRegistryStorage} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistryStorage.sol";
import {ITrustedIssuersRegistry} from "@lattice/interfaces/tokens/erc3643/ITrustedIssuersRegistry.sol";
import {ERC3643ExecutionInProgress} from "@lattice/tokens/ERC3643/libraries/ERC3643ExecutionLib.sol";

contract ERC3643RegistriesTest is ERC3643RegistryTestBase {
    address diamond;
    IClaimTopicsRegistry topics;
    ITrustedIssuersRegistry issuers;
    IIdentityRegistry identities;
    RegistryIdentityMock investor;
    RegistryIssuerMock issuer;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        diamond = _deployRegistry(address(0));
        topics = IClaimTopicsRegistry(diamond);
        issuers = ITrustedIssuersRegistry(diamond);
        identities = IIdentityRegistry(diamond);
        investor = new RegistryIdentityMock();
        issuer = new RegistryIssuerMock();
    }

    function test_StandardInterfacesRegistered() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IClaimTopicsRegistry).interfaceId));
        assertTrue(ERC165Facet(diamond).supportsInterface(type(ITrustedIssuersRegistry).interfaceId));
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IIdentityRegistry).interfaceId));
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IIdentityRegistryStorage).interfaceId));
    }

    function test_TopicSetUniqueRemoveAndReadd() public {
        topics.addClaimTopic(7);
        topics.addClaimTopic(9);
        vm.expectRevert(abi.encodeWithSelector(IClaimTopicsRegistry.ERC3643ClaimTopicAlreadyRequired.selector, 7));
        topics.addClaimTopic(7);
        topics.removeClaimTopic(7);
        topics.addClaimTopic(7);
        uint256[] memory values = topics.getClaimTopics();
        assertEq(values.length, 2);
        assertTrue(values[0] != values[1]);
        vm.expectRevert(abi.encodeWithSelector(IClaimTopicsRegistry.ERC3643ClaimTopicNotRequired.selector, 8));
        topics.removeClaimTopic(8);
    }

    function test_TopicLimitFifteenAndRemovalFreesCapacity() public {
        for (uint256 i; i < 15; ++i) {
            topics.addClaimTopic(i);
        }
        vm.expectRevert(IClaimTopicsRegistry.ERC3643ClaimTopicsLimit.selector);
        topics.addClaimTopic(15);
        topics.removeClaimTopic(3);
        topics.addClaimTopic(15);
        assertEq(topics.getClaimTopics().length, 15);
    }

    function test_IssuerReverseIndexesRemainConsistentAcrossReplacementRemovalAndReadd() public {
        uint256[] memory initial = new uint256[](3);
        initial[0] = 7;
        initial[1] = 7;
        initial[2] = 9;
        issuers.addTrustedIssuer(issuer, initial);
        assertEq(issuers.getTrustedIssuerClaimTopics(issuer).length, 2);
        assertEq(issuers.getTrustedIssuersForClaimTopic(7).length, 1);
        uint256[] memory next = new uint256[](2);
        next[0] = 9;
        next[1] = 10;
        issuers.updateIssuerClaimTopics(issuer, next);
        assertFalse(issuers.hasClaimTopic(address(issuer), 7));
        assertEq(issuers.getTrustedIssuersForClaimTopic(7).length, 0);
        assertTrue(issuers.hasClaimTopic(address(issuer), 10));
        issuers.removeTrustedIssuer(issuer);
        assertFalse(issuers.isTrustedIssuer(address(issuer)));
        assertFalse(issuers.hasClaimTopic(address(issuer), 9));
        assertEq(issuers.getTrustedIssuersForClaimTopic(9).length, 0);
        assertEq(issuers.getTrustedIssuerClaimTopics(issuer).length, 0);
        issuers.addTrustedIssuer(issuer, _topics(11));
        assertFalse(issuers.hasClaimTopic(address(issuer), 9));
        assertTrue(issuers.hasClaimTopic(address(issuer), 11));
        assertEq(issuers.getTrustedIssuers().length, 1);
    }

    function test_IssuerValidationAndUnknownOperations() public {
        vm.expectRevert(abi.encodeWithSelector(ITrustedIssuersRegistry.ERC3643InvalidIssuer.selector, alice));
        issuers.addTrustedIssuer(IERC3643ClaimIssuer(alice), _topics(7));
        vm.expectRevert(
            abi.encodeWithSelector(ITrustedIssuersRegistry.ERC3643IssuerNotTrusted.selector, address(issuer))
        );
        issuers.removeTrustedIssuer(issuer);
        vm.expectRevert(
            abi.encodeWithSelector(ITrustedIssuersRegistry.ERC3643IssuerNotTrusted.selector, address(issuer))
        );
        issuers.updateIssuerClaimTopics(issuer, _topics(7));
        vm.expectRevert(abi.encodeWithSelector(ITrustedIssuersRegistry.ERC3643IssuerTopicsLength.selector, 0));
        issuers.addTrustedIssuer(issuer, new uint256[](0));
        issuers.addTrustedIssuer(issuer, _topics(7));
        assertTrue(issuers.isTrustedIssuer(address(issuer)));
        vm.expectRevert(
            abi.encodeWithSelector(ITrustedIssuersRegistry.ERC3643IssuerAlreadyTrusted.selector, address(issuer))
        );
        issuers.addTrustedIssuer(issuer, _topics(7));
    }

    function test_IssuerTopicLengthBoundsAndFailedUpdatePreservesReverseIndexes() public {
        issuers.addTrustedIssuer(issuer, _topics(7));
        vm.expectRevert(abi.encodeWithSelector(ITrustedIssuersRegistry.ERC3643IssuerTopicsLength.selector, 0));
        issuers.updateIssuerClaimTopics(issuer, new uint256[](0));
        vm.expectRevert(abi.encodeWithSelector(ITrustedIssuersRegistry.ERC3643IssuerTopicsLength.selector, 16));
        issuers.updateIssuerClaimTopics(issuer, new uint256[](16));
        assertTrue(issuers.hasClaimTopic(address(issuer), 7));
        assertEq(issuers.getTrustedIssuersForClaimTopic(7).length, 1);
        uint256[] memory maximum = new uint256[](15);
        for (uint256 i; i < 15; ++i) {
            maximum[i] = i;
        }
        issuers.updateIssuerClaimTopics(issuer, maximum);
        assertEq(issuers.getTrustedIssuerClaimTopics(issuer).length, 15);
    }

    function test_FiftyIssuerLimitAndRemovalReleasesCapacity() public {
        for (uint256 i = 1; i <= 51; ++i) {
            vm.etch(address(uint160(i + 0x1000)), address(issuer).code);
        }
        for (uint256 i = 1; i <= 50; ++i) {
            issuers.addTrustedIssuer(IERC3643ClaimIssuer(address(uint160(i + 0x1000))), _topics(7));
        }
        vm.expectRevert(ITrustedIssuersRegistry.ERC3643TrustedIssuersLimit.selector);
        issuers.addTrustedIssuer(IERC3643ClaimIssuer(address(0x1033)), _topics(7));
        issuers.removeTrustedIssuer(IERC3643ClaimIssuer(address(0x1001)));
        issuers.addTrustedIssuer(IERC3643ClaimIssuer(address(0x1033)), _topics(7));
        assertEq(issuers.getTrustedIssuers().length, 50);
        assertEq(issuers.getTrustedIssuersForClaimTopic(7).length, 50);
    }

    function test_OwnerTransferImmediatelyControlsTopicIssuerAndDependencyAdministration() public {
        OwnableFacet(diamond).transferOwnership(bob);
        vm.expectRevert();
        topics.addClaimTopic(7);
        vm.expectRevert();
        issuers.addTrustedIssuer(issuer, _topics(7));
        vm.prank(bob);
        topics.addClaimTopic(7);
        vm.prank(bob);
        issuers.addTrustedIssuer(issuer, _topics(7));
        // Agent membership remains independent: the old owner remains a seeded agent.
        assertTrue(IAgentRole(diamond).isAgent(address(this)));
        identities.registerIdentity(alice, investor, 840);
        assertEq(identities.investorCountry(alice), 840);
    }

    function test_OnlyAgentsRegisterAndMutateInvestors() public {
        vm.prank(alice);
        vm.expectRevert();
        identities.registerIdentity(alice, investor, 840);
        identities.registerIdentity(alice, investor, 840);
        vm.prank(bob);
        vm.expectRevert();
        identities.updateCountry(alice, 826);
        vm.prank(bob);
        vm.expectRevert();
        identities.deleteIdentity(alice);
        assertEq(identities.investorCountry(alice), 840);
    }

    function test_IdentityRegistrationCountryUpdateAndRemoval() public {
        identities.registerIdentity(alice, investor, 840);
        assertTrue(identities.contains(alice));
        assertEq(address(identities.identity(alice)), address(investor));
        assertEq(identities.investorCountry(alice), 840);
        identities.updateCountry(alice, 826);
        assertEq(identities.investorCountry(alice), 826);
        identities.deleteIdentity(alice);
        assertFalse(identities.contains(alice));
        assertEq(identities.investorCountry(alice), 0);
    }

    function test_BatchRegistrationAtomicOnDuplicateAndMismatchedLengths() public {
        address[] memory wallets = new address[](2);
        wallets[0] = alice;
        wallets[1] = alice;
        IERC3643Identity[] memory values = new IERC3643Identity[](2);
        values[0] = investor;
        values[1] = investor;
        uint16[] memory countries = new uint16[](2);
        countries[0] = 840;
        countries[1] = 826;
        vm.expectRevert(abi.encodeWithSelector(IIdentityRegistryStorage.ERC3643IdentityAlreadyStored.selector, alice));
        identities.batchRegisterIdentity(wallets, values, countries);
        assertFalse(identities.contains(alice));
        vm.expectRevert(IIdentityRegistry.ERC3643RegistryArrayLengths.selector);
        identities.batchRegisterIdentity(wallets, values, new uint16[](0));
        wallets[1] = bob;
        identities.batchRegisterIdentity(wallets, values, countries);
        assertTrue(identities.contains(alice));
        assertTrue(identities.contains(bob));
    }

    function test_IdentityUpdatesRequireWalletManagementKeyButInitialRegistrationDoesNot() public {
        identities.registerIdentity(alice, investor, 840);
        RegistryIdentityMock replacement = new RegistryIdentityMock();
        vm.expectRevert(
            abi.encodeWithSelector(
                IIdentityRegistryStorage.ERC3643IdentityKeyMissing.selector, address(replacement), alice
            )
        );
        identities.updateIdentity(alice, replacement);
        replacement.setManagement(alice, true);
        identities.updateIdentity(alice, replacement);
        assertEq(address(identities.identity(alice)), address(replacement));
    }

    function test_DependencySettersRejectZeroEoaAndUnboundStoreAtomically() public {
        vm.expectRevert(abi.encodeWithSelector(IIdentityRegistry.ERC3643InvalidRegistryDependency.selector, address(0)));
        identities.setClaimTopicsRegistry(address(0));
        vm.expectRevert(abi.encodeWithSelector(IIdentityRegistry.ERC3643InvalidRegistryDependency.selector, alice));
        identities.setTrustedIssuersRegistry(alice);
        address other = _deployStorage();
        vm.expectRevert(
            abi.encodeWithSelector(IIdentityRegistry.ERC3643UnboundIdentityStorage.selector, other, diamond)
        );
        identities.setIdentityRegistryStorage(other);
        assertEq(address(identities.identityStorage()), diamond);
        IIdentityRegistryStorage(other).bindIdentityRegistry(diamond);
        identities.setIdentityRegistryStorage(other);
        assertEq(address(identities.identityStorage()), other);
    }

    function test_SharedExternalStoreReflectsBothRegistriesAndUnbindingStopsWrites() public {
        address store = _deployStorage();
        address first = _deployRegistry(store);
        address second = _deployRegistry(store);
        IIdentityRegistry(first).registerIdentity(alice, investor, 840);
        assertEq(address(IIdentityRegistry(second).identity(alice)), address(investor));
        IIdentityRegistry(second).updateCountry(alice, 826);
        assertEq(IIdentityRegistry(first).investorCountry(alice), 826);
        IIdentityRegistryStorage(store).unbindIdentityRegistry(first);
        vm.expectRevert(abi.encodeWithSelector(IIdentityRegistryStorage.ERC3643UnauthorizedRegistry.selector, first));
        IIdentityRegistry(first).deleteIdentity(alice);
        assertTrue(IIdentityRegistry(second).contains(alice));
    }

    function test_GuardedRegistryMutationCannotReenterAndGuardClearsAfterFailure() public {
        bytes memory input = abi.encodeCall(IClaimTopicsRegistry.addClaimTopic, (7));
        (bool ok, bytes memory result) = RegistryExecutionProbe(diamond).attempt(input);
        assertFalse(ok);
        assertEq(result, abi.encodeWithSelector(ERC3643ExecutionInProgress.selector));
        topics.addClaimTopic(7);
        assertEq(topics.getClaimTopics().length, 1);
    }

    function testFuzz_ReplacementRemovesOldTopicIndexes(uint32 oldTopic, uint32 nextTopic) public {
        vm.assume(oldTopic != nextTopic);
        issuers.addTrustedIssuer(issuer, _topics(oldTopic));
        issuers.updateIssuerClaimTopics(issuer, _topics(nextTopic));
        assertFalse(issuers.hasClaimTopic(address(issuer), oldTopic));
        assertEq(issuers.getTrustedIssuersForClaimTopic(oldTopic).length, 0);
        assertTrue(issuers.hasClaimTopic(address(issuer), nextTopic));
    }
}
