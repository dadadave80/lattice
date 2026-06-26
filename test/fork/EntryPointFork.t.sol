// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AccountSigner} from "@lattice/accounts/AccountSigner.sol";
import {ERC4337Validation} from "@lattice/accounts/ERC4337Validation.sol";
import {ERC7821Executor} from "@lattice/accounts/ERC7821Executor.sol";
import {AccountSignerLib} from "@lattice/accounts/libraries/AccountSignerLib.sol";
import {DEFAULT_ENTRY_POINT, ERC4337ValidationLib} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {ERC7821ExecutorLib} from "@lattice/accounts/libraries/ERC7821ExecutorLib.sol";
import {IAccount, PackedUserOperation} from "@lattice/interfaces/external/IAccount.sol";
import {Call} from "@lattice/interfaces/external/IERC7821.sol";
import {IEntryPoint} from "@lattice/interfaces/external/IEntryPoint.sol";
import {ECDSA} from "@lattice/utils/libraries/ECDSA.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCKS
// ---------------------------------------------------------------------------

/// @notice Single-owner ERC-4337 account: signer + validation + executor facets, self-administering.
contract MockEntryPointAccount is AccessControl, AccountSigner, ERC4337Validation, ERC7821Executor {
    function initialize(address owner_, address entryPoint_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(address(this));
        AccountSignerLib.__AccountSigner_init(owner_);
        ERC4337ValidationLib.__ERC4337Validation_init(entryPoint_);
        ERC7821ExecutorLib.__ERC7821Executor_init();
        InitializableLib.postInitializer(s);
    }

    receive() external payable {}
}

/// @notice Observable execution target.
contract Target {
    uint256 public value;

    function bump(uint256 v) external {
        value = v;
    }
}

// ---------------------------------------------------------------------------
//                              FORK TESTS
// ---------------------------------------------------------------------------

/// @title EntryPointFork
/// @author David Dada
/// @notice Live-fork integration test (#58 item 9): a Lattice account drives a full user-operation round-trip
///         through the REAL ERC-4337 v0.9 EntryPoint singleton on mainnet — `getNonce` → `getUserOpHash` →
///         signed `handleOps` → executed batch — and rejects a bad signature via the EntryPoint's own path.
///
/// Enabling fork tests:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   forge test --match-path "test/fork/EntryPointFork.t.sol"
///
/// Without MAINNET_RPC_URL set, all tests in this contract are skipped.
contract EntryPointFork is Test {
    /// @notice Pinned mainnet block (2026, after the v0.9 EntryPoint deployment on 2025-12-22).
    uint256 constant FORK_BLOCK = 25_000_000;

    /// @dev ERC-7821 single-batch mode, no opData: `executionData = abi.encode(Call[])`.
    bytes32 constant BATCH_MODE = 0x0100000000000000000000000000000000000000000000000000000000000000;

    IEntryPoint constant ENTRY_POINT = IEntryPoint(DEFAULT_ENTRY_POINT);

    MockEntryPointAccount account;
    Target target;
    address owner;
    uint256 ownerPk;
    address payable beneficiary = payable(address(0xB0B));
    /// @dev v0.9 `handleOps` is gated by `nonReentrant`: `tx.origin == msg.sender && msg.sender.code.length == 0`,
    ///      so it must be called as a top-level tx from a code-less EOA (a 2-arg prank sets both). This also bars
    ///      contract relayers and EIP-7702-delegated EOAs (`code.length == 23`) from acting as the bundler.
    address bundler;

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", FORK_BLOCK);
        // Defensive: skip rather than fail if this RPC's pinned block predates the v0.9 singleton.
        if (address(ENTRY_POINT).code.length == 0) {
            vm.skip(true);
            return;
        }

        (owner, ownerPk) = makeAddrAndKey("owner");
        bundler = makeAddr("bundler"); // fresh, code-less EOA
        account = new MockEntryPointAccount();
        account.initialize(owner, address(ENTRY_POINT));
        target = new Target();
        vm.deal(address(account), 1 ether); // cover the EntryPoint prefund
    }

    /// @dev Builds a UserOp whose callData is an ERC-7821 batch calling `target.bump(v)`, signed by `pk`.
    function _buildOp(uint256 pk, uint256 v) internal view returns (PackedUserOperation memory op) {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(Target.bump, (v))});

        op.sender = address(account);
        op.nonce = ENTRY_POINT.getNonce(address(account), 0);
        op.callData = abi.encodeCall(ERC7821Executor.execute, (BATCH_MODE, abi.encode(calls)));
        op.accountGasLimits = bytes32((uint256(600_000) << 128) | uint256(600_000)); // verifGas || callGas
        op.preVerificationGas = 100_000;
        op.gasFees = bytes32((uint256(1 gwei) << 128) | uint256(10 gwei)); // maxPriorityFee || maxFee

        bytes32 userOpHash = ENTRY_POINT.getUserOpHash(op);
        (uint8 sv, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toEthSignedMessageHash(userOpHash));
        op.signature = abi.encodePacked(r, s, sv);
    }

    function _submit(PackedUserOperation memory op) internal {
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.prank(bundler, bundler); // both msg.sender and tx.origin = code-less EOA (v0.9 nonReentrant gate)
        ENTRY_POINT.handleOps(ops, beneficiary);
    }

    /// @notice The real EntryPoint validates the owner signature and executes the account's batch.
    function test_RealEntryPoint_ExecutesSignedUserOp() public {
        _submit(_buildOp(ownerPk, 42));
        assertEq(target.value(), 42, "batch not executed via real EntryPoint");
    }

    /// @notice A non-owner signature is rejected by the EntryPoint (validateUserOp returns SIG failure → AA24).
    function test_RealEntryPoint_RejectsBadSignature() public {
        (, uint256 strangerPk) = makeAddrAndKey("stranger");
        PackedUserOperation memory op = _buildOp(strangerPk, 7); // build first (makes its own staticcalls)
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.prank(bundler, bundler);
        vm.expectRevert(); // EntryPoint reverts handleOps with FailedOp(0, "AA24 signature error")
        ENTRY_POINT.handleOps(ops, beneficiary);
    }

    /// @notice Nonce advances after a successful op, so the same op cannot be replayed.
    function test_RealEntryPoint_NonceAdvances() public {
        uint256 before = ENTRY_POINT.getNonce(address(account), 0);
        _submit(_buildOp(ownerPk, 1));
        assertEq(ENTRY_POINT.getNonce(address(account), 0), before + 1, "nonce did not advance");
    }
}
