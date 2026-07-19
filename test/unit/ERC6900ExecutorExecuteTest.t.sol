// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC6900Executor} from "@lattice/accounts/erc6900/ERC6900Executor.sol";
import {ERC6900ModuleManager} from "@lattice/accounts/erc6900/ERC6900ModuleManager.sol";
import {ModularAccount6900} from "@lattice/accounts/erc6900/ModularAccount6900.sol";
import {ERC6900TypesLib} from "@lattice/accounts/erc6900/libraries/ERC6900TypesLib.sol";
import {IERC6900Executor} from "@lattice/interfaces/accounts/IERC6900Executor.sol";
import {
    Call,
    DIRECT_CALL_VALIDATION_ENTITY_ID,
    IERC6900Account,
    ValidationConfig
} from "@lattice/interfaces/external/ercs/IERC6900.sol";
import {Test} from "forge-std/Test.sol";

contract Target {
    uint256 public v;
    bool public doRevert;

    function setV(uint256 x) external payable {
        if (doRevert) revert("target failed");
        v = x;
    }

    function setRevert(bool r) external {
        doRevert = r;
    }
}

contract MockExecAccount is ModularAccount6900, AccessControl, ERC6900ModuleManager, ERC6900Executor {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(AccessControl, ERC6900ModuleManager, ERC6900Executor)
        returns (bytes memory)
    {}

    function initialize(address admin_) external initializer {
        AccessControlLib.__AccessControl_init(admin_);
    }
}

contract ERC6900ExecutorExecuteTest is Test {
    MockExecAccount account;
    Target t1;
    Target t2;
    address admin = address(0xA11CE);
    address caller = address(0xCA11E2);

    function setUp() public {
        account = new MockExecAccount();
        account.initialize(admin);
        t1 = new Target();
        t2 = new Target();
    }

    /// @dev Installs a direct-call validation authorizing `caller` (the validation "module" is the caller; the
    ///      `selectors` it may validate, or global if `global`).
    function _authorize(bool global, bytes4[] memory sels) internal {
        ValidationConfig cfg = ERC6900TypesLib.pack(caller, DIRECT_CALL_VALIDATION_ENTITY_ID, global, false, false);
        vm.prank(admin);
        account.installValidation(cfg, sels, "", new bytes[](0));
    }

    function _sel(bytes4 a) internal pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = a;
    }

    // ---- execute ----

    function test_Execute_AuthorizedDirectCall_ForwardsValue() public {
        _authorize(false, _sel(IERC6900Account.execute.selector));
        vm.deal(address(account), 1 ether);
        vm.prank(caller);
        account.execute(address(t1), 1 ether, abi.encodeCall(Target.setV, (42)));
        assertEq(t1.v(), 42, "target state");
        assertEq(address(t1).balance, 1 ether, "value forwarded from account balance");
        assertEq(address(account).balance, 0, "account balance drained");
    }

    function test_Execute_GlobalValidation() public {
        _authorize(true, new bytes4[](0)); // global, no per-selector list; execute opts into global validation
        vm.prank(caller);
        account.execute(address(t1), 0, abi.encodeCall(Target.setV, (7)));
        assertEq(t1.v(), 7, "global validation should authorize execute");
    }

    function test_Execute_RevertUnauthorized() public {
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC6900Executor.ValidationFunctionMissing.selector, IERC6900Account.execute.selector
            )
        );
        account.execute(address(t1), 0, abi.encodeCall(Target.setV, (1)));
    }

    function test_Execute_SelfRecursionGuard() public {
        _authorize(false, _sel(IERC6900Account.execute.selector));
        bytes memory inner = abi.encodeCall(IERC6900Account.execute, (address(t1), 0, ""));
        vm.prank(caller);
        vm.expectRevert(IERC6900Executor.SelfCallRecursionDepthExceeded.selector);
        account.execute(address(account), 0, inner);
    }

    function test_Execute_BubblesTargetRevert() public {
        _authorize(false, _sel(IERC6900Account.execute.selector));
        t1.setRevert(true);
        vm.prank(caller);
        vm.expectRevert(bytes("target failed"));
        account.execute(address(t1), 0, abi.encodeCall(Target.setV, (1)));
    }

    // ---- executeBatch ----

    function test_ExecuteBatch_RunsAll() public {
        _authorize(false, _sel(IERC6900Account.executeBatch.selector));
        Call[] memory calls = new Call[](2);
        calls[0] = Call({target: address(t1), value: 0, data: abi.encodeCall(Target.setV, (11))});
        calls[1] = Call({target: address(t2), value: 0, data: abi.encodeCall(Target.setV, (22))});
        vm.prank(caller);
        bytes[] memory results = account.executeBatch(calls);
        assertEq(results.length, 2, "results");
        assertEq(t1.v(), 11, "t1");
        assertEq(t2.v(), 22, "t2");
    }

    function test_ExecuteBatch_CannotSelfCallAdminConfig() public {
        // Privilege-escalation guard: a (non-admin) validation holder must NOT be able to smuggle an admin-gated
        // installValidation through an executeBatch self-call (msg.sender == address(this) would satisfy the
        // manager's admin gate). All self-targeted sub-calls must be rejected.
        _authorize(true, new bytes4[](0)); // caller holds only a global direct-call validation
        ValidationConfig attackerCfg = ERC6900TypesLib.pack(caller, 1, true, false, false);
        bytes memory configCall =
            abi.encodeCall(IERC6900Account.installValidation, (attackerCfg, new bytes4[](0), "", new bytes[](0)));
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(account), value: 0, data: configCall});
        vm.prank(caller);
        vm.expectRevert(IERC6900Executor.SelfCallRecursionDepthExceeded.selector);
        account.executeBatch(calls);
    }

    function test_Execute_CannotSelfCallAdminConfig() public {
        // The single-execute path likewise rejects any self-target (defense in depth / regression guard).
        _authorize(true, new bytes4[](0));
        bytes memory configCall = abi.encodeCall(
            IERC6900Account.installValidation,
            (ERC6900TypesLib.pack(caller, 1, true, false, false), new bytes4[](0), "", new bytes[](0))
        );
        vm.prank(caller);
        vm.expectRevert(IERC6900Executor.SelfCallRecursionDepthExceeded.selector);
        account.execute(address(account), 0, configCall);
    }

    function test_ExecuteBatch_Atomic() public {
        _authorize(false, _sel(IERC6900Account.executeBatch.selector));
        t2.setRevert(true);
        Call[] memory calls = new Call[](2);
        calls[0] = Call({target: address(t1), value: 0, data: abi.encodeCall(Target.setV, (11))});
        calls[1] = Call({target: address(t2), value: 0, data: abi.encodeCall(Target.setV, (22))});
        vm.prank(caller);
        vm.expectRevert(bytes("target failed"));
        account.executeBatch(calls);
        assertEq(t1.v(), 0, "first call rolled back (atomic)");
    }
}
