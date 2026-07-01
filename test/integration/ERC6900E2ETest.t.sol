// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {Account6900BlueprintHelper} from "@lattice-test/helpers/Account6900BlueprintHelper.sol";
import {AccountFactory6900} from "@lattice/accounts/erc6900/AccountFactory6900.sol";
import {AccountInit6900} from "@lattice/accounts/erc6900/AccountInit6900.sol";
import {ERC6900TypesLib} from "@lattice/accounts/erc6900/libraries/ERC6900TypesLib.sol";
import {SingleSignerValidation} from "@lattice/accounts/erc6900/modules/SingleSignerValidation.sol";
import {SpendingLimit} from "@lattice/accounts/erc6900/modules/SpendingLimit.sol";
import {IERC6900Executor} from "@lattice/interfaces/accounts/IERC6900Executor.sol";
import {IAccount, PackedUserOperation} from "@lattice/interfaces/external/IAccount.sol";
import {
    DIRECT_CALL_VALIDATION_ENTITY_ID,
    ExecutionManifest,
    IERC6900Account,
    ManifestExecutionFunction,
    ManifestExecutionHook,
    ModuleEntity,
    ValidationConfig
} from "@lattice/interfaces/external/IERC6900.sol";
import {ECDSA} from "@lattice/utils/libraries/ECDSA.sol";

contract PayableTarget {
    receive() external payable {}
}

