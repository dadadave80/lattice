// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AccountSigner} from "@lattice/accounts/AccountSigner.sol";
import {AccountSignerLib} from "@lattice/accounts/libraries/AccountSignerLib.sol";
import {IAccountSigner} from "@lattice/interfaces/IAccountSigner.sol";
import {Base64} from "@lattice/utils/libraries/Base64.sol";
import {WebAuthn} from "@lattice/utils/libraries/WebAuthn.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Test harness: the signer facet + access facet, with an `initialize` that runs the module inits.
contract MockAccountSigner is AccessControl, AccountSigner {
    function initialize(address admin_, address owner_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        AccountSignerLib.__AccountSigner_init(owner_);
        InitializableLib.postInitializer(s);
    }

    /// @dev Exposes the internal signer seam for direct unit coverage.
    function rawValidate(bytes32 hash, bytes calldata signature) external view returns (bool) {
        return AccountSignerLib.isValidSignatureNow(hash, signature);
    }
}

contract AccountSignerTester is Test {
    MockAccountSigner signer;
    address admin = address(0x1);
    address ownerAddr;
    uint256 ownerPk;
    address stranger;
    uint256 strangerPk;

    function setUp() public {
        (ownerAddr, ownerPk) = makeAddrAndKey("owner");
        (stranger, strangerPk) = makeAddrAndKey("stranger");
        signer = new MockAccountSigner();
        signer.initialize(admin, ownerAddr);
    }

    function test_InitialOwner() public view {
        assertEq(signer.owner(), ownerAddr, "owner not set at init");
    }

    function test_SetOwner() public {
        address newOwner = address(0xBEEF);
        vm.expectEmit(true, true, false, true, address(signer));
        emit IAccountSigner.OwnerSet(ownerAddr, newOwner);
        vm.prank(admin);
        signer.setOwner(newOwner);
        assertEq(signer.owner(), newOwner, "owner not updated");
    }

    function test_SetOwner_RevertZero() public {
        vm.prank(admin);
        vm.expectRevert(IAccountSigner.InvalidOwner.selector);
        signer.setOwner(address(0));
    }

    function test_SetOwner_RevertNotAdmin() public {
        vm.prank(stranger);
        vm.expectRevert();
        signer.setOwner(address(0xBEEF));
    }

    function test_RawValidate_OwnerSig() public view {
        bytes32 digest = keccak256("lattice account message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);
        assertTrue(signer.rawValidate(digest, abi.encodePacked(r, s, v)), "owner signature rejected");
    }

    function test_RawValidate_WrongSigner() public view {
        bytes32 digest = keccak256("lattice account message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(strangerPk, digest);
        assertFalse(signer.rawValidate(digest, abi.encodePacked(r, s, v)), "stranger signature accepted");
    }

    // ---- P256 (secp256r1) passkey owner ----

    uint256 constant P256_N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551;
    uint256 constant PASSKEY_PK = 0xC0FFEE;

    function _signP256Low(uint256 pk, bytes32 digest) internal returns (bytes32 r, bytes32 s) {
        (r, s) = vm.signP256(pk, digest);
        if (uint256(s) > P256_N / 2) s = bytes32(P256_N - uint256(s)); // mandatory low-S normalization
    }

    function test_P256_Valid() public {
        (uint256 x, uint256 y) = vm.publicKeyP256(PASSKEY_PK);
        vm.expectEmit(false, false, false, true, address(signer));
        emit IAccountSigner.P256SignerSet(bytes32(x), bytes32(y));
        vm.prank(admin);
        signer.setP256Signer(bytes32(x), bytes32(y));
        assertEq(uint8(signer.signerType()), uint8(IAccountSigner.SignerType.P256), "type not P256");
        bytes32 digest = keccak256("p256 message");
        (bytes32 r, bytes32 s) = _signP256Low(PASSKEY_PK, digest);
        assertTrue(signer.rawValidate(digest, abi.encodePacked(r, s)), "valid P256 sig rejected");
    }

    function test_P256_TamperedRejected() public {
        (uint256 x, uint256 y) = vm.publicKeyP256(PASSKEY_PK);
        vm.prank(admin);
        signer.setP256Signer(bytes32(x), bytes32(y));
        (bytes32 r, bytes32 s) = _signP256Low(PASSKEY_PK, keccak256("p256 message"));
        assertFalse(signer.rawValidate(keccak256("other digest"), abi.encodePacked(r, s)), "tampered accepted");
    }

    function test_P256_BadLengthRejected() public {
        (uint256 x, uint256 y) = vm.publicKeyP256(PASSKEY_PK);
        vm.prank(admin);
        signer.setP256Signer(bytes32(x), bytes32(y));
        bytes32 digest = keccak256("p256 message");
        (bytes32 r, bytes32 s) = _signP256Low(PASSKEY_PK, digest);
        // 65-byte (ECDSA-shaped) signature must be rejected with no revert.
        assertFalse(signer.rawValidate(digest, abi.encodePacked(r, s, uint8(27))), "65-byte sig accepted");
    }

    function test_P256_SwitchBackToECDSA() public {
        (uint256 x, uint256 y) = vm.publicKeyP256(PASSKEY_PK);
        vm.prank(admin);
        signer.setP256Signer(bytes32(x), bytes32(y));
        vm.prank(admin);
        signer.setOwner(ownerAddr); // re-arms ECDSA
        assertEq(uint8(signer.signerType()), uint8(IAccountSigner.SignerType.ECDSA), "type not reset");
        bytes32 digest = keccak256("back to ecdsa");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);
        assertTrue(signer.rawValidate(digest, abi.encodePacked(r, s, v)), "ECDSA owner sig rejected after switch");
    }

    function test_SetP256Signer_RevertNotAdmin() public {
        (uint256 x, uint256 y) = vm.publicKeyP256(PASSKEY_PK);
        vm.prank(stranger);
        vm.expectRevert();
        signer.setP256Signer(bytes32(x), bytes32(y));
    }

    function test_SetP256Signer_RevertZeroKey() public {
        vm.prank(admin);
        vm.expectRevert(IAccountSigner.InvalidP256Key.selector);
        signer.setP256Signer(bytes32(0), bytes32(0));
    }

    // ---- WebAuthn passkey owner ----

    function _webauthnSig(uint256 pk, bytes32 challenge, bool uvFlagSet) internal returns (bytes memory) {
        bytes memory authData =
            abi.encodePacked(keccak256("lattice.rp"), bytes1(uint8(uvFlagSet ? 5 : 1)), bytes4(0x00000001));
        string memory chB64 = Base64.encode(abi.encodePacked(challenge), true, true); // URL-safe, no padding
        string memory head = '{"type":"webauthn.get",';
        string memory cdj = string.concat(head, '"challenge":"', chB64, '","origin":"https://lattice.xyz"}');
        bytes32 message = sha256(abi.encodePacked(authData, sha256(bytes(cdj))));
        (bytes32 r, bytes32 s) = _signP256Low(pk, message);
        return abi.encode(
            WebAuthn.WebAuthnAuth({
                authenticatorData: authData,
                clientDataJSON: cdj,
                challengeIndex: bytes(head).length,
                typeIndex: 1,
                r: r,
                s: s
            })
        );
    }

    function test_WebAuthn_Valid() public {
        (uint256 x, uint256 y) = vm.publicKeyP256(PASSKEY_PK);
        vm.expectEmit(false, false, false, true, address(signer));
        emit IAccountSigner.WebAuthnSignerSet(bytes32(x), bytes32(y), false);
        vm.prank(admin);
        signer.setWebAuthnSigner(bytes32(x), bytes32(y), false);
        assertEq(uint8(signer.signerType()), uint8(IAccountSigner.SignerType.WebAuthn), "type not WebAuthn");
        bytes32 challenge = keccak256("webauthn challenge");
        assertTrue(signer.rawValidate(challenge, _webauthnSig(PASSKEY_PK, challenge, false)), "valid passkey rejected");
    }

    function test_WebAuthn_RequireUserVerification() public {
        (uint256 x, uint256 y) = vm.publicKeyP256(PASSKEY_PK);
        vm.prank(admin);
        signer.setWebAuthnSigner(bytes32(x), bytes32(y), true); // UV required
        bytes32 challenge = keccak256("uv challenge");
        assertTrue(signer.rawValidate(challenge, _webauthnSig(PASSKEY_PK, challenge, true)), "UV assertion rejected");
        assertFalse(
            signer.rawValidate(challenge, _webauthnSig(PASSKEY_PK, challenge, false)), "non-UV assertion accepted"
        );
    }

    function test_WebAuthn_MalformedRejected() public {
        (uint256 x, uint256 y) = vm.publicKeyP256(PASSKEY_PK);
        vm.prank(admin);
        signer.setWebAuthnSigner(bytes32(x), bytes32(y), false);
        assertFalse(signer.rawValidate(keccak256("c"), abi.encode("not a webauthn envelope")), "malformed accepted");
    }
}
