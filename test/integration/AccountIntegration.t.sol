// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC1271Signature} from "@lattice/accounts/ERC1271Signature.sol";
import {ERC4337Validation} from "@lattice/accounts/ERC4337Validation.sol";
import {AccountSigner} from "@lattice/accounts/erc7579/AccountSigner.sol";
import {ERC7821Executor} from "@lattice/accounts/erc7579/ERC7821Executor.sol";
import {ERC7821ExecutorLib} from "@lattice/accounts/erc7579/libraries/ERC7821ExecutorLib.sol";
import {AccountSignerLib} from "@lattice/accounts/libraries/AccountSignerLib.sol";
import {ERC1271SignatureLib} from "@lattice/accounts/libraries/ERC1271SignatureLib.sol";
import {ERC4337ValidationLib} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {IAccount, PackedUserOperation} from "@lattice/interfaces/external/ercs/IAccount.sol";
import {Call, IERC7821} from "@lattice/interfaces/external/ercs/IERC7821.sol";
import {Base64} from "@lattice/utils/libraries/Base64.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {WebAuthn} from "@lattice/utils/libraries/WebAuthn.sol";
import {Test} from "forge-std/Test.sol";

/// @dev A Lattice account assembled from all four v1 facets — the shape a deployed Diamond would have.
contract LatticeAccount is AccessControl, AccountSigner, ERC1271Signature, ERC4337Validation, ERC7821Executor {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(AccessControl, AccountSigner, ERC1271Signature, ERC4337Validation, ERC7821Executor)
        returns (bytes memory)
    {}

    function initialize(address admin_, address owner_, address entryPoint_) external {
        bytes32 s = InitializableLib.initializableSlot();
        s = InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        EIP712Lib.__EIP712_init("LatticeAccount", "1");
        AccountSignerLib.__AccountSigner_init(owner_);
        ERC1271SignatureLib.__ERC1271Signature_init();
        ERC4337ValidationLib.__ERC4337Validation_init(entryPoint_);
        ERC7821ExecutorLib.__ERC7821Executor_init();
        InitializableLib.postInitializer(s);
    }
}

/// @dev Minimal EntryPoint: validates the op against the account, then runs its callData (as the EntryPoint).
contract MockEntryPoint {
    error ValidationFailed(uint256 validationData);

    function handleUserOp(address account, PackedUserOperation calldata op, bytes32 userOpHash, uint256 prefund)
        external
    {
        uint256 validationData = IAccount(account).validateUserOp(op, userOpHash, prefund);
        if (validationData != 0) revert ValidationFailed(validationData);
        (bool ok, bytes memory ret) = account.call(op.callData);
        if (!ok) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }

    receive() external payable {}
}

contract Target {
    uint256 public value;

    function setValue(uint256 v) external {
        value = v;
    }
}

/// @dev External contract that gates on the account's ERC-1271 signature (as Seaport/Permit2 would).
contract Consumer {
    bytes4 constant MAGIC = 0x1626ba7e;

    function accepts(address account, bytes32 hash, bytes calldata sig) external view returns (bool) {
        return ERC1271Signature(payable(account)).isValidSignature(hash, sig) == MAGIC;
    }
}

