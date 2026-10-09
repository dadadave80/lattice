// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC1363} from "@lattice-script/base/tokens/DeployERC1363.s.sol";
import {ERC20TestBase} from "@lattice-test/base/ERC20TestBase.sol";
import {TokenTestFacet} from "@lattice-test/helpers/TokenTestFacet.sol";
import {IERC1363, IERC1363Receiver, IERC1363Spender} from "@lattice/interfaces/tokens/IERC1363.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
// The recipe loads the facet by artifact path, so a filtered `forge test` must compile it.
import {ERC1363} from "@lattice/tokens/ERC20/ERC1363.sol";

/// @notice ERC-1363 receiver and spender double: accepts by default and records what the token passed in.
///         `mode` switches it to return a wrong value, revert with a custom error, or revert with no data.
contract Mock1363Recipient is IERC1363Receiver, IERC1363Spender {
    enum Mode {
        Accept,
        WrongValue,
        RevertWithReason,
        RevertEmpty
    }

    error RecipientRejected(uint256 value);

    Mode public mode;
    address public lastOperator;
    address public lastFrom;
    uint256 public lastValue;
    bytes public lastData;
    uint256 public balanceSeen;
    uint256 public allowanceSeen;

    function setMode(Mode m) external {
        mode = m;
    }

    function onTransferReceived(address operator, address from, uint256 value, bytes calldata data)
        external
        returns (bytes4)
    {
        _enforce(value);
        (lastOperator, lastFrom, lastValue, lastData) = (operator, from, value, data);
        balanceSeen = IERC20(msg.sender).balanceOf(address(this));
        return mode == Mode.WrongValue ? bytes4(0xdeadbeef) : IERC1363Receiver.onTransferReceived.selector;
    }

    function onApprovalReceived(address owner, uint256 value, bytes calldata data) external returns (bytes4) {
        _enforce(value);
        (lastOperator, lastFrom, lastValue, lastData) = (address(0), owner, value, data);
        allowanceSeen = IERC20(msg.sender).allowance(owner, address(this));
        return mode == Mode.WrongValue ? bytes4(0xdeadbeef) : IERC1363Spender.onApprovalReceived.selector;
    }

    function _enforce(uint256 value) private view {
        if (mode == Mode.RevertWithReason) revert RecipientRejected(value);
        if (mode == Mode.RevertEmpty) revert();
    }
}

