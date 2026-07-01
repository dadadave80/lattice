// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC1271Signature} from "@lattice/accounts/ERC1271Signature.sol";
import {AccountSigner} from "@lattice/accounts/erc7579/AccountSigner.sol";
import {AccountSignerLib} from "@lattice/accounts/libraries/AccountSignerLib.sol";
import {ERC1271SignatureLib} from "@lattice/accounts/libraries/ERC1271SignatureLib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Harness: 1271 facet + signer facet + access facet + EIP-712 domain, with an `initialize` that runs the
///      module inits.
contract MockERC1271 is AccessControl, AccountSigner, ERC1271Signature {
    function initialize(address admin_, address owner_, string memory name_, string memory version_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        EIP712Lib.__EIP712_init(name_, version_);
        AccountSignerLib.__AccountSigner_init(owner_);
        ERC1271SignatureLib.__ERC1271Signature_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) public view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

contract ERC1271SignatureTest is Test {
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

    function setUp() public {
        (ownerAddr, ownerPk) = makeAddrAndKey("owner");
        (stranger, strangerPk) = makeAddrAndKey("stranger");
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
}
