// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployStargateBusBridgeAdapter} from "@lattice-script/base/crosschain/DeployStargateBusBridgeAdapter.s.sol";
import {StargateBusBridgeAdapterTestBase} from "@lattice-test/base/StargateBusBridgeAdapterTestBase.sol";
import {MockStargateBusPool} from "@lattice-test/mocks/MockStargateBusPool.sol";
import {MockStargateBusToken} from "@lattice-test/mocks/MockStargateBusToken.sol";
import {MockReentrantToken, MockToken} from "@lattice-test/unit/StargateBridgeAdapterTest.t.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {StargateBridgeAdapter} from "@lattice/crosschain/layerzero/StargateBridgeAdapter.sol";
import {StargateBusBridgeAdapter} from "@lattice/crosschain/layerzero/StargateBusBridgeAdapter.sol";
import {StargateBusBridgeAdapterInit} from "@lattice/crosschain/layerzero/StargateBusBridgeAdapterInit.sol";
import {ERC165_MAP_ISTARGATEBUSBRIDGEADAPTER_SLOT} from "@lattice/crosschain/layerzero/StargateBusBridgeAdapterLib.sol";
import {NonEvmAddress} from "@lattice/crosschain/libraries/NonEvmAddress.sol";
import {AdapterBaseLib} from "@lattice/defi/libraries/AdapterBaseLib.sol";
import {IBridgeFungible} from "@lattice/interfaces/crosschain/IBridgeFungible.sol";
import {IStargateBridgeAdapter} from "@lattice/interfaces/crosschain/IStargateBridgeAdapter.sol";
import {IStargateBusBridgeAdapter} from "@lattice/interfaces/crosschain/IStargateBusBridgeAdapter.sol";
import {MessagingReceipt} from "@lattice/interfaces/external/layerzero/ILayerZeroEndpointV2.sol";
import {IAccessControlDiamondCut} from "@lattice/interfaces/governance/IAccessControlDiamondCut.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {ReinitMultiInit} from "@lattice/utils/ReinitMultiInit.sol";
import {NotInitializing} from "@lattice/utils/libraries/InitializableLib.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