/// @title ERC1363Test
/// @notice Exercises the {ERC1363} facet through a REAL {Diamond} assembled by the ready-to-deploy {DeployERC1363}
///         recipe (base ERC-20 + the additive ERC-1363 facet). Every call routes through the diamond's
///         `delegatecall` dispatch; `mint` comes from the test-only {TokenTestFacet} (`helper`) and
///         `supportsInterface` from the cut-in `ERC165Facet`.
contract ERC1363Test is ERC20TestBase {
    IERC1363 internal t1363;
    Mock1363Recipient internal recipient;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address eoa = makeAddr("eoa");

    uint256 constant INITIAL = 1_000e18;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public override {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            new DeployERC1363().buildCuts("Callable Token", "CALL");
        diamond = _deployWithHelper(cuts, inits, initCalldatas);
        token = ERC20(diamond);
        helper = TokenTestFacet(diamond);
        t1363 = IERC1363(diamond);
        recipient = new Mock1363Recipient();

        helper.mint(alice, INITIAL);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              TRANSFER AND CALL
    //////////////////////////////////////////////////////////////////////////*//

    function test_TransferAndCall_NoData() public {
        vm.expectEmit(true, true, false, true, diamond);
        emit Transfer(alice, address(recipient), 10e18);
        vm.prank(alice);
        assertTrue(t1363.transferAndCall(address(recipient), 10e18));

        assertEq(token.balanceOf(alice), INITIAL - 10e18);
        assertEq(token.balanceOf(address(recipient)), 10e18);
        _assertReceived(alice, alice, 10e18, "");
    }

    function test_TransferAndCall_WithData() public {
        vm.prank(alice);
        assertTrue(t1363.transferAndCall(address(recipient), 10e18, hex"c0ffee"));
        _assertReceived(alice, alice, 10e18, hex"c0ffee");
    }

    /// @notice The hook runs after the transfer, so the receiver already holds the tokens when it is called.
    function test_TransferAndCall_ReceiverSeesCreditedBalance() public {
        vm.prank(alice);
        t1363.transferAndCall(address(recipient), 7e18);
        assertEq(recipient.balanceSeen(), 7e18);
    }

    function test_TransferAndCall_EOAReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC1363.ERC1363InvalidReceiver.selector, eoa));
        t1363.transferAndCall(eoa, 1e18);
    }

    function test_TransferAndCall_WrongReturnValueReverts() public {
        recipient.setMode(Mock1363Recipient.Mode.WrongValue);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC1363.ERC1363InvalidReceiver.selector, address(recipient)));
        t1363.transferAndCall(address(recipient), 1e18, hex"01");
    }

    function test_TransferAndCall_BubblesReceiverReason() public {
        recipient.setMode(Mock1363Recipient.Mode.RevertWithReason);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Mock1363Recipient.RecipientRejected.selector, 1e18));
        t1363.transferAndCall(address(recipient), 1e18);
        assertEq(token.balanceOf(alice), INITIAL, "the transfer rolled back");
    }

    function test_TransferAndCall_EmptyRevertIsInvalidReceiver() public {
        recipient.setMode(Mock1363Recipient.Mode.RevertEmpty);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC1363.ERC1363InvalidReceiver.selector, address(recipient)));
        t1363.transferAndCall(address(recipient), 1e18);
    }

    /// @dev The receiver would revert with its own error, so the balance error surfacing proves the debit runs
    ///      before the hook.
    function test_TransferAndCall_InsufficientBalanceRevertsBeforeHook() public {
        recipient.setMode(Mock1363Recipient.Mode.RevertWithReason);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InsufficientBalance.selector, bob, 0, 1));
        t1363.transferAndCall(address(recipient), 1);
    }

    function testFuzz_TransferAndCall(uint256 value, bytes calldata data) public {
        value = bound(value, 0, INITIAL);
        vm.prank(alice);
        t1363.transferAndCall(address(recipient), value, data);
        assertEq(token.balanceOf(address(recipient)), value);
        assertEq(token.balanceOf(alice) + value, INITIAL);
        _assertReceived(alice, alice, value, data);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           TRANSFER FROM AND CALL
    //////////////////////////////////////////////////////////////////////////*//

    function test_TransferFromAndCall_NoData() public {
        vm.prank(alice);
        token.approve(bob, 30e18);

        vm.expectEmit(true, true, false, true, diamond);
        emit Transfer(alice, address(recipient), 20e18);
        vm.prank(bob);
        assertTrue(t1363.transferFromAndCall(alice, address(recipient), 20e18));

        assertEq(token.balanceOf(address(recipient)), 20e18);
        assertEq(token.allowance(alice, bob), 10e18, "allowance spent");
        _assertReceived(bob, alice, 20e18, "");
    }

    function test_TransferFromAndCall_WithData() public {
        vm.prank(alice);
        token.approve(bob, 30e18);
        vm.prank(bob);
        assertTrue(t1363.transferFromAndCall(alice, address(recipient), 20e18, hex"beef"));
        _assertReceived(bob, alice, 20e18, hex"beef");
    }

    function test_TransferFromAndCall_InsufficientAllowanceReverts() public {
        vm.prank(alice);
        token.approve(bob, 1e18);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InsufficientAllowance.selector, bob, 1e18, 2e18));
        t1363.transferFromAndCall(alice, address(recipient), 2e18);
    }

    function test_TransferFromAndCall_EOAReverts() public {
        vm.prank(alice);
        token.approve(bob, 1e18);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC1363.ERC1363InvalidReceiver.selector, eoa));
        t1363.transferFromAndCall(alice, eoa, 1e18, "");
    }

    function test_TransferFromAndCall_WrongReturnValueReverts() public {
        recipient.setMode(Mock1363Recipient.Mode.WrongValue);
        vm.prank(alice);
        token.approve(bob, 1e18);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC1363.ERC1363InvalidReceiver.selector, address(recipient)));
        t1363.transferFromAndCall(alice, address(recipient), 1e18);
    }

    function test_TransferFromAndCall_BubblesReceiverReason() public {
        recipient.setMode(Mock1363Recipient.Mode.RevertWithReason);
        vm.prank(alice);
        token.approve(bob, 1e18);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Mock1363Recipient.RecipientRejected.selector, 1e18));
        t1363.transferFromAndCall(alice, address(recipient), 1e18, hex"02");
        assertEq(token.allowance(alice, bob), 1e18, "the allowance spend rolled back");
    }

    function test_TransferFromAndCall_EmptyRevertIsInvalidReceiver() public {
        recipient.setMode(Mock1363Recipient.Mode.RevertEmpty);
        vm.prank(alice);
        token.approve(bob, 1e18);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC1363.ERC1363InvalidReceiver.selector, address(recipient)));
        t1363.transferFromAndCall(alice, address(recipient), 1e18);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              APPROVE AND CALL
    //////////////////////////////////////////////////////////////////////////*//

    function test_ApproveAndCall_NoData() public {
        vm.expectEmit(true, true, false, true, diamond);
        emit Approval(alice, address(recipient), 5e18);
        vm.prank(alice);
        assertTrue(t1363.approveAndCall(address(recipient), 5e18));

        assertEq(token.allowance(alice, address(recipient)), 5e18);
        assertEq(recipient.allowanceSeen(), 5e18, "the spender is called after the approval");
        assertEq(recipient.lastFrom(), alice);
        assertEq(recipient.lastValue(), 5e18);
        assertEq(recipient.lastData(), "");
    }

    function test_ApproveAndCall_WithData() public {
        vm.prank(alice);
        assertTrue(t1363.approveAndCall(address(recipient), 5e18, hex"abcd"));
        assertEq(recipient.lastFrom(), alice);
        assertEq(recipient.lastData(), hex"abcd");
    }

    function test_ApproveAndCall_EOAReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC1363.ERC1363InvalidSpender.selector, eoa));
        t1363.approveAndCall(eoa, 1e18);
    }

    function test_ApproveAndCall_WrongReturnValueReverts() public {
        recipient.setMode(Mock1363Recipient.Mode.WrongValue);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC1363.ERC1363InvalidSpender.selector, address(recipient)));
        t1363.approveAndCall(address(recipient), 1e18, hex"03");
    }

    function test_ApproveAndCall_BubblesSpenderReason() public {
        recipient.setMode(Mock1363Recipient.Mode.RevertWithReason);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Mock1363Recipient.RecipientRejected.selector, 1e18));
        t1363.approveAndCall(address(recipient), 1e18);
        assertEq(token.allowance(alice, address(recipient)), 0, "the approval rolled back");
    }

    function test_ApproveAndCall_EmptyRevertIsInvalidSpender() public {
        recipient.setMode(Mock1363Recipient.Mode.RevertEmpty);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC1363.ERC1363InvalidSpender.selector, address(recipient)));
        t1363.approveAndCall(address(recipient), 1e18);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  ERC-165
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsInterface() public view {
        assertEq(type(IERC1363).interfaceId, bytes4(0xb0202a11), "canonical ERC-1363 id");
        assertTrue(ERC165Facet(diamond).supportsInterface(0xb0202a11));
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC20).interfaceId)); // base ERC-20
    }

    function _assertReceived(address operator, address from, uint256 value, bytes memory data) internal view {
        assertEq(recipient.lastOperator(), operator, "operator");
        assertEq(recipient.lastFrom(), from, "from");
        assertEq(recipient.lastValue(), value, "value");
        assertEq(recipient.lastData(), data, "data");
    }
}
