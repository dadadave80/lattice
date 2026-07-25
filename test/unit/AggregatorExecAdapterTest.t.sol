// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {AggregatorExecAdapterTestBase} from "@lattice-test/base/AggregatorExecAdapterTestBase.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {AggregatorExecAdapter} from "@lattice/defi/AggregatorExecAdapter.sol";
import {IAggregatorExecAdapter} from "@lattice/interfaces/defi/IAggregatorExecAdapter.sol";
import {IReentrancyGuard} from "@lattice/interfaces/security/IReentrancyGuard.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  FIXTURES
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal ERC-20 (mint/approve/transfer/transferFrom). 0.8 arithmetic reverts on
///         insufficient-allowance / insufficient-balance underflow, modelling a real token's revert.
contract MockERC20 is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;
    string private _name;
    string private _symbol;

    constructor(string memory n, string memory s) {
        _name = n;
        _symbol = s;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        allowance[from][msg.sender] -= value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        return true;
    }
}

/// @notice A well-behaved aggregator: pulls `inputToken` from the caller (the diamond) up to its allowance,
///         then mints a configurable `outputToken` to a configurable receiver (the diamond or the end user).
///         Variants: under-spend the input, or refund some native to the caller.
contract MockAggregator {
    address public outputToken;
    uint256 public outputAmount;
    address public outputReceiver;
    uint256 public inputSpend; // amount of input to pull
    bool public spendFull = true; // when true, pull the full `amount` argument
    uint256 public nativeRefund; // native to send back to the caller (the diamond)

    function configureOutput(address token, uint256 amount, address receiver) external {
        outputToken = token;
        outputAmount = amount;
        outputReceiver = receiver;
    }

    function setInputSpend(uint256 s) external {
        inputSpend = s;
        spendFull = false;
    }

    function setNativeRefund(uint256 r) external {
        nativeRefund = r;
    }

    /// @dev The selector allow-listed in tests. `bytes4(callData)` == `swap.selector`.
    function swap(address inputToken, uint256 amount) external payable {
        if (inputToken != address(0)) {
            uint256 toPull = spendFull ? amount : inputSpend;
            if (toPull > 0) IERC20(inputToken).transferFrom(msg.sender, address(this), toPull);
        }
        if (outputToken != address(0) && outputAmount > 0) {
            MockERC20(outputToken).mint(outputReceiver, outputAmount);
        }
        if (nativeRefund > 0) {
            (bool ok,) = payable(msg.sender).call{value: nativeRefund}("");
            require(ok, "refund failed");
        }
    }

    receive() external payable {}
}

/// @notice Confused-deputy attacker: on `swap`, tries to drain the caller's (diamond's) standing balance of a
///         token it was NEVER approved for. The `transferFrom` reverts (no allowance) and the revert bubbles up.
contract MockThiefAggregator {
    address public victimToken;
    address public thief;

    function setTarget(address victimToken_, address thief_) external {
        victimToken = victimToken_;
        thief = thief_;
    }

    function swap(address, uint256) external payable {
        uint256 bal = IERC20(victimToken).balanceOf(msg.sender);
        IERC20(victimToken).transferFrom(msg.sender, thief, bal);
    }
}

