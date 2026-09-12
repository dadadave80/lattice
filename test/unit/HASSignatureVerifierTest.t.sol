// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {MockHederaAccountService} from "@lattice-test/mocks/hedera/MockHederaAccountService.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {HASSignatureVerifier} from "@lattice/accounts/hedera/HASSignatureVerifier.sol";
import {HASSignatureVerifierInit} from "@lattice/accounts/hedera/HASSignatureVerifierInit.sol";
import {HAS_SYSTEM_CONTRACT} from "@lattice/accounts/hedera/HASSignatureVerifierLib.sol";
import {IHASSignatureVerifier} from "@lattice/interfaces/accounts/IHASSignatureVerifier.sol";
import {IERC8153} from "@lattice/interfaces/external/ercs/IERC8153.sol";
import {Test} from "forge-std/Test.sol";

/// @title HASSignatureVerifierTest
/// @notice Exercises the stateless HAS verifier facet through a REAL {Lattice} diamond (ERC165Facet +
///         HASSignatureVerifier + {HASSignatureVerifierInit}), with a {MockHederaAccountService} etched at the
///         system-contract address 0x16a. The facet's whole contract is "never revert": every system-contract
///         failure — a malformed blob, a missing system contract — must surface as `false`.
/// @dev `test_SupportsInterface` is the guard on the precomputed `ERC165_MAP_IHASSIGNATUREVERIFIER_SLOT`: the
///      read path recomputes the keccak at runtime, so a wrong constant fails here. No `script/base` recipe
///      exists for this facet yet, so the cuts are assembled from each facet's own ERC-8153 `exportSelectors()`
///      — the same selector source {BaseDeploy} uses, not a divergent hand-written selector list.
contract HASSignatureVerifierTest is Test {
    IHASSignatureVerifier verifier; // typed handle on the diamond
    MockHederaAccountService hederaService; // the etched stand-in living at 0x16a

    address constant ED25519_ACCOUNT = address(0x0000000000000000000000000000000000000457);
    bytes4 constant IHAS_SIGNATURE_VERIFIER_ID = 0x96c247cb;

    address signerAddr;
    uint256 signerPk;

    function setUp() public {
        (signerAddr, signerPk) = makeAddrAndKey("hederaAccount");

        FacetCut[] memory cuts = new FacetCut[](2);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new HASSignatureVerifier()));
        Lattice diamond = new Lattice();
        diamond.initialize(
            cuts, address(new HASSignatureVerifierInit()), abi.encodeCall(HASSignatureVerifierInit.init, ())
        );
        verifier = IHASSignatureVerifier(address(diamond));

        vm.etch(HAS_SYSTEM_CONTRACT, address(new MockHederaAccountService()).code);
        hederaService = MockHederaAccountService(HAS_SYSTEM_CONTRACT);
    }

    /// @dev An `Add` cut whose selectors come from the facet's own ERC-8153 self-report.
    function _cut(address facet) internal view returns (FacetCut memory) {
        bytes memory packed = IERC8153(facet).exportSelectors();
        bytes4[] memory selectors = new bytes4[](packed.length / 4);
        for (uint256 i; i < selectors.length; ++i) {
            selectors[i] = bytes4(
                bytes32(
                    uint256(uint8(packed[i * 4])) << 248 | uint256(uint8(packed[i * 4 + 1])) << 240
                        | uint256(uint8(packed[i * 4 + 2])) << 232 | uint256(uint8(packed[i * 4 + 3])) << 224
                )
            );
        }
        return FacetCut({facetAddress: facet, action: FacetCutAction.Add, functionSelectors: selectors});
    }

    function _ecdsaSig(uint256 pk, bytes32 messageHash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, messageHash);
        return abi.encodePacked(r, s, v);
    }

    /// @dev A 64-byte stand-in for an ED25519 signature (the mock keys its fixture table on the exact bytes).
    function _ed25519Sig() internal pure returns (bytes memory) {
        return abi.encodePacked(keccak256("ed25519-R"), keccak256("ed25519-S"));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The init's single precomputed-slot `sstore` is what the runtime-keccak read path must find.
    function test_SupportsInterface() public view {
        assertEq(type(IHASSignatureVerifier).interfaceId, IHAS_SIGNATURE_VERIFIER_ID, "interfaceId drifted");
        assertTrue(
            ERC165Facet(address(verifier)).supportsInterface(IHAS_SIGNATURE_VERIFIER_ID),
            "IHASSignatureVerifier not registered (precomputed ERC-165 map slot wrong?)"
        );
    }

    function test_SupportsInterface_UnknownId() public view {
        assertFalse(ERC165Facet(address(verifier)).supportsInterface(0xdeadbeef), "unknown id reported supported");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           isAuthorizedRaw
    //////////////////////////////////////////////////////////////////////////*//

    function test_IsAuthorizedRaw_EcdsaValid() public view {
        bytes32 messageHash = keccak256("hedera message");
        assertTrue(
            verifier.isAuthorizedRaw(signerAddr, messageHash, _ecdsaSig(signerPk, messageHash)), "valid sig rejected"
        );
    }

    function test_IsAuthorizedRaw_EcdsaWrongAccount() public view {
        bytes32 messageHash = keccak256("hedera message");
        assertFalse(
            verifier.isAuthorizedRaw(address(0xBAD), messageHash, _ecdsaSig(signerPk, messageHash)),
            "signature accepted for the wrong account"
        );
    }

    function test_IsAuthorizedRaw_Ed25519Authorized() public {
        bytes32 messageHash = keccak256("hedera message");
        bytes memory sig = _ed25519Sig();
        hederaService.setEd25519Authorized(ED25519_ACCOUNT, messageHash, sig, true);
        assertTrue(verifier.isAuthorizedRaw(ED25519_ACCOUNT, messageHash, sig), "authorized ED25519 sig rejected");
    }

    function test_IsAuthorizedRaw_Ed25519Unauthorized() public view {
        assertFalse(
            verifier.isAuthorizedRaw(ED25519_ACCOUNT, keccak256("hedera message"), _ed25519Sig()),
            "unauthorized ED25519 sig accepted"
        );
    }

    /// @notice THE contract of this facet: the system contract reverts on a blob that is neither 64 nor 65
    ///         bytes, and the wrapper reports that as `false` instead of propagating the revert.
    function test_IsAuthorizedRaw_MalformedReturnsFalse() public {
        bytes32 messageHash = keccak256("hedera message");
        bytes memory malformed = hex"00112233445566778899"; // 10 bytes

        vm.expectRevert(MockHederaAccountService.InvalidTransactionBody.selector);
        hederaService.isAuthorizedRaw(signerAddr, abi.encodePacked(messageHash), malformed);

        assertFalse(verifier.isAuthorizedRaw(signerAddr, messageHash, malformed), "malformed blob not swallowed");
    }

    /// @notice The other half of the never-revert contract: a halted frame whose revert reason is LONGER than
    ///         a decodable word. The returndata-length guard cannot catch this one — only the failed-call flag
    ///         can — so the wrapper must still answer `false` instead of decoding the reason as a bool.
    function test_IsAuthorizedRaw_HaltedFrameReturnsFalse() public {
        bytes32 messageHash = keccak256("hedera message");
        bytes memory sig = _ecdsaSig(signerPk, messageHash);
        hederaService.forceRevert(true);

        vm.expectRevert(bytes("MockHederaAccountService: the system contract halted this frame"));
        hederaService.isAuthorizedRaw(signerAddr, abi.encodePacked(messageHash), sig);

        assertFalse(verifier.isAuthorizedRaw(signerAddr, messageHash, sig), "halted frame not swallowed");
    }

    /// @notice Off Hedera there is no system contract at 0x16a: the staticcall returns no data and the wrapper
    ///         must answer `false` rather than decode garbage or revert.
    function test_IsAuthorizedRaw_NoSystemContract() public {
        vm.etch(HAS_SYSTEM_CONTRACT, "");
        bytes32 messageHash = keccak256("hedera message");
        assertFalse(
            verifier.isAuthorizedRaw(signerAddr, messageHash, _ecdsaSig(signerPk, messageHash)),
            "missing system contract not reported as false"
        );
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             isAuthorized
    //////////////////////////////////////////////////////////////////////////*//

    function test_IsAuthorized_SignatureMapAuthorized() public {
        bytes memory message = bytes("a hedera transaction body");
        bytes memory signatureMap = hex"0a180a0c";
        hederaService.setAuthorized(ED25519_ACCOUNT, message, signatureMap, true);
        assertTrue(verifier.isAuthorized(ED25519_ACCOUNT, message, signatureMap), "authorized SignatureMap rejected");
    }

    function test_IsAuthorized_SignatureMapUnauthorized() public view {
        assertFalse(
            verifier.isAuthorized(ED25519_ACCOUNT, bytes("a hedera transaction body"), hex"0a180a0c"),
            "unauthorized SignatureMap accepted"
        );
    }

    function test_IsAuthorized_NoSystemContract() public {
        vm.etch(HAS_SYSTEM_CONTRACT, "");
        assertFalse(
            verifier.isAuthorized(ED25519_ACCOUNT, bytes("a hedera transaction body"), hex"0a180a0c"),
            "missing system contract not reported as false"
        );
    }
}
