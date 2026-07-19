// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {AccountBlueprintHelper} from "@lattice-test/helpers/AccountBlueprintHelper.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {AccountInit} from "@lattice/accounts/erc7579/AccountInit.sol";
import {AccountSigner} from "@lattice/accounts/erc7579/AccountSigner.sol";
import {ERC7821Executor} from "@lattice/accounts/erc7579/ERC7821Executor.sol";
import {DEFAULT_ENTRY_POINT} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {PackedUserOperation} from "@lattice/interfaces/external/ercs/IAccount.sol";
import {Call} from "@lattice/interfaces/external/ercs/IERC7821.sol";
import {IEntryPoint} from "@lattice/interfaces/external/ercs/IEntryPoint.sol";
import {ECDSA} from "@lattice/utils/libraries/ECDSA.sol";

contract Target {
    uint256 public value;

    function bump(uint256 v) external {
        value = v;
    }
}

/// @title EntryPoint7702Fork
/// @author David Dada
/// @notice #58 item 7 — live-fork proof of in-band EIP-7702 onboarding: a delegated EOA's FIRST UserOperation
///         carries a `0x7702`-prefixed initCode, and the REAL v0.9 EntryPoint initializes the EOA's own storage
///         (via SenderCreator) and then validates + executes — all in one op, no separate init tx.
/// @dev This is the safe ATOMIC onboarding: in production the EOA's 7702 authorization is carried in the same
///      handleOps transaction, so delegation + init cannot be front-run. (The hardened `Account7702Diamond`
///      delegate additionally gates init on an EOA signature for non-atomic flows.)
///
/// Enabling: `export MAINNET_RPC_URL=<url>; forge test --match-path "test/fork/EntryPoint7702Fork.t.sol"`.
/// Without MAINNET_RPC_URL set, all tests are skipped.
contract EntryPoint7702Fork is AccountBlueprintHelper {
    /// @notice Pinned mainnet block (2026, after the v0.9 EntryPoint deployment on 2025-12-22).
    uint256 constant FORK_BLOCK = 25_000_000;

    /// @dev The 20-byte ERC-4337 v0.9 EIP-7702 initCode marker: `0x7702` left-padded to 20 bytes.
    bytes20 constant MARKER_7702 = hex"7702000000000000000000000000000000000000";

    /// @dev ERC-7821 single-batch mode (no opData).
    bytes32 constant BATCH_MODE = 0x0100000000000000000000000000000000000000000000000000000000000000;

    IEntryPoint constant ENTRY_POINT = IEntryPoint(DEFAULT_ENTRY_POINT);

    LatticeDiamond diamondImpl; // the shared 7702 delegate code
    AccountInit accountInit;
    FacetCut[] blueprint;
    Target target;
    address eoa;
    uint256 eoaPk;
    address bundler; // code-less EOA (v0.9 handleOps gate)

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", FORK_BLOCK);
        if (address(ENTRY_POINT).code.length == 0) {
            vm.skip(true);
            return;
        }

        (FacetCut[] memory cuts, AccountInit init) = _accountBlueprint(address(ENTRY_POINT));
        for (uint256 i; i < cuts.length; ++i) {
            blueprint.push(cuts[i]);
        }
        accountInit = init;
        diamondImpl = new LatticeDiamond();
        (eoa, eoaPk) = makeAddrAndKey("eoa");
        bundler = makeAddr("bundler");
        target = new Target();
        vm.deal(eoa, 1 ether); // prefund (no paymaster)
    }

    /// @notice First op with `0x7702` initCode: the real EntryPoint inits the EOA's storage in-band, then runs it.
    function test_InBand7702InitCode_InitializesAndExecutes() public {
        // Delegate the EOA to the shared Diamond (EOA now carries 0xef0100‖diamond code; storage still empty).
        vm.signAndAttachDelegation(address(diamondImpl), eoaPk);

        // initCode = 20-byte marker ‖ raw calldata the EntryPoint CALLs on the EOA (init7702 → owner = the EOA).
        bytes memory initData = abi.encodeCall(
            LatticeDiamond.initialize, (blueprint, address(accountInit), abi.encodeCall(AccountInit.init7702, ()))
        );
        bytes memory initCode = abi.encodePacked(MARKER_7702, initData);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(Target.bump, (42))});

        PackedUserOperation memory op;
        op.sender = eoa;
        op.nonce = ENTRY_POINT.getNonce(eoa, 0);
        op.initCode = initCode;
        op.callData = abi.encodeCall(ERC7821Executor.execute, (BATCH_MODE, abi.encode(calls)));
        // verificationGasLimit must cover the full 8-facet diamondCut init AND validateUserOp.
        op.accountGasLimits = bytes32((uint256(5_000_000) << 128) | uint256(1_000_000));
        op.preVerificationGas = 200_000;
        op.gasFees = bytes32((uint256(1 gwei) << 128) | uint256(10 gwei));

        // getUserOpHash folds in the 7702 override (keccak(delegate ‖ initCode[20:])); sign exactly that.
        bytes32 userOpHash = ENTRY_POINT.getUserOpHash(op);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPk, ECDSA.toEthSignedMessageHash(userOpHash));
        op.signature = abi.encodePacked(r, s, v);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.prank(bundler, bundler); // code-less EOA bundler
        ENTRY_POINT.handleOps(ops, payable(bundler));

        // In-band init wired the EOA's own storage (owner = the EOA) and the batch executed.
        assertEq(AccountSigner(eoa).owner(), eoa, "EOA not self-initialized in-band");
        assertEq(target.value(), 42, "batch not executed after in-band onboarding");
    }
}
