// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {ERC20TestBase} from "@lattice-test/base/ERC20TestBase.sol";
import {TemporaryApprovalActor as Actor} from "@lattice-test/helpers/TemporaryApprovalActor.sol";
import {TemporaryApprovalUpgradeInit} from "@lattice-test/helpers/TemporaryApprovalUpgradeInit.sol";
import {TokenTestFacet} from "@lattice-test/helpers/TokenTestFacet.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20TemporaryApproval} from "@lattice/tokens/ERC20/ERC20TemporaryApproval.sol";
import {ERC20TemporaryApprovalInit} from "@lattice/tokens/ERC20/ERC20TemporaryApprovalInit.sol";
import {ERC20_STORAGE_SLOT} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {Vm} from "forge-std/Vm.sol";

import {DeployERC20TemporaryApproval} from "@lattice-script/base/tokens/DeployERC20TemporaryApproval.s.sol";
import {IERC20TemporaryApproval} from "@lattice/interfaces/tokens/IERC20TemporaryApproval.sol";

/// forge-config: default.isolate = true
contract ERC20TemporaryApprovalTest is ERC20TestBase {
    Actor internal owner;
    Actor internal spender;
    address internal recipient = address(0xB0B);

    function setUp() public override {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory data) =
            new DeployERC20TemporaryApproval().buildCuts("Temporary Token", "TEMP");
        diamond = _deployWithHelper(cuts, inits, data);
        token = ERC20(diamond);
        helper = TokenTestFacet(diamond);
        owner = new Actor();
        spender = new Actor();
        helper.mint(address(owner), 100);
    }

    function _action(address target, bytes memory data) internal pure returns (Actor.Action memory) {
        return Actor.Action(target, data, false);
    }

    function _grant(uint256 value) internal view returns (Actor.Action memory) {
        return _action(diamond, abi.encodeCall(IERC20TemporaryApproval.temporaryApprove, (address(spender), value)));
    }

    function _query() internal view returns (Actor.Action memory) {
        return _action(diamond, abi.encodeCall(ERC20.allowance, (address(owner), address(spender))));
    }

    function _approve(uint256 value) internal {
        Actor.Action[] memory actions = new Actor.Action[](1);
        actions[0] = _action(diamond, abi.encodeCall(ERC20.approve, (address(spender), value)));
        owner.run(actions);
    }

    function _spend(uint256 value) internal view returns (Actor.Action memory) {
        Actor.Action[] memory inner = new Actor.Action[](1);
        inner[0] = _action(diamond, abi.encodeCall(ERC20.transferFrom, (address(owner), recipient, value)));
        return _action(address(spender), abi.encodeCall(Actor.run, (inner)));
    }

    function test_AllowanceIncludesSameTransactionGrant() public {
        Actor.Action[] memory persistent = new Actor.Action[](1);
        persistent[0] = _action(diamond, abi.encodeCall(ERC20.approve, (address(spender), 3)));
        owner.run(persistent);
        Actor.Action[] memory actions = new Actor.Action[](2);
        actions[0] = _grant(7);
        actions[1] = _action(diamond, abi.encodeCall(ERC20.allowance, (address(owner), address(spender))));
        bytes[] memory results = owner.run(actions);
        assertEq(abi.decode(results[1], (uint256)), 10);
    }

    function test_SpendUsesSameTransactionGrant() public {
        Actor.Action[] memory actions = new Actor.Action[](2);
        actions[0] = _grant(7);
        actions[1] = _spend(6);
        owner.run(actions);
        assertEq(token.balanceOf(recipient), 6);
    }

    function test_TemporaryClearsAtNextTransaction() public {
        _approve(3);
        Actor.Action[] memory actions = new Actor.Action[](2);
        actions[0] = _grant(7);
        actions[1] = _query();
        bytes[] memory results = owner.run(actions);
        assertEq(abi.decode(results[1], (uint256)), 10, "positive same-transaction control");
        assertEq(token.allowance(address(owner), address(spender)), 3, "new transaction clears grant");
    }

    function test_TemporaryFirstAcrossRepeatedAndMixedSpends() public {
        _approve(9);
        Actor.Action[] memory actions = new Actor.Action[](6);
        actions[0] = _grant(7);
        actions[1] = _spend(4);
        actions[2] = _query();
        actions[3] = _spend(6);
        actions[4] = _query();
        actions[5] = _spend(2);
        bytes[] memory results = owner.run(actions);
        assertEq(abi.decode(results[2], (uint256)), 12);
        assertEq(abi.decode(results[4], (uint256)), 6);
        assertEq(token.allowance(address(owner), address(spender)), 4);
        assertEq(token.balanceOf(recipient), 12);
    }

    function test_InfiniteTemporaryDoesNotConsumePersistent() public {
        _approve(3);
        Actor.Action[] memory actions = new Actor.Action[](4);
        actions[0] = _grant(type(uint256).max);
        actions[1] = _spend(9);
        actions[2] = _spend(11);
        actions[3] = _query();
        bytes[] memory results = owner.run(actions);
        assertEq(abi.decode(results[3], (uint256)), type(uint256).max);
        assertEq(token.allowance(address(owner), address(spender)), 3);
    }

    function test_FiniteTemporaryConsumedBeforeInfinitePersistent() public {
        _approve(type(uint256).max);
        Actor.Action[] memory actions = new Actor.Action[](4);
        actions[0] = _grant(7);
        actions[1] = _spend(9);
        actions[2] = _action(diamond, abi.encodeCall(ERC20.approve, (address(spender), 0)));
        actions[3] = _query();
        bytes[] memory results = owner.run(actions);
        assertEq(abi.decode(results[3], (uint256)), 0, "temporary was consumed despite infinite persistent");
    }

    function test_AllowanceSaturatesOnOverflow() public {
        _approve(type(uint256).max - 3);
        Actor.Action[] memory actions = new Actor.Action[](2);
        actions[0] = _grant(7);
        actions[1] = _query();
        assertEq(abi.decode(owner.run(actions)[1], (uint256)), type(uint256).max);
    }

    function test_OverwriteIncludingZeroDoesNotChangePersistent() public {
        _approve(3);
        Actor.Action[] memory actions = new Actor.Action[](5);
        actions[0] = _grant(7);
        actions[1] = _grant(2);
        actions[2] = _query();
        actions[3] = _grant(0);
        actions[4] = _query();
        bytes[] memory results = owner.run(actions);
        assertEq(abi.decode(results[2], (uint256)), 5);
        assertEq(abi.decode(results[4], (uint256)), 3);
        assertEq(token.allowance(address(owner), address(spender)), 3);
    }

    function test_PersistentApproveDoesNotRevokeTemporary() public {
        Actor.Action[] memory actions = new Actor.Action[](4);
        actions[0] = _grant(7);
        actions[1] = _action(diamond, abi.encodeCall(ERC20.approve, (address(spender), 0)));
        actions[2] = _spend(6);
        actions[3] = _query();
        assertEq(abi.decode(owner.run(actions)[3], (uint256)), 1);
    }

    function test_NoApprovalEventForGrantOrSpend() public {
        _approve(9);
        Actor.Action[] memory actions = new Actor.Action[](3);
        actions[0] = _grant(7);
        actions[1] = _spend(3);
        actions[2] = _spend(6);
        vm.recordLogs();
        owner.run(actions);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i; i < entries.length; ++i) {
            assertTrue(entries[i].topics[0] != keccak256("Approval(address,address,uint256)"));
        }
        assertEq(entries.length, 2, "only two Transfer events");
    }

    function test_InsufficientAllowanceRollsBackTemporaryConsumption() public {
        _approve(3);
        Actor.Action[] memory actions = new Actor.Action[](3);
        actions[0] = _grant(7);
        actions[1] = _spend(20);
        actions[1].allowFailure = true;
        actions[2] = _query();
        bytes[] memory results = owner.run(actions);
        assertEq(
            results[1], abi.encodeWithSelector(IERC20.ERC20InsufficientAllowance.selector, address(spender), 3, 13)
        );
        assertEq(abi.decode(results[2], (uint256)), 10);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(address(owner), address(spender)), 3);
    }

    function test_BalanceRevertRestoresBothAllowances() public {
        _approve(150);
        Actor.Action[] memory actions = new Actor.Action[](3);
        actions[0] = _grant(7);
        actions[1] = _spend(120);
        actions[1].allowFailure = true;
        actions[2] = _query();
        bytes[] memory results = owner.run(actions);
        assertEq(results[1], abi.encodeWithSelector(IERC20.ERC20InsufficientBalance.selector, address(owner), 100, 120));
        assertEq(abi.decode(results[2], (uint256)), 157);
        assertEq(token.allowance(address(owner), address(spender)), 150);
    }

    function test_RevertedOverwriteRestoresPreviousTransientGrant() public {
        Actor.Action[] memory nested = new Actor.Action[](1);
        nested[0] = _grant(1);
        Actor.Action[] memory actions = new Actor.Action[](3);
        actions[0] = _grant(7);
        actions[1] = Actor.Action(address(owner), abi.encodeCall(Actor.runAndRevert, (nested)), true);
        actions[2] = _query();
        bytes[] memory results = owner.run(actions);
        assertEq(results[1], abi.encodeWithSelector(Actor.DeliberateRollback.selector));
        assertEq(abi.decode(results[2], (uint256)), 7);
    }

    function test_OwnerAndSpenderKeysAreIndependent() public {
        Actor.Action[] memory actions = new Actor.Action[](4);
        actions[0] = _grant(7);
        actions[1] = _action(diamond, abi.encodeCall(ERC20.allowance, (address(owner), recipient)));
        actions[2] = _action(diamond, abi.encodeCall(ERC20.allowance, (recipient, address(spender))));
        actions[3] = _query();
        bytes[] memory results = owner.run(actions);
        assertEq(abi.decode(results[1], (uint256)), 0);
        assertEq(abi.decode(results[2], (uint256)), 0);
        assertEq(abi.decode(results[3], (uint256)), 7);
    }

    function test_ZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InvalidSpender.selector, address(0)));
        IERC20TemporaryApproval(diamond).temporaryApprove(address(0), 1);
    }

    function test_ZeroApproverReverts() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InvalidApprover.selector, address(0)));
        IERC20TemporaryApproval(diamond).temporaryApprove(address(spender), 1);
    }

    function test_AdditiveFacetNeedsNoPersistentActivation() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IERC20TemporaryApproval.temporaryApprove.selector;
        FacetCut[] memory extras = new FacetCut[](1);
        extras[0] = FacetCut(address(new ERC20TemporaryApproval()), FacetCutAction.Add, selectors);
        diamond = _deployERC20("Additive", "ADD", extras);
        token = ERC20(diamond);
        TokenTestFacet(diamond).mint(address(owner), 100);
        Actor.Action[] memory actions = new Actor.Action[](2);
        actions[0] = _grant(7);
        actions[1] = _spend(6);
        owner.run(actions);
        assertEq(token.balanceOf(recipient), 6);
        // The optional init registers discovery; it is not an allowance activation switch.
        assertFalse(ERC165Facet(diamond).supportsInterface(type(IERC20TemporaryApproval).interfaceId));
    }

    function test_SupportsInterfaceAndFrozenERC20Surface() public view {
        assertEq(type(IERC20).interfaceId, bytes4(0x942e8b22));
        assertEq(type(IERC20TemporaryApproval).interfaceId, bytes4(0x42232a4c));
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC20TemporaryApproval).interfaceId));
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC20).interfaceId));
    }

    function test_InitRequiresInitializingWindow() public {
        ERC20TemporaryApprovalInit init = new ERC20TemporaryApprovalInit();
        vm.expectRevert();
        init.init();
    }

    function test_TemporaryCoveredSpendSkipsPersistentAllowanceSlot() public {
        // A single top-level actor transaction must contain grant and spend. record() observes both;
        // neither operation reads the persistent allowance. The getter is deliberately outside that range.
        Actor.Action[] memory actions = new Actor.Action[](2);
        actions[0] = _grant(7);
        actions[1] = _spend(6);
        vm.record();
        owner.run(actions);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(diamond);
        bytes32 allowanceSlot = keccak256(
            abi.encode(address(spender), keccak256(abi.encode(address(owner), uint256(ERC20_STORAGE_SLOT) + 1)))
        );
        for (uint256 i; i < reads.length; ++i) {
            assertTrue(reads[i] != allowanceSlot, "persistent allowance read");
        }
        for (uint256 i; i < writes.length; ++i) {
            assertTrue(writes[i] != allowanceSlot, "persistent allowance written");
        }
        assertEq(token.balanceOf(recipient), 6, "positive spend control");
    }

    function testFuzz_CombinedAllowanceSaturates(uint256 persistent, uint256 temporary) public {
        _approve(persistent);
        Actor.Action[] memory actions = new Actor.Action[](2);
        actions[0] = _grant(temporary);
        actions[1] = _query();
        uint256 expected;
        unchecked {
            expected = persistent + temporary;
        }
        if (expected < persistent) expected = type(uint256).max;
        assertEq(abi.decode(owner.run(actions)[1], (uint256)), expected);
    }

    function testFuzz_TemporaryFirstConsumption(uint96 persistent, uint96 temporary, uint96 value) public {
        persistent = uint96(bound(persistent, 0, 100));
        temporary = uint96(bound(temporary, 0, 100));
        value = uint96(bound(value, 0, persistent + temporary < 100 ? persistent + temporary : 100));
        _approve(persistent);
        Actor.Action[] memory actions = new Actor.Action[](3);
        actions[0] = _grant(temporary);
        actions[1] = _spend(value);
        actions[2] = _query();
        bytes[] memory results = owner.run(actions);
        assertEq(abi.decode(results[2], (uint256)), uint256(persistent) + temporary - value);
        uint256 persistentSpent = value > temporary ? value - temporary : 0;
        assertEq(token.allowance(address(owner), address(spender)), persistent - persistentSpent);
    }

    function test_DiamondsSharingFacetsHaveIsolatedTemporaryState() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory data) =
            new DeployERC20TemporaryApproval().buildCuts("Shared", "SAME");
        address first = _deployWithHelper(cuts, inits, data);
        address second = _deployWithHelper(cuts, inits, data);
        Actor.Action[] memory actions = new Actor.Action[](3);
        actions[0] = _action(first, abi.encodeCall(IERC20TemporaryApproval.temporaryApprove, (address(spender), 7)));
        actions[1] = _action(first, abi.encodeCall(ERC20.allowance, (address(owner), address(spender))));
        actions[2] = _action(second, abi.encodeCall(ERC20.allowance, (address(owner), address(spender))));
        bytes[] memory results = owner.run(actions);
        assertEq(abi.decode(results[1], (uint256)), 7);
        assertEq(abi.decode(results[2], (uint256)), 0);
    }

    function test_AddingTemporaryApprovalPreservesExistingTokenStorage() public {
        (FacetCut[] memory base, address init, bytes memory initData) =
            new DeployERC20().buildCuts("Existing", "OLD", address(this));
        address[] memory inits = new address[](1);
        inits[0] = init;
        bytes[] memory data = new bytes[](1);
        data[0] = initData;
        address existing = _deployWithHelper(base, inits, data);
        TokenTestFacet(existing).mint(address(owner), 123);
        Actor.Action[] memory actions = new Actor.Action[](1);
        actions[0] = _action(existing, abi.encodeCall(ERC20.approve, (address(spender), 41)));
        owner.run(actions);
        bytes32[] memory beforeSlots = new bytes32[](5);
        for (uint256 i; i < 5; ++i) {
            beforeSlots[i] = vm.load(existing, bytes32(uint256(ERC20_STORAGE_SLOT) + i));
        }
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IERC20TemporaryApproval.temporaryApprove.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(new ERC20TemporaryApproval()), FacetCutAction.Add, selectors);
        TemporaryApprovalUpgradeInit upgradeInit = new TemporaryApprovalUpgradeInit();
        AccessControlDiamondCut(existing)
            .diamondCut(cuts, address(upgradeInit), abi.encodeCall(TemporaryApprovalUpgradeInit.init, ()));
        for (uint256 i; i < 5; ++i) {
            assertEq(vm.load(existing, bytes32(uint256(ERC20_STORAGE_SLOT) + i)), beforeSlots[i]);
        }
        assertEq(vm.load(existing, bytes32(uint256(ERC20_STORAGE_SLOT) + 5)), bytes32(0), "no activation field");
        assertEq(ERC20(existing).name(), "Existing");
        assertEq(ERC20(existing).symbol(), "OLD");
        assertEq(ERC20(existing).totalSupply(), 123);
        assertEq(ERC20(existing).balanceOf(address(owner)), 123);
        assertEq(ERC20(existing).allowance(address(owner), address(spender)), 41);
        actions = new Actor.Action[](2);
        actions[0] = _action(existing, abi.encodeCall(IERC20TemporaryApproval.temporaryApprove, (address(spender), 7)));
        actions[1] = _action(existing, abi.encodeCall(ERC20.allowance, (address(owner), address(spender))));
        assertEq(abi.decode(owner.run(actions)[1], (uint256)), 48);
    }
}
