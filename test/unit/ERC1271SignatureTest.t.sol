// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccountBlueprintHelper} from "@lattice-test/helpers/AccountBlueprintHelper.sol";
import {MockHederaAccountService} from "@lattice-test/mocks/hedera/MockHederaAccountService.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC1271Signature} from "@lattice/accounts/ERC1271Signature.sol";
import {AccountInit} from "@lattice/accounts/erc7579/AccountInit.sol";
import {AccountSigner} from "@lattice/accounts/erc7579/AccountSigner.sol";
import {HAS_SYSTEM_CONTRACT} from "@lattice/accounts/hedera/HASSignatureVerifierLib.sol";
import {AccountSignerLib} from "@lattice/accounts/libraries/AccountSignerLib.sol";
import {ERC1271SignatureLib} from "@lattice/accounts/libraries/ERC1271SignatureLib.sol";
import {IAccountSigner} from "@lattice/interfaces/accounts/IAccountSigner.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";

/// @dev Harness: 1271 facet + signer facet + access facet + EIP-712 domain, with an `initialize` that runs the
///      module inits.
contract MockERC1271 is AccessControl, AccountSigner, ERC1271Signature, Initializable {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(AccessControl, AccountSigner, ERC1271Signature)
        returns (bytes memory)
    {}

    function initialize(address admin_, address owner_, string memory name_, string memory version_)
        external
        initializer
    {
        AccessControlLib.__AccessControl_init(admin_);
        EIP712Lib.__EIP712_init(name_, version_);
        AccountSignerLib.__AccountSigner_init(owner_);
        ERC1271SignatureLib.__ERC1271Signature_init();
    }

    function supportsInterface(bytes4 id) public view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

contract ERC1271SignatureTest is AccountBlueprintHelper {
    MockERC1271 account;
    address admin = address(0x1);
    address ownerAddr;
    uint256 ownerPk;
    address stranger;
    uint256 strangerPk;

    string constant NAME = "LatticeAccount";
    string constant VERSION = "1";

    bytes4 constant MAGIC = 0x1626ba7e;
    bytes4 constant INVALID = 0xffffffff;
    bytes4 constant ERC7739_SUPPORT = 0x77390001;
    bytes32 constant SENTINEL = 0x7739773977397739773977397739773977397739773977397739773977397739;
    bytes32 constant PERSONAL_SIGN_TYPEHASH = 0x983e65e5148e570cd828ead231ee759a8d7958721a768f93bc4483ba005c32de;
    bytes32 constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    address hederaAddr; // ECDSA-keyed Hedera account: its EVM alias IS the recovered address
    uint256 hederaPk;

    function setUp() public {
        (ownerAddr, ownerPk) = makeAddrAndKey("owner");
        (stranger, strangerPk) = makeAddrAndKey("stranger");
        (hederaAddr, hederaPk) = makeAddrAndKey("hederaAccount");
        account = new MockERC1271();
        account.initialize(admin, ownerAddr, NAME, VERSION);
    }

    function _accountSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH, keccak256(bytes(NAME)), keccak256(bytes(VERSION)), block.chainid, address(account)
            )
        );
    }

    function _toTypedDataHash(bytes32 separator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(hex"1901", separator, structHash));
    }

    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_SupportsInterface() public view {
        assertTrue(account.supportsInterface(MAGIC), "IERC1271 not registered");
    }

    function test_Sentinel() public view {
        assertEq(account.isValidSignature(SENTINEL, ""), ERC7739_SUPPORT, "7739 support sentinel not returned");
    }

    function test_PersonalSign_Valid() public view {
        bytes32 appHash = keccak256("a message to sign");
        bytes32 structHash = keccak256(abi.encode(PERSONAL_SIGN_TYPEHASH, appHash));
        bytes32 digest = _toTypedDataHash(_accountSeparator(), structHash);
        assertEq(account.isValidSignature(appHash, _sign(ownerPk, digest)), MAGIC, "PersonalSign rejected");
    }

    function test_PersonalSign_WrongSigner() public view {
        bytes32 appHash = keccak256("a message to sign");
        bytes32 structHash = keccak256(abi.encode(PERSONAL_SIGN_TYPEHASH, appHash));
        bytes32 digest = _toTypedDataHash(_accountSeparator(), structHash);
        assertEq(
            account.isValidSignature(appHash, _sign(strangerPk, digest)), INVALID, "stranger PersonalSign accepted"
        );
    }

    /// @dev A plain signature over the raw hash (no nesting) MUST be rejected — this is the cross-account
    ///      replay protection ERC-7739 adds over plain ERC-1271.
    function test_RawSignatureRejected() public view {
        bytes32 appHash = keccak256("a message to sign");
        assertEq(account.isValidSignature(appHash, _sign(ownerPk, appHash)), INVALID, "raw signature accepted");
    }

    function test_TypedDataSign_Valid() public view {
        // App (dapp) EIP-712 domain + a Contents struct the dapp asks the user to sign.
        bytes32 appSep =
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("DApp"), keccak256("1"), block.chainid, address(0xDA99)));
        bytes32 contentsHash = keccak256(abi.encode(keccak256("Contents(bytes32 stuff)"), keccak256("payload")));
        string memory contentsDescr = "Contents(bytes32 stuff)"; // implicit form; name = "Contents"

        // What the dapp itself would verify: the app's typed-data hash.
        bytes32 outerHash = _toTypedDataHash(appSep, contentsHash);

        // The TypedDataSign struct binds the contents to THIS account's domain (salt = 0).
        bytes32 typedDataSignTypehash = keccak256(
            abi.encodePacked(
                "TypedDataSign(Contents contents,string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)",
                "Contents(bytes32 stuff)"
            )
        );
        bytes memory domainBytes =
            abi.encode(keccak256(bytes(NAME)), keccak256(bytes(VERSION)), block.chainid, address(account), bytes32(0));
        bytes32 tdsStructHash = keccak256(abi.encodePacked(typedDataSignTypehash, contentsHash, domainBytes));

        // Owner signs over the APP separator (not the account's).
        bytes memory innerSig = _sign(ownerPk, _toTypedDataHash(appSep, tdsStructHash));

        // Wire: innerSig ‖ appSep ‖ contentsHash ‖ contentsDescr ‖ uint16(len)
        bytes memory envelope =
            abi.encodePacked(innerSig, appSep, contentsHash, bytes(contentsDescr), uint16(bytes(contentsDescr).length));

        assertEq(account.isValidSignature(outerHash, envelope), MAGIC, "TypedDataSign rejected");
    }

    function test_TypedDataSign_WrongOuterHash() public view {
        bytes32 appSep =
            keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256("DApp"), keccak256("1"), block.chainid, address(0xDA99)));
        bytes32 contentsHash = keccak256(abi.encode(keccak256("Contents(bytes32 stuff)"), keccak256("payload")));
        string memory contentsDescr = "Contents(bytes32 stuff)";
        bytes32 typedDataSignTypehash = keccak256(
            abi.encodePacked(
                "TypedDataSign(Contents contents,string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)",
                "Contents(bytes32 stuff)"
            )
        );
        bytes memory domainBytes =
            abi.encode(keccak256(bytes(NAME)), keccak256(bytes(VERSION)), block.chainid, address(account), bytes32(0));
        bytes32 tdsStructHash = keccak256(abi.encodePacked(typedDataSignTypehash, contentsHash, domainBytes));
        bytes memory innerSig = _sign(ownerPk, _toTypedDataHash(appSep, tdsStructHash));
        bytes memory envelope =
            abi.encodePacked(innerSig, appSep, contentsHash, bytes(contentsDescr), uint16(bytes(contentsDescr).length));

        // Outer hash that does NOT match keccak(0x1901 || appSep || contentsHash) must be rejected.
        assertEq(account.isValidSignature(keccak256("wrong"), envelope), INVALID, "mismatched outer hash accepted");
    }

    // ---- native Hedera account owner (HIP-632, through the HAS system contract at 0x16a) ----

    address constant HEDERA_ENTRY_POINT = address(0xE417);
    /// @dev A Hedera account whose key is ED25519 has no EVM alias to recover — it is a long-zero address.
    address constant ED25519_ACCOUNT = address(0x0000000000000000000000000000000000000457);

    MockHederaAccountService hederaService; // the etched stand-in living at 0x16a

    /// @dev Assembles a REAL account diamond from the canonical {DeployAccount} blueprint (1271 facet cut in),
    ///      etches the HAS mock at 0x16a, and repoints the signer at `hederaAccount`. The account administers
    ///      itself ({AccountInit} grants it `DEFAULT_ADMIN_ROLE`), so the setter is pranked as the diamond.
    function _hederaAccountDiamond(address hederaAccount) internal returns (address diamond) {
        (FacetCut[] memory cuts, AccountInit init) = _accountBlueprint(HEDERA_ENTRY_POINT);
        Lattice d = new Lattice();
        d.initialize(cuts, address(init), abi.encodeCall(AccountInit.init, (ownerAddr)));
        diamond = address(d);
        hederaService = MockHederaAccountService(HAS_SYSTEM_CONTRACT);
        vm.etch(HAS_SYSTEM_CONTRACT, address(new MockHederaAccountService()).code);
        vm.prank(diamond);
        AccountSigner(diamond).setHederaAccountSigner(hederaAccount);
    }

    /// @dev The account blueprint does not seed an EIP-712 name/version, so the diamond's domain separator is
    ///      built from zero hashes — the digest the ERC-7739 `PersonalSign` path hands to the signer seam.
    function _personalSignDigest(address diamond, bytes32 appHash) internal view returns (bytes32) {
        bytes32 separator = keccak256(abi.encode(DOMAIN_TYPEHASH, bytes32(0), bytes32(0), block.chainid, diamond));
        return _toTypedDataHash(separator, keccak256(abi.encode(PERSONAL_SIGN_TYPEHASH, appHash)));
    }

    function test_Hedera_PersonalSign_Valid() public {
        address diamond = _hederaAccountDiamond(hederaAddr);
        bytes32 appHash = keccak256("a message for the hedera owner");
        bytes memory sig = _sign(hederaPk, _personalSignDigest(diamond, appHash));
        assertEq(ERC1271Signature(diamond).isValidSignature(appHash, sig), MAGIC, "HAS ECDSA PersonalSign rejected");
    }

    function test_Hedera_PersonalSign_WrongSigner() public {
        address diamond = _hederaAccountDiamond(hederaAddr);
        bytes32 appHash = keccak256("a message for the hedera owner");
        bytes memory sig = _sign(strangerPk, _personalSignDigest(diamond, appHash));
        assertEq(ERC1271Signature(diamond).isValidSignature(appHash, sig), INVALID, "stranger signature accepted");
    }

    function test_Hedera_Ed25519_Authorized() public {
        address diamond = _hederaAccountDiamond(ED25519_ACCOUNT);
        bytes32 appHash = keccak256("a message for the ed25519 owner");
        bytes memory sig = _ed25519Sig();
        hederaService.setEd25519Authorized(ED25519_ACCOUNT, _personalSignDigest(diamond, appHash), sig, true);
        assertEq(ERC1271Signature(diamond).isValidSignature(appHash, sig), MAGIC, "authorized ED25519 sig rejected");
    }

    function test_Hedera_Ed25519_Unauthorized() public {
        address diamond = _hederaAccountDiamond(ED25519_ACCOUNT);
        bytes32 appHash = keccak256("a message for the ed25519 owner");
        assertEq(
            ERC1271Signature(diamond).isValidSignature(appHash, _ed25519Sig()),
            INVALID,
            "unauthorized ED25519 sig accepted"
        );
    }

    /// @dev The system contract reverts on a blob that is neither 64 nor 65 bytes; ERC-1271 must still answer
    ///      `0xffffffff` instead of bubbling that revert up to the calling dapp.
    function test_Hedera_MalformedSignatureDoesNotRevert() public {
        address diamond = _hederaAccountDiamond(hederaAddr);
        bytes32 appHash = keccak256("a message for the hedera owner");
        bytes memory malformed = hex"00112233445566778899"; // 10 bytes: the mock reverts on this length
        assertEq(ERC1271Signature(diamond).isValidSignature(appHash, malformed), INVALID, "malformed sig accepted");
    }

    function test_Hedera_SetOwnerReArmsEcdsa() public {
        address diamond = _hederaAccountDiamond(hederaAddr);
        vm.prank(diamond);
        AccountSigner(diamond).setOwner(ownerAddr);
        assertEq(uint8(AccountSigner(diamond).signerType()), uint8(IAccountSigner.SignerType.ECDSA), "type not reset");
        bytes32 appHash = keccak256("back to ecdsa");
        bytes memory ownerSig = _sign(ownerPk, _personalSignDigest(diamond, appHash));
        assertEq(ERC1271Signature(diamond).isValidSignature(appHash, ownerSig), MAGIC, "ECDSA owner sig rejected");
        bytes memory hederaSig = _sign(hederaPk, _personalSignDigest(diamond, appHash));
        assertEq(
            ERC1271Signature(diamond).isValidSignature(appHash, hederaSig), INVALID, "Hedera account still authorized"
        );
    }

    /// @dev A 64-byte stand-in for an ED25519 signature (the mock keys its fixture table on the exact bytes).
    function _ed25519Sig() internal pure returns (bytes memory) {
        return abi.encodePacked(keccak256("ed25519-R"), keccak256("ed25519-S"));
    }
}
