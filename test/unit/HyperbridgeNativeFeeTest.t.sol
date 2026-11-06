// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {HyperbridgeGatewayAdapterTestBase} from "@lattice-test/base/HyperbridgeGatewayAdapterTestBase.sol";
import {MockHyperbridgeNativeRouter} from "@lattice-test/mocks/MockHyperbridgeNativeRouter.sol";
import {MockIsmpHost} from "@lattice-test/mocks/MockIsmpHost.sol";
import {MockFeeToken} from "@lattice-test/unit/HyperbridgeGatewayAdapterTest.t.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {Receive} from "@lattice/Receive.sol";
import {HyperbridgeGatewayAdapter} from "@lattice/crosschain/hyperbridge/HyperbridgeGatewayAdapter.sol";
import {
    HYPERBRIDGE_GATEWAY_ADAPTER_STORAGE_SLOT
} from "@lattice/crosschain/hyperbridge/HyperbridgeGatewayAdapterLib.sol";
import {IHyperbridgeGatewayAdapter} from "@lattice/interfaces/crosschain/IHyperbridgeGatewayAdapter.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {IHyperbridgeNativeFeeRouter} from "@lattice/interfaces/external/hyperbridge/IHyperbridgeNativeFeeRouter.sol";
import {PostRequest} from "@lattice/interfaces/external/hyperbridge/IIsmpDispatcher.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

/// @notice Caller fixture that can reject a refund or attempt a nested native send while accepting it.
contract HyperbridgeNativeCaller {
    bool public rejectRefund;
    bool public reenter;
    bool public reenterERC20;
    address public adapter;
    bytes public recipient;
    bool public nestedSucceeded;
    bytes public nestedResult;

    function configure(bool reject, bool nested) external {
        rejectRefund = reject;
        reenter = nested;
        reenterERC20 = false;
    }

    function configureERC20Reentry() external {
        reenter = true;
        reenterERC20 = true;
    }

    function send(address target, bytes calldata to) external payable returns (bytes32) {
        adapter = target;
        recipient = to;
        return HyperbridgeGatewayAdapter(payable(target)).sendMessage{value: msg.value}(to, hex"01", new bytes[](0));
    }

    receive() external payable {
        require(!rejectRefund, "caller: refund rejected");
        if (reenter) {
            (nestedSucceeded, nestedResult) = adapter.call{value: reenterERC20 ? 0 : 1 wei}(
                abi.encodeCall(IERC7786GatewaySource.sendMessage, (recipient, hex"02", new bytes[](0)))
            );
        }
    }
}

