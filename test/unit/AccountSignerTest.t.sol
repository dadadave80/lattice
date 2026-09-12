// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {AccountBlueprintHelper} from "@lattice-test/helpers/AccountBlueprintHelper.sol";
import {MockHederaAccountService} from "@lattice-test/mocks/hedera/MockHederaAccountService.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC4337Validation} from "@lattice/accounts/ERC4337Validation.sol";
import {AccountInit} from "@lattice/accounts/erc7579/AccountInit.sol";
import {AccountSigner} from "@lattice/accounts/erc7579/AccountSigner.sol";
import {HAS_SYSTEM_CONTRACT} from "@lattice/accounts/hedera/HASSignatureVerifierLib.sol";
import {AccountSignerLib} from "@lattice/accounts/libraries/AccountSignerLib.sol";
import {IAccountSigner} from "@lattice/interfaces/accounts/IAccountSigner.sol";
import {PackedUserOperation} from "@lattice/interfaces/external/ercs/IAccount.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Base64} from "@lattice/utils/libraries/Base64.sol";
import {ECDSA} from "@lattice/utils/libraries/ECDSA.sol";
import {WebAuthn} from "@lattice/utils/libraries/WebAuthn.sol";

/// @dev Test harness: the signer facet + access facet, with an `initialize` that runs the module inits.
contract MockAccountSigner is AccessControl, AccountSigner, Initializable {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(AccessControl, AccountSigner) returns (bytes memory) {}

    function initialize(address admin_, address owner_) external initializer {
        AccessControlLib.__AccessControl_init(admin_);
        AccountSignerLib.__AccountSigner_init(owner_);
    }

    /// @dev Exposes the internal signer seam for direct unit coverage.
    function rawValidate(bytes32 hash, bytes calldata signature) external view returns (bool) {
        return AccountSignerLib.isValidSignatureNow(hash, signature);
    }
}

