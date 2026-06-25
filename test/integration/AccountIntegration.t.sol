// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC1271Signature} from "@lattice/accounts/ERC1271Signature.sol";
import {ERC4337Validation} from "@lattice/accounts/ERC4337Validation.sol";
import {ERC7821Executor} from "@lattice/accounts/ERC7821Executor.sol";
import {SignerECDSA} from "@lattice/accounts/SignerECDSA.sol";
import {ERC1271SignatureLib} from "@lattice/accounts/libraries/ERC1271SignatureLib.sol";
import {ERC4337ValidationLib} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {ERC7821ExecutorLib} from "@lattice/accounts/libraries/ERC7821ExecutorLib.sol";
import {SignerECDSALib} from "@lattice/accounts/libraries/SignerECDSALib.sol";
import {IAccount, PackedUserOperation} from "@lattice/interfaces/external/IAccount.sol";
import {Call, IERC7821} from "@lattice/interfaces/external/IERC7821.sol";
import {Test} from "forge-std/Test.sol";

/// @dev A Lattice account assembled from all four v1 facets — the shape a deployed Diamond would have.
contract LatticeAccount is AccessControl, SignerECDSA, ERC1271Signature, ERC4337Validation, ERC7821Executor {
    function initialize(address admin_, address owner_, address entryPoint_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        SignerECDSALib.__SignerECDSA_init(owner_);
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
        bytes32 hash = keccak256("seaport order");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, hash);
        assertTrue(consumer.accepts(address(account), hash, abi.encodePacked(r, s, v)), "1271 sig rejected");
    }
}
