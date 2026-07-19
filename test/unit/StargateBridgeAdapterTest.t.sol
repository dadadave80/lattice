// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {StargateBridgeAdapterTestBase} from "@lattice-test/base/StargateBridgeAdapterTestBase.sol";
import {MockStargatePool} from "@lattice-test/mocks/MockStargatePool.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {StargateBridgeAdapter} from "@lattice/crosschain/layerzero/StargateBridgeAdapter.sol";
import {StargateBridgeAdapterInit} from "@lattice/crosschain/layerzero/StargateBridgeAdapterInit.sol";
import {NonEvmAddress} from "@lattice/crosschain/libraries/NonEvmAddress.sol";
import {IStargateBridgeAdapter} from "@lattice/interfaces/crosschain/IStargateBridgeAdapter.sol";
import {IReentrancyGuard} from "@lattice/interfaces/security/IReentrancyGuard.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {NotInitializing} from "@lattice/utils/libraries/InitializableLib.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

/// @notice Minimal ERC-20 (mint/approve/transfer/transferFrom) used as the pooled Stargate token.
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

/// @notice Reentrancy attacker: a pooled token whose `transferFrom` re-enters `sendToken` on the diamond
///         mid-pull, REQUIRES the re-enter to revert with exactly {ReentrancyGuardReentrantCall} (recorded in
///         `sawGuardRevert`), then completes the transfer normally so the outer send succeeds.
contract MockReentrantToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public diamond;
    bytes public reenterData;
    bool public sawGuardRevert;

    function setReenter(address diamond_, bytes calldata data_) external {
        diamond = diamond_;
        reenterData = data_;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
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
        if (reenterData.length != 0) {
            bytes memory data = reenterData;
            reenterData = "";
            (bool ok, bytes memory ret) = diamond.call(data);
            require(!ok, "re-enter unexpectedly succeeded");
            sawGuardRevert =
                keccak256(ret) == keccak256(abi.encodePacked(IReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        }
        allowance[from][msg.sender] -= value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        return true;
    }
}

contract StargateBridgeAdapterTest is StargateBridgeAdapterTestBase {
    MockStargatePool pool;
    MockToken token;

    address diamond;
    StargateBridgeAdapter adapter;

    address admin = address(0x1);
    address user = address(0x2);
    address evmRecipient = address(0xCAFE);

    uint256 constant DEST_CHAIN = 8453; // Base
    uint32 constant DEST_EID = 30184; // Base's LayerZero eid (Stargate rides LayerZero)
    uint256 constant AMOUNT = 1 ether;
    uint256 constant MIN_AMOUNT = 0.99 ether;
    uint256 constant NATIVE_FEE = 0.01 ether;
    uint256 constant POOL_FEE = 0.001 ether;
    uint256 constant GRANULARITY = 1e12; // the mock's default shared-decimal truncation

    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    function setUp() public {
        token = new MockToken();
        pool = new MockStargatePool(address(token));
        pool.setNativeFee(NATIVE_FEE);
        pool.setPoolFee(POOL_FEE);

        diamond = _deployStargateBridgeAdapter(admin);
        adapter = StargateBridgeAdapter(diamond);

        vm.prank(admin);
        adapter.registerStargateEid(DEST_CHAIN, DEST_EID);
        vm.prank(admin);
        adapter.registerPool(address(token), address(pool));

        vm.deal(user, 100 ether);
    }

    function _fund(address who, uint256 amount) internal {
        token.mint(who, amount);
        vm.prank(who);
        token.approve(diamond, amount);
    }

    /// @notice Fully-populated default params toward an EVM (Base) recipient.
    function _defaultParams() internal view returns (IStargateBridgeAdapter.SendTokenParams memory p) {
        p = IStargateBridgeAdapter.SendTokenParams({
            recipient: InteroperableAddress.formatEvmV1(DEST_CHAIN, evmRecipient),
            token: address(token),
            amountLD: AMOUNT,
            minAmountLD: MIN_AMOUNT,
            destinationChainId: DEST_CHAIN
        });
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   INIT
    //////////////////////////////////////////////////////////////////////////*//

    function test_InitSeedsAdmin() public view {
        assertTrue(AccessControl(diamond).hasRole(bytes32(0), admin), "admin holds DEFAULT_ADMIN_ROLE");
    }

    function test_InitOutsideInitializingWindowReverts() public {
        StargateBridgeAdapterInit init = new StargateBridgeAdapterInit();
        vm.expectRevert(NotInitializing.selector);
        init.init(admin);
    }

    function test_SupportsInterface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IStargateBridgeAdapter).interfaceId));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegisterEidStoresBothDirections() public view {
        assertEq(adapter.stargateEidOf(DEST_CHAIN), DEST_EID);
        assertEq(adapter.stargateChainIdOf(DEST_EID), DEST_CHAIN);
    }

    function test_RegisterEidEmitsEvent() public {
        vm.expectEmit(true, false, false, true, diamond);
        emit IStargateBridgeAdapter.RegisteredEid(10, 30111);
        vm.prank(admin);
        adapter.registerStargateEid(10, 30111);
    }

    function test_RegisterEidRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.registerStargateEid(10, 30111);
    }

    function test_RegisterEidRevertsZeroChainId() public {
        vm.prank(admin);
        vm.expectRevert(IStargateBridgeAdapter.StargateZeroChainId.selector);
        adapter.registerStargateEid(0, 30111);
    }

    function test_RegisterEidRevertsZeroEid() public {
        vm.prank(admin);
        vm.expectRevert(IStargateBridgeAdapter.StargateZeroEid.selector);
        adapter.registerStargateEid(10, 0);
    }

    /// @notice FAIL-LOUD both directions: an already-mapped chainId reverts, whatever the new eid.
    function test_RegisterEidRevertsDuplicateChainId() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IStargateBridgeAdapter.StargateEidAlreadyRegistered.selector, DEST_CHAIN, 30111)
        );
        adapter.registerStargateEid(DEST_CHAIN, 30111);
    }

    /// @notice FAIL-LOUD both directions: an already-mapped eid reverts, whatever the new chainId.
    function test_RegisterEidRevertsDuplicateEid() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IStargateBridgeAdapter.StargateEidAlreadyRegistered.selector, 10, DEST_EID)
        );
        adapter.registerStargateEid(10, DEST_EID);
    }

    function test_RegisterPoolStoresPool() public view {
        assertEq(adapter.poolOf(address(token)), address(pool));
    }

    function test_RegisterPoolEmitsEvent() public {
        MockToken other = new MockToken();
        MockStargatePool otherPool = new MockStargatePool(address(other));
        vm.expectEmit(true, true, false, true, diamond);
        emit IStargateBridgeAdapter.RegisteredPool(address(other), address(otherPool));
        vm.prank(admin);
        adapter.registerPool(address(other), address(otherPool));
    }

    function test_RegisterPoolRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.registerPool(address(token), address(pool));
    }

    function test_RegisterPoolRevertsZeroToken() public {
        vm.prank(admin);
        vm.expectRevert(IStargateBridgeAdapter.StargateZeroAddress.selector);
        adapter.registerPool(address(0), address(pool));
    }

    function test_RegisterPoolRevertsZeroPool() public {
        vm.prank(admin);
        vm.expectRevert(IStargateBridgeAdapter.StargateZeroAddress.selector);
        adapter.registerPool(address(token), address(0));
    }

    /// @notice Pool registration is IDENTITY (register once): a pool upgrade cannot re-point a token in v1.
    function test_RegisterPoolRevertsDuplicateToken() public {
        MockStargatePool second = new MockStargatePool(address(token));
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IStargateBridgeAdapter.StargateTokenAlreadyRegistered.selector, address(token))
        );
        adapter.registerPool(address(token), address(second));
    }

    /// @notice FAIL-CLOSED cross-check: a pool wired to a DIFFERENT asset is rejected — a mis-registered pool
    ///         would burn user approvals against the wrong asset.
    function test_RegisterPoolRevertsTokenMismatch() public {
        MockToken other = new MockToken();
        MockStargatePool wrongPool = new MockStargatePool(address(other));
        MockToken fresh = new MockToken();
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IStargateBridgeAdapter.StargatePoolTokenMismatch.selector, address(fresh), address(other)
            )
        );
        adapter.registerPool(address(fresh), address(wrongPool));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                SEND TOKEN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Every SendParam field lands verbatim — with the empty `extraOptions`/`composeMsg`/`oftCmd`
    ///         asserted EXPLICITLY (taxi mode pinned; bus / lzCompose deferred), plus the fee tuple
    ///         `{msg.value, 0}` and the returned guid/amounts.
    function test_SendTokenHappyPath() public {
        _fund(user, AMOUNT);
        bytes32 expectedGuid = pool.nextGuid();

        vm.prank(user);
        (bytes32 guid, uint256 amountSentLD, uint256 amountReceivedLD) =
            adapter.sendToken{value: NATIVE_FEE}(_defaultParams());

        assertEq(pool.calls(), 1);
        assertEq(pool.lastDstEid(), DEST_EID, "dstEid = the registered LayerZero eid");
        assertEq(pool.lastTo(), bytes32(uint256(uint160(evmRecipient))), "to parsed from ERC-7930");
        assertEq(pool.lastAmountLD(), AMOUNT);
        assertEq(pool.lastMinAmountLD(), MIN_AMOUNT, "mandatory slippage floor passthrough");
        assertEq(pool.lastExtraOptions(), hex"", "extraOptions EMPTY (pool default executor options)");
        assertEq(pool.lastComposeMsg(), hex"", "composeMsg EMPTY (lzCompose deferred)");
        assertEq(pool.lastOftCmd(), hex"", "oftCmd EMPTY (taxi mode pinned; bus deferred)");
        assertEq(pool.lastNativeFee(), NATIVE_FEE, "fee tuple nativeFee = msg.value, forwarded WHOLE");
        assertEq(pool.lastLzTokenFee(), 0, "fee tuple lzTokenFee = 0");
        assertEq(pool.lastMsgValue(), NATIVE_FEE, "msg.value forwarded whole");

        assertEq(guid, expectedGuid, "LayerZero guid returned");
        assertEq(amountSentLD, AMOUNT, "no truncation for a granularity-aligned amount");
        assertEq(amountReceivedLD, AMOUNT - POOL_FEE, "destination credit after pool fees");
    }

    /// @notice REFUND-STRANDING GUARD (regression): excess LayerZero fee refunds go to the refundAddress. If
    ///         the adapter ever passed `address(this)` (the diamond) instead of the calling user, every fee
    ///         surplus would be stranded in the diamond. This test pins `refundAddress == msg.sender` forever
    ///         (same stranding class as the Across depositor).
    function test_SendTokenRefundAddressIsUser() public {
        _fund(user, AMOUNT);
        vm.prank(user);
        adapter.sendToken{value: NATIVE_FEE}(_defaultParams());
        assertEq(pool.lastRefundAddress(), user, "excess fee refunds to the USER");
        assertTrue(pool.lastRefundAddress() != diamond, "NEVER the diamond");
    }

    function test_SendTokenEmitsEvent() public {
        _fund(user, AMOUNT);
        bytes32 expectedGuid = pool.nextGuid();
        vm.expectEmit(true, true, true, true, diamond);
        emit IStargateBridgeAdapter.StargateTokenSent(
            user,
            address(token),
            DEST_CHAIN,
            expectedGuid,
            AMOUNT,
            AMOUNT - POOL_FEE,
            bytes32(uint256(uint160(evmRecipient)))
        );
        vm.prank(user);
        adapter.sendToken{value: NATIVE_FEE}(_defaultParams());
    }

    function test_SendTokenExactApprovalGrantedAndReset() public {
        _fund(user, AMOUNT);
        vm.prank(user);
        adapter.sendToken{value: NATIVE_FEE}(_defaultParams());
        assertEq(pool.allowanceSeen(), AMOUNT, "pool granted EXACTLY amountLD");
        assertEq(token.allowance(diamond, address(pool)), 0, "allowance reset to 0 (hygiene)");
    }

    /// @notice DUST REGRESSION (fund-safety critical): the pool debits `amountLD` truncated to shared
    ///         decimals, so it pulls LESS than the adapter pulled from the user. The exact dust
    ///         (`amountLD % granularity`) must land back with the user in the SAME call — the diamond nets
    ///         zero, keeps zero allowance, and the pool holds exactly what it debited.
    function test_SendTokenSweepsTruncationDustBackToUser() public {
        uint256 dustyAmount = 1 ether + 999; // 999 wei of shared-decimal dust
        uint256 dust = dustyAmount % GRANULARITY;
        assertEq(dust, 999, "fixture sanity");

        _fund(user, dustyAmount);
        vm.prank(user);
        (, uint256 amountSentLD,) = adapter.sendToken{value: NATIVE_FEE}(
            IStargateBridgeAdapter.SendTokenParams({
                recipient: InteroperableAddress.formatEvmV1(DEST_CHAIN, evmRecipient),
                token: address(token),
                amountLD: dustyAmount,
                minAmountLD: MIN_AMOUNT,
                destinationChainId: DEST_CHAIN
            })
        );

        assertEq(amountSentLD, 1 ether, "pool debited only the truncated amount");
        assertEq(token.balanceOf(user), dust, "the EXACT dust returned to the user");
        assertEq(token.balanceOf(address(pool)), 1 ether, "pool escrowed exactly what it debited");
        assertEq(token.balanceOf(diamond), 0, "diamond nets zero");
        assertEq(token.allowance(diamond, address(pool)), 0, "allowance reset to 0");
    }

    /// @notice Approval hygiene + full sweep even when the pool consumes NOTHING: the receipt still claims a
    ///         debit, but the sweep keys off REAL balances — everything returns to the user.
    function test_SendTokenResetsAllowanceAndSweepsWhenPoolDoesNotPull() public {
        pool.setPullFunds(false);
        _fund(user, AMOUNT);
        vm.prank(user);
        adapter.sendToken{value: NATIVE_FEE}(_defaultParams());
        assertEq(token.allowance(diamond, address(pool)), 0, "allowance reset to 0 (hygiene)");
        assertEq(token.balanceOf(user), AMOUNT, "everything swept back to the user");
        assertEq(token.balanceOf(diamond), 0, "diamond nets zero");
    }

    function test_SendTokenPullsFromCallerNoStuck() public {
        _fund(user, AMOUNT);
        vm.prank(user);
        adapter.sendToken{value: NATIVE_FEE}(_defaultParams());
        assertEq(token.balanceOf(user), 0, "user balance reduced by amountLD (granularity-aligned)");
        assertEq(token.balanceOf(diamond), 0, "no token stuck in the diamond");
        assertEq(token.balanceOf(address(pool)), AMOUNT, "pool escrowed the amount");
    }

    /// @notice A solana-style non-EVM recipient (chainType 0x0002, 32-byte address) passes through verbatim —
    ///         no eip-155 cross-check is possible for non-EVM chainTypes.
    function test_SendTokenNonEvmRecipient() public {
        bytes32 solanaKey = keccak256("solana-recipient");
        IStargateBridgeAdapter.SendTokenParams memory p = _defaultParams();
        p.recipient = NonEvmAddress.formatV1(0x0002, abi.encodePacked(uint32(101)), solanaKey);

        _fund(user, AMOUNT);
        vm.prank(user);
        adapter.sendToken{value: NATIVE_FEE}(p);

        assertEq(pool.lastTo(), solanaKey, "32-byte non-EVM recipient verbatim");
        assertEq(pool.lastDstEid(), DEST_EID, "routed by the registered eid of destinationChainId");
    }

    /// @notice REENTRANCY REGRESSION: a malicious pooled token re-entering `sendToken` mid-`transferFrom`
    ///         must be stopped by the diamond-global guard with {ReentrancyGuardReentrantCall}.
    function test_SendTokenNonReentrantViaMaliciousToken() public {
        MockReentrantToken evil = new MockReentrantToken();
        MockStargatePool evilPool = new MockStargatePool(address(evil));
        evilPool.setNativeFee(NATIVE_FEE);
        vm.prank(admin);
        adapter.registerPool(address(evil), address(evilPool));

        IStargateBridgeAdapter.SendTokenParams memory p = _defaultParams();
        p.token = address(evil);
        evil.setReenter(diamond, abi.encodeCall(IStargateBridgeAdapter.sendToken, (p)));

        evil.mint(user, AMOUNT);
        vm.prank(user);
        evil.approve(diamond, AMOUNT);

        vm.prank(user);
        adapter.sendToken{value: NATIVE_FEE}(p);

        assertTrue(evil.sawGuardRevert(), "inner re-enter reverted with ReentrancyGuardReentrantCall");
        assertEq(evilPool.calls(), 1, "outer send completed exactly once");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              SEND REVERTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SendTokenRevertsUnregisteredToken() public {
        MockToken unregistered = new MockToken();
        IStargateBridgeAdapter.SendTokenParams memory p = _defaultParams();
        p.token = address(unregistered);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IStargateBridgeAdapter.StargateTokenNotRegistered.selector, address(unregistered))
        );
        adapter.sendToken{value: NATIVE_FEE}(p);
    }

    function test_SendTokenRevertsUnregisteredChain() public {
        IStargateBridgeAdapter.SendTokenParams memory p = _defaultParams();
        p.recipient = InteroperableAddress.formatEvmV1(10, evmRecipient);
        p.destinationChainId = 10; // Optimism — never registered
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IStargateBridgeAdapter.StargateUnknownDestinationChain.selector, 10));
        adapter.sendToken{value: NATIVE_FEE}(p);
    }

    function test_SendTokenRevertsSameChain() public {
        IStargateBridgeAdapter.SendTokenParams memory p = _defaultParams();
        p.destinationChainId = block.chainid;
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IStargateBridgeAdapter.StargateSameChain.selector, block.chainid));
        adapter.sendToken{value: NATIVE_FEE}(p);
    }

    function test_SendTokenRevertsZeroAmount() public {
        IStargateBridgeAdapter.SendTokenParams memory p = _defaultParams();
        p.amountLD = 0;
        vm.prank(user);
        vm.expectRevert(IStargateBridgeAdapter.StargateZeroAmount.selector);
        adapter.sendToken{value: NATIVE_FEE}(p);
    }

    /// @notice The slippage floor is MANDATORY: pools charge fees so output < input — `minAmountLD == 0`
    ///         would mean unlimited slippage and is rejected outright.
    function test_SendTokenRevertsZeroMinAmount() public {
        IStargateBridgeAdapter.SendTokenParams memory p = _defaultParams();
        p.minAmountLD = 0;
        vm.prank(user);
        vm.expectRevert(IStargateBridgeAdapter.StargateZeroMinAmount.selector);
        adapter.sendToken{value: NATIVE_FEE}(p);
    }

    /// @notice FAIL-CLOSED cross-check: an eip-155 recipient whose ERC-7930 chain reference differs from
    ///         `destinationChainId` is rejected (mirrors the Across sibling).
    function test_SendTokenRevertsEip155DestinationMismatch() public {
        IStargateBridgeAdapter.SendTokenParams memory p = _defaultParams();
        p.recipient = InteroperableAddress.formatEvmV1(10, evmRecipient); // declares Optimism...
        // ...but claims Base
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IStargateBridgeAdapter.StargateDestinationMismatch.selector, 10, DEST_CHAIN)
        );
        adapter.sendToken{value: NATIVE_FEE}(p);
    }

    function test_SendTokenRevertsEmptyRecipientBytes() public {
        IStargateBridgeAdapter.SendTokenParams memory p = _defaultParams();
        p.recipient = hex"";
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(InteroperableAddress.InteroperableAddressParsingError.selector, hex""));
        adapter.sendToken{value: NATIVE_FEE}(p);
    }

    function test_SendTokenRevertsEmptyAddressField() public {
        IStargateBridgeAdapter.SendTokenParams memory p = _defaultParams();
        p.recipient = InteroperableAddress.formatEvmV1(DEST_CHAIN); // chain-only, empty address field
        vm.prank(user);
        vm.expectRevert(NonEvmAddress.NonEvmAddressEmpty.selector);
        adapter.sendToken{value: NATIVE_FEE}(p);
    }

    function test_SendTokenRevertsMalformedEvmWidth() public {
        IStargateBridgeAdapter.SendTokenParams memory p = _defaultParams();
        // eip-155 chainType with a 19-byte address field: rejected instead of right-aligning into a WRONG bytes32.
        p.recipient =
            InteroperableAddress.formatV1(bytes2(0x0000), abi.encodePacked(uint16(uint256(DEST_CHAIN))), new bytes(19));
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NonEvmAddress.NonEvmAddressInvalidEvmWidth.selector, 19));
        adapter.sendToken{value: NATIVE_FEE}(p);
    }

    /// @notice FEE PRECHECK (mirrors the Hyperlane sibling): a `msg.value` below the quoted LayerZero native
    ///         fee reverts {StargateInsufficientFee} BEFORE any funds move.
    function test_SendTokenRevertsInsufficientFee() public {
        _fund(user, AMOUNT);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IStargateBridgeAdapter.StargateInsufficientFee.selector, NATIVE_FEE, NATIVE_FEE - 1)
        );
        adapter.sendToken{value: NATIVE_FEE - 1}(_defaultParams());
        assertEq(token.balanceOf(user), AMOUNT, "no funds moved on the fee precheck revert");
    }

    function test_SendTokenRevertsNoApproval() public {
        token.mint(user, AMOUNT); // minted, not approved to the diamond
        vm.prank(user);
        vm.expectRevert(); // pullExact transferFrom underflows without allowance
        adapter.sendToken{value: NATIVE_FEE}(_defaultParams());
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   QUOTE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice `quoteSendFee` uses the SAME internal SendParam builder as the send path — a send funded with
    ///         exactly the quoted fee always passes the precheck.
    function test_QuoteSendFeeMatchesSendPath() public {
        assertEq(adapter.quoteSendFee(_defaultParams()), NATIVE_FEE);

        _fund(user, AMOUNT);
        uint256 quoted = adapter.quoteSendFee(_defaultParams());
        vm.prank(user);
        adapter.sendToken{value: quoted}(_defaultParams());
        assertEq(pool.calls(), 1, "exactly-quoted fee passes the precheck");
    }

    /// @notice The quote path runs the identical checks as the send path (shared builder — no drift).
    function test_QuoteSendFeeRevertsUnregisteredToken() public {
        MockToken unregistered = new MockToken();
        IStargateBridgeAdapter.SendTokenParams memory p = _defaultParams();
        p.token = address(unregistered);
        vm.expectRevert(
            abi.encodeWithSelector(IStargateBridgeAdapter.StargateTokenNotRegistered.selector, address(unregistered))
        );
        adapter.quoteSendFee(p);
    }

    //*//////////////////////////////////////////////////////////////////////////
    /// @notice DELTA-SWEEP ISOLATION (review finding): a PRE-EXISTING diamond balance of the same token
    ///         (e.g. vault-module holdings in a combined diamond) must survive a dusty send untouched — the
    ///         sweep is snapshot-delta-based, never absolute. A refactor to an absolute balanceOf sweep would
    ///         fail this test by leaking the diamond's own holdings to the sender.
    function test_SendTokenPreservesPreExistingDiamondBalance() public {
        uint256 preExisting = 5 ether;
        token.mint(diamond, preExisting);

        IStargateBridgeAdapter.SendTokenParams memory p = _defaultParams();
        p.amountLD = AMOUNT + 999; // dusty: 999 wei below the 1e12 granularity

        _fund(user, p.amountLD);
        vm.prank(user);
        adapter.sendToken{value: NATIVE_FEE}(p);

        assertEq(token.balanceOf(diamond), preExisting, "pre-existing diamond balance untouched by the sweep");
        assertEq(token.balanceOf(user), 999, "user got exactly the dust, nothing more");
    }

    /// @notice SURPLUS FEE FORWARDING (review finding): msg.value above the quoted fee is forwarded WHOLE to
    ///         the pool with refundAddress = the user — the surplus refund is LayerZero's job, and no wei may
    ///         stick to the diamond.
    function test_SendTokenForwardsSurplusFeeWholeWithUserRefund() public {
        uint256 surplus = 0.005 ether;
        _fund(user, AMOUNT);
        vm.prank(user);
        adapter.sendToken{value: NATIVE_FEE + surplus}(_defaultParams());

        assertEq(pool.lastMsgValue(), NATIVE_FEE + surplus, "entire value forwarded, surplus included");
        assertEq(pool.lastNativeFee(), NATIVE_FEE + surplus, "fee tuple carries the full msg.value");
        assertEq(pool.lastRefundAddress(), user, "surplus refunds to the USER");
        assertEq(diamond.balance, 0, "no wei sticks to the diamond");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   FUZZ
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Conservation invariant under shared-decimal truncation: for any amount, the pool holds exactly
    ///         the truncated debit, the user keeps exactly the dust, and the diamond nets zero with zero
    ///         standing allowance.
    function testFuzz_SendTokenAmountConservation(uint256 amountLD, uint96 preBalance) public {
        amountLD = bound(amountLD, 1, uint256(type(uint96).max));
        uint256 truncated = amountLD - (amountLD % GRANULARITY);
        token.mint(diamond, preBalance); // fuzzed pre-existing diamond holdings must survive untouched

        IStargateBridgeAdapter.SendTokenParams memory p = _defaultParams();
        p.amountLD = amountLD;

        _fund(user, amountLD);
        vm.prank(user);
        (, uint256 amountSentLD,) = adapter.sendToken{value: NATIVE_FEE}(p);

        assertEq(amountSentLD, truncated, "pool debited the truncated amount");
        assertEq(token.balanceOf(address(pool)), truncated, "pool holds exactly its debit");
        assertEq(token.balanceOf(user), amountLD - truncated, "user keeps exactly the dust");
        assertEq(token.balanceOf(diamond), uint256(preBalance), "diamond nets zero beyond its own holdings");
        assertEq(token.allowance(diamond, address(pool)), 0, "no standing allowance");
    }

    function testFuzz_SendTokenChainRouting(uint64 destChainId, uint32 eid) public {
        vm.assume(destChainId != 0 && destChainId != block.chainid && destChainId != DEST_CHAIN);
        vm.assume(eid != 0 && eid != DEST_EID);
        vm.prank(admin);
        adapter.registerStargateEid(destChainId, eid);

        IStargateBridgeAdapter.SendTokenParams memory p = _defaultParams();
        p.recipient = InteroperableAddress.formatEvmV1(destChainId, evmRecipient);
        p.destinationChainId = destChainId;

        _fund(user, AMOUNT);
        vm.prank(user);
        adapter.sendToken{value: NATIVE_FEE}(p);

        assertEq(pool.lastDstEid(), eid, "routed by the admin-registered eid");
        assertEq(pool.lastTo(), bytes32(uint256(uint160(evmRecipient))));
    }
}
