// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {LidoAdapter} from "@lattice/defi/LidoAdapter.sol";
import {LidoAdapterLib} from "@lattice/defi/libraries/LidoAdapterLib.sol";
import {ILidoAdapter} from "@lattice/interfaces/defi/ILidoAdapter.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                              MOCK TOKENS / LIDO
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal 18-decimal ERC20 base shared by the stETH / wstETH mocks.
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory n, string memory s) {
        name = n;
        symbol = s;
    }

    function _mint(address to, uint256 a) internal {
        balanceOf[to] += a;
    }

    function _burn(address from, uint256 a) internal {
        require(balanceOf[from] >= a, "bal");
        balanceOf[from] -= a;
    }

    function transfer(address to, uint256 a) external returns (bool) {
        require(balanceOf[msg.sender] >= a, "bal");
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
        return true;
    }

    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        require(balanceOf[f] >= a, "bal");
        require(allowance[f][msg.sender] >= a, "allow");
        allowance[f][msg.sender] -= a;
        balanceOf[f] -= a;
        balanceOf[t] += a;
        return true;
    }

    function approve(address s, uint256 a) external returns (bool) {
        allowance[msg.sender][s] = a;
        return true;
    }
}

/// @notice Wrapped Ether mock: `deposit()` wraps attached ETH 1:1; `withdraw(amount)` burns WETH and
///         returns native ETH. `mint` is a test convenience to fund a buffer without sending ETH.
contract MockWETH is MockERC20 {
    constructor() MockERC20("Wrapped Ether", "WETH") {}

    function mint(address to, uint256 a) external {
        _mint(to, a);
    }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "eth send");
    }

    receive() external payable {
        _mint(msg.sender, msg.value);
    }
}

/// @notice Lido stETH mock: `submit{value}()` mints stETH 1:1 with the ETH staked (the simplified
///         steady-state of Lido's 1:1 submit). Holds the staked ETH so it can later fund the queue's
///         claim payouts.
contract MockStETH is MockERC20 {
    constructor() MockERC20("Liquid staked Ether", "stETH") {}

    function submit(address) external payable returns (uint256) {
        _mint(msg.sender, msg.value);
        return msg.value;
    }

    /// @dev Used by the wstETH/queue mocks to move stETH around in tests.
    function mintTo(address to, uint256 a) external {
        _mint(to, a);
    }

    function burnFrom(address from, uint256 a) external {
        _burn(from, a);
    }
}

/// @notice Lido wstETH mock: non-rebasing wrapper. `wrap` pulls `stETHAmount` stETH and mints
///         `stETH / rate` wstETH; `unwrap` burns wstETH and returns `wst * rate` stETH. `rate` (WAD)
///         is the stETH-per-wstETH price; bumping it simulates staking yield accruing to wstETH.
contract MockWstETH is MockERC20 {
    MockStETH public stETH;
    uint256 public rate = 1e18; // stETH per 1 wstETH (WAD)

    constructor(MockStETH s) MockERC20("Wrapped liquid staked Ether", "wstETH") {
        stETH = s;
    }

    function setRate(uint256 r) external {
        rate = r;
    }

    function getStETHByWstETH(uint256 wst) external view returns (uint256) {
        return (wst * rate) / 1e18;
    }

    function getWstETHByStETH(uint256 st) external view returns (uint256) {
        return (st * 1e18) / rate;
    }

    function wrap(uint256 stETHAmount) external returns (uint256 wstETHAmount) {
        require(stETH.transferFrom(msg.sender, address(this), stETHAmount), "pull stETH");
        wstETHAmount = (stETHAmount * 1e18) / rate;
        _mint(msg.sender, wstETHAmount);
    }

    function unwrap(uint256 wstETHAmount) external returns (uint256 stETHAmount) {
        _burn(msg.sender, wstETHAmount);
        stETHAmount = (wstETHAmount * rate) / 1e18;
        require(stETH.transfer(msg.sender, stETHAmount), "send stETH");
    }
}

