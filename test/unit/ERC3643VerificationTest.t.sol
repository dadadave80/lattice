// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    ERC3643RegistryTestBase,
    RegistryIdentityMock,
    RegistryIssuerMock,
    RegistryRawIdentity
} from "@lattice-test/helpers/ERC3643RegistryTestHelpers.sol";
import {IERC3643Identity} from "@lattice/interfaces/external/erc3643/IERC3643Identity.sol";
import {IClaimTopicsRegistry} from "@lattice/interfaces/tokens/erc3643/IClaimTopicsRegistry.sol";
import {IIdentityRegistry} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistry.sol";
import {ITrustedIssuersRegistry} from "@lattice/interfaces/tokens/erc3643/ITrustedIssuersRegistry.sol";

contract ERC3643VerificationTest is ERC3643RegistryTestBase {
    address diamond;
    IClaimTopicsRegistry topics;
    ITrustedIssuersRegistry issuers;
    IIdentityRegistry identities;
    RegistryIdentityMock investor;
    RegistryIssuerMock issuer;
    address alice = address(0xA11CE);

    function setUp() public {
        diamond = _deployRegistry(address(0));
        topics = IClaimTopicsRegistry(diamond);
        issuers = ITrustedIssuersRegistry(diamond);
        identities = IIdentityRegistry(diamond);
        investor = new RegistryIdentityMock();
        issuer = new RegistryIssuerMock();
        identities.registerIdentity(alice, investor, 840);
    }

    function _requireClaim(uint256 topic) internal {
        topics.addClaimTopic(topic);
        issuers.addTrustedIssuer(issuer, _topics(topic));
        investor.setClaim(topic, address(issuer), hex"cafe", hex"beef");
        issuer.setSubject(address(investor), topic);
    }

    function test_RegisteredIdentityWithNoRequiredTopicsIsVerified() public view {
        assertTrue(identities.isVerified(alice));
        assertFalse(identities.isVerified(address(0)));
        assertFalse(identities.isVerified(address(0xB0B)));
    }

    function test_EveryRequiredTopicNeedsAnAuthorizedValidClaim() public {
        _requireClaim(7);
        assertTrue(identities.isVerified(alice));
        topics.addClaimTopic(9);
        assertFalse(identities.isVerified(alice));
        RegistryIssuerMock second = new RegistryIssuerMock();
        issuers.addTrustedIssuer(second, _topics(9));
        investor.setClaim(9, address(second), hex"cafe", hex"beef");
        assertTrue(identities.isVerified(alice));
        investor.clearClaim(7, address(issuer));
        assertFalse(identities.isVerified(alice));
    }

    function test_VerificationFreshlyReflectsClaimRevocationIssuerRemovalAndTopicReplacement() public {
        _requireClaim(7);
        assertTrue(identities.isVerified(alice));
        issuer.setValid(false);
        assertFalse(identities.isVerified(alice));
        issuer.setValid(true);
        assertTrue(identities.isVerified(alice));
        issuers.updateIssuerClaimTopics(issuer, _topics(9));
        assertFalse(identities.isVerified(alice));
        issuers.updateIssuerClaimTopics(issuer, _topics(7));
        assertTrue(identities.isVerified(alice));
        issuers.removeTrustedIssuer(issuer);
        assertFalse(identities.isVerified(alice));
        issuers.addTrustedIssuer(issuer, _topics(7));
        assertTrue(identities.isVerified(alice));
        identities.deleteIdentity(alice);
        assertFalse(identities.isVerified(alice));
    }

    function test_InvalidSignatureDataAndRevertingIdentityOrIssuerFailClosed() public {
        _requireClaim(7);
        investor.setClaim(7, address(issuer), hex"dead", hex"beef");
        assertFalse(identities.isVerified(alice));
        investor.setClaim(7, address(issuer), hex"cafe", hex"dead");
        assertFalse(identities.isVerified(alice));
        investor.setClaim(7, address(issuer), hex"cafe", hex"beef");
        investor.setRevert(true);
        assertFalse(identities.isVerified(alice));
        investor.setRevert(false);
        issuer.setRevert(true);
        assertFalse(identities.isVerified(alice));
        issuer.setRevert(false);
        assertTrue(identities.isVerified(alice));
    }

    function test_ValidLaterCandidateSurvivesInvalidOrRevertingEarlierIssuer() public {
        _requireClaim(7);
        RegistryIssuerMock second = new RegistryIssuerMock();
        issuers.addTrustedIssuer(second, _topics(7));
        investor.setClaim(7, address(second), hex"cafe", hex"beef");
        issuer.setValid(false);
        assertTrue(identities.isVerified(alice));
        issuer.setRevert(true);
        assertTrue(identities.isVerified(alice));
        issuers.removeTrustedIssuer(second);
        assertFalse(identities.isVerified(alice));
    }

    function test_OnlyCanonicalTrueBooleanFromIssuerIsAccepted() public {
        _requireClaim(7);
        issuer.setReturnMode(1);
        assertFalse(identities.isVerified(alice));
        issuer.setReturnMode(2);
        assertFalse(identities.isVerified(alice));
        issuer.setReturnMode(0);
        assertTrue(identities.isVerified(alice));
    }

    function test_ClaimMustMatchDeterministicIssuerAndTopic() public {
        topics.addClaimTopic(7);
        issuers.addTrustedIssuer(issuer, _topics(7));
        RegistryRawIdentity raw = new RegistryRawIdentity();
        identities.deleteIdentity(alice);
        identities.registerIdentity(alice, IERC3643Identity(address(raw)), 840);
        raw.setReply(abi.encode(uint256(8), uint256(1), address(issuer), hex"cafe", hex"beef", ""));
        assertFalse(identities.isVerified(alice));
        raw.setReply(abi.encode(uint256(7), uint256(1), address(0xBAD), hex"cafe", hex"beef", ""));
        assertFalse(identities.isVerified(alice));
        raw.setReply(abi.encode(uint256(7), uint256(1), address(issuer), hex"cafe", hex"beef", ""));
        assertTrue(identities.isVerified(alice));
    }

    function test_MalformedClaimHeadOffsetsLengthsAndDirtyAddressFailClosed() public {
        topics.addClaimTopic(7);
        issuers.addTrustedIssuer(issuer, _topics(7));
        RegistryRawIdentity raw = new RegistryRawIdentity();
        identities.deleteIdentity(alice);
        identities.registerIdentity(alice, IERC3643Identity(address(raw)), 840);
        raw.setReply(hex"01");
        assertFalse(identities.isVerified(alice));
        bytes memory result = abi.encode(uint256(7), uint256(1), address(issuer), hex"cafe", hex"beef", "");
        assembly ("memory-safe") { mstore(add(result, 128), 0) }
        raw.setReply(result);
        assertFalse(identities.isVerified(alice));
        result = abi.encode(uint256(7), uint256(1), address(issuer), hex"cafe", hex"beef", "");
        assembly ("memory-safe") { mstore(add(result, 128), 193) }
        raw.setReply(result);
        assertFalse(identities.isVerified(alice));
        result = abi.encode(uint256(7), uint256(1), address(issuer), hex"cafe", hex"beef", "");
        assembly ("memory-safe") { mstore(add(result, 224), not(0)) }
        raw.setReply(result);
        assertFalse(identities.isVerified(alice));
        result = abi.encode(uint256(7), uint256(1), address(issuer), hex"cafe", hex"beef", "");
        assembly ("memory-safe") { mstore(add(result, 96), or(mload(add(result, 96)), shl(160, 1))) }
        raw.setReply(result);
        assertFalse(identities.isVerified(alice));
    }

    function test_StaticClaimAndValidationCallsCannotMutateRegistry() public {
        _requireClaim(7);
        investor.setReentry(diamond, abi.encodeCall(IClaimTopicsRegistry.addClaimTopic, (9)));
        assertTrue(identities.isVerified(alice));
        assertEq(topics.getClaimTopics().length, 1);
        topics.addClaimTopic(9);
        assertEq(topics.getClaimTopics().length, 2);
    }

    function test_ExternalTrustedIssuerAndTopicRegistriesUseFreshLiveState() public {
        address endpoint = _deployRegistry(address(0));
        identities.setClaimTopicsRegistry(endpoint);
        identities.setTrustedIssuersRegistry(endpoint);
        IClaimTopicsRegistry(endpoint).addClaimTopic(7);
        ITrustedIssuersRegistry(endpoint).addTrustedIssuer(issuer, _topics(7));
        investor.setClaim(7, address(issuer), hex"cafe", hex"beef");
        assertTrue(identities.isVerified(alice));
        ITrustedIssuersRegistry(endpoint).removeTrustedIssuer(issuer);
        assertFalse(identities.isVerified(alice));
        IClaimTopicsRegistry(endpoint).removeClaimTopic(7);
        assertTrue(identities.isVerified(alice));
    }
}