/// @notice Reentrancy attacker: on `swap`, re-enters `execute` on the diamond. The reentrancy guard must fire.
contract MockReentrantAggregator {
    address public diamond;
    bytes public reenterData;

    function setReenter(address diamond_, bytes calldata data_) external {
        diamond = diamond_;
        reenterData = data_;
    }

    function swap(address, uint256) external payable {
        (bool ok, bytes memory ret) = diamond.call(reenterData);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                   TESTS
//////////////////////////////////////////////////////////////////////////*//

contract AggregatorExecAdapterTest is AggregatorExecAdapterTestBase {
    address diamond;
    AggregatorExecAdapter adapter;

    MockAggregator aggregator;
    MockERC20 inputToken;
    MockERC20 outputToken;

    address admin = address(0x1);
    address user = address(0x2);
    address stranger = address(0x3);

    bytes4 constant SWAP_SEL = MockAggregator.swap.selector;
    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    function setUp() public {
        diamond = _deployAggregatorExecAdapter(admin);
        adapter = AggregatorExecAdapter(diamond);

        aggregator = new MockAggregator();
        inputToken = new MockERC20("Input", "IN");
        outputToken = new MockERC20("Output", "OUT");

        vm.prank(admin);
        adapter.setAllowedCall(address(aggregator), SWAP_SEL, true);
    }

    /// @dev Funds `user` with `amount` input and approves the diamond to pull it.
    function _fundUser(uint256 amount) internal {
        inputToken.mint(user, amount);
        vm.prank(user);
        inputToken.approve(diamond, amount);
    }

    function _swapData(uint256 amount) internal view returns (bytes memory) {
        return abi.encodeCall(MockAggregator.swap, (address(inputToken), amount));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   INIT
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsInterface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IAggregatorExecAdapter).interfaceId));
    }

    function test_InitRejectsZeroAdmin() public {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(address(0));
        Lattice d = new Lattice();
        vm.expectRevert(IAggregatorExecAdapter.AggregatorExecZeroAdmin.selector);
        d.initialize(cuts, init, initCalldata);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 ALLOW-LIST
    //////////////////////////////////////////////////////////////////////////*//

    function test_SetAllowedCall() public {
        assertTrue(adapter.isAllowedCall(address(aggregator), SWAP_SEL));
        vm.prank(admin);
        adapter.setAllowedCall(address(aggregator), SWAP_SEL, false);
        assertFalse(adapter.isAllowedCall(address(aggregator), SWAP_SEL));
    }

    function test_SetAllowedCallEmitsEvent() public {
        vm.expectEmit(true, true, false, true, diamond);
        emit IAggregatorExecAdapter.AllowedCallSet(address(aggregator), SWAP_SEL, true);
        vm.prank(admin);
        adapter.setAllowedCall(address(aggregator), SWAP_SEL, true);
    }

    function test_SetAllowedCallRevertsNonAdmin() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, stranger, bytes32(0)));
        adapter.setAllowedCall(address(aggregator), SWAP_SEL, true);
    }

    function test_SetAllowedCallRejectsZeroAggregator() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IAggregatorExecAdapter.AggregatorExecInvalidAggregator.selector, address(0))
        );
        adapter.setAllowedCall(address(0), SWAP_SEL, true);
    }

    /// @notice The diamond must NEVER be able to allow-list ITSELF (would let calldata re-enter privileged facets).
    function test_SetAllowedCallRejectsSelf() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IAggregatorExecAdapter.AggregatorExecInvalidAggregator.selector, diamond)
        );
        adapter.setAllowedCall(diamond, SWAP_SEL, true);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              EXECUTE: HAPPY PATH
    //////////////////////////////////////////////////////////////////////////*//

    function test_ExecuteHappyPath() public {
        uint256 amount = 1_000e18;
        _fundUser(amount);
        // Aggregator sends the output to the diamond; the adapter sweeps the delta to the user.
        aggregator.configureOutput(address(outputToken), 900e18, diamond);

        vm.prank(user);
        adapter.execute(address(aggregator), address(inputToken), amount, address(outputToken), _swapData(amount));

        assertEq(inputToken.balanceOf(user), 0, "input pulled from caller");
        assertEq(inputToken.balanceOf(address(aggregator)), amount, "aggregator consumed input");
        assertEq(inputToken.balanceOf(diamond), 0, "no input stuck in diamond");
        assertEq(outputToken.balanceOf(user), 900e18, "output delta swept to user");
        assertEq(outputToken.balanceOf(diamond), 0, "no output stuck in diamond");
    }

    function test_ExecuteEmitsEvent() public {
        uint256 amount = 500e18;
        _fundUser(amount);
        aggregator.configureOutput(address(outputToken), 1, diamond);

        vm.expectEmit(true, true, true, true, diamond);
        emit IAggregatorExecAdapter.AggregatorCall(
            user, address(aggregator), SWAP_SEL, address(inputToken), amount, address(outputToken)
        );
        vm.prank(user);
        adapter.execute(address(aggregator), address(inputToken), amount, address(outputToken), _swapData(amount));
    }

    /// @notice Output can be routed directly to the user; the diamond nets zero and sweeps nothing.
    function test_ExecuteOutputToUserDirectly() public {
        uint256 amount = 1_000e18;
        _fundUser(amount);
        aggregator.configureOutput(address(outputToken), 950e18, user);

        vm.prank(user);
        adapter.execute(address(aggregator), address(inputToken), amount, address(outputToken), _swapData(amount));

        assertEq(outputToken.balanceOf(user), 950e18);
        assertEq(outputToken.balanceOf(diamond), 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          ALLOW-LIST ENFORCEMENT
    //////////////////////////////////////////////////////////////////////////*//

    function test_ExecuteRevertsUnknownAggregator() public {
        MockAggregator other = new MockAggregator();
        uint256 amount = 100e18;
        _fundUser(amount);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IAggregatorExecAdapter.AggregatorExecNotAllowed.selector, address(other), SWAP_SEL)
        );
        adapter.execute(address(other), address(inputToken), amount, address(outputToken), _swapData(amount));
    }

    function test_ExecuteRevertsUnknownSelector() public {
        uint256 amount = 100e18;
        _fundUser(amount);
        // Same aggregator, but a selector that was never allow-listed.
        bytes memory data = abi.encodeWithSelector(bytes4(0xdeadbeef), address(inputToken), amount);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAggregatorExecAdapter.AggregatorExecNotAllowed.selector, address(aggregator), bytes4(0xdeadbeef)
            )
        );
        adapter.execute(address(aggregator), address(inputToken), amount, address(outputToken), data);
    }

    function test_ExecuteRevertsAfterRevoke() public {
        uint256 amount = 100e18;
        _fundUser(amount);
        vm.prank(admin);
        adapter.setAllowedCall(address(aggregator), SWAP_SEL, false);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAggregatorExecAdapter.AggregatorExecNotAllowed.selector, address(aggregator), SWAP_SEL
            )
        );
        adapter.execute(address(aggregator), address(inputToken), amount, address(outputToken), _swapData(amount));
    }

    function test_ExecuteRevertsEmptyCallData() public {
        vm.prank(user);
        vm.expectRevert(IAggregatorExecAdapter.AggregatorExecEmptyCallData.selector);
        adapter.execute(address(aggregator), address(inputToken), 0, address(outputToken), hex"010203");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          APPROVAL HYGIENE / RESET
    //////////////////////////////////////////////////////////////////////////*//

    function test_ExecuteResetsApprovalToZero() public {
        uint256 amount = 1_000e18;
        _fundUser(amount);
        aggregator.configureOutput(address(outputToken), 1, diamond);

        vm.prank(user);
        adapter.execute(address(aggregator), address(inputToken), amount, address(outputToken), _swapData(amount));

        assertEq(inputToken.allowance(diamond, address(aggregator)), 0, "allowance reset to 0");
    }

    /// @notice Even when the aggregator UNDER-spends, the allowance is reset to 0 and the unspent input is swept.
    function test_ExecuteUnderspendResetsAndSweeps() public {
        uint256 amount = 1_000e18;
        _fundUser(amount);
        aggregator.setInputSpend(400e18); // spend only 400 of the 1000 approved
        aggregator.configureOutput(address(outputToken), 350e18, diamond);

        vm.prank(user);
        adapter.execute(address(aggregator), address(inputToken), amount, address(outputToken), _swapData(amount));

        assertEq(inputToken.allowance(diamond, address(aggregator)), 0, "allowance reset even on under-spend");
        assertEq(inputToken.balanceOf(user), 600e18, "unspent input swept back to caller");
        assertEq(inputToken.balanceOf(diamond), 0, "no input stuck");
        assertEq(inputToken.balanceOf(address(aggregator)), 400e18, "aggregator kept only what it spent");
        assertEq(outputToken.balanceOf(user), 350e18, "output delta swept");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        CONFUSED-DEPUTY / FUND ISOLATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice A pre-existing standing balance of a DIFFERENT token is unreachable: the aggregator has no
    ///         allowance for it, so a crafted drain reverts and the standing balance is untouched.
    function test_CannotDrainStandingOtherToken() public {
        MockThiefAggregator thief = new MockThiefAggregator();
        MockERC20 victim = new MockERC20("Victim", "VIC");
        victim.mint(diamond, 5_000e18); // diamond holds a standing balance of `victim`
        thief.setTarget(address(victim), stranger);

        vm.prank(admin);
        adapter.setAllowedCall(address(thief), MockThiefAggregator.swap.selector, true);

        uint256 amount = 100e18;
        _fundUser(amount);
        bytes memory data = abi.encodeWithSelector(MockThiefAggregator.swap.selector, address(inputToken), amount);

        vm.prank(user);
        vm.expectRevert(); // transferFrom of the un-approved victim token reverts (no allowance)
        adapter.execute(address(thief), address(inputToken), amount, address(victim), data);

        assertEq(victim.balanceOf(diamond), 5_000e18, "standing balance untouched");
        assertEq(victim.balanceOf(stranger), 0, "nothing routed out");
    }

    /// @notice A standing balance of the SAME token as `inputToken` is isolated: the aggregator is approved for
    ///         EXACTLY `amount`, cannot pull more, and the delta-based sweep leaves the standing balance intact.
    function test_StandingInputBalanceIsolated() public {
        inputToken.mint(diamond, 5_000e18); // diamond holds a standing balance of the input token
        uint256 amount = 1_000e18;
        _fundUser(amount);
        aggregator.configureOutput(address(0), 0, diamond); // no output

        vm.prank(user);
        adapter.execute(address(aggregator), address(inputToken), amount, address(inputToken), _swapData(amount));

        assertEq(inputToken.balanceOf(diamond), 5_000e18, "standing input balance untouched by the swap");
        assertEq(inputToken.balanceOf(user), 0, "user's input fully consumed");
        assertEq(inputToken.balanceOf(address(aggregator)), amount, "aggregator got only the approved amount");
    }

    /// @notice The aggregator cannot pull MORE than the exact `amount` approved, even with standing input balance.
    function test_CannotOverspendApproval() public {
        inputToken.mint(diamond, 5_000e18);
        uint256 amount = 1_000e18;
        _fundUser(amount);
        aggregator.setInputSpend(1_500e18); // tries to pull more than the 1000 approved

        vm.prank(user);
        vm.expectRevert(); // allowance is exactly `amount`; over-pull underflows the allowance
        adapter.execute(address(aggregator), address(inputToken), amount, address(inputToken), _swapData(amount));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              NATIVE SWEEP
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Unspent native (msg.value the aggregator refunds) is swept back to the caller; a standing native
    ///         balance in the diamond is left untouched (delta-based).
    function test_ExecuteSweepsLeftoverNative() public {
        vm.deal(diamond, 3 ether); // standing native balance
        vm.deal(user, 5 ether);
        aggregator.setNativeRefund(2 ether); // aggregator returns 2 of the 5 forwarded

        uint256 userBefore = user.balance;
        // Native-in swap: inputToken == address(0); value forwarded via msg.value.
        bytes memory data = abi.encodeCall(MockAggregator.swap, (address(0), 0));
        vm.prank(user);
        adapter.execute{value: 5 ether}(address(aggregator), address(0), 0, address(0), data);

        assertEq(user.balance, userBefore - 5 ether + 2 ether, "unspent native refunded to user");
        assertEq(address(diamond).balance, 3 ether, "standing native untouched");
        assertEq(address(aggregator).balance, 3 ether, "aggregator kept the spent native");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              REVERT BUBBLING
    //////////////////////////////////////////////////////////////////////////*//

    function test_ExecuteBubblesAggregatorRevert() public {
        // Aggregator will try to pull input but the user granted no approval -> transferFrom reverts.
        uint256 amount = 100e18;
        inputToken.mint(user, amount); // minted but NOT approved to the diamond
        vm.prank(user);
        vm.expectRevert(); // pullExact's transferFrom underflows without allowance
        adapter.execute(address(aggregator), address(inputToken), amount, address(outputToken), _swapData(amount));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                REENTRANCY
    //////////////////////////////////////////////////////////////////////////*//

    function test_ExecuteNonReentrant() public {
        MockReentrantAggregator evil = new MockReentrantAggregator();
        vm.prank(admin);
        adapter.setAllowedCall(address(evil), MockReentrantAggregator.swap.selector, true);

        // The re-entrant payload calls execute again on the diamond.
        bytes memory inner = abi.encodeCall(
            IAggregatorExecAdapter.execute,
            (
                address(evil),
                address(0),
                0,
                address(0),
                abi.encodeWithSelector(MockReentrantAggregator.swap.selector, address(0), uint256(0))
            )
        );
        evil.setReenter(diamond, inner);

        bytes memory data = abi.encodeWithSelector(MockReentrantAggregator.swap.selector, address(0), uint256(0));
        vm.prank(user);
        vm.expectRevert(IReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        adapter.execute(address(evil), address(0), 0, address(0), data);
    }
}
