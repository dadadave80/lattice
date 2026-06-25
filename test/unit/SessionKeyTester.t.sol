// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {SessionKey} from "@lattice/accounts/SessionKey.sol";
import {ANY_SELECTOR, ANY_TARGET, NATIVE_TOKEN, SessionKeyLib} from "@lattice/accounts/libraries/SessionKeyLib.sol";
import {ISessionKey} from "@lattice/interfaces/ISessionKey.sol";
import {Call} from "@lattice/interfaces/external/IERC7821.sol";
import {Test} from "forge-std/Test.sol";

contract MockSessionKey is AccessControl, SessionKey {
    function initialize(address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        SessionKeyLib.__SessionKey_init();
        InitializableLib.postInitializer(s);
    }

    /// @dev Exposes the executor-side authorization hook (policy + spend accrual) for direct unit coverage.
    function authorize(address key, Call[] calldata calls) external {
        SessionKeyLib.authorizeBatch(key, calls);
    }
}

contract SessionKeyTester is Test {
    MockSessionKey acct;
    address admin = address(0x1);
    address key = address(0x5E55);
    address target = address(0x7A46);
    bytes4 selector = 0x12345678;
    uint48 until = uint48(1000);

    function setUp() public {
        acct = new MockSessionKey();
        acct.initialize(admin);
        vm.warp(1);
    }

    function _perm(address t, bytes4 s) internal pure returns (ISessionKey.Permission[] memory p) {
        p = new ISessionKey.Permission[](1);
        p[0] = ISessionKey.Permission({target: t, selector: s});
    }

    function _register(address k, uint48 validAfter, uint48 validUntil, ISessionKey.Permission[] memory p) internal {
        vm.prank(admin);
        acct.registerSessionKey(k, validAfter, validUntil, p);
    }

    function test_RegisterAndActive() public {
        _register(key, 0, until, _perm(target, selector));
        assertTrue(acct.isSessionKeyActive(key), "key should be active");
        (uint48 va, uint48 vu) = acct.sessionKeyValidity(key);
        assertEq(va, 0, "validAfter");
        assertEq(vu, until, "validUntil");
    }

    function test_NotYetActive() public {
        _register(key, 500, until, _perm(target, selector));
        assertFalse(acct.isSessionKeyActive(key), "key not active before validAfter");
        vm.warp(500);
        assertTrue(acct.isSessionKeyActive(key), "key active at validAfter");
    }

    function test_Expired() public {
        _register(key, 0, until, _perm(target, selector));
        vm.warp(uint256(until) + 1);
        assertFalse(acct.isSessionKeyActive(key), "expired key should be inactive");
    }

    function test_Revoke() public {
        _register(key, 0, until, _perm(target, selector));
        vm.prank(admin);
        acct.revokeSessionKey(key);
        assertFalse(acct.isSessionKeyActive(key), "revoked key should be inactive");
        (, uint48 vu) = acct.sessionKeyValidity(key);
        assertEq(vu, 0, "validUntil cleared");
    }

    function test_IsCallPermitted_Exact() public {
        _register(key, 0, until, _perm(target, selector));
        assertTrue(acct.isCallPermitted(key, target, selector), "exact permitted");
        assertFalse(acct.isCallPermitted(key, target, 0xdeadbeef), "other selector denied");
        assertFalse(acct.isCallPermitted(key, address(0xBEEF), selector), "other target denied");
    }

    function test_IsCallPermitted_AnyTarget() public {
        _register(key, 0, until, _perm(ANY_TARGET, selector));
        assertTrue(acct.isCallPermitted(key, address(0xAAAA), selector), "any-target permitted");
        assertTrue(acct.isCallPermitted(key, address(0xBBBB), selector), "any-target permitted 2");
        assertFalse(acct.isCallPermitted(key, address(0xAAAA), 0xdeadbeef), "wrong selector denied");
    }

    function test_IsCallPermitted_AnySelector() public {
        _register(key, 0, until, _perm(target, ANY_SELECTOR));
        assertTrue(acct.isCallPermitted(key, target, 0x11111111), "any-selector permitted");
        assertTrue(acct.isCallPermitted(key, target, 0x22222222), "any-selector permitted 2");
        assertFalse(acct.isCallPermitted(key, address(0xBEEF), 0x11111111), "wrong target denied");
    }

    function test_IsCallPermitted_AnyBoth() public {
        _register(key, 0, until, _perm(ANY_TARGET, ANY_SELECTOR));
        assertTrue(acct.isCallPermitted(key, address(0xAAAA), 0x11111111), "wildcard-all permitted");
    }

    function test_Register_RevertNotAdmin() public {
        ISessionKey.Permission[] memory p = _perm(target, selector);
        vm.prank(address(0xBAD));
        vm.expectRevert();
        acct.registerSessionKey(key, 0, until, p);
    }

    function test_Register_RevertInvalidKey() public {
        ISessionKey.Permission[] memory p = _perm(target, selector);
        vm.prank(admin);
        vm.expectRevert(ISessionKey.InvalidSessionKey.selector);
        acct.registerSessionKey(address(0), 0, until, p);
    }

    function test_Register_RevertInvalidExpiry() public {
        ISessionKey.Permission[] memory p = _perm(target, selector);
        vm.prank(admin);
        vm.expectRevert(ISessionKey.InvalidExpiry.selector);
        acct.registerSessionKey(key, 0, uint48(1), p); // validUntil == block.timestamp (warped to 1)
    }

    function test_Revoke_RevertNotAdmin() public {
        _register(key, 0, until, _perm(target, selector));
        vm.prank(address(0xBAD));
        vm.expectRevert();
        acct.revokeSessionKey(key);
    }

    // ---- spend limits ----

    address tok = address(0x70CE);
    address dest = address(0xD357);

    function _transferCall(address token, address to, uint256 amount) internal pure returns (Call[] memory c) {
        c = new Call[](1);
        c[0] = Call({target: token, value: 0, data: abi.encodeWithSignature("transfer(address,uint256)", to, amount)});
    }

    function _transferFromCall(address token, address from, address to, uint256 amount)
        internal
        pure
        returns (Call[] memory c)
    {
        c = new Call[](1);
        c[0] = Call({
            target: token,
            value: 0,
            data: abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, amount)
        });
    }

    function test_SetSpendLimit() public {
        vm.expectEmit(true, true, false, true, address(acct));
        emit ISessionKey.SpendLimitSet(key, tok, 100);
        vm.prank(admin);
        acct.setSpendLimit(key, tok, 100);
        (uint256 cap, uint256 spent) = acct.spendLimit(key, tok);
        assertEq(cap, 100, "cap");
        assertEq(spent, 0, "spent");
    }

    function test_SetSpendLimit_RevertNotAdmin() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        acct.setSpendLimit(key, tok, 100);
    }

    function test_Spend_WithinCap() public {
        _register(key, 0, until, _perm(tok, 0xa9059cbb));
        vm.prank(admin);
        acct.setSpendLimit(key, tok, 100);
        acct.authorize(key, _transferCall(tok, dest, 60));
        (, uint256 spent) = acct.spendLimit(key, tok);
        assertEq(spent, 60, "spent accrued");
    }

    function test_Spend_Exceeds() public {
        _register(key, 0, until, _perm(tok, 0xa9059cbb));
        vm.prank(admin);
        acct.setSpendLimit(key, tok, 100);
        vm.expectRevert(abi.encodeWithSelector(ISessionKey.SpendLimitExceeded.selector, key, tok, 100, 150));
        acct.authorize(key, _transferCall(tok, dest, 150));
    }

    function test_Spend_AccumulatesAcrossBatches() public {
        _register(key, 0, until, _perm(tok, 0xa9059cbb));
        vm.prank(admin);
        acct.setSpendLimit(key, tok, 100);
        acct.authorize(key, _transferCall(tok, dest, 60));
        vm.expectRevert(abi.encodeWithSelector(ISessionKey.SpendLimitExceeded.selector, key, tok, 100, 110));
        acct.authorize(key, _transferCall(tok, dest, 50));
    }

    function test_Spend_UnconfiguredIsUncapped() public {
        _register(key, 0, until, _perm(tok, 0xa9059cbb));
        acct.authorize(key, _transferCall(tok, dest, 1e30)); // no limit set → no revert
        (uint256 cap, uint256 spent) = acct.spendLimit(key, tok);
        assertEq(cap, 0, "uncapped");
        assertEq(spent, 0, "untracked");
    }

    function test_Spend_Native() public {
        _register(key, 0, until, _perm(ANY_TARGET, ANY_SELECTOR));
        vm.prank(admin);
        acct.setSpendLimit(key, NATIVE_TOKEN, 1 ether);
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: dest, value: 0.5 ether, data: ""});
        acct.authorize(key, calls);
        (, uint256 spent) = acct.spendLimit(key, NATIVE_TOKEN);
        assertEq(spent, 0.5 ether, "native spent accrued");
    }

    function test_Spend_OnlyTransferFromSelf() public {
        _register(key, 0, until, _perm(tok, 0x23b872dd));
        vm.prank(admin);
        acct.setSpendLimit(key, tok, 100);
        acct.authorize(key, _transferFromCall(tok, address(acct), dest, 40)); // from self → counts
        (, uint256 spent) = acct.spendLimit(key, tok);
        assertEq(spent, 40, "self transferFrom counted");
        acct.authorize(key, _transferFromCall(tok, address(0x9999), dest, 50)); // from other → ignored
        (, uint256 spent2) = acct.spendLimit(key, tok);
        assertEq(spent2, 40, "non-self transferFrom not counted");
    }
}