/// @notice Lido withdrawal-queue mock. `requestWithdrawals` pulls stETH and mints sequential request
///         ids; `claimWithdrawal` pays out the recorded stETH amount as native ETH (1:1) — but only
///         when the request is finalized. `setFinalized` toggles finalization to exercise the
///         pending state; the queue is funded with ETH in the test so claims can pay out.
contract MockLidoWithdrawalQueue {
    MockStETH public stETH;
    uint256 public nextId = 1;

    mapping(uint256 => uint256) public amountOf; // requestId => stETH locked
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => bool) public finalized;
    mapping(uint256 => bool) public claimed;

    constructor(MockStETH s) {
        stETH = s;
    }

    function setFinalized(uint256 id, bool f) external {
        finalized[id] = f;
    }

    function requestWithdrawals(uint256[] calldata amounts, address owner) external returns (uint256[] memory ids) {
        ids = new uint256[](amounts.length);
        for (uint256 i; i < amounts.length; ++i) {
            require(stETH.transferFrom(msg.sender, address(this), amounts[i]), "pull stETH");
            uint256 id = nextId++;
            amountOf[id] = amounts[i];
            ownerOf[id] = owner;
            finalized[id] = true; // default to immediately claimable; flip with setFinalized for pending tests
            ids[i] = id;
        }
    }

    function claimWithdrawal(uint256 id) external {
        require(finalized[id], "not finalized");
        require(!claimed[id], "claimed");
        claimed[id] = true;
        uint256 amt = amountOf[id];
        // Burn the queue's locked stETH (it was transferred in on request) and pay native ETH 1:1.
        stETH.burnFrom(address(this), amt);
        (bool ok,) = ownerOf[id].call{value: amt}("");
        require(ok, "eth pay");
    }

    receive() external payable {}
}

//*//////////////////////////////////////////////////////////////////////////
//                                ADAPTER MOCK
//////////////////////////////////////////////////////////////////////////*//

/// @notice Adapter composed with Pausable + EmergencyStop facets (as a real Diamond would).
contract MockLidoAdapter is LidoAdapter, Pausable, EmergencyStop {
    function initialize(
        address admin_,
        address weth_,
        address lido_,
        address wstETH_,
        address withdrawalQueue_,
        address vault_,
        address recipient_
    ) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        ReentrancyGuardLib.__ReentrancyGuard_init();
        PausableLib.__Pausable_init();
        EmergencyStopLib.__EmergencyStop_init();
        LidoAdapterLib.__LidoAdapter_init(weth_, lido_, wstETH_, withdrawalQueue_, vault_, recipient_);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) external view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

