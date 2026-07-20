// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {GelatoAutomateAdapterTestBase} from "@lattice-test/base/GelatoAutomateAdapterTestBase.sol";
import {GelatoAutomateAdapterTestFacet} from "@lattice-test/helpers/GelatoAutomateAdapterTestFacet.sol";
import {IGelatoAutomate} from "@lattice/interfaces/external/gelato/IGelatoAutomate.sol";
import {IGelatoAutomateAdapter} from "@lattice/interfaces/oracles/IGelatoAutomateAdapter.sol";
import {GelatoAutomateAdapter} from "@lattice/oracles/gelato/GelatoAutomateAdapter.sol";

// ---------------------------------------------------------------------------
//                              EXTERNAL MOCK FIXTURE
// ---------------------------------------------------------------------------

/// @notice Mock Gelato Automate that returns deterministic task IDs and records args. This is the EXTERNAL
///         contract the adapter integrates with (not the facet under test) — kept as a test fixture.
contract MockAutomate is IGelatoAutomate {
    uint256 private _nonce;

    struct CreatedTask {
        address execAddress;
        bytes execDataOrSelector;
        address feeToken;
    }

    mapping(bytes32 => CreatedTask) public created;
    mapping(bytes32 => bool) public cancelled;

    function createTask(address execAddress, bytes calldata execDataOrSelector, ModuleData calldata, address feeToken)
        external
        returns (bytes32 taskId)
    {
        taskId = keccak256(abi.encode(++_nonce));
        created[taskId] =
            CreatedTask({execAddress: execAddress, execDataOrSelector: execDataOrSelector, feeToken: feeToken});
    }

    function cancelTask(bytes32 taskId) external {
        cancelled[taskId] = true;
    }
}

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