/// @dev An ERC-6900 execution module exposing `increment()` (its own storage; reached via the account's dispatch).
contract Counter {
    uint256 public count;

    function increment() external {
        ++count;
    }

    function onInstall(bytes calldata) external {}
    function onUninstall(bytes calldata) external {}

    function moduleId() external pure returns (string memory) {
        return "lattice.counter.1.0.0";
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

interface ICounter {
    function increment() external;
}

/// @title ERC6900E2ETest
/// @notice End-to-end (#74 sub-task 8): a factory-deployed ERC-6900 account driven through the WHOLE pipeline
///         with reference modules — a `SingleSignerValidation` (userOp validation) and a `SpendingLimit`
///         execution hook — plus a direct-call execution function and install/uninstall.
contract ERC6900E2ETest is Account6900BlueprintHelper {
    AccountFactory6900 factory;
    SingleSignerValidation ssv;
    SpendingLimit spend;
    Counter counter;
    PayableTarget target;

    address entryPoint = address(0xE417);
    uint256 ownerKey = uint256(keccak256("owner"));
    address owner;
    bytes32 salt = keccak256("e2e");
    address account;

    uint32 constant SSV_ENTITY = 10;
    uint32 constant SPEND_ENTITY = 1;
    uint256 constant CAP = 1 ether;

    function setUp() public {
        owner = vm.addr(ownerKey);
        (FacetCut[] memory blueprint, AccountInit6900 init) = _accountBlueprint6900(entryPoint);
        factory = new AccountFactory6900(blueprint, address(init));
        ssv = new SingleSignerValidation();
        spend = new SpendingLimit();
        counter = new Counter();
        target = new PayableTarget();

        account = factory.createAccount(owner, salt);

        // owner (admin) installs a global validation (userOp + 1271) signed by the owner key, and a spending-limit
        // pre-execution hook on `execute`.
        vm.startPrank(owner);
        IERC6900Account(account)
            .installValidation(
                ERC6900TypesLib.pack(address(ssv), SSV_ENTITY, true, true, true),
                new bytes4[](0),
                abi.encode(SSV_ENTITY, owner),
                new bytes[](0)
            );
        ExecutionManifest memory m;
        m.executionHooks = new ManifestExecutionHook[](1);
        m.executionHooks[0] = ManifestExecutionHook({
            executionSelector: IERC6900Account.execute.selector,
            entityId: SPEND_ENTITY,
            isPreHook: true,
            isPostHook: false
        });
        IERC6900Account(account).installExecution(address(spend), m, abi.encode(SPEND_ENTITY, CAP));
        vm.stopPrank();
    }

    function _ssvMe() internal view returns (ModuleEntity) {
        return ERC6900TypesLib.pack(address(ssv), SSV_ENTITY);
    }

    function _signedOp(uint256 pk, bytes32 userOpHash) internal view returns (PackedUserOperation memory op) {
        op.sender = account;
        op.callData = abi.encodeCall(IERC6900Account.execute, (address(target), 0, ""));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toEthSignedMessageHash(userOpHash));
        op.signature =
            abi.encodePacked(ModuleEntity.unwrap(_ssvMe()), bytes1(0x01), bytes1(0xff), abi.encodePacked(r, s, v));
    }

    // ---- userOp validation through the real account ----

    function test_E2E_UserOpValidatesWithOwnerSignature() public {
        bytes32 userOpHash = keccak256("op-1");
        vm.prank(entryPoint);
        assertEq(IAccount(account).validateUserOp(_signedOp(ownerKey, userOpHash), userOpHash, 0), 0, "owner op valid");
    }

    function test_E2E_UserOpRejectsWrongSigner() public {
        bytes32 userOpHash = keccak256("op-2");
        vm.prank(entryPoint);
        assertEq(IAccount(account).validateUserOp(_signedOp(0xBAD5161, userOpHash), userOpHash, 0), 1, "bad sig fails");
    }

    // ---- execution + spend-limit hook enforcement ----

    function test_E2E_ExecuteEnforcesSpendLimit() public {
        vm.deal(account, 2 ether);

        // EntryPoint-driven execution (validation already done) runs the selector's pre-exec hooks.
        vm.prank(entryPoint);
        IERC6900Account(account).execute(address(target), 0.6 ether, "");
        assertEq(address(target).balance, 0.6 ether, "first spend went through");
        assertEq(spend.spentOf(account, SPEND_ENTITY), 0.6 ether, "budget decremented");

        // 0.6 + 0.6 > 1.0 cap → blocked. The executor wraps a reverting hook as PreExecHookReverted(module,
        // entityId, reason), with the module's SpendCapExceeded data in `reason`.
        vm.prank(entryPoint);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC6900Executor.PreExecHookReverted.selector,
                address(spend),
                SPEND_ENTITY,
                abi.encodeWithSelector(SpendingLimit.SpendCapExceeded.selector, 1.2 ether, CAP)
            )
        );
        IERC6900Account(account).execute(address(target), 0.6 ether, "");
    }

    // ---- direct-call execution function (module dispatch + direct-call validation) ----

    function test_E2E_DirectCallExecutionFunction() public {
        // Install the Counter execution module + a direct-call validation permitting `caller` to call increment().
        address caller = address(0xCA11E2);
        ExecutionManifest memory m;
        m.executionFunctions = new ManifestExecutionFunction[](1);
        m.executionFunctions[0] = ManifestExecutionFunction({
            executionSelector: Counter.increment.selector, skipRuntimeValidation: false, allowGlobalValidation: false
        });
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = Counter.increment.selector;

        vm.startPrank(owner);
        IERC6900Account(account).installExecution(address(counter), m, "");
        IERC6900Account(account)
            .installValidation(
                ERC6900TypesLib.pack(caller, DIRECT_CALL_VALIDATION_ENTITY_ID, false, false, false),
                sels,
                "",
                new bytes[](0)
            );
        vm.stopPrank();

        vm.prank(caller);
        ICounter(account).increment();
        assertEq(counter.count(), 1, "module exec function dispatched in its own storage");

        // An unauthorized caller has no direct-call validation for the selector.
        vm.prank(address(0xBAD));
        vm.expectRevert(
            abi.encodeWithSelector(IERC6900Executor.ValidationFunctionMissing.selector, Counter.increment.selector)
        );
        ICounter(account).increment();
    }

    // ---- uninstall ----

    function test_E2E_UninstallRemovesValidation() public {
        vm.prank(owner);
        IERC6900Account(account).uninstallValidation(_ssvMe(), abi.encode(SSV_ENTITY), new bytes[](0));
        assertEq(ssv.signerOf(account, SSV_ENTITY), address(0), "module signer cleared");

        // The validation no longer applies → userOp validation reverts.
        bytes32 userOpHash = keccak256("op-3");
        PackedUserOperation memory op = _signedOp(ownerKey, userOpHash);
        vm.prank(entryPoint);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC6900Executor.ValidationFunctionMissing.selector, IERC6900Account.execute.selector
            )
        );
        IAccount(account).validateUserOp(op, userOpHash, 0);
    }
}
