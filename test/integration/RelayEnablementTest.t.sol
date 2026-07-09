// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {RelayConfig} from "@lattice-script/config/EnableRelay.s.sol";
import {AggregatorExecAdapterTestBase} from "@lattice-test/base/AggregatorExecAdapterTestBase.sol";
import {AggregatorExecAdapter} from "@lattice/defi/AggregatorExecAdapter.sol";
import {IAggregatorExecAdapter} from "@lattice/interfaces/defi/IAggregatorExecAdapter.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";

/// @notice Canonical relay-periphery shapes (MIT), mirrored so the mocks' function selectors independently
///         cross-check {RelayConfig}'s keccak-derived constants.
struct Call3Value {
    address target;
    bool allowFailure;
    uint256 value;
    bytes callData;
}

struct Result {
    bool success;
    bytes returnData;
}

/// @notice Minimal ERC-20 used as the Relay input token.
contract MockToken is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    function name() external pure returns (string memory) {
        return "Mock Token";
    }

    function symbol() external pure returns (string memory) {
        return "MOCK";
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

/// @notice Canonical-signature stand-in for `RelayApprovalProxyV3`: pulls the listed tokens from the caller
///         (the diamond, via the adapter's exact approval) and records everything verbatim.
contract MockRelayApprovalProxy {
    address public lastRefundTo;
    bytes public lastMetadata;
    uint256 public calls;

    function transferAndMulticall(
        address[] calldata tokens,
        uint256[] calldata amounts,
        Call3Value[] calldata, /* calls */
        address refundTo,
        address, /* nftRecipient */
        bytes calldata metadata
    ) external payable returns (Result[] memory returnData) {
        for (uint256 i; i < tokens.length; ++i) {
            IERC20(tokens[i]).transferFrom(msg.sender, address(this), amounts[i]);
        }
        lastRefundTo = refundTo;
        lastMetadata = metadata;
        ++calls;
        return new Result[](0);
    }
}

/// @notice Canonical-signature stand-in for `RelayRouterV3.multicall`: refunds half the supplied value to
///         `refundTo` (exercising the quote-API refundTo-equals-diamond path the base adapter must sweep).
contract MockRelayRouter {
    uint256 public lastValue;

    function multicall(Call3Value[] calldata, address refundTo, address, bytes calldata)
        external
        payable
        returns (Result[] memory returnData)
    {
        lastValue = msg.value;
        uint256 refund = msg.value / 2;
        if (refund != 0) {
            (bool ok,) = payable(refundTo).call{value: refund}("");
            require(ok, "refund failed");
        }
        return new Result[](0);
    }
}

/// @notice Canonical-signature stand-in for `RelayReceiver.forward(bytes)`: forwards the value to the SOLVER
///         and records the request id, exactly like upstream.
contract MockRelayReceiver {
    address public immutable SOLVER;
    bytes public lastData;

    constructor(address solver) {
        SOLVER = solver;
    }

    function forward(bytes calldata data) external payable {
        (bool ok,) = payable(SOLVER).call{value: msg.value}("");
        require(ok, "solver send failed");
        lastData = data;
    }
}

/// @title RelayEnablementTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice #77 sub-task 15 integration proof: Reservoir's Relay (solver intents) enabled as a pure
///         {RelayConfig} allow-list configuration of the sub-task-7 `AggregatorExecAdapter` — NO new facet.
///         Mocks carry the CANONICAL relay-periphery signatures so their compiler-derived selectors
///         independently verify the config's keccak-derived constants.
/// @dev Solver-trust model under test only insofar as it is on-chain: there is no inbound surface, no
///      `receiveId`, and no completion signal — source-tx success does not prove the destination fill
///      (integrators reconcile off-chain against Relay's API; see {RelayConfig}).
contract RelayEnablementTest is AggregatorExecAdapterTestBase {
    IAggregatorExecAdapter adapter;
    address diamond;

    MockToken token;
    MockRelayApprovalProxy approvalProxy;
    MockRelayRouter router;
    MockRelayReceiver receiver;

    address admin = address(0x1);
    address user = address(0x2);
    address solver = address(0x501);

    uint256 constant AMOUNT = 1 ether;

    function setUp() public {
        diamond = _deployAggregatorExecAdapter(admin);
        adapter = IAggregatorExecAdapter(diamond);

        token = new MockToken();
        approvalProxy = new MockRelayApprovalProxy();
        router = new MockRelayRouter();
        receiver = new MockRelayReceiver(solver);

        vm.startPrank(admin);
        RelayConfig.configure(adapter, address(approvalProxy), address(router), address(receiver));
        vm.stopPrank();

        vm.deal(user, 10 ether);
    }

    /// @notice The keccak-derived selector constants match the COMPILER-derived selectors of the canonical
    ///         signatures (mirrored by the mocks) — an independent cross-check of the signature strings.
    function test_SelectorConstantsMatchCanonicalSignatures() public pure {
        assertEq(
            RelayConfig.TRANSFER_AND_MULTICALL_SELECTOR,
            MockRelayApprovalProxy.transferAndMulticall.selector,
            "transferAndMulticall selector"
        );
        assertEq(RelayConfig.MULTICALL_SELECTOR, MockRelayRouter.multicall.selector, "multicall selector");
        assertEq(RelayConfig.FORWARD_SELECTOR, MockRelayReceiver.forward.selector, "forward selector");
    }

    function test_ApplySetsExactlyTheCanonicalPairs() public view {
        assertTrue(adapter.isAllowedCall(address(approvalProxy), RelayConfig.TRANSFER_AND_MULTICALL_SELECTOR));
        assertTrue(adapter.isAllowedCall(address(router), RelayConfig.MULTICALL_SELECTOR));
        assertTrue(adapter.isAllowedCall(address(receiver), RelayConfig.FORWARD_SELECTOR));
        // The permit* variants are EOA-signature paths and are deliberately NOT allow-listed.
        assertFalse(
            adapter.isAllowedCall(
                address(approvalProxy),
                bytes4(
                    keccak256(
                        "permitTransferAndMulticall(address[],uint256[],(address,bool,uint256,bytes)[],address,address,bytes,bytes)"
                    )
                )
            ),
            "permit variant must stay unlisted"
        );
        // Selectors are gated PER aggregator: the proxy's selector is not allowed on the router.
        assertFalse(adapter.isAllowedCall(address(router), RelayConfig.TRANSFER_AND_MULTICALL_SELECTOR));
    }

    /// @notice ERC-20 pay-in through the ApprovalProxy: the base pulls from the user, exact-approves the
    ///         proxy, the proxy pulls into itself (solver settlement is off-chain), approval resets to 0.
    function test_Erc20FlowThroughApprovalProxy() public {
        token.mint(user, AMOUNT);
        vm.prank(user);
        token.approve(diamond, AMOUNT);

        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = AMOUNT;
        bytes memory callData = abi.encodeCall(
            MockRelayApprovalProxy.transferAndMulticall,
            (tokens, amounts, new Call3Value[](0), diamond, address(0), hex"1e1a")
        );

        vm.prank(user);
        adapter.execute(address(approvalProxy), address(token), AMOUNT, address(0), callData);

        assertEq(approvalProxy.calls(), 1, "proxy called once");
        assertEq(token.balanceOf(address(approvalProxy)), AMOUNT, "proxy pulled the pay-in");
        assertEq(token.balanceOf(user), 0, "user paid in");
        assertEq(token.balanceOf(diamond), 0, "diamond nets zero");
        assertEq(token.allowance(diamond, address(approvalProxy)), 0, "approval reset to 0");
        assertEq(approvalProxy.lastMetadata(), hex"1e1a", "request id forwarded verbatim");
    }

    /// @notice Native pay-in through the RelayReceiver: `forward(bytes)` sends the value straight to the
    ///         solver (the raw fallback path cannot be allow-listed — quotes must use forward, documented).
    function test_NativeFlowThroughReceiver() public {
        bytes memory callData = abi.encodeCall(MockRelayReceiver.forward, (hex"c0ffee"));
        vm.prank(user);
        adapter.execute{value: 1 ether}(address(receiver), address(0), 0, address(0), callData);

        assertEq(solver.balance, 1 ether, "solver fronted the full pay-in");
        assertEq(diamond.balance, 0, "no wei sticks to the diamond");
        assertEq(receiver.lastData(), hex"c0ffee", "request id recorded");
    }

    /// @notice A quote whose embedded `refundTo` points at the DIAMOND: the mid-call native refund lands on
    ///         the diamond and the base's delta sweep forwards it to the calling user — no stranding.
    function test_RouterRefundToDiamondSweptToUser() public {
        bytes memory callData =
            abi.encodeCall(MockRelayRouter.multicall, (new Call3Value[](0), diamond, address(0), hex""));
        uint256 balanceBefore = user.balance;

        vm.prank(user);
        adapter.execute{value: 2 ether}(address(router), address(0), 0, address(0), callData);

        assertEq(router.lastValue(), 2 ether, "full value forwarded to the router");
        assertEq(user.balance, balanceBefore - 1 ether, "the 1 ether refund swept back to the user");
        assertEq(diamond.balance, 0, "no wei sticks to the diamond");
    }

    function test_UnlistedSelectorReverts() public {
        bytes memory callData = abi.encodeWithSignature("withdraw(address)", address(token));
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAggregatorExecAdapter.AggregatorExecNotAllowed.selector, address(approvalProxy), bytes4(callData)
            )
        );
        adapter.execute(address(approvalProxy), address(0), 0, address(0), callData);
    }

    function test_NonAdminCannotApply() public {
        vm.prank(user);
        vm.expectRevert(); // AccessControlUnauthorizedAccount
        adapter.setAllowedCall(address(approvalProxy), RelayConfig.FORWARD_SELECTOR, true);
    }
}