/// @title GelatoAutomateAdapterTest
/// @notice Exercises the GelatoAutomateAdapter facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployGelatoAutomateAdapter} script (see {GelatoAutomateAdapterTestBase}) — every call below routes
///         through the diamond's `delegatecall` dispatch, not a flattened inheritance mock. Admin gating is
///         enforced by the cut-in `AccessControl` facet; the dedicated-msg.sender exec gate by the test-only
///         {GelatoAutomateAdapterTestFacet}; `supportsInterface` by the cut-in `ERC165Facet`.
contract GelatoAutomateAdapterTest is GelatoAutomateAdapterTestBase {
    MockAutomate automate;

    address admin = address(0x1);
    address user = address(0x2);
    address dedicatedMsgSender = address(0xD);
    address execAddress = address(0xE);
    address feeToken = address(0);

    function setUp() public {
        diamond = _deployGelatoAutomateAdapter(admin);
        gelato = GelatoAutomateAdapter(diamond);
        execGuard = GelatoAutomateAdapterTestFacet(diamond);

        automate = new MockAutomate();
    }

    /// @notice Builds a trivial ModuleData with empty arrays.
    function _emptyModuleData() internal pure returns (IGelatoAutomate.ModuleData memory) {
        return IGelatoAutomate.ModuleData({modules: new IGelatoAutomate.Module[](0), args: new bytes[](0)});
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           SET CONFIG TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Non-admin cannot set config.
    function test_SetConfigRevertsForNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        gelato.setConfig(address(automate), dedicatedMsgSender);
    }

    /// @notice setConfig with zero automate reverts GelatoAutomateInvalidConfig.
    function test_SetConfigRevertsOnZeroAutomate() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IGelatoAutomateAdapter.GelatoAutomateInvalidConfig.selector));
        gelato.setConfig(address(0), dedicatedMsgSender);
    }

    /// @notice setConfig with zero dedicatedMsgSender reverts GelatoAutomateInvalidConfig.
    function test_SetConfigRevertsOnZeroDedicatedMsgSender() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IGelatoAutomateAdapter.GelatoAutomateInvalidConfig.selector));
        gelato.setConfig(address(automate), address(0));
    }

    /// @notice Admin can set config and it is stored correctly.
    function test_SetConfigByAdmin() public {
        vm.prank(admin);
        gelato.setConfig(address(automate), dedicatedMsgSender);

        (address storedAutomate, address storedDedicated) = gelato.getConfig();
        assertEq(storedAutomate, address(automate));
        assertEq(storedDedicated, dedicatedMsgSender);
    }

    /// @notice setConfig emits GelatoAutomateConfigSet event.
    function test_SetConfigEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit IGelatoAutomateAdapter.GelatoAutomateConfigSet(address(automate), dedicatedMsgSender);
        gelato.setConfig(address(automate), dedicatedMsgSender);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           CREATE TASK TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice createTask tracks the task ID, emits, and isTask returns true.
    function test_CreateTaskTracksAndEmits() public {
        vm.prank(admin);
        gelato.setConfig(address(automate), dedicatedMsgSender);

        bytes32 expectedTaskId = keccak256(abi.encode(uint256(1)));

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IGelatoAutomateAdapter.TaskCreated(expectedTaskId, execAddress);
        bytes32 taskId = gelato.createTask(execAddress, bytes("data"), _emptyModuleData(), feeToken);

        assertEq(taskId, expectedTaskId);
        assertTrue(gelato.isTask(taskId));
    }

    /// @notice Non-admin cannot create a task.
    function test_CreateTaskRevertsForNonAdmin() public {
        vm.prank(admin);
        gelato.setConfig(address(automate), dedicatedMsgSender);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        gelato.createTask(execAddress, bytes("data"), _emptyModuleData(), feeToken);
    }

    /// @notice createTask without config reverts GelatoAutomateNotConfigured.
    function test_CreateTaskRevertsWhenNotConfigured() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IGelatoAutomateAdapter.GelatoAutomateNotConfigured.selector));
        gelato.createTask(execAddress, bytes("data"), _emptyModuleData(), feeToken);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           CANCEL TASK TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice cancelTask on an untracked task reverts GelatoAutomateTaskNotFound.
    function test_CancelTaskRevertsWhenUntracked() public {
        vm.prank(admin);
        gelato.setConfig(address(automate), dedicatedMsgSender);

        bytes32 unknown = keccak256("unknown");
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IGelatoAutomateAdapter.GelatoAutomateTaskNotFound.selector, unknown));
        gelato.cancelTask(unknown);
    }

    /// @notice Non-admin cannot cancel a task.
    function test_CancelTaskRevertsForNonAdmin() public {
        vm.prank(admin);
        gelato.setConfig(address(automate), dedicatedMsgSender);

        vm.prank(admin);
        bytes32 taskId = gelato.createTask(execAddress, bytes("data"), _emptyModuleData(), feeToken);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        gelato.cancelTask(taskId);
    }

    /// @notice cancelTask untracks the task and emits TaskCancelled.
    function test_CancelTaskUntracksAndEmits() public {
        vm.prank(admin);
        gelato.setConfig(address(automate), dedicatedMsgSender);

        vm.prank(admin);
        bytes32 taskId = gelato.createTask(execAddress, bytes("data"), _emptyModuleData(), feeToken);
        assertTrue(gelato.isTask(taskId));

        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit IGelatoAutomateAdapter.TaskCancelled(taskId);
        gelato.cancelTask(taskId);

        assertFalse(gelato.isTask(taskId));
        assertTrue(automate.cancelled(taskId));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       DEDICATED MSG.SENDER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice exec() from a non-dedicated caller reverts GelatoAutomateOnlyDedicatedMsgSender.
    function test_ExecRevertsFromNonDedicated() public {
        vm.prank(admin);
        gelato.setConfig(address(automate), dedicatedMsgSender);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IGelatoAutomateAdapter.GelatoAutomateOnlyDedicatedMsgSender.selector, user)
        );
        execGuard.exec();
    }

    /// @notice exec() from the dedicated msg.sender succeeds.
    function test_ExecSucceedsFromDedicated() public {
        vm.prank(admin);
        gelato.setConfig(address(automate), dedicatedMsgSender);

        vm.prank(dedicatedMsgSender);
        execGuard.exec();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice supportsInterface returns true for IGelatoAutomateAdapter after init.
    function test_SupportsInterfaceGelatoAutomateAdapter() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IGelatoAutomateAdapter).interfaceId));
    }
}
