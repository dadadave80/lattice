// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC4337Validation} from "@lattice/accounts/ERC4337Validation.sol";
import {ERC7821Executor} from "@lattice/accounts/ERC7821Executor.sol";
import {SignerECDSA} from "@lattice/accounts/SignerECDSA.sol";
import {ERC4337ValidationLib} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {ERC7821ExecutorLib} from "@lattice/accounts/libraries/ERC7821ExecutorLib.sol";
import {SignerECDSALib} from "@lattice/accounts/libraries/SignerECDSALib.sol";
import {IERC7821Executor} from "@lattice/interfaces/IERC7821Executor.sol";
import {INonces} from "@lattice/interfaces/INonces.sol";
import {ISessionKey} from "@lattice/interfaces/ISessionKey.sol";
import {Call} from "@lattice/interfaces/external/IERC7821.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Harness: executor + 4337 validation (EntryPoint auth) + signer + EIP-712 domain + nonces.
contract MockERC7821 is AccessControl, SignerECDSA, ERC4337Validation, ERC7821Executor {
    function initialize(address admin_, address owner_, address entryPoint_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        EIP712Lib.__EIP712_init("LatticeAccount", "1");
        NoncesLib.__Nonces_init();
        SignerECDSALib.__SignerECDSA_init(owner_);
        ERC4337ValidationLib.__ERC4337Validation_init(entryPoint_);
        ERC7821ExecutorLib.__ERC7821Executor_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) public view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

/// @dev Call target that records the last value + total ETH received, and a reverting function.
contract Target {
    uint256 public value;
    uint256 public received;

    function setValue(uint256 v) external payable {
        value = v;
        received += msg.value;
    }

    function boom() external pure {
        revert("boom");
    }
}

contract ERC7821ExecutorTester is Test {
    MockERC7821 account;
    Target target;
    address admin = address(0x1);
    address entryPointAddr = address(0xE47);
    address ownerAddr;
    uint256 ownerPk;
    address stranger;
    uint256 strangerPk;

    string constant NAME = "LatticeAccount";
    string constant VERSION = "1";

    bytes32 constant BATCH = 0x0100000000000000000000000000000000000000000000000000000000000000;
    bytes32 constant BATCH_OPDATA = 0x0100000000007821000100000000000000000000000000000000000000000000;
    bytes32 constant BAD_MODE = 0x0200000000000000000000000000000000000000000000000000000000000000;
    bytes4 constant IERC7821_ID = 0x39922547;
    bytes32 constant EXECUTE_TYPEHASH = 0xb63526befbf5b966e64c36954eb12c5d09096e0b0a8a06e90bd0c857b842ebcb;
    bytes32 constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function setUp() public {
        (ownerAddr, ownerPk) = makeAddrAndKey("owner");
        (stranger, strangerPk) = makeAddrAndKey("stranger");
        account = new MockERC7821();
        account.initialize(admin, ownerAddr, entryPointAddr);
        target = new Target();
    }

    function _oneCall(uint256 v, uint256 weiValue) internal view returns (Call[] memory calls) {
        calls = new Call[](1);
        calls[0] = Call({target: address(target), value: weiValue, data: abi.encodeCall(Target.setValue, (v))});
    }

    function _accountSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH, keccak256(bytes(NAME)), keccak256(bytes(VERSION)), block.chainid, address(account)
            )
        );
    }

    /// @dev Builds the owner-signed opData envelope `abi.encode(nonce, signature)` for a batch.
    function _signOpData(uint256 pk, bytes32 mode, Call[] memory calls, uint256 nonce)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(EXECUTE_TYPEHASH, mode, keccak256(abi.encode(calls)), nonce));
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", _accountSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encode(nonce, abi.encodePacked(r, s, v));
    }

    // ---- direct authorization (unchanged behavior) ----

    function test_SupportsMode() public view {
        assertTrue(account.supportsExecutionMode(BATCH), "batch unsupported");
        assertTrue(account.supportsExecutionMode(BATCH_OPDATA), "opData batch unsupported");
        assertFalse(account.supportsExecutionMode(BAD_MODE), "bad mode reported supported");
    }

    function test_SupportsInterface() public view {
        assertTrue(account.supportsInterface(IERC7821_ID), "IERC7821 not registered");
    }

    function test_ExecuteBatch_AsAdmin() public {
        vm.expectEmit(true, false, false, true, address(account));
        emit IERC7821Executor.BatchExecuted(BATCH, 1);
        vm.prank(admin);
        account.execute(BATCH, abi.encode(_oneCall(42, 0)));
        assertEq(target.value(), 42, "call not executed");
    }

    function test_ExecuteBatch_AsEntryPoint() public {
        vm.prank(entryPointAddr);
        account.execute(BATCH, abi.encode(_oneCall(7, 0)));
        assertEq(target.value(), 7, "entryPoint call not executed");
    }

    function test_ExecuteBatch_AsSelf() public {
        vm.prank(address(account));
        account.execute(BATCH, abi.encode(_oneCall(9, 0)));
        assertEq(target.value(), 9, "self call not executed");
    }

    function test_ExecuteBatch_ForwardsValue() public {
        vm.deal(address(account), 1 ether);
        vm.prank(admin);
        account.execute(BATCH, abi.encode(_oneCall(5, 0.5 ether)));
        assertEq(target.value(), 5, "value call not executed");
        assertEq(target.received(), 0.5 ether, "ETH not forwarded");
    }

    /// @dev An admin is directly authorized, so opData is ignored even when present (here empty).
    function test_ExecuteBatch_OpData_DirectAdmin() public {
        Call[] memory calls = _oneCall(11, 0);
        vm.prank(admin);
        account.execute(BATCH_OPDATA, abi.encode(calls, bytes("")));
        assertEq(target.value(), 11, "opData batch not executed");
    }

    function test_Execute_RevertUnauthorized() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IERC7821Executor.UnauthorizedExecutor.selector, stranger));
        account.execute(BATCH, abi.encode(_oneCall(1, 0)));
    }

    function test_Execute_RevertUnsupportedMode() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IERC7821Executor.UnsupportedExecutionMode.selector, BAD_MODE));
        account.execute(BAD_MODE, abi.encode(_oneCall(1, 0)));
    }

    function test_Execute_BubblesRevert() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(Target.boom, ())});
        vm.prank(admin);
        vm.expectRevert(bytes("boom"));
        account.execute(BATCH, abi.encode(calls));
    }

    // ---- signed opData (relayer-submitted, owner-authorized) ----

    function test_SignedOpData_AsRelayer() public {
        Call[] memory calls = _oneCall(77, 0);
        bytes memory opData = _signOpData(ownerPk, BATCH_OPDATA, calls, 0);
        vm.prank(stranger); // an unauthorized relayer
        account.execute(BATCH_OPDATA, abi.encode(calls, opData));
        assertEq(target.value(), 77, "owner-signed batch not executed by relayer");
    }

    /// @dev A non-owner signer is treated as a session key; an unregistered one is rejected.
    function test_SignedOpData_RejectsUnknownSigner() public {
        Call[] memory calls = _oneCall(1, 0);
        bytes memory opData = _signOpData(strangerPk, BATCH_OPDATA, calls, 0); // neither owner nor a session key
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ISessionKey.SessionKeyNotActive.selector, stranger));
        account.execute(BATCH_OPDATA, abi.encode(calls, opData));
    }

    function test_SignedOpData_RejectsReplay() public {
        Call[] memory calls = _oneCall(1, 0);
        bytes memory opData = _signOpData(ownerPk, BATCH_OPDATA, calls, 0);
        vm.prank(stranger);
        account.execute(BATCH_OPDATA, abi.encode(calls, opData)); // nonce 0 consumed
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(INonces.InvalidAccountNonce.selector, address(account), 1));
        account.execute(BATCH_OPDATA, abi.encode(calls, opData)); // replay: account nonce is now 1
    }

    function test_SignedOpData_RejectsWrongNonce() public {
        Call[] memory calls = _oneCall(1, 0);
        bytes memory opData = _signOpData(ownerPk, BATCH_OPDATA, calls, 5); // wrong nonce (current is 0)
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(INonces.InvalidAccountNonce.selector, address(account), 0));
        account.execute(BATCH_OPDATA, abi.encode(calls, opData));
    }
}