contract AccountSignerTest is AccountBlueprintHelper {
    MockAccountSigner signer;
    address admin = address(0x1);
    address ownerAddr;
    uint256 ownerPk;
    address stranger;
    uint256 strangerPk;
    address hederaAddr; // ECDSA-keyed Hedera account: its EVM alias IS the recovered address
    uint256 hederaPk;

    function setUp() public {
        (ownerAddr, ownerPk) = makeAddrAndKey("owner");
        (stranger, strangerPk) = makeAddrAndKey("stranger");
        (hederaAddr, hederaPk) = makeAddrAndKey("hederaAccount");
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
        return WebAuthn.tryEncodeAuthCompact(
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

    /// @dev The reason the WebAuthn path uses the compact codec: it's materially smaller than the ABI envelope,
    ///      which is what dominates a passkey UserOp's calldata cost.
    function test_WebAuthn_CompactEncodingIsSmaller() public pure {
        WebAuthn.WebAuthnAuth memory auth = WebAuthn.WebAuthnAuth({
            authenticatorData: abi.encodePacked(keccak256("lattice.rp"), bytes1(uint8(1)), bytes4(0x00000001)),
            clientDataJSON: '{"type":"webauthn.get","challenge":"abc","origin":"https://lattice.xyz"}',
            challengeIndex: 23,
            typeIndex: 1,
            r: bytes32(uint256(1)),
            s: bytes32(uint256(2))
        });
        bytes memory compact = WebAuthn.tryEncodeAuthCompact(auth);
        assertGt(compact.length, 0, "compact encode failed");
        assertLt(compact.length, abi.encode(auth).length, "compact not smaller than the ABI envelope");
    }

    // ---- native Hedera account owner (HIP-632, through the HAS system contract at 0x16a) ----

    address constant HEDERA_ENTRY_POINT = address(0xE417);
    /// @dev A Hedera account whose key is ED25519 has no EVM alias to recover — it is a long-zero address.
    address constant ED25519_ACCOUNT = address(0x0000000000000000000000000000000000000457);

    MockHederaAccountService hederaService; // the etched stand-in living at 0x16a

    /// @dev Assembles a REAL account diamond from the canonical {DeployAccount} blueprint, etches the HAS
    ///      mock at 0x16a, and repoints the signer at `hederaAccount`. The account administers itself
    ///      ({AccountInit} grants it `DEFAULT_ADMIN_ROLE`), so every setter is pranked as the diamond.
    function _hederaAccountDiamond(address hederaAccount) internal returns (address account) {
        account = _newAccountDiamond();
        hederaService = MockHederaAccountService(HAS_SYSTEM_CONTRACT);
        vm.etch(HAS_SYSTEM_CONTRACT, address(new MockHederaAccountService()).code);
        vm.prank(account);
        AccountSigner(account).setHederaAccountSigner(hederaAccount);
    }

    /// @dev A complete single-owner account diamond owned (ECDSA) by `ownerAddr`.
    function _newAccountDiamond() internal returns (address account) {
        (FacetCut[] memory cuts, AccountInit init) = _accountBlueprint(HEDERA_ENTRY_POINT);
        Lattice diamond = new Lattice();
        diamond.initialize(cuts, address(init), abi.encodeCall(AccountInit.init, (ownerAddr)));
        account = address(diamond);
    }

    /// @dev Drives the ERC-4337 seam: the EntryPoint validating `signature` over `opHash`. Returns
    ///      `validationData` (0 = accepted, 1 = SIG_VALIDATION_FAILED).
    function _validateUserOp(address account, bytes32 opHash, bytes memory signature) internal returns (uint256) {
        PackedUserOperation memory op;
        op.sender = account;
        op.signature = signature;
        vm.prank(HEDERA_ENTRY_POINT);
        return ERC4337Validation(payable(account)).validateUserOp(op, opHash, 0);
    }

    /// @dev The digest the signer seam actually sees for a user op (EIP-191 over the user op hash).
    function _opDigest(bytes32 opHash) internal pure returns (bytes32) {
        return ECDSA.toEthSignedMessageHash(opHash);
    }

    function test_Hedera_SetSignerEmitsAndSwitchesType() public {
        address account = _newAccountDiamond();
        vm.expectEmit(true, false, false, true, account);
        emit IAccountSigner.HederaAccountSignerSet(hederaAddr);
        vm.prank(account);
        AccountSigner(account).setHederaAccountSigner(hederaAddr);
        assertEq(
            uint8(AccountSigner(account).signerType()),
            uint8(IAccountSigner.SignerType.HederaAccount),
            "type not HederaAccount"
        );
        assertEq(AccountSigner(account).owner(), hederaAddr, "Hedera account not stored as the owner");
    }

    /// @dev The switch must leave no stale passkey material behind.
    function test_Hedera_SetSignerClearsPasskeyFields() public {
        address account = _newAccountDiamond();
        (uint256 x, uint256 y) = vm.publicKeyP256(PASSKEY_PK);
        vm.prank(account);
        AccountSigner(account).setWebAuthnSigner(bytes32(x), bytes32(y), true);
        vm.prank(account);
        AccountSigner(account).setHederaAccountSigner(hederaAddr);
        (bytes32 px, bytes32 py) = AccountSigner(account).p256PublicKey();
        assertEq(px, bytes32(0), "P256 X not cleared");
        assertEq(py, bytes32(0), "P256 Y not cleared");
        assertFalse(AccountSigner(account).requireUserVerification(), "UV policy not cleared");
    }

    function test_Hedera_SetSignerRevertZero() public {
        address account = _newAccountDiamond();
        vm.prank(account);
        vm.expectRevert(IAccountSigner.InvalidOwner.selector);
        AccountSigner(account).setHederaAccountSigner(address(0));
    }

    function test_Hedera_SetSignerRevertNotAdmin() public {
        address account = _newAccountDiamond();
        vm.prank(stranger);
        vm.expectRevert();
        AccountSigner(account).setHederaAccountSigner(hederaAddr);
    }

    /// @dev ECDSA-keyed Hedera account: HAS recovers the EVM alias from the 65-byte blob and it matches.
    function test_Hedera_EcdsaSignatureAccepted() public {
        address account = _hederaAccountDiamond(hederaAddr);
        bytes32 opHash = keccak256("hedera user op");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(hederaPk, _opDigest(opHash));
        assertEq(_validateUserOp(account, opHash, abi.encodePacked(r, s, v)), 0, "HAS ECDSA signature rejected");
    }

    function test_Hedera_EcdsaWrongSignerRejected() public {
        address account = _hederaAccountDiamond(hederaAddr);
        bytes32 opHash = keccak256("hedera user op");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(strangerPk, _opDigest(opHash));
        assertEq(_validateUserOp(account, opHash, abi.encodePacked(r, s, v)), 1, "stranger signature accepted");
    }

    /// @dev ED25519 has no EVM precompile, so the network answers from its own key lookup — modelled here by
    ///      the mock's fixture table over (account, messageHash, signature).
    function test_Hedera_Ed25519AuthorizedAccepted() public {
        address account = _hederaAccountDiamond(ED25519_ACCOUNT);
        bytes32 opHash = keccak256("ed25519 user op");
        bytes memory sig = _ed25519Sig();
        hederaService.setEd25519Authorized(ED25519_ACCOUNT, _opDigest(opHash), sig, true);
        assertEq(_validateUserOp(account, opHash, sig), 0, "authorized ED25519 signature rejected");
    }

    function test_Hedera_Ed25519UnauthorizedRejected() public {
        address account = _hederaAccountDiamond(ED25519_ACCOUNT);
        bytes32 opHash = keccak256("ed25519 user op");
        assertEq(_validateUserOp(account, opHash, _ed25519Sig()), 1, "unauthorized ED25519 signature accepted");
    }

    /// @dev THE never-revert proof: the system contract reverts on a blob that is neither 64 nor 65 bytes, and
    ///      the seam must still return `false` — so the 4337 path yields SIG_VALIDATION_FAILED, not a revert.
    function test_Hedera_MalformedSignatureFailsWithoutReverting() public {
        address account = _hederaAccountDiamond(hederaAddr);
        bytes32 opHash = keccak256("hedera user op");
        bytes memory malformed = hex"00112233445566778899"; // 10 bytes: the mock reverts on this length
        vm.expectRevert(MockHederaAccountService.InvalidTransactionBody.selector);
        MockHederaAccountService(HAS_SYSTEM_CONTRACT)
            .isAuthorizedRaw(hederaAddr, abi.encodePacked(_opDigest(opHash)), malformed);
        assertEq(_validateUserOp(account, opHash, malformed), 1, "malformed signature did not fail safely");
    }

    /// @dev Switching back is a plain `setOwner`, which re-arms the ECDSA scheme (the Hedera branch is gone).
    function test_Hedera_SetOwnerReArmsEcdsa() public {
        address account = _hederaAccountDiamond(hederaAddr);
        vm.prank(account);
        AccountSigner(account).setOwner(ownerAddr);
        assertEq(uint8(AccountSigner(account).signerType()), uint8(IAccountSigner.SignerType.ECDSA), "type not reset");
        bytes32 opHash = keccak256("back to ecdsa op");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, _opDigest(opHash));
        assertEq(_validateUserOp(account, opHash, abi.encodePacked(r, s, v)), 0, "ECDSA owner sig rejected");
        (v, r, s) = vm.sign(hederaPk, _opDigest(opHash));
        assertEq(_validateUserOp(account, opHash, abi.encodePacked(r, s, v)), 1, "Hedera account still authorized");
    }

    /// @dev A 64-byte stand-in for an ED25519 signature (the mock keys its fixture table on the exact bytes).
    function _ed25519Sig() internal pure returns (bytes memory) {
        return abi.encodePacked(keccak256("ed25519-R"), keccak256("ed25519-S"));
    }
}