contract StargateBusBridgeAdapterTest is StargateBusBridgeAdapterTestBase {
    address constant ADMIN = address(0xad);
    address constant USER = address(0xbeef);
    address constant RECIPIENT = address(0xcafe);
    uint256 constant CHAIN = 8453;
    uint32 constant EID = 30184;
    uint256 constant FARE = 0.002 ether;
    uint256 constant AMOUNT = 1 ether;
    uint256 constant POOL_FEE = 0.001 ether;
    address diamond;
    MockToken token;
    MockStargateBusPool pool;
    StargateBusBridgeAdapter bus;
    StargateBridgeAdapter taxi;

    function setUp() public {
        token = new MockToken();
        pool = new MockStargateBusPool(address(token));
        pool.setNativeFee(0.01 ether);
        pool.setPoolFee(POOL_FEE);
        diamond = _deployStargateBusBridgeAdapter(ADMIN);
        bus = StargateBusBridgeAdapter(diamond);
        taxi = StargateBridgeAdapter(diamond);
        vm.startPrank(ADMIN);
        taxi.registerPool(address(token), address(pool));
        taxi.registerStargateEid(CHAIN, EID);
        vm.stopPrank();
        vm.deal(USER, 100 ether);
    }

    function _params() internal view returns (IStargateBridgeAdapter.SendTokenParams memory) {
        return IStargateBridgeAdapter.SendTokenParams(
            InteroperableAddress.formatEvmV1(CHAIN, RECIPIENT), address(token), AMOUNT, 0.99 ether, CHAIN
        );
    }

    function _fund(uint256 amount) internal {
        token.mint(USER, amount);
        vm.prank(USER);
        token.approve(diamond, amount);
    }

    function test_BusQuoteHasItsOwnProxyRoute() public view {
        assertEq(bus.quoteBusFee(_params()), FARE);
        assertEq(taxi.quoteSendFee(_params()), 0.01 ether, "taxi fee/mode stays separate");
    }

    function test_EnqueueReturnsValidZeroTicketAndOpaquePassenger() public {
        _fund(AMOUNT);
        bytes memory expected = abi.encode(uint72(0), bytes32(uint256(uint160(RECIPIENT))), AMOUNT - POOL_FEE);
        vm.expectEmit(true, true, true, true, diamond);
        emit IStargateBusBridgeAdapter.StargateBusQueued(
            USER, address(token), CHAIN, 0, expected, AMOUNT, AMOUNT - POOL_FEE, bytes32(uint256(uint160(RECIPIENT)))
        );
        vm.prank(USER);
        (uint72 id, bytes memory data, uint256 sent, uint256 received) = bus.sendTokenBus{value: FARE}(_params());
        assertEq(id, 0, "zero is the first valid ticket");
        assertEq(data, expected);
        assertEq(sent, AMOUNT);
        assertEq(received, AMOUNT - POOL_FEE);
        assertEq(pool.nextTicket(EID), 1);
        assertEq(pool.nextTicketToDrive(EID), 0, "queued only, no dispatch");
        assertEq(pool.nonce(), 0, "no messaging nonce at enqueue");
        assertEq(pool.lastOftCmd(), hex"00");
        assertEq(pool.lastExtraOptions(), "");
        assertEq(pool.lastComposeMsg(), "");
        assertEq(pool.lastRefundAddress(), USER);
        assertEq(pool.lastNativeFee(), FARE);
        assertEq(pool.lastLzTokenFee(), 0);
        assertEq(pool.allowanceSeen(), AMOUNT);
        assertEq(token.allowance(diamond, address(pool)), 0);
    }

    function _feeMismatch(uint256 value) internal {
        _fund(AMOUNT);
        vm.mockCallRevert(
            address(token), abi.encodeWithSelector(IERC20.transferFrom.selector, USER, diamond, AMOUNT), hex"deadbeef"
        );
        vm.expectRevert(abi.encodeWithSelector(IStargateBusBridgeAdapter.StargateBusFeeMismatch.selector, FARE, value));
        vm.prank(USER);
        bus.sendTokenBus{value: value}(_params());
        assertEq(pool.calls(), 0);
        assertEq(token.balanceOf(USER), AMOUNT);
        assertEq(token.balanceOf(diamond), 0);
    }

    function test_UnderpaymentRejectsBeforeTokenPull() public {
        _feeMismatch(FARE - 1);
    }

    function test_OverpaymentRejectsBeforeTokenPull() public {
        _feeMismatch(FARE + 1);
    }

    function test_ExactFeeReachesPullSentinel() public {
        _fund(AMOUNT);
        vm.mockCallRevert(
            address(token), abi.encodeWithSelector(IERC20.transferFrom.selector, USER, diamond, AMOUNT), hex"deadbeef"
        );
        vm.expectRevert(abi.encodeWithSelector(IBridgeFungible.BridgeTransferFailed.selector, address(token)));
        vm.prank(USER);
        bus.sendTokenBus{value: FARE}(_params());
    }

    function test_SeparateDriveRequiresQueuedPrefixAndCreatesGuidLater() public {
        _fund(2 * AMOUNT);
        vm.prank(USER);
        (uint72 first, bytes memory a,,) = bus.sendTokenBus{value: FARE}(_params());
        vm.prank(USER);
        (uint72 second, bytes memory b,,) = bus.sendTokenBus{value: FARE}(_params());
        assertEq(first, 0);
        assertEq(second, 1);
        assertEq(pool.nextTicketToDrive(EID), 0, "no fabricated dispatch progress");
        vm.expectRevert(MockStargateBusPool.MockBusPrefix.selector);
        pool.quoteDriveBus(EID, b);
        bytes memory prefix = bytes.concat(a, b);
        uint256 fee = pool.quoteDriveBus(EID, prefix).nativeFee;
        vm.prank(USER);
        MessagingReceipt memory receipt = pool.driveBus{value: fee}(EID, prefix);
        assertTrue(receipt.guid != bytes32(0), "only drive gets a GUID");
        assertEq(receipt.nonce, 1);
        assertEq(pool.nextTicketToDrive(EID), 2);
        vm.expectRevert(MockStargateBusPool.MockBusPrefix.selector);
        pool.quoteDriveBus(EID, prefix);
    }

    function _unexpectedReceipt(uint8 kind) internal {
        _fund(AMOUNT);
        pool.setReceiptFailure(kind);
        if (kind <= 3) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IStargateBusBridgeAdapter.StargateBusUnexpectedReceipt.selector,
                    kind == 1 ? bytes32(uint256(1)) : bytes32(0),
                    kind == 2 ? uint64(1) : uint64(0),
                    kind == 3 ? uint256(0) : uint256(96)
                )
            );
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IStargateBusBridgeAdapter.StargateBusUnexpectedFare.selector,
                    FARE,
                    kind == 4 ? FARE - 1 : FARE,
                    kind == 5 ? uint256(1) : uint256(0)
                )
            );
        }
        vm.prank(USER);
        bus.sendTokenBus{value: FARE}(_params());
        _assertRollback();
        pool.setReceiptFailure(0);
        vm.prank(USER);
        (uint72 id,,,) = bus.sendTokenBus{value: FARE}(_params());
        assertEq(id, 0, "failed enqueue and guard rolled back");
    }

    function _assertRollback() internal view {
        assertEq(token.balanceOf(USER), AMOUNT);
        assertEq(token.balanceOf(diamond), 0);
        assertEq(token.balanceOf(address(pool)), 0);
        assertEq(token.allowance(diamond, address(pool)), 0);
        assertEq(pool.calls(), 0);
        assertEq(pool.nextTicket(EID), 0);
        assertEq(diamond.balance, 0);
    }

    function test_NonzeroGuidRejectsAndRollsBack() public {
        _unexpectedReceipt(1);
    }

    function test_NonzeroNonceRejectsAndRollsBack() public {
        _unexpectedReceipt(2);
    }

    function test_EmptyPassengerRejectsAndRollsBack() public {
        _unexpectedReceipt(3);
    }

    function test_ChangedFareRejectsAndRollsBack() public {
        _unexpectedReceipt(4);
    }

    function test_LzTokenFareRejectsAndRollsBack() public {
        _unexpectedReceipt(5);
    }

    function test_PoolFailureRollsBackAndGuardCanRetry() public {
        _fund(AMOUNT);
        pool.setFailAfterPull(true);
        vm.expectRevert(MockStargateBusPool.MockBusFailure.selector);
        vm.prank(USER);
        bus.sendTokenBus{value: FARE}(_params());
        _assertRollback();
        pool.setFailAfterPull(false);
        vm.prank(USER);
        bus.sendTokenBus{value: FARE}(_params());
        assertEq(pool.nextTicket(EID), 1);
    }

    function test_QueueFullLeavesThirdCallerFundsUntouched() public {
        pool.setMaxQueued(1);
        _fund(2 * AMOUNT);
        vm.prank(USER);
        bus.sendTokenBus{value: FARE}(_params());
        vm.expectRevert(MockStargateBusPool.MockBusFull.selector);
        vm.prank(USER);
        bus.sendTokenBus{value: FARE}(_params());
        assertEq(token.balanceOf(USER), AMOUNT);
        assertEq(pool.nextTicket(EID), 1);
        assertEq(pool.calls(), 1);
        assertEq(token.allowance(diamond, address(pool)), 0);
    }

    function test_SlippageFailureRollsBackEverything() public {
        _fund(AMOUNT);
        IStargateBridgeAdapter.SendTokenParams memory p = _params();
        p.minAmountLD = AMOUNT;
        vm.expectRevert(MockStargateBusPool.MockBusSlippage.selector);
        vm.prank(USER);
        bus.sendTokenBus{value: FARE}(p);
        _assertRollback();
    }

    function test_PrefundsSurviveDustSweep() public {
        token.mint(diamond, 5 ether);
        vm.deal(diamond, 3 ether);
        IStargateBridgeAdapter.SendTokenParams memory p = _params();
        p.amountLD += 999;
        _fund(p.amountLD);
        vm.prank(USER);
        bus.sendTokenBus{value: FARE}(p);
        assertEq(token.balanceOf(USER), 999);
        assertEq(token.balanceOf(diamond), 5 ether);
        assertEq(diamond.balance, 3 ether);
        assertEq(token.allowance(diamond, address(pool)), 0);
    }

    function test_NoPullSweepsOnlyCallerDelta() public {
        token.mint(diamond, 5 ether);
        pool.setPullFunds(false);
        _fund(AMOUNT);
        vm.prank(USER);
        bus.sendTokenBus{value: FARE}(_params());
        assertEq(token.balanceOf(USER), AMOUNT);
        assertEq(token.balanceOf(diamond), 5 ether);
        assertEq(token.allowance(diamond, address(pool)), 0);
    }

    function test_PoolCannotReenterTaxiFromBus() public {
        pool.setCallback(diamond, abi.encodeCall(IStargateBridgeAdapter.sendToken, (_params())));
        _fund(AMOUNT);
        vm.prank(USER);
        bus.sendTokenBus{value: FARE}(_params());
        assertTrue(pool.sawGuard());
        assertEq(pool.calls(), 1);
    }

    function test_TokenCannotReenterBusFromTaxi() public {
        MockReentrantToken evil = new MockReentrantToken();
        MockStargateBusPool other = new MockStargateBusPool(address(evil));
        other.setNativeFee(0.01 ether);
        vm.prank(ADMIN);
        taxi.registerPool(address(evil), address(other));
        IStargateBridgeAdapter.SendTokenParams memory p = _params();
        p.token = address(evil);
        evil.setReenter(diamond, abi.encodeCall(IStargateBusBridgeAdapter.sendTokenBus, (p)));
        evil.mint(USER, AMOUNT);
        vm.prank(USER);
        evil.approve(diamond, AMOUNT);
        vm.prank(USER);
        taxi.sendToken{value: 0.01 ether}(p);
        assertTrue(evil.sawGuardRevert());
    }

    function test_InitializerRequiresWindow() public {
        StargateBusBridgeAdapterInit init = new StargateBusBridgeAdapterInit();
        vm.expectRevert(NotInitializing.selector);
        init.init();
    }

    function test_InterfaceAndMapSlotAndOldIdStayExact() public view {
        bytes4 id = type(IStargateBusBridgeAdapter).interfaceId;
        assertEq(id, bytes4(0x93e4e11a));
        assertEq(type(IStargateBridgeAdapter).interfaceId, bytes4(0x199fc6b0));
        assertTrue(ERC165Facet(diamond).supportsInterface(id));
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IStargateBridgeAdapter).interfaceId));
        assertEq(
            ERC165_MAP_ISTARGATEBUSBRIDGEADAPTER_SLOT,
            keccak256(abi.encode(id, bytes32(0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200)))
        );
    }

    function _alternateToken(uint8 mode)
        internal
        returns (
            MockStargateBusToken asset,
            MockStargateBusPool target,
            IStargateBridgeAdapter.SendTokenParams memory p
        )
    {
        asset = new MockStargateBusToken();
        target = new MockStargateBusPool(address(asset));
        vm.prank(ADMIN);
        taxi.registerPool(address(asset), address(target));
        asset.mint(USER, AMOUNT + 999);
        vm.prank(USER);
        asset.approve(diamond, AMOUNT + 999);
        asset.setMode(mode);
        p = _params();
        p.token = address(asset);
        p.amountLD = AMOUNT + 999;
    }

    function test_NoReturnTokenPullApprovalAndDustWork() public {
        (MockStargateBusToken asset, MockStargateBusPool target, IStargateBridgeAdapter.SendTokenParams memory p) =
            _alternateToken(1);
        vm.prank(USER);
        bus.sendTokenBus{value: FARE}(p);
        assertEq(asset.balanceOf(USER), 999);
        assertEq(asset.balanceOf(diamond), 0);
        assertEq(asset.balanceOf(address(target)), AMOUNT);
        assertEq(asset.allowance(diamond, address(target)), 0);
    }

    function test_FalsePullRejectsAndRollsBack() public {
        (MockStargateBusToken asset, MockStargateBusPool target, IStargateBridgeAdapter.SendTokenParams memory p) =
            _alternateToken(2);
        vm.expectRevert(abi.encodeWithSelector(IBridgeFungible.BridgeTransferFailed.selector, address(asset)));
        vm.prank(USER);
        bus.sendTokenBus{value: FARE}(p);
        assertEq(asset.balanceOf(USER), p.amountLD);
        assertEq(asset.balanceOf(diamond), 0);
        assertEq(target.calls(), 0);
    }

    function test_FeeOnTransferPullRejectsExactDelta() public {
        (MockStargateBusToken asset, MockStargateBusPool target, IStargateBridgeAdapter.SendTokenParams memory p) =
            _alternateToken(3);
        vm.expectRevert(
            abi.encodeWithSelector(IBridgeFungible.BridgeAmountMismatch.selector, p.amountLD, p.amountLD - 1)
        );
        vm.prank(USER);
        bus.sendTokenBus{value: FARE}(p);
        assertEq(asset.balanceOf(USER), p.amountLD);
        assertEq(asset.balanceOf(diamond), 0);
        assertEq(target.calls(), 0);
    }

    function test_FalseApprovalRollsBackPull() public {
        (MockStargateBusToken asset, MockStargateBusPool target, IStargateBridgeAdapter.SendTokenParams memory p) =
            _alternateToken(4);
        vm.expectRevert(abi.encodeWithSelector(AdapterBaseLib.AdapterSafeERC20FailedOperation.selector, address(asset)));
        vm.prank(USER);
        bus.sendTokenBus{value: FARE}(p);
        assertEq(asset.balanceOf(USER), p.amountLD);
        assertEq(asset.balanceOf(diamond), 0);
        assertEq(asset.allowance(diamond, address(target)), 0);
        assertEq(target.calls(), 0);
    }

    function test_FailedDustTransferRollsBackQueueAndAllFunds() public {
        (MockStargateBusToken asset, MockStargateBusPool target, IStargateBridgeAdapter.SendTokenParams memory p) =
            _alternateToken(5);
        asset.mint(diamond, 5 ether);
        vm.expectRevert(abi.encodeWithSelector(AdapterBaseLib.AdapterSafeERC20FailedOperation.selector, address(asset)));
        vm.prank(USER);
        bus.sendTokenBus{value: FARE}(p);
        assertEq(asset.balanceOf(USER), p.amountLD);
        assertEq(asset.balanceOf(diamond), 5 ether);
        assertEq(asset.balanceOf(address(target)), 0);
        assertEq(asset.allowance(diamond, address(target)), 0);
        assertEq(target.nextTicket(EID), 0);
    }

    function _bothReject(IStargateBridgeAdapter.SendTokenParams memory p, bytes memory reason) internal {
        vm.expectRevert(reason);
        bus.quoteBusFee(p);
        vm.expectRevert(reason);
        vm.prank(USER);
        bus.sendTokenBus{value: FARE}(p);
        assertEq(pool.calls(), 0);
    }

    function test_QuoteAndSendRejectZeroAmount() public {
        IStargateBridgeAdapter.SendTokenParams memory p = _params();
        p.amountLD = 0;
        _bothReject(p, abi.encodeWithSelector(IStargateBridgeAdapter.StargateZeroAmount.selector));
    }

    function test_QuoteAndSendRejectZeroSlippageFloor() public {
        IStargateBridgeAdapter.SendTokenParams memory p = _params();
        p.minAmountLD = 0;
        _bothReject(p, abi.encodeWithSelector(IStargateBridgeAdapter.StargateZeroMinAmount.selector));
    }

    function test_QuoteAndSendRejectUnregisteredToken() public {
        IStargateBridgeAdapter.SendTokenParams memory p = _params();
        p.token = address(0x1234);
        _bothReject(p, abi.encodeWithSelector(IStargateBridgeAdapter.StargateTokenNotRegistered.selector, p.token));
    }

    function test_QuoteAndSendRejectUnregisteredChain() public {
        IStargateBridgeAdapter.SendTokenParams memory p = _params();
        p.destinationChainId = 10;
        _bothReject(
            p, abi.encodeWithSelector(IStargateBridgeAdapter.StargateUnknownDestinationChain.selector, uint256(10))
        );
    }

    function test_QuoteAndSendRejectSameChain() public {
        IStargateBridgeAdapter.SendTokenParams memory p = _params();
        p.destinationChainId = block.chainid;
        _bothReject(p, abi.encodeWithSelector(IStargateBridgeAdapter.StargateSameChain.selector, block.chainid));
    }

    function test_QuoteAndSendRejectDestinationMismatch() public {
        IStargateBridgeAdapter.SendTokenParams memory p = _params();
        p.recipient = InteroperableAddress.formatEvmV1(10, RECIPIENT);
        _bothReject(
            p, abi.encodeWithSelector(IStargateBridgeAdapter.StargateDestinationMismatch.selector, uint256(10), CHAIN)
        );
    }

    function test_QuoteAndSendRejectMissingRecipient() public {
        IStargateBridgeAdapter.SendTokenParams memory p = _params();
        p.recipient = InteroperableAddress.formatEvmV1(CHAIN);
        _bothReject(p, abi.encodeWithSelector(NonEvmAddress.NonEvmAddressEmpty.selector));
    }

    function test_UnsupportedBusRouteRejectsBeforePull() public {
        pool.setBusEnabled(false);
        _bothReject(_params(), abi.encodeWithSelector(MockStargateBusPool.MockBusUnavailable.selector));
    }

    function test_OriginalTaxiRecipeKeepsFiveCutsAndNoBusClaim() public {
        address old = _deployStargateBridgeAdapter(ADMIN);
        (FacetCut[] memory cuts,,) = deployer.buildCuts(ADMIN);
        assertEq(cuts.length, 5);
        assertTrue(ERC165Facet(old).supportsInterface(type(IStargateBridgeAdapter).interfaceId));
        assertFalse(ERC165Facet(old).supportsInterface(type(IStargateBusBridgeAdapter).interfaceId));
        assertEq(
            new StargateBridgeAdapter().exportSelectors(), hex"988b1fa7248b67b07286e5e5b18dcea7396e0d4c67a67974385ce1dd"
        );
        vm.expectRevert(
            abi.encodeWithSignature("FunctionDoesNotExist(bytes4)", IStargateBusBridgeAdapter.quoteBusFee.selector)
        );
        StargateBusBridgeAdapter(old).quoteBusFee(_params());
    }

    function test_ExistingConfiguredTaxiUpgradesThroughGuardedReinit() public {
        address old = _deployStargateBridgeAdapter(ADMIN);
        vm.startPrank(ADMIN);
        StargateBridgeAdapter(old).registerPool(address(token), address(pool));
        StargateBridgeAdapter(old).registerStargateEid(CHAIN, EID);
        vm.stopPrank();
        (FacetCut[] memory built,,) = new DeployStargateBusBridgeAdapter().buildCuts(ADMIN);
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = built[3];
        StargateBusBridgeAdapterInit registration = new StargateBusBridgeAdapterInit();
        vm.expectRevert(NotInitializing.selector);
        vm.prank(ADMIN);
        IAccessControlDiamondCut(old)
            .diamondCut(cuts, address(registration), abi.encodeCall(StargateBusBridgeAdapterInit.init, ()));
        assertEq(
            IDiamondLoupe(old).facetAddress(IStargateBusBridgeAdapter.sendTokenBus.selector),
            address(0),
            "failed unguarded init rolls cut back"
        );
        address[] memory inits = new address[](1);
        inits[0] = address(registration);
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(StargateBusBridgeAdapterInit.init, ());
        ReinitMultiInit batch = new ReinitMultiInit();
        vm.prank(ADMIN);
        IAccessControlDiamondCut(old)
            .diamondCut(cuts, address(batch), abi.encodeCall(ReinitMultiInit.reinitMulti, (uint64(2), inits, calls)));
        assertTrue(ERC165Facet(old).supportsInterface(type(IStargateBusBridgeAdapter).interfaceId));
        assertTrue(ERC165Facet(old).supportsInterface(type(IStargateBridgeAdapter).interfaceId));
        assertTrue(AccessControl(old).hasRole(bytes32(0), ADMIN));
        assertFalse(AccessControl(old).hasRole(bytes32(0), USER));
        assertEq(StargateBridgeAdapter(old).poolOf(address(token)), address(pool));
        assertEq(StargateBridgeAdapter(old).stargateEidOf(CHAIN), EID);
        token.mint(USER, AMOUNT);
        vm.prank(USER);
        token.approve(old, AMOUNT);
        vm.prank(USER);
        (uint72 id,,,) = StargateBusBridgeAdapter(old).sendTokenBus{value: FARE}(_params());
        assertEq(id, 0);
    }

    function testFuzz_DustAndPrefundConservation(uint96 amount, uint96 preexisting) public {
        uint256 value = bound(uint256(amount), 0.01 ether, type(uint96).max);
        token.mint(diamond, preexisting);
        IStargateBridgeAdapter.SendTokenParams memory p = _params();
        p.amountLD = value;
        p.minAmountLD = 1;
        _fund(value);
        vm.prank(USER);
        (,, uint256 sent,) = bus.sendTokenBus{value: FARE}(p);
        assertEq(sent, value - value % 1e12);
        assertEq(token.balanceOf(USER), value % 1e12);
        assertEq(token.balanceOf(diamond), preexisting);
        assertEq(token.allowance(diamond, address(pool)), 0);
    }
}