contract LidoAdapterTest is Test {
    MockWETH weth;
    MockStETH stETH;
    MockWstETH wstETH;
    MockLidoWithdrawalQueue queue;
    MockLidoAdapter adapter;

    address admin = address(0xAD);
    address guardian = address(0x6);
    address vault = address(0x7A17);
    address treasury = address(0x7E0);

    function setUp() public {
        weth = new MockWETH();
        stETH = new MockStETH();
        wstETH = new MockWstETH(stETH);
        queue = new MockLidoWithdrawalQueue(stETH);
        // Fund the queue with ETH so finalized claims can pay out native ETH.
        vm.deal(address(queue), 1_000_000 ether);

        adapter = new MockLidoAdapter();
        adapter.initialize(admin, address(weth), address(stETH), address(wstETH), address(queue), vault, treasury);
        vm.startPrank(admin);
        adapter.addGuardian(guardian);
        // Authorize this test contract as the operator so the direct deploy/withdraw/harvest calls
        // (which the StrategyManager would make in production) pass the operator gate.
        adapter.setOperator(address(this));
        vm.stopPrank();
    }

    // Helper: mint `a` WETH to `to` AND back it with real ETH in the WETH contract, so a later
    // `WETH.withdraw` (in deploy) can actually pay out native ETH (real WETH is always 1:1 ETH-backed).
    function _mintWeth(address to, uint256 a) internal {
        weth.mint(to, a);
        vm.deal(address(weth), address(weth).balance + a);
    }

    // Helper: fund the adapter with `a` WETH (idle buffer) and deploy it into Lido.
    function _fundAndDeploy(uint256 a) internal returns (uint256 deployed) {
        _mintWeth(address(adapter), a);
        deployed = adapter.deploy();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  DEPLOY
    //////////////////////////////////////////////////////////////////////////*//

    function test_Deploy_StakesWethToWstETH() public {
        uint256 deployed = _fundAndDeploy(10 ether);
        assertEq(deployed, 10 ether, "reports idle deployed");
        assertEq(weth.balanceOf(address(adapter)), 0, "WETH buffer swept into Lido");
        // rate == 1e18, so 10 WETH -> 10 stETH -> 10 wstETH held by the adapter.
        assertEq(wstETH.balanceOf(address(adapter)), 10 ether, "wstETH held");
        assertEq(stETH.balanceOf(address(adapter)), 0, "no loose stETH (all wrapped)");
        assertEq(adapter.stakedWstETH(), 10 ether, "stakedWstETH getter");
        assertEq(adapter.totalAssetsManaged(), 10 ether, "NAV == staked value at 1:1");
    }

    function test_Deploy_RevertsWhenNothingToDeploy() public {
        vm.expectRevert(IProtocolAdapter.ProtocolAdapterNothingToDeploy.selector);
        adapter.deploy();
    }

    function test_Deploy_RevertsWhenPaused() public {
        weth.mint(address(adapter), 1 ether);
        vm.prank(admin);
        adapter.pause();
        vm.expectRevert(IProtocolAdapter.ProtocolAdapterPaused.selector);
        adapter.deploy();
    }

    function test_Deploy_RevertsWhenStopped() public {
        weth.mint(address(adapter), 1 ether);
        vm.prank(guardian);
        adapter.emergencyStop("incident");
        vm.expectRevert(IProtocolAdapter.ProtocolAdapterPaused.selector);
        adapter.deploy();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              TOTAL ASSETS
    //////////////////////////////////////////////////////////////////////////*//

    function test_TotalAssets_IsBufferPlusStakedPlusPending() public {
        // Stake 10, leave a 3 WETH idle buffer.
        _fundAndDeploy(10 ether);
        weth.mint(address(adapter), 3 ether);
        assertEq(adapter.bufferBalance(), 3 ether, "buffer getter");
        assertEq(adapter.totalAssetsManaged(), 13 ether, "buffer + staked");

        // Enqueue 4 wstETH (-> 4 stETH pending); NAV must be unchanged (staked falls, pending rises).
        vm.prank(admin);
        adapter.requestWithdrawal(4 ether);
        assertEq(adapter.pendingWithdrawalAssets(), 4 ether, "pending stETH tracked");
        assertEq(adapter.stakedWstETH(), 6 ether, "staked reduced");
        assertEq(adapter.totalAssetsManaged(), 13 ether, "NAV unchanged by enqueue: 3 + 6 + 4");
    }

    function test_TotalAssets_YieldRaisesNavViaRate() public {
        _fundAndDeploy(10 ether);
        assertEq(adapter.totalAssetsManaged(), 10 ether, "baseline NAV");
        wstETH.setRate(1.1e18); // +10% staking yield: each wstETH now worth 1.1 stETH
        assertEq(adapter.totalAssetsManaged(), 11 ether, "NAV scales with wstETH->stETH rate");
    }

    function test_TotalAssets_ZeroWhenEmpty() public view {
        assertEq(adapter.totalAssetsManaged(), 0, "nothing staked/buffered -> 0");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       SYNCHRONOUS WITHDRAW (buffer)
    //////////////////////////////////////////////////////////////////////////*//

    function test_Withdraw_ServesFromBuffer() public {
        _fundAndDeploy(10 ether);
        // Refill a buffer (as a claim would).
        weth.mint(address(adapter), 5 ether);
        uint256 got = adapter.withdraw(4 ether, vault);
        assertEq(got, 4 ether, "served fully from buffer");
        assertEq(weth.balanceOf(vault), 4 ether, "vault received WETH");
        assertEq(adapter.bufferBalance(), 1 ether, "buffer drawn down");
        // Staked position untouched by a synchronous withdraw.
        assertEq(adapter.stakedWstETH(), 10 ether, "stake untouched");
    }

    function test_Withdraw_ShortfallHonest_WhenBufferShort() public {
        _fundAndDeploy(10 ether); // all staked, buffer is 0
        weth.mint(address(adapter), 2 ether); // only 2 WETH in buffer
        // Ask for 7; the buffer only has 2 -> returns 2 (the staked leg must come via the queue).
        uint256 got = adapter.withdraw(7 ether, vault);
        assertEq(got, 2 ether, "shortfall-honest: returns only what the buffer holds");
        assertEq(weth.balanceOf(vault), 2 ether, "vault got the partial amount");
        assertEq(adapter.bufferBalance(), 0, "buffer fully drained");
        assertEq(adapter.stakedWstETH(), 10 ether, "staked NOT touched by sync withdraw");
    }

    function test_Withdraw_ZeroWhenBufferEmpty() public {
        _fundAndDeploy(10 ether); // buffer == 0
        uint256 got = adapter.withdraw(5 ether, vault);
        assertEq(got, 0, "empty buffer -> returns 0 (rest is async)");
        assertEq(weth.balanceOf(vault), 0);
    }

    function test_Withdraw_RevertsZeroRecipient() public {
        _fundAndDeploy(10 ether);
        weth.mint(address(adapter), 1 ether);
        // The recipient is now pinned to the adapter's vault, so any non-vault recipient (incl. the
        // zero address) is rejected with ProtocolAdapterInvalidRecipient.
        vm.expectRevert(abi.encodeWithSelector(IProtocolAdapter.ProtocolAdapterInvalidRecipient.selector, address(0)));
        adapter.withdraw(1 ether, address(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     ASYNC QUEUE: request + claim
    //////////////////////////////////////////////////////////////////////////*//

    function test_RequestWithdrawal_MovesWstToPending_NavUnchanged() public {
        _fundAndDeploy(10 ether);
        uint256 navBefore = adapter.totalAssetsManaged();
        vm.prank(admin);
        uint256 id = adapter.requestWithdrawal(4 ether);
        assertEq(adapter.stakedWstETH(), 6 ether, "wstETH reduced by enqueue");
        assertEq(adapter.pendingWithdrawalAssets(), 4 ether, "pending stETH recorded");
        assertEq(adapter.pendingRequestCount(), 1, "one pending request");
        assertEq(adapter.pendingRequestAt(0), id, "request id tracked");
        assertEq(adapter.totalAssetsManaged(), navBefore, "NAV unchanged by enqueue");
    }

    function test_RequestWithdrawal_OnlyAdmin() public {
        _fundAndDeploy(10 ether);
        vm.prank(address(0xBAD));
        vm.expectRevert(); // AccessControlUnauthorizedAccount
        adapter.requestWithdrawal(1 ether);
    }

    function test_RequestWithdrawal_RevertsWhenExceedsBalance() public {
        _fundAndDeploy(10 ether);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILidoAdapter.LidoAdapterInsufficientWstETH.selector, 11 ether, 10 ether));
        adapter.requestWithdrawal(11 ether);
    }

    function test_ClaimWithdrawal_RefillsBuffer_ThenSyncWithdrawSucceeds() public {
        _fundAndDeploy(10 ether);
        vm.prank(admin);
        uint256 id = adapter.requestWithdrawal(4 ether);
        assertEq(adapter.bufferBalance(), 0, "buffer empty pre-claim");

        // Claim (permissionless): ETH from the queue -> wrapped into the WETH buffer.
        uint256 ethClaimed = adapter.claimWithdrawal(id);
        assertEq(ethClaimed, 4 ether, "claimed the finalized amount");
        assertEq(adapter.bufferBalance(), 4 ether, "buffer refilled by claim");
        assertEq(adapter.pendingWithdrawalAssets(), 0, "pending cleared");
        assertEq(adapter.pendingRequestCount(), 0, "request removed from pending");
        // NAV preserved: 6 staked + 4 buffer.
        assertEq(adapter.totalAssetsManaged(), 10 ether, "NAV preserved across queue round-trip");

        // Now the synchronous withdraw can be served from the refilled buffer.
        uint256 got = adapter.withdraw(4 ether, vault);
        assertEq(got, 4 ether, "sync withdraw served after claim");
        assertEq(weth.balanceOf(vault), 4 ether, "vault received");
    }

    function test_ClaimWithdrawal_RevertsUnknownRequest() public {
        _fundAndDeploy(10 ether);
        vm.expectRevert(abi.encodeWithSelector(ILidoAdapter.LidoAdapterUnknownRequest.selector, uint256(999)));
        adapter.claimWithdrawal(999);
    }

    function test_PendingState_NotClaimableUntilFinalized() public {
        _fundAndDeploy(10 ether);
        vm.prank(admin);
        uint256 id = adapter.requestWithdrawal(4 ether);
        // Mark the request not-yet-finalized: the underlying claim reverts and it stays pending.
        queue.setFinalized(id, false);
        vm.expectRevert(bytes("not finalized"));
        adapter.claimWithdrawal(id);
        // Still pending, NAV still whole.
        assertEq(adapter.pendingRequestCount(), 1, "request still pending");
        assertEq(adapter.pendingWithdrawalAssets(), 4 ether, "pending stETH retained");
        assertEq(adapter.totalAssetsManaged(), 10 ether, "NAV retained while in queue");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 HARVEST
    //////////////////////////////////////////////////////////////////////////*//

    function test_Harvest_NoOp_DoesNotChangeNav() public {
        _fundAndDeploy(10 ether);
        uint256 navBefore = adapter.totalAssetsManaged();
        adapter.harvest(); // yield is in the rate, not a reward token -> no-op
        assertEq(adapter.totalAssetsManaged(), navBefore, "harvest does not change NAV");
        assertEq(adapter.stakedWstETH(), 10 ether, "stake untouched");
    }

    function test_Harvest_ForwardsStrayToken() public {
        _fundAndDeploy(10 ether);
        // A stray airdropped token (not WETH/stETH/wstETH) is swept to the reward recipient (admin/keeper).
        MockERC20 stray = new MockWETH();
        MockWETH(payable(address(stray))).mint(address(adapter), 5 ether);
        vm.prank(admin);
        adapter.harvestToken(address(stray));
        assertEq(stray.balanceOf(treasury), 5 ether, "stray token forwarded to recipient");
    }

    function test_HarvestToken_RejectsCoreTokens() public {
        _fundAndDeploy(10 ether);
        // The core tokens (WETH buffer / stETH hop / wstETH stake) must never be sweepable.
        vm.prank(admin);
        vm.expectRevert(IProtocolAdapter.ProtocolAdapterZeroAddress.selector);
        adapter.harvestToken(address(wstETH));
        vm.prank(admin);
        vm.expectRevert(IProtocolAdapter.ProtocolAdapterZeroAddress.selector);
        adapter.harvestToken(address(weth));
        // Stake untouched.
        assertEq(adapter.stakedWstETH(), 10 ether, "core sweep blocked, stake intact");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            EMERGENCY WITHDRAW
    //////////////////////////////////////////////////////////////////////////*//

    function test_EmergencyWithdraw_DrainsBufferAndQueuesRest() public {
        _fundAndDeploy(10 ether);
        weth.mint(address(adapter), 3 ether); // buffer == 3, staked == 10
        vm.prank(admin);
        uint256 rec = adapter.emergencyWithdraw();
        // Buffer goes to the vault immediately.
        assertEq(rec, 3 ether, "buffer sent to vault now");
        assertEq(weth.balanceOf(vault), 3 ether, "vault received buffer");
        assertEq(adapter.bufferBalance(), 0, "buffer drained");
        // The whole wstETH stake is queued (the slow leg completes later via claimWithdrawal).
        assertEq(adapter.stakedWstETH(), 0, "all wstETH enqueued");
        assertEq(adapter.pendingWithdrawalAssets(), 10 ether, "full stake now pending in queue");
        assertEq(adapter.pendingRequestCount(), 1, "one pending request created");
        // NAV still accounts for the in-flight stake.
        assertEq(adapter.totalAssetsManaged(), 10 ether, "in-flight stake still in NAV");
    }

    function test_EmergencyWithdraw_WorksWhenStopped() public {
        _fundAndDeploy(10 ether);
        weth.mint(address(adapter), 2 ether);
        vm.prank(guardian);
        adapter.emergencyStop("incident"); // must NOT block the emergency exit
        vm.prank(admin);
        uint256 rec = adapter.emergencyWithdraw();
        assertEq(rec, 2 ether, "buffer exits even when stopped");
        assertEq(adapter.stakedWstETH(), 0, "stake queued even when stopped");
        assertEq(adapter.pendingWithdrawalAssets(), 10 ether, "stake pending");
    }

    function test_EmergencyWithdraw_ThenClaim_FullyExits() public {
        _fundAndDeploy(10 ether);
        vm.prank(admin);
        adapter.emergencyWithdraw(); // buffer (0) out, full 10 wstETH queued
        uint256 id = adapter.pendingRequestAt(0);
        // The async leg completes: claim refills the buffer with the staked ETH.
        adapter.claimWithdrawal(id);
        assertEq(adapter.bufferBalance(), 10 ether, "claim brought the staked ETH back");
        // A final sweep withdraw moves it to the vault (StrategyManager would do this).
        uint256 got = adapter.withdraw(10 ether, vault);
        assertEq(got, 10 ether, "remaining recovered to vault after claim");
        assertEq(adapter.totalAssetsManaged(), 0, "fully exited");
    }

    function test_EmergencyWithdraw_OnlyAdmin() public {
        _fundAndDeploy(10 ether);
        vm.prank(address(0xBAD));
        vm.expectRevert(); // AccessControlUnauthorizedAccount
        adapter.emergencyWithdraw();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function test_Config_Getters() public view {
        assertEq(adapter.asset(), address(weth), "asset == WETH");
        assertEq(adapter.weth(), address(weth));
        assertEq(adapter.lido(), address(stETH));
        assertEq(adapter.wstETH(), address(wstETH));
        assertEq(adapter.withdrawalQueue(), address(queue));
        assertEq(adapter.vault(), vault);
        assertEq(adapter.rewardRecipient(), treasury);
        assertEq(adapter.minHealthFactor(), type(uint256).max, "no debt");
        assertEq(adapter.healthFactor(), type(uint256).max, "no debt");
    }

    function test_SetRewardRecipient_OnlyAdmin() public {
        vm.prank(admin);
        adapter.setRewardRecipient(address(0xCAFE));
        assertEq(adapter.rewardRecipient(), address(0xCAFE));

        vm.prank(address(0xBAD));
        vm.expectRevert();
        adapter.setRewardRecipient(address(0xCAFE));

        vm.prank(admin);
        vm.expectRevert(IProtocolAdapter.ProtocolAdapterZeroAddress.selector);
        adapter.setRewardRecipient(address(0));
    }

    function test_IsPaused_ReflectsState() public {
        assertEq(adapter.isPaused(), false);
        vm.prank(admin);
        adapter.pause();
        assertEq(adapter.isPaused(), true);
    }

    function test_SupportsInterface() public view {
        assertTrue(adapter.supportsInterface(type(ILidoAdapter).interfaceId), "ILidoAdapter");
        assertTrue(adapter.supportsInterface(type(IProtocolAdapter).interfaceId), "IProtocolAdapter");
    }
}
