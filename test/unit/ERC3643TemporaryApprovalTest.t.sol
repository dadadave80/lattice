// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC3643TestBase} from "@lattice-test/base/ERC3643TestBase.sol";
import {ERC3643TokenIdentityMock, ERC3643TokenPolicyMock} from "@lattice-test/helpers/ERC3643TokenMocks.sol";
import {TemporaryApprovalActor as Actor} from "@lattice-test/helpers/TemporaryApprovalActor.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20TemporaryApproval} from "@lattice/interfaces/tokens/IERC20TemporaryApproval.sol";
import {IERC3643} from "@lattice/interfaces/tokens/erc3643/IERC3643.sol";
import {IIdentityRegistry} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistry.sol";

/// forge-config: default.isolate = true
contract ERC3643TemporaryApprovalTest is ERC3643TestBase {
    Actor internal ownerActor;
    Actor internal spenderActor;

    function setUp() public override {
        super.setUp();
        diamond = _deploy(_config(true));
        token = IERC3643(diamond);
        registry = IIdentityRegistry(diamond);
        ownerActor = new Actor();
        spenderActor = new Actor();
        _register(address(ownerActor), aliceIdentity, 11);
        _register(bob, bobIdentity, 22);
        token.mint(address(ownerActor), 100);
        token.unpause();
        Actor.Action[] memory actions = new Actor.Action[](1);
        actions[0] = _action(diamond, abi.encodeCall(IERC20.approve, (address(spenderActor), 9)));
        ownerActor.run(actions);
    }

    function _action(address target, bytes memory data) internal pure returns (Actor.Action memory) {
        return Actor.Action(target, data, false);
    }

    function _query() internal view returns (Actor.Action memory) {
        return _action(diamond, abi.encodeCall(IERC20.allowance, (address(ownerActor), address(spenderActor))));
    }

    function _spend(uint256 amount, bool allowFailure) internal view returns (Actor.Action memory action) {
        Actor.Action[] memory inner = new Actor.Action[](1);
        inner[0] = _action(diamond, abi.encodeCall(IERC20.transferFrom, (address(ownerActor), bob, amount)));
        action = Actor.Action(address(spenderActor), abi.encodeCall(Actor.run, (inner)), allowFailure);
    }

    function test_OptionalGrantSpendsTemporaryFirstAndExpiresBetweenTransactions() public {
        Actor.Action[] memory actions = new Actor.Action[](6);
        actions[0] =
            _action(diamond, abi.encodeCall(IERC20TemporaryApproval.temporaryApprove, (address(spenderActor), 7)));
        actions[1] = _query();
        actions[2] = _spend(4, false);
        actions[3] = _query();
        actions[4] = _spend(6, false);
        actions[5] = _query();
        bytes[] memory results = ownerActor.run(actions);
        assertEq(abi.decode(results[1], (uint256)), 16);
        assertEq(abi.decode(results[3], (uint256)), 12);
        assertEq(abi.decode(results[5], (uint256)), 6);
        assertEq(
            token.allowance(address(ownerActor), address(spenderActor)), 6, "new transaction retains persistent only"
        );
        assertEq(token.balanceOf(bob), 10);
    }

    function test_CallbackRollbackRestoresTemporaryAndPersistentAllowanceWithinTransaction() public {
        ERC3643TokenPolicyMock policy = _externalPolicy();
        policy.configure(true, false, true);
        Actor.Action[] memory actions = new Actor.Action[](6);
        actions[0] =
            _action(diamond, abi.encodeCall(IERC20TemporaryApproval.temporaryApprove, (address(spenderActor), 7)));
        actions[1] = _spend(10, true);
        actions[2] = _query();
        actions[3] = _action(address(policy), abi.encodeCall(ERC3643TokenPolicyMock.configure, (true, false, false)));
        actions[4] = _spend(10, false);
        actions[5] = _query();
        bytes[] memory results = ownerActor.run(actions);
        assertEq(bytes4(results[1]), ERC3643TokenPolicyMock.PolicyFailure.selector);
        assertEq(abi.decode(results[2], (uint256)), 16, "failed callback restores both allowance sources");
        assertEq(abi.decode(results[5], (uint256)), 6);
        assertEq(token.balanceOf(bob), 10);
        assertEq(policy.transfers(), 1);
    }

    function test_FrozenWalletGrantDoesNotBypassMovementPolicy() public {
        token.freezePartialTokens(address(ownerActor), 100);
        Actor.Action[] memory actions = new Actor.Action[](3);
        actions[0] =
            _action(diamond, abi.encodeCall(IERC20TemporaryApproval.temporaryApprove, (address(spenderActor), 7)));
        actions[1] = _spend(1, true);
        actions[2] = _query();
        bytes[] memory results = ownerActor.run(actions);
        assertEq(bytes4(results[1]), IERC3643.ERC3643InsufficientFreeBalance.selector);
        assertEq(abi.decode(results[2], (uint256)), 16);
        assertEq(token.allowance(address(ownerActor), address(spenderActor)), 9);
        assertEq(token.balanceOf(bob), 0);
    }
}