contract AccountIntegration is Test {
    LatticeAccount account;
    MockEntryPoint entryPoint;
    Target target;
    Consumer consumer;

    address admin = address(0x1);
    address ownerAddr;
    uint256 ownerPk;

    bytes32 constant BATCH = 0x0100000000000000000000000000000000000000000000000000000000000000;

    function setUp() public {
        (ownerAddr, ownerPk) = makeAddrAndKey("owner");
        entryPoint = new MockEntryPoint();
        account = new LatticeAccount();
        account.initialize(admin, ownerAddr, address(entryPoint));
        target = new Target();
        consumer = new Consumer();
    }

    function _signOp(bytes32 userOpHash, bytes memory callData) internal view returns (PackedUserOperation memory op) {
        op.sender = address(account);
        op.callData = callData;
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, ethHash);
        op.signature = abi.encodePacked(r, s, v);
    }

    function test_FullUserOpFlow() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(Target.setValue, (42))});
        bytes memory callData = abi.encodeCall(IERC7821.execute, (BATCH, abi.encode(calls)));

        bytes32 userOpHash = keccak256("op1");
        PackedUserOperation memory op = _signOp(userOpHash, callData);

        entryPoint.handleUserOp(address(account), op, userOpHash, 0);
        assertEq(target.value(), 42, "batch not executed via EntryPoint");
    }

    function test_FullUserOpFlow_RejectsBadSignature() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(Target.setValue, (99))});
        bytes memory callData = abi.encodeCall(IERC7821.execute, (BATCH, abi.encode(calls)));

        bytes32 userOpHash = keccak256("op2");
        PackedUserOperation memory op = _signOp(userOpHash, callData);
        // tamper: validate against a different hash, so the signature no longer matches
        bytes32 wrongHash = keccak256("other");

        vm.expectRevert(abi.encodeWithSelector(MockEntryPoint.ValidationFailed.selector, uint256(1)));
        entryPoint.handleUserOp(address(account), op, wrongHash, 0);
        assertEq(target.value(), 0, "should not have executed");
    }

    function test_PrefundPaidDuringValidation() public {
        vm.deal(address(account), 1 ether);
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(Target.setValue, (1))});
        bytes memory callData = abi.encodeCall(IERC7821.execute, (BATCH, abi.encode(calls)));

        bytes32 userOpHash = keccak256("op3");
        PackedUserOperation memory op = _signOp(userOpHash, callData);

        uint256 before = address(entryPoint).balance;
        entryPoint.handleUserOp(address(account), op, userOpHash, 0.3 ether);
        assertEq(address(entryPoint).balance - before, 0.3 ether, "prefund not received by EntryPoint");
        assertEq(target.value(), 1, "batch not executed");
    }

    function test_ExternalConsumerAcceptsOwner1271Sig() public view {
        // Owner wraps the order hash in this account's domain (ERC-7739 PersonalSign); a plain sig is rejected.
        bytes32 orderHash = keccak256("seaport order");
        bytes32 sep = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("LatticeAccount"),
                keccak256("1"),
                block.chainid,
                address(account)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(bytes32(0x983e65e5148e570cd828ead231ee759a8d7958721a768f93bc4483ba005c32de), orderHash)
        );
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", sep, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);
        assertTrue(consumer.accepts(address(account), orderHash, abi.encodePacked(r, s, v)), "1271 sig rejected");
    }

    // ---- passkey owners (P256 / WebAuthn) ----

    uint256 constant P256_N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551;
    uint256 constant PASSKEY_PK = 0xC0FFEE;
    bytes32 constant PERSONAL_SIGN_TYPEHASH = 0x983e65e5148e570cd828ead231ee759a8d7958721a768f93bc4483ba005c32de;
    bytes32 constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function _signP256Low(uint256 pk, bytes32 digest) internal returns (bytes32 r, bytes32 s) {
        (r, s) = vm.signP256(pk, digest);
        if (uint256(s) > P256_N / 2) s = bytes32(P256_N - uint256(s));
    }

    function _webauthnSig(uint256 pk, bytes32 challenge) internal returns (bytes memory) {
        bytes memory authData = abi.encodePacked(keccak256("lattice.rp"), bytes1(uint8(1)), bytes4(0x00000001));
        string memory chB64 = Base64.encode(abi.encodePacked(challenge), true, true);
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

    /// @dev A P256-passkey-owned account validates AND executes a userOp end-to-end via the EntryPoint.
    function test_P256Owner_FullUserOpFlow() public {
        (uint256 x, uint256 y) = vm.publicKeyP256(PASSKEY_PK);
        vm.prank(admin);
        account.setP256Signer(bytes32(x), bytes32(y));

        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(Target.setValue, (55))});
        bytes memory callData = abi.encodeCall(IERC7821.execute, (BATCH, abi.encode(calls)));

        bytes32 userOpHash = keccak256("p256 op");
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));
        (bytes32 r, bytes32 s) = _signP256Low(PASSKEY_PK, ethHash);

        PackedUserOperation memory op;
        op.sender = address(account);
        op.callData = callData;
        op.signature = abi.encodePacked(r, s); // 64-byte P256

        entryPoint.handleUserOp(address(account), op, userOpHash, 0);
        assertEq(target.value(), 55, "P256 userOp batch not executed");
    }

    /// @dev A WebAuthn-passkey-owned account satisfies an external ERC-1271 / ERC-7739 consumer.
    function test_WebAuthnOwner_ERC1271Consumer() public {
        (uint256 x, uint256 y) = vm.publicKeyP256(PASSKEY_PK);
        vm.prank(admin);
        account.setWebAuthnSigner(bytes32(x), bytes32(y), false);

        bytes32 orderHash = keccak256("seaport order");
        bytes32 sep = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256("LatticeAccount"), keccak256("1"), block.chainid, address(account))
        );
        bytes32 structHash = keccak256(abi.encode(PERSONAL_SIGN_TYPEHASH, orderHash));
        bytes32 nested = keccak256(abi.encodePacked(hex"1901", sep, structHash)); // ERC-7739 PersonalSign digest

        bytes memory envelope = _webauthnSig(PASSKEY_PK, nested); // passkey signs over the nested digest
        assertTrue(consumer.accepts(address(account), orderHash, envelope), "WebAuthn 1271 rejected");
    }
}