/// @notice Native fee regressions through the production diamond recipe and a legacy-compatible host.
contract HyperbridgeNativeFeeTest is HyperbridgeGatewayAdapterTestBase {
    MockFeeToken internal feeToken;
    MockIsmpHost internal host;
    MockHyperbridgeNativeRouter internal router;
    address internal constant ADMIN = address(0xAD);
    address internal constant USER = address(0xB0B);
    uint256 internal constant COST = 0.02 ether;
    uint256 internal constant BUDGET = 0.05 ether;
    uint256 internal constant REMOTE = 8453;
    bytes4 internal constant REENTRANT = 0x3ee5aeb5;
    bytes internal recipient;

    function setUp() public {
        feeToken = new MockFeeToken();
        host = new MockIsmpHost(address(feeToken), 11);
        router = new MockHyperbridgeNativeRouter(COST);
        host.setNativeRouter(address(router));
        diamond = _deployHyperbridgeGatewayAdapter(ADMIN, address(host));
        adapter = HyperbridgeGatewayAdapter(payable(diamond));
        _configure();
        vm.deal(USER, 1 ether);
        vm.deal(diamond, 2 ether);
        vm.deal(address(host), 3 ether);
    }

    function _configure() internal {
        recipient = InteroperableAddress.formatEvmV1(REMOTE, address(0xCAFE));
        vm.startPrank(ADMIN);
        adapter.registerStateMachine(REMOTE);
        adapter.registerRemoteModule(REMOTE, abi.encodePacked(address(0xA11CE)));
        adapter.configureDestinationTimeout(REMOTE, 86_400);
        vm.stopPrank();
    }

    function _send() internal returns (bytes32) {
        vm.prank(USER);
        return adapter.sendMessage{value: BUDGET}(recipient, hex"01", new bytes[](0));
    }

    function _nonce() internal view returns (uint256) {
        return uint256(vm.load(diamond, bytes32(uint256(HYPERBRIDGE_GATEWAY_ADAPTER_STORAGE_SLOT) + 5)));
    }

    function _assertRolledBack() internal view {
        assertEq(_nonce(), 0, "failed native send must not consume nonce");
        assertEq(host.dispatches(), 0);
        assertEq(router.quoteCalls(), 0);
        assertEq(USER.balance, 1 ether);
        assertEq(diamond.balance, 2 ether);
        assertEq(address(host).balance, 3 ether);
        assertEq(feeToken.balanceOf(address(host)), 0);
        assertEq(feeToken.allowance(diamond, address(host)), 0);
    }

    function _invalidQuote() internal {
        vm.expectRevert(IHyperbridgeGatewayAdapter.HyperbridgeInvalidNativeQuote.selector);
        _send();
        _assertRolledBack();
    }

    function test_NativeWithRelayerFeeUsesLiveTokenAndRefundsOnlyFeeTokenOnTimeout() public {
        MockFeeToken migrated = new MockFeeToken();
        host.setFeeToken(address(migrated));
        feeToken.mint(diamond, 123);
        migrated.mint(diamond, 456);
        uint256 relayerFee = 0.001 ether;
        vm.prank(USER);
        bytes32 id = adapter.sendMessageWithFee{value: BUDGET}(recipient, hex"01", relayerFee);
        assertEq(id, keccak256(abi.encode(block.chainid, uint256(1))));
        assertEq(host.lastFee(), relayerFee);
        assertEq(host.lastPayer(), USER);
        assertEq(host.lastTimeout(), 86_400);
        assertEq(router.quotedInput(), address(0xC0FFEE));
        assertEq(router.quotedOutput(), address(migrated));
        assertEq(router.quotedFee(), 11 * host.lastBody().length + relayerFee);
        assertEq(feeToken.balanceOf(diamond), 123);
        assertEq(migrated.balanceOf(diamond), 456);
        assertEq(migrated.allowance(diamond, address(host)), 0);
        assertEq(USER.balance, 1 ether - COST);

        PostRequest memory request = PostRequest({
            source: bytes("EVM-31337"),
            dest: bytes("EVM-8453"),
            nonce: 1,
            from: abi.encodePacked(diamond),
            to: host.lastTo(),
            timeoutTimestamp: uint64(block.timestamp + 86_400),
            body: host.lastBody()
        });
        host.refundLastDispatchTimeout(diamond, request);
        assertEq(migrated.balanceOf(USER), relayerFee, "timeout returns relayer fee in feeToken");
        assertEq(migrated.balanceOf(address(host)), 11 * host.lastBody().length, "protocol fee stays paid");
        assertEq(USER.balance, 1 ether - COST, "timeout does not refund native swap cost");
        assertEq(diamond.balance, 2 ether);
    }

    function test_NativeZeroFeeSkipsMissingRouterAndRefundsWholeBudget() public {
        host.setPerByteFee(0);
        host.setNativeRouter(address(0));
        _send();
        assertEq(host.lastValue(), 0);
        assertEq(host.dispatches(), 1);
        assertEq(router.quoteCalls(), 0);
        assertEq(USER.balance, 1 ether);
        assertEq(diamond.balance, 2 ether);
        assertEq(address(host).balance, 3 ether);
    }

    function test_NativeZeroProtocolFeeStillQuotesRelayerFee() public {
        host.setPerByteFee(0);
        vm.prank(USER);
        adapter.sendMessageWithFee{value: BUDGET}(recipient, hex"01", 123);
        assertEq(router.quotedFee(), 123);
        assertEq(host.lastValue(), COST);
        assertEq(feeToken.balanceOf(address(host)), 123);
    }

    function test_NativeMessageSentRecordsCurrentBudgetAndSequentialNonce() public {
        vm.expectEmit(true, false, false, true, diamond);
        emit IERC7786GatewaySource.MessageSent(
            keccak256(abi.encode(block.chainid, uint256(1))),
            InteroperableAddress.formatEvmV1(block.chainid, USER),
            recipient,
            hex"01",
            BUDGET,
            new bytes[](0)
        );
        _send();
        assertEq(_send(), keccak256(abi.encode(block.chainid, uint256(2))));
        assertEq(_nonce(), 2);
        assertEq(host.dispatches(), 2);
        assertEq(USER.balance, 1 ether - 2 * COST);
        assertEq(diamond.balance, 2 ether);
    }

    function test_NativeMissingRouterRejects() public {
        host.setNativeRouter(address(0));
        _invalidQuote();
    }

    function test_NativeZeroFeeTokenRejectsEvenForZeroTotal() public {
        host.setFeeToken(address(0));
        host.setPerByteFee(0);
        _invalidQuote();
    }

    function test_NativeZeroWrappedTokenRejects() public {
        vm.mockCall(address(router), abi.encodeCall(IHyperbridgeNativeFeeRouter.WETH, ()), abi.encode(address(0)));
        _invalidQuote();
    }

    function test_NativeIdenticalPathTokensReject() public {
        host.setFeeToken(address(0xC0FFEE));
        _invalidQuote();
    }

    function testFuzz_NativeWrongQuoteLengthRejects(uint8 length) public {
        length = uint8(bound(length, 0, 4));
        vm.assume(length != 2);
        uint256[] memory amounts = new uint256[](length);
        vm.mockCall(
            address(router),
            abi.encodeWithSelector(IHyperbridgeNativeFeeRouter.getAmountsIn.selector),
            abi.encode(amounts)
        );
        _invalidQuote();
    }

    function test_NativeWrongOutputAmountRejects() public {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = COST;
        amounts[1] = 1;
        vm.mockCall(
            address(router),
            abi.encodeWithSelector(IHyperbridgeNativeFeeRouter.getAmountsIn.selector),
            abi.encode(amounts)
        );
        _invalidQuote();
    }

    function test_NativeZeroInputForPositiveFeeRejects() public {
        router.setCosts(0, 0);
        _invalidQuote();
    }

    function test_NativeMalformedQuoteRevertsAndRollsBack() public {
        vm.mockCall(address(router), abi.encodeWithSelector(IHyperbridgeNativeFeeRouter.getAmountsIn.selector), hex"01");
        vm.expectRevert();
        _send();
        _assertRolledBack();
    }

    function test_NativeQuoteRevertBubblesAndRollsBack() public {
        bytes memory reason = abi.encodeWithSignature("Error(string)", "router: no route");
        vm.mockCallRevert(
            address(router), abi.encodeWithSelector(IHyperbridgeNativeFeeRouter.getAmountsIn.selector), reason
        );
        vm.expectRevert(reason);
        _send();
        _assertRolledBack();
    }

    function test_NativeHostRetainedRouterSurplusRejectsAndCanRetrySameNonce() public {
        router.setCosts(COST, COST - 1 wei);
        vm.expectRevert(
            abi.encodeWithSelector(
                IHyperbridgeGatewayAdapter.HyperbridgeHostNativeBalanceChanged.selector, 3 ether, 3 ether + 1 wei
            )
        );
        _send();
        _assertRolledBack();
        router.setCosts(COST, COST);
        assertEq(_send(), keccak256(abi.encode(block.chainid, uint256(1))));
    }

    function test_NativeSnapshotPrecedesQuoteExternalWork() public {
        vm.deal(address(router), 1 ether);
        router.setQuoteDonation(address(host), 1 wei);
        vm.expectRevert(
            abi.encodeWithSelector(
                IHyperbridgeGatewayAdapter.HyperbridgeHostNativeBalanceChanged.selector, 3 ether, 3 ether + 1 wei
            )
        );
        _send();
        _assertRolledBack();
        assertEq(address(router).balance, 1 ether, "quote-time donation rolls back");
    }

    function test_NativeHostStandingBalanceDecreaseRejects() public {
        host.setDispatchNativePayout(1 wei);
        vm.expectRevert(
            abi.encodeWithSelector(
                IHyperbridgeGatewayAdapter.HyperbridgeHostNativeBalanceChanged.selector, 3 ether, 3 ether - 1 wei
            )
        );
        _send();
        _assertRolledBack();
    }

    function test_NativeDirectAdapterRefundSweepsOnlyDelta() public {
        // Defensive nonstandard-host case: opt into Receive without expanding the canonical recipe.
        (FacetCut[] memory original, address init, bytes memory data) = deployer.buildCuts(ADMIN, address(host));
        FacetCut[] memory cuts = new FacetCut[](original.length + 1);
        for (uint256 i; i < original.length; ++i) {
            cuts[i] = original[i];
        }
        bytes4[] memory zero = new bytes4[](1);
        cuts[original.length] = FacetCut(address(new Receive()), FacetCutAction.Add, zero);
        Lattice proxy = new Lattice();
        proxy.initialize(cuts, init, data);
        diamond = address(proxy);
        adapter = HyperbridgeGatewayAdapter(payable(diamond));
        _configure();
        vm.deal(diamond, 2 ether);
        router.setCosts(COST, COST - 1 wei);
        host.setForwardNativeSurplus(true);
        _send();
        assertEq(USER.balance, 1 ether - COST + 1 wei, "includes refund returned to adapter");
        assertEq(diamond.balance, 2 ether, "standing native balance is untouched");
        assertEq(address(host).balance, 3 ether);
    }

    function test_NativeRouterReentryBlockedBeforeNestedQuote() public {
        vm.deal(address(router), 1 ether);
        router.setQuoteHook(
            diamond, abi.encodeCall(IERC7786GatewaySource.sendMessage, (recipient, hex"02", new bytes[](0))), 1 wei
        );
        _send();
        assertFalse(router.hookSucceeded());
        assertEq(router.hookResult(), abi.encodeWithSelector(REENTRANT));
        assertEq(_nonce(), 1);
        assertEq(router.quoteCalls(), 1);
        assertEq(address(router).balance, 1 ether + COST);
    }

    function test_NativeRouterSwapReentryBlockedDuringHostDispatch() public {
        vm.deal(address(router), 1 ether);
        router.setSwapHook(
            diamond, abi.encodeCall(IERC7786GatewaySource.sendMessage, (recipient, hex"02", new bytes[](0))), 1 wei
        );
        _send();
        assertFalse(router.hookSucceeded());
        assertEq(router.hookResult(), abi.encodeWithSelector(REENTRANT));
        assertEq(_nonce(), 1);
        assertEq(host.dispatches(), 1);
        assertEq(router.quoteCalls(), 1);
    }

    function test_NativeQuoteAllowsSeparatelyFundedERC20SendWithoutSpendingNative() public {
        uint256 tokenFunds = 1 ether;
        uint256 nestedRelayerFee = 17;
        feeToken.mint(address(router), tokenFunds);
        vm.prank(address(router));
        feeToken.approve(diamond, type(uint256).max);
        vm.deal(address(router), 4 ether);
        router.setQuoteHook(
            diamond,
            abi.encodeCall(IHyperbridgeGatewayAdapter.sendMessageWithFee, (recipient, hex"02", nestedRelayerFee)),
            0
        );
        bytes32 outerId = _send();
        bytes32 nestedId = abi.decode(router.hookResult(), (bytes32));
        assertTrue(router.hookSucceeded(), "existing ERC20 path remains callable");
        assertEq(outerId, keccak256(abi.encode(block.chainid, uint256(1))));
        assertEq(nestedId, keccak256(abi.encode(block.chainid, uint256(2))));
        assertNotEq(outerId, nestedId);
        uint256 nestedCost = 11
            * abi.encode(
                InteroperableAddress.formatEvmV1(block.chainid, address(router)), recipient, hex"02", uint256(2)
            )
            .length + nestedRelayerFee;
        assertEq(feeToken.balanceOf(address(router)), tokenFunds - nestedCost);
        assertEq(feeToken.balanceOf(address(host)), nestedCost + router.quotedFee(), "both sends pay fees");
        assertEq(feeToken.balanceOf(diamond), 0);
        assertEq(feeToken.allowance(diamond, address(host)), 0);
        assertEq(_nonce(), 2);
        assertEq(host.dispatches(), 2);
        assertEq(router.quoteCalls(), 1);
        assertEq(USER.balance, 1 ether - COST);
        assertEq(diamond.balance, 2 ether);
        assertEq(address(host).balance, 3 ether);
        assertEq(address(router).balance, 4 ether + COST, "nested ERC20 send spends no native");
    }

    function test_NativeRefundAllowsSeparatelyFundedERC20SendWithoutSpendingNative() public {
        HyperbridgeNativeCaller caller = new HyperbridgeNativeCaller();
        caller.configureERC20Reentry();
        uint256 tokenFunds = 1 ether;
        feeToken.mint(address(caller), tokenFunds);
        vm.prank(address(caller));
        feeToken.approve(diamond, type(uint256).max);
        vm.deal(address(caller), 4 ether);
        vm.deal(address(this), BUDGET);
        bytes32 outerId = caller.send{value: BUDGET}(diamond, recipient);
        assertTrue(caller.nestedSucceeded(), "existing ERC20 path remains callable");
        bytes32 nestedId = abi.decode(caller.nestedResult(), (bytes32));
        assertEq(outerId, keccak256(abi.encode(block.chainid, uint256(1))));
        assertEq(nestedId, keccak256(abi.encode(block.chainid, uint256(2))));
        assertNotEq(outerId, nestedId);
        uint256 nestedCost = 11
            * abi.encode(
                InteroperableAddress.formatEvmV1(block.chainid, address(caller)), recipient, hex"02", uint256(2)
            )
            .length;
        assertEq(feeToken.balanceOf(address(caller)), tokenFunds - nestedCost);
        assertEq(feeToken.balanceOf(address(host)), nestedCost + router.quotedFee(), "both sends pay fees");
        assertEq(feeToken.balanceOf(diamond), 0);
        assertEq(feeToken.allowance(diamond, address(host)), 0);
        assertEq(_nonce(), 2);
        assertEq(host.dispatches(), 2);
        assertEq(router.quoteCalls(), 1);
        assertEq(address(caller).balance, 4 ether + BUDGET - COST);
        assertEq(diamond.balance, 2 ether);
        assertEq(address(host).balance, 3 ether);
    }

    function test_NativeRefundReentryBlockedAndCallerKeepsRefund() public {
        HyperbridgeNativeCaller caller = new HyperbridgeNativeCaller();
        caller.configure(false, true);
        vm.deal(address(this), BUDGET);
        caller.send{value: BUDGET}(diamond, recipient);
        assertFalse(caller.nestedSucceeded());
        assertEq(caller.nestedResult(), abi.encodeWithSelector(REENTRANT));
        assertEq(address(caller).balance, BUDGET - COST);
        assertEq(_nonce(), 1);
        assertEq(host.lastPayer(), address(caller));
        assertEq(diamond.balance, 2 ether);
    }

    function test_NativeRejectingRefundRevertsAllDispatchEffects() public {
        HyperbridgeNativeCaller caller = new HyperbridgeNativeCaller();
        caller.configure(true, false);
        vm.deal(address(this), BUDGET);
        vm.expectRevert(IHyperbridgeGatewayAdapter.HyperbridgeNativeRefundFailed.selector);
        caller.send{value: BUDGET}(diamond, recipient);
        _assertRolledBack();
        assertEq(address(this).balance, BUDGET);
        assertEq(address(caller).balance, 0);
        assertEq(address(router).balance, 0);
    }

    function test_NativeExactBudgetNeedsNoRefundAcceptance() public {
        HyperbridgeNativeCaller caller = new HyperbridgeNativeCaller();
        caller.configure(true, false);
        vm.deal(address(this), COST);
        caller.send{value: COST}(diamond, recipient);
        assertEq(host.dispatches(), 1);
        assertEq(_nonce(), 1);
        assertEq(diamond.balance, 2 ether);
    }

    function test_NativeReentryUsesTransientGuardOnMainnet() public {
        vm.chainId(1);
        test_NativeRouterReentryBlockedBeforeNestedQuote();
    }

    function testFuzz_NativeOnlyCurrentBudgetRefunded(uint96 quote, uint96 extra, uint96 prefund) public {
        uint256 cost = bound(uint256(quote), 1, 1 ether);
        uint256 budget = cost + bound(uint256(extra), 0, 1 ether);
        uint256 standing = bound(uint256(prefund), 0, 100 ether);
        router.setCosts(cost, cost);
        vm.deal(USER, budget + 5 ether);
        vm.deal(diamond, standing);
        vm.prank(USER);
        adapter.sendMessageWithFee{value: budget}(recipient, hex"01", 123);
        assertEq(USER.balance, budget + 5 ether - cost);
        assertEq(diamond.balance, standing);
        assertEq(address(host).balance, 3 ether);
        assertEq(host.lastValue(), cost);
        assertEq(host.lastPayer(), USER);
        assertEq(_nonce(), 1);
        assertEq(feeToken.allowance(diamond, address(host)), 0);
    }

    function testFuzz_NativeInsufficientBudgetCannotSpendPrefunds(uint96 quote, uint96 prefund) public {
        uint256 cost = bound(uint256(quote), 2, 1 ether);
        uint256 budget = cost - 1;
        uint256 standing = bound(uint256(prefund), 0, 100 ether);
        router.setCosts(cost, cost);
        vm.deal(diamond, standing);
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(IHyperbridgeGatewayAdapter.HyperbridgeInsufficientNativeFee.selector, cost, budget)
        );
        adapter.sendMessageWithFee{value: budget}(recipient, hex"01", 123);
        assertEq(USER.balance, 1 ether);
        assertEq(diamond.balance, standing);
        assertEq(_nonce(), 0);
        assertEq(host.dispatches(), 0);
        assertEq(router.quoteCalls(), 0);
    }
}
