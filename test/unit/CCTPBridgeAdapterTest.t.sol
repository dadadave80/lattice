// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {CCTPBridgeAdapterTestBase} from "@lattice-test/base/CCTPBridgeAdapterTestBase.sol";
import {CCTPBridgeAdapter} from "@lattice/crosschain/CCTPBridgeAdapter.sol";
import {HOOK_MAGIC} from "@lattice/crosschain/libraries/CCTPBridgeAdapterLib.sol";
import {NonEvmAddress} from "@lattice/crosschain/libraries/NonEvmAddress.sol";
import {ICCTPBridgeAdapter} from "@lattice/interfaces/crosschain/ICCTPBridgeAdapter.sol";
import {ICCTPHookExecutor} from "@lattice/interfaces/crosschain/ICCTPHookExecutor.sol";
import {ICCTPHookReceiver} from "@lattice/interfaces/crosschain/ICCTPHookReceiver.sol";
import {IReceiverV2} from "@lattice/interfaces/external/circle/IReceiverV2.sol";
import {ITokenMessengerV2} from "@lattice/interfaces/external/circle/ITokenMessengerV2.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

/// @notice Records `depositForBurn` args and the allowance it was granted; optionally pulls the burn amount
///         (as the real TokenMessenger does) so the adapter's balance settles to 0 (no-USDC-stuck).
contract MockTokenMessenger is ITokenMessengerV2 {
    uint256 public lastAmount;
    uint32 public lastDestinationDomain;
    bytes32 public lastMintRecipient;
    address public lastBurnToken;
    bytes32 public lastDestinationCaller;
    uint256 public lastMaxFee;
    uint32 public lastMinFinalityThreshold;
    uint256 public allowanceSeen;
    uint256 public calls;
    bool public pullFunds = true;
    bytes public lastHookData;
    bool public lastWasHook;

    function setPullFunds(bool p) external {
        pullFunds = p;
    }

    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external {
        _record(amount, destinationDomain, mintRecipient, burnToken, destinationCaller, maxFee, minFinalityThreshold);
        lastWasHook = false;
    }

    function depositForBurnWithHook(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold,
        bytes calldata hookData
    ) external {
        _record(amount, destinationDomain, mintRecipient, burnToken, destinationCaller, maxFee, minFinalityThreshold);
        lastHookData = hookData;
        lastWasHook = true;
    }

    function _record(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) internal {
        allowanceSeen = IERC20(burnToken).allowance(msg.sender, address(this));
        lastAmount = amount;
        lastDestinationDomain = destinationDomain;
        lastMintRecipient = mintRecipient;
        lastBurnToken = burnToken;
        lastDestinationCaller = destinationCaller;
        lastMaxFee = maxFee;
        lastMinFinalityThreshold = minFinalityThreshold;
        ++calls;
        if (pullFunds) IERC20(burnToken).transferFrom(msg.sender, address(this), amount);
    }
}

/// @notice A Lattice CCTP hook target: records the exact {ICCTPHookReceiver-onCCTPHook} args + `msg.sender` (must
///         be the executor, never the diamond). Settable to revert, to return-bomb (huge returndata), or to
///         re-enter the diamond's guarded relay path (proving the shared reentrancy guard fails the inner call).
contract MockHookReceiver is ICCTPHookReceiver {
    uint32 public lastSourceDomain;
    bytes32 public lastSender;
    bytes32 public lastMintRecipient;
    uint256 public lastAmount;
    bytes public lastPayload;
    address public lastCaller;
    uint256 public calls;

    bool public shouldRevert;
    bool public returnBomb;
    address public reenterTarget; // if set, re-enter this diamond's relayMessage (must hit the reentrancy guard)

    function setShouldRevert(bool v) external {
        shouldRevert = v;
    }

    function setReturnBomb(bool v) external {
        returnBomb = v;
    }

    function setReenterTarget(address t) external {
        reenterTarget = t;
    }

    function onCCTPHook(
        uint32 sourceDomain,
        bytes32 sender,
        bytes32 mintRecipient,
        uint256 amount,
        bytes calldata payload
    ) external {
        lastCaller = msg.sender;
        lastSourceDomain = sourceDomain;
        lastSender = sender;
        lastMintRecipient = mintRecipient;
        lastAmount = amount;
        lastPayload = payload;
        ++calls;

        if (reenterTarget != address(0)) {
            // Hostile re-entry: the inner relayMessage must revert on the shared reentrancy guard, which
            // propagates up and makes this hook revert — the executor then reports success == false.
            ICCTPBridgeAdapter(reenterTarget).relayMessage(hex"00", hex"00");
        }
        if (shouldRevert) revert("hook reverted");
        if (returnBomb) {
            assembly {
                return(0x00, 0x40000) // 256 KiB of returndata — a return bomb the executor must ignore
            }
        }
    }
}

/// @notice MessageTransmitterV2 receive side: `receiveMessage` returns a settable true/false and records args.
contract MockMessageTransmitter is IReceiverV2 {
    bool public receiveResult = true;
    bytes public lastMessage;
    bytes public lastAttestation;
    address public lastCaller;
    uint256 public calls;

    function setReceiveResult(bool r) external {
        receiveResult = r;
    }

    function receiveMessage(bytes calldata message, bytes calldata attestation) external returns (bool) {
        lastMessage = message;
        lastAttestation = attestation;
        lastCaller = msg.sender;
        ++calls;
        return receiveResult;
    }

    function localDomain() external pure returns (uint32) {
        return 0;
    }
}

/// @notice Minimal USDC-like ERC-20 (mint/approve/transfer/transferFrom).
contract MockUSDC is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    function name() external pure returns (string memory) {
        return "USD Coin";
    }

    function symbol() external pure returns (string memory) {
        return "USDC";
    }

    function decimals() external pure returns (uint8) {
        return 6;
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

contract CCTPBridgeAdapterTest is CCTPBridgeAdapterTestBase {
    MockTokenMessenger messenger;
    MockMessageTransmitter transmitter;
    MockUSDC usdcToken;
    MockHookReceiver hookReceiver;

    address diamond;
    CCTPBridgeAdapter adapter;

    address admin = address(0x1);
    address user = address(0x2);
    address relayer = address(0x3);
    address evmRecipient = address(0xCAFE);

    // Base = chainId 8453, CCTP domain 6. Ethereum = chainId 1, CCTP domain 0 (registered flag disambiguates).
    uint256 constant BASE_CHAIN = 8453;
    uint32 constant BASE_DOMAIN = 6;
    uint256 constant ETH_CHAIN = 1;
    uint32 constant ETH_DOMAIN = 0;

    // Per-domain config for Base.
    uint256 constant MAX_FEE = 500; // 0.0005 USDC
    uint32 constant MIN_FINALITY = 1000;
    bytes32 constant DEST_CALLER = bytes32(uint256(0xABCD));

    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    bytes recip; // ERC-7930 EVM recipient on Base

    // --- Inbound synthetic-message fixtures (attested context read from the message, never from hookData). ---
    uint32 constant SRC_DOMAIN = 6; // Base (source of the inbound burn)
    bytes32 constant NONCE = bytes32(uint256(0x1234));
    bytes32 constant SENDER = bytes32(uint256(0xB0B)); // burner on the source domain
    uint256 constant HOOK_AMOUNT = 777_000; // minted USDC amount carried in the burn body

    function setUp() public {
        messenger = new MockTokenMessenger();
        transmitter = new MockMessageTransmitter();
        usdcToken = new MockUSDC();
        hookReceiver = new MockHookReceiver();

        diamond = _deployCCTPBridgeAdapter(admin, address(messenger), address(transmitter), address(usdcToken));
        adapter = CCTPBridgeAdapter(diamond);

        recip = InteroperableAddress.formatEvmV1(BASE_CHAIN, evmRecipient);

        vm.startPrank(admin);
        adapter.registerChainDomain(BASE_CHAIN, BASE_DOMAIN);
        adapter.registerChainDomain(ETH_CHAIN, ETH_DOMAIN);
        adapter.configureDomain(BASE_DOMAIN, MAX_FEE, MIN_FINALITY, DEST_CALLER);
        vm.stopPrank();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   INIT
    //////////////////////////////////////////////////////////////////////////*//

    function test_InitWiresAddresses() public view {
        assertEq(adapter.tokenMessenger(), address(messenger));
        assertEq(adapter.messageTransmitter(), address(transmitter));
        assertEq(adapter.usdc(), address(usdcToken));
    }

    /// @dev Only `d.initialize` is wrapped in `expectRevert` (the `CCTPZeroAddress` revert bubbles up through
    ///      {Diamond.initialize}); `deployer` was created in `setUp`.
    function _expectZeroAddressInitRevert(address tm, address mt, address u) internal {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, tm, mt, u);
        Diamond d = new Diamond();
        vm.expectRevert(ICCTPBridgeAdapter.CCTPZeroAddress.selector);
        d.initialize(cuts, init, initCalldata);
    }

    function test_InitRejectsZeroTokenMessenger() public {
        _expectZeroAddressInitRevert(address(0), address(transmitter), address(usdcToken));
    }

    function test_InitRejectsZeroTransmitter() public {
        _expectZeroAddressInitRevert(address(messenger), address(0), address(usdcToken));
    }

    function test_InitRejectsZeroUsdc() public {
        _expectZeroAddressInitRevert(address(messenger), address(transmitter), address(0));
    }

    function test_SupportsInterface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(ICCTPBridgeAdapter).interfaceId));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegisterChainDomain() public view {
        assertTrue(adapter.isChainRegistered(BASE_CHAIN));
        assertEq(adapter.getDomain(BASE_CHAIN), BASE_DOMAIN);
    }

    /// @notice Domain 0 (Ethereum) must be distinguishable from an unregistered chain via the registered flag.
    function test_RegisterChainDomainZeroDomainDistinguished() public view {
        assertTrue(adapter.isChainRegistered(ETH_CHAIN));
        assertEq(adapter.getDomain(ETH_CHAIN), ETH_DOMAIN);
        assertFalse(adapter.isChainRegistered(999)); // never registered
        assertEq(adapter.getDomain(999), 0);
    }

    function test_RegisterChainDomainRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.registerChainDomain(42, 7);
    }

    function test_ConfigureDomain() public view {
        (uint256 maxFee, uint32 minFinality, bytes32 destCaller) = adapter.getDomainConfig(BASE_DOMAIN);
        assertEq(maxFee, MAX_FEE);
        assertEq(minFinality, MIN_FINALITY);
        assertEq(destCaller, DEST_CALLER);
    }

    function test_ConfigureDomainRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.configureDomain(BASE_DOMAIN, 1, 1, bytes32(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   BURN
    //////////////////////////////////////////////////////////////////////////*//

    function _fund(uint256 amount) internal {
        usdcToken.mint(user, amount);
        vm.prank(user);
        usdcToken.approve(diamond, amount);
    }

    function test_DepositForBurnHappyPath() public {
        uint256 amount = 1_000_000; // 1 USDC
        _fund(amount);

        vm.prank(user);
        adapter.depositForBurn(amount, recip);

        // Args recorded by the messenger (domain mapping + bytes32 mintRecipient down-convert + per-domain config).
        assertEq(messenger.calls(), 1);
        assertFalse(messenger.lastWasHook(), "took the plain 7-arg depositForBurn path");
        assertEq(messenger.lastAmount(), amount);
        assertEq(messenger.lastDestinationDomain(), BASE_DOMAIN, "chainId -> CCTP domain");
        assertEq(messenger.lastMintRecipient(), bytes32(uint256(uint160(evmRecipient))), "20-byte down-convert");
        assertEq(messenger.lastBurnToken(), address(usdcToken));
        assertEq(messenger.lastDestinationCaller(), DEST_CALLER);
        assertEq(messenger.lastMaxFee(), MAX_FEE);
        assertEq(messenger.lastMinFinalityThreshold(), MIN_FINALITY);
    }

    function test_DepositForBurnExactApprovalGranted() public {
        uint256 amount = 2_500_000;
        _fund(amount);
        vm.prank(user);
        adapter.depositForBurn(amount, recip);
        assertEq(messenger.allowanceSeen(), amount, "messenger granted EXACTLY amount");
    }

    /// @notice Approval hygiene: the allowance is reset to 0 even when the messenger does NOT consume it.
    function test_DepositForBurnResetsAllowanceToZero() public {
        messenger.setPullFunds(false); // messenger leaves the allowance untouched
        uint256 amount = 3_000_000;
        _fund(amount);
        vm.prank(user);
        adapter.depositForBurn(amount, recip);
        assertEq(messenger.allowanceSeen(), amount, "exact allowance at burn time");
        assertEq(usdcToken.allowance(diamond, address(messenger)), 0, "allowance reset to 0 (hygiene)");
    }

    /// @notice The USDC is pulled from the caller (not the Diamond), and none is left stuck in the Diamond.
    function test_DepositForBurnPullsFromCallerNoStuck() public {
        uint256 amount = 4_000_000;
        _fund(amount);
        vm.prank(user);
        adapter.depositForBurn(amount, recip);
        assertEq(usdcToken.balanceOf(user), 0, "pulled from caller");
        assertEq(usdcToken.balanceOf(diamond), 0, "no USDC stuck in the Diamond");
        assertEq(usdcToken.balanceOf(address(messenger)), amount, "messenger burned the amount");
    }

    /// @notice A 32-byte non-EVM recipient is passed to CCTP verbatim as the bytes32 mintRecipient.
    function test_DepositForBurnNonEvmRecipient() public {
        uint256 solanaChain = 501; // arbitrary admin-registered id for a Solana-like domain
        uint32 solanaDomain = 5;
        bytes32 solanaKey = keccak256("solana-recipient");
        vm.prank(admin);
        adapter.registerChainDomain(solanaChain, solanaDomain);

        // ERC-7930 with a chain reference that decodes to `solanaChain` and a full 32-byte address.
        bytes memory ref = abi.encodePacked(uint16(solanaChain)); // 0x01F5 -> 501
        bytes memory nonEvmRecip = NonEvmAddress.formatV1(0x0002, ref, solanaKey);

        uint256 amount = 1_000_000;
        _fund(amount);
        vm.prank(user);
        adapter.depositForBurn(amount, nonEvmRecip);

        assertEq(messenger.lastDestinationDomain(), solanaDomain);
        assertEq(messenger.lastMintRecipient(), solanaKey, "32-byte non-EVM recipient verbatim");
    }

    function test_DepositForBurnEmitsEvent() public {
        uint256 amount = 1_000_000;
        _fund(amount);
        vm.expectEmit(true, true, false, true, diamond);
        emit ICCTPBridgeAdapter.DepositForBurn(
            user, BASE_CHAIN, BASE_DOMAIN, bytes32(uint256(uint160(evmRecipient))), amount
        );
        vm.prank(user);
        adapter.depositForBurn(amount, recip);
    }

    function test_DepositForBurnUnknownDestinationReverts() public {
        bytes memory unknown = InteroperableAddress.formatEvmV1(4242, evmRecipient);
        _fund(1_000_000);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ICCTPBridgeAdapter.CCTPUnknownDestinationChain.selector, 4242));
        adapter.depositForBurn(1_000_000, unknown);
    }

    function test_DepositForBurnNoApprovalReverts() public {
        usdcToken.mint(user, 1_000_000); // minted, not approved to the diamond
        vm.prank(user);
        vm.expectRevert(); // pullExact transferFrom underflows without allowance
        adapter.depositForBurn(1_000_000, recip);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   RELAY
    //////////////////////////////////////////////////////////////////////////*//

    function test_RelayMessagePermissionlessSuccess() public {
        bytes memory message = hex"deadbeef";
        bytes memory attestation = hex"c0ffee";

        // Any address may relay (permissionless).
        vm.prank(relayer);
        adapter.relayMessage(message, attestation);

        assertEq(transmitter.calls(), 1);
        assertEq(transmitter.lastMessage(), message);
        assertEq(transmitter.lastAttestation(), attestation);
        assertEq(transmitter.lastCaller(), diamond, "transmitter called by the Diamond");
    }

    function test_RelayMessageEmitsEvent() public {
        vm.expectEmit(true, false, false, false, diamond);
        emit ICCTPBridgeAdapter.RelayedMessage(relayer);
        vm.prank(relayer);
        adapter.relayMessage(hex"01", hex"02");
    }

    function test_RelayMessageRevertsOnFalse() public {
        transmitter.setReceiveResult(false);
        vm.prank(relayer);
        vm.expectRevert(ICCTPBridgeAdapter.CCTPRelayFailed.selector);
        adapter.relayMessage(hex"01", hex"02");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            maxFee GUARD (OUTBOUND)
    //////////////////////////////////////////////////////////////////////////*//

    function test_DepositForBurnMaxFeeEqualAmountReverts() public {
        _fund(MAX_FEE);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ICCTPBridgeAdapter.CCTPMaxFeeExceedsAmount.selector, MAX_FEE, MAX_FEE));
        adapter.depositForBurn(MAX_FEE, recip); // amount == maxFee → CCTP requires amount > maxFee
    }

    function test_DepositForBurnMaxFeeAboveAmountReverts() public {
        uint256 amount = MAX_FEE - 1;
        _fund(amount);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ICCTPBridgeAdapter.CCTPMaxFeeExceedsAmount.selector, MAX_FEE, amount));
        adapter.depositForBurn(amount, recip);
    }

    function test_DepositForBurnZeroAmountReverts() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ICCTPBridgeAdapter.CCTPMaxFeeExceedsAmount.selector, MAX_FEE, 0));
        adapter.depositForBurn(0, recip);
    }

    function test_DepositForBurnMaxFeeBoundaryPasses() public {
        uint256 amount = MAX_FEE + 1; // maxFee == amount - 1 → the tightest passing burn
        _fund(amount);
        vm.prank(user);
        adapter.depositForBurn(amount, recip);
        assertEq(messenger.calls(), 1);
        assertEq(messenger.lastAmount(), amount);
        assertEq(messenger.lastMaxFee(), MAX_FEE);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            OUTBOUND HOOKS
    //////////////////////////////////////////////////////////////////////////*//

    function test_DepositForBurnWithHookHappyPath() public {
        uint256 amount = 1_000_000;
        bytes memory hookData = _latticeHookData(address(hookReceiver), hex"cafe1234");
        _fund(amount);

        vm.prank(user);
        adapter.depositForBurnWithHook(amount, recip, hookData);

        assertEq(messenger.calls(), 1);
        assertTrue(messenger.lastWasHook(), "took the depositForBurnWithHook path");
        assertEq(messenger.lastAmount(), amount);
        assertEq(messenger.lastDestinationDomain(), BASE_DOMAIN);
        assertEq(messenger.lastMintRecipient(), bytes32(uint256(uint160(evmRecipient))));
        assertEq(messenger.lastBurnToken(), address(usdcToken));
        assertEq(messenger.lastDestinationCaller(), DEST_CALLER);
        assertEq(messenger.lastMaxFee(), MAX_FEE);
        assertEq(messenger.lastMinFinalityThreshold(), MIN_FINALITY);
        assertEq(messenger.lastHookData(), hookData, "hookData forwarded verbatim");
    }

    function test_DepositForBurnWithHookEmptyHookDataReverts() public {
        _fund(1_000_000);
        vm.prank(user);
        vm.expectRevert(ICCTPBridgeAdapter.CCTPEmptyHookData.selector);
        adapter.depositForBurnWithHook(1_000_000, recip, hex"");
    }

    function test_DepositForBurnWithHookUnknownDestinationReverts() public {
        bytes memory unknown = InteroperableAddress.formatEvmV1(4242, evmRecipient);
        bytes memory hookData = _latticeHookData(address(hookReceiver), hex"01");
        _fund(1_000_000);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ICCTPBridgeAdapter.CCTPUnknownDestinationChain.selector, 4242));
        adapter.depositForBurnWithHook(1_000_000, unknown, hookData);
    }

    function test_DepositForBurnWithHookMaxFeeGuard() public {
        bytes memory hookData = _latticeHookData(address(hookReceiver), hex"01");
        _fund(MAX_FEE);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ICCTPBridgeAdapter.CCTPMaxFeeExceedsAmount.selector, MAX_FEE, MAX_FEE));
        adapter.depositForBurnWithHook(MAX_FEE, recip, hookData);
    }

    function test_DepositForBurnWithHookExactApprovalAndReset() public {
        messenger.setPullFunds(false); // leave the allowance untouched so the reset is observable
        uint256 amount = 3_000_000;
        bytes memory hookData = _latticeHookData(address(hookReceiver), hex"aa");
        _fund(amount);
        vm.prank(user);
        adapter.depositForBurnWithHook(amount, recip, hookData);
        assertEq(messenger.allowanceSeen(), amount, "messenger granted EXACTLY amount");
        assertEq(usdcToken.allowance(diamond, address(messenger)), 0, "allowance reset to 0 (hygiene)");
    }

    function test_DepositForBurnWithHookPullsFromCallerNoStuck() public {
        uint256 amount = 4_000_000;
        bytes memory hookData = _latticeHookData(address(hookReceiver), hex"bb");
        _fund(amount);
        vm.prank(user);
        adapter.depositForBurnWithHook(amount, recip, hookData);
        assertEq(usdcToken.balanceOf(user), 0, "pulled from caller");
        assertEq(usdcToken.balanceOf(diamond), 0, "no USDC stuck in the diamond");
        assertEq(usdcToken.balanceOf(address(messenger)), amount, "messenger burned the amount");
    }

    function test_DepositForBurnWithHookEmitsEvent() public {
        uint256 amount = 1_000_000;
        bytes memory hookData = _latticeHookData(address(hookReceiver), hex"deadbeef");
        _fund(amount);
        vm.expectEmit(true, true, false, true, diamond);
        emit ICCTPBridgeAdapter.DepositForBurnWithHook(
            user, BASE_CHAIN, BASE_DOMAIN, bytes32(uint256(uint160(evmRecipient))), amount, hookData
        );
        vm.prank(user);
        adapter.depositForBurnWithHook(amount, recip, hookData);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          EXECUTOR + INIT
    //////////////////////////////////////////////////////////////////////////*//

    function test_HookExecutorWiredAtInit() public view {
        address exec = adapter.hookExecutor();
        assertTrue(exec != address(0), "executor deployed at init");
        assertGt(exec.code.length, 0, "executor has code");
        assertEq(ICCTPHookExecutor(exec).relay(), diamond, "executor bound to the diamond as relay");
    }

    function test_HookExecutorDirectCallReverts() public {
        ICCTPHookExecutor exec = ICCTPHookExecutor(adapter.hookExecutor());
        vm.prank(user); // anyone other than the diamond
        vm.expectRevert(ICCTPHookExecutor.CCTPHookExecutorUnauthorized.selector);
        exec.executeHook(SRC_DOMAIN, SENDER, bytes32(0), HOOK_AMOUNT, NONCE, address(hookReceiver), hex"01");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          INBOUND HOOKS
    //////////////////////////////////////////////////////////////////////////*//

    function test_RelayMessageIgnoresHookData() public {
        bytes memory message = _validHookedMessage(address(hookReceiver), hex"1122");
        vm.prank(relayer);
        adapter.relayMessage(message, hex"c0ffee"); // plain relay never touches the executor

        assertEq(transmitter.calls(), 1, "transmitter minted");
        assertEq(hookReceiver.calls(), 0, "hook receiver NEVER called by the plain relay");
    }

    function test_RelayMessageWithHookExecutesHook() public {
        bytes memory payload = hex"1122334455";
        bytes memory message = _validHookedMessage(address(hookReceiver), payload);

        vm.prank(relayer);
        adapter.relayMessageWithHook(message, hex"c0ffee");

        assertEq(transmitter.calls(), 1, "transmitter minted");
        assertEq(hookReceiver.calls(), 1, "hook receiver called exactly once");
        assertEq(hookReceiver.lastCaller(), adapter.hookExecutor(), "called BY the executor, not the diamond");
        assertTrue(hookReceiver.lastCaller() != diamond, "definitively not the diamond");
        assertEq(hookReceiver.lastSourceDomain(), SRC_DOMAIN, "attested source domain");
        assertEq(hookReceiver.lastSender(), SENDER, "attested sender");
        assertEq(hookReceiver.lastMintRecipient(), bytes32(uint256(uint160(evmRecipient))), "attested mintRecipient");
        assertEq(hookReceiver.lastAmount(), HOOK_AMOUNT, "attested amount");
        assertEq(hookReceiver.lastPayload(), payload, "payload forwarded verbatim");
    }

    function test_RelayMessageWithHookEmitsHookExecuted() public {
        bytes memory message = _validHookedMessage(address(hookReceiver), hex"01");
        vm.expectEmit(true, true, false, true, diamond);
        emit ICCTPBridgeAdapter.HookExecuted(NONCE, address(hookReceiver), true);
        vm.prank(relayer);
        adapter.relayMessageWithHook(message, hex"01");
    }

    function test_RelayMessageWithHookRevertingHookDoesNotRevertRelay() public {
        hookReceiver.setShouldRevert(true);
        bytes memory message = _validHookedMessage(address(hookReceiver), hex"01");

        vm.expectEmit(true, true, false, true, diamond);
        emit ICCTPBridgeAdapter.HookExecuted(NONCE, address(hookReceiver), false); // lenient: relay still completes
        vm.prank(relayer);
        adapter.relayMessageWithHook(message, hex"01");

        assertEq(transmitter.calls(), 1, "mint still happened despite the reverting hook");
    }

    function test_RelayMessageWithHookGarbageEnvelopeReverts() public {
        // (a) leading bytes are not HOOK_MAGIC.
        bytes memory badMagic = abi.encodePacked(bytes4(0xdeadbeef), bytes20(address(hookReceiver)), hex"01");
        bytes memory msgA =
            _buildMessage(1, SRC_DOMAIN, NONCE, address(messenger), 1, bytes32(0), HOOK_AMOUNT, SENDER, badMagic);
        vm.prank(relayer);
        vm.expectRevert(ICCTPBridgeAdapter.CCTPInvalidHookData.selector);
        adapter.relayMessageWithHook(msgA, hex"01");
        assertEq(transmitter.calls(), 0, "transmitter NOT called on garbage magic");

        // (b) envelope shorter than 24 bytes (magic + partial target).
        bytes memory tooShort = abi.encodePacked(HOOK_MAGIC, bytes8(0));
        bytes memory msgB =
            _buildMessage(1, SRC_DOMAIN, NONCE, address(messenger), 1, bytes32(0), HOOK_AMOUNT, SENDER, tooShort);
        vm.prank(relayer);
        vm.expectRevert(ICCTPBridgeAdapter.CCTPInvalidHookData.selector);
        adapter.relayMessageWithHook(msgB, hex"01");
        assertEq(transmitter.calls(), 0, "transmitter NOT called on short envelope");
    }

    function test_RelayMessageWithHookNonBurnMessageReverts() public {
        // header recipient != this adapter's TokenMessenger.
        bytes memory message = _buildMessage(
            1,
            SRC_DOMAIN,
            NONCE,
            address(0xBAD),
            1,
            bytes32(0),
            HOOK_AMOUNT,
            SENDER,
            _latticeHookData(address(hookReceiver), hex"01")
        );
        vm.prank(relayer);
        vm.expectRevert(ICCTPBridgeAdapter.CCTPNotBurnMessage.selector);
        adapter.relayMessageWithHook(message, hex"01");
        assertEq(transmitter.calls(), 0, "transmitter NOT called on non-burn message");
    }

    function test_RelayMessageWithHookWrongHeaderVersionReverts() public {
        // headerVersion = 0 (not the CCTP v2 discriminant 1), bodyVersion = 1.
        bytes memory message = _buildMessage(
            0,
            SRC_DOMAIN,
            NONCE,
            address(messenger),
            1,
            bytes32(0),
            HOOK_AMOUNT,
            SENDER,
            _latticeHookData(address(hookReceiver), hex"01")
        );
        vm.prank(relayer);
        vm.expectRevert(ICCTPBridgeAdapter.CCTPNotBurnMessage.selector);
        adapter.relayMessageWithHook(message, hex"01");
        assertEq(transmitter.calls(), 0, "transmitter NOT called on wrong header version");
    }

    function test_RelayMessageWithHookWrongBodyVersionReverts() public {
        // headerVersion = 1, bodyVersion = 0 (not the CCTP v2 discriminant 1).
        bytes memory message = _buildMessage(
            1,
            SRC_DOMAIN,
            NONCE,
            address(messenger),
            0,
            bytes32(0),
            HOOK_AMOUNT,
            SENDER,
            _latticeHookData(address(hookReceiver), hex"01")
        );
        vm.prank(relayer);
        vm.expectRevert(ICCTPBridgeAdapter.CCTPNotBurnMessage.selector);
        adapter.relayMessageWithHook(message, hex"01");
        assertEq(transmitter.calls(), 0, "transmitter NOT called on wrong body version");
    }

    function test_RelayMessageWithHookShortMessageReverts() public {
        bytes memory tooShort = new bytes(375); // one byte under the 376 minimum
        vm.prank(relayer);
        vm.expectRevert(ICCTPBridgeAdapter.CCTPNotBurnMessage.selector);
        adapter.relayMessageWithHook(tooShort, hex"01");
        assertEq(transmitter.calls(), 0, "transmitter NOT called on short message");
    }

    function test_RelayMessageWithHookTransmitterFalseReverts() public {
        transmitter.setReceiveResult(false);
        bytes memory message = _validHookedMessage(address(hookReceiver), hex"01");
        vm.prank(relayer);
        vm.expectRevert(ICCTPBridgeAdapter.CCTPRelayFailed.selector);
        adapter.relayMessageWithHook(message, hex"01");
        assertEq(hookReceiver.calls(), 0, "hook NEVER runs when the mint fails");
    }

    function test_RelayMessageWithHookReentrancyBlocked() public {
        hookReceiver.setReenterTarget(diamond); // hostile: re-enter the diamond's guarded relay
        bytes memory message = _validHookedMessage(address(hookReceiver), hex"01");

        vm.expectEmit(true, true, false, true, diamond);
        emit ICCTPBridgeAdapter.HookExecuted(NONCE, address(hookReceiver), false); // inner reverts on the guard
        vm.prank(relayer);
        adapter.relayMessageWithHook(message, hex"01");

        assertEq(transmitter.calls(), 1, "only the OUTER relay minted (inner reentry hit the guard)");
    }

    function test_HookExecutorReturnBombTolerated() public {
        hookReceiver.setReturnBomb(true); // returns 256 KiB of returndata
        bytes memory message = _validHookedMessage(address(hookReceiver), hex"01");

        vm.expectEmit(true, true, false, true, diamond);
        emit ICCTPBridgeAdapter.HookExecuted(NONCE, address(hookReceiver), true); // return-bomb is a SUCCESSFUL return
        vm.prank(relayer);
        // Bounded gas so a returndata-COPYING executor (a mutant using `(bool ok, bytes memory ret) = call(...)`)
        // OOGs on the 256 KiB copy while the real zero-copy executor (~660k) completes within the stipend.
        adapter.relayMessageWithHook{gas: 750_000}(message, hex"01");

        assertEq(transmitter.calls(), 1, "relay succeeded despite the return bomb");
    }

    /// @notice The hook receives the amount ACTUALLY MINTED — burn `amount` (@216) minus `feeExecuted` (@312) —
    ///         not the gross burn amount (CCTP v2 nets the fee at mint time on fast transfers).
    function test_RelayMessageWithHookNetsFeeFromMintedAmount() public {
        uint256 fee = 1_500;
        bytes memory message = _validHookedMessageWithFee(address(hookReceiver), hex"1122", fee);
        vm.prank(relayer);
        adapter.relayMessageWithHook(message, hex"01");
        assertEq(hookReceiver.calls(), 1);
        assertEq(hookReceiver.lastAmount(), HOOK_AMOUNT - fee, "hook sees minted amount = burn amount - feeExecuted");
    }

    /// @notice GROUNDS the parse offsets against Circle's ACTUAL bytes: loads the REAL captured 376-byte
    ///         header+body (Sepolia->Base Sepolia), appends a synthetic Lattice envelope, and drives it through
    ///         `relayMessageWithHook` — asserting the parser reproduces Circle's INDEPENDENTLY-DECODED
    ///         sourceDomain / nonce / mintRecipient / minted-amount. A shared wrong offset in the builder AND
    ///         parser would agree with each other but NOT with these real Circle-decoded truth values. Runs with
    ///         no RPC (foundry.toml grants `test/fixtures` read).
    function test_RelayMessageWithHookGroundsOffsetsOnRealFixture() public {
        string memory json = vm.readFile("test/fixtures/cctp/sepolia-to-base-sepolia-v2.json");
        bytes memory realMsg = vm.parseJsonBytes(json, ".message");
        if (realMsg.length == 0) {
            vm.skip(true); // fixture not yet captured — see the file's provenance/TODO
            return;
        }
        assertEq(realMsg.length, 376, "fixture message must be the 376-byte header+body (no hookData)");

        uint32 realSourceDomain = uint32(vm.parseJsonUint(json, ".sourceDomain"));
        bytes32 realNonce = vm.parseJsonBytes32(json, ".nonce");
        address realRecipient = vm.parseJsonAddress(json, ".recipient");
        uint256 realAmount = vm.parseJsonUint(json, ".amount");
        uint256 realFee = vm.parseJsonUint(json, ".feeExecuted");
        // The fixture's header recipient (@76) — a real Base Sepolia TokenMessengerV2 address.
        address realHeaderRecipient = 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA;

        // A diamond wired to that REAL header recipient so the burn-message check passes; the mock transmitter
        // (returns true) stands in for MessageTransmitterV2.
        address destDiamond =
            _deployCCTPBridgeAdapter(admin, realHeaderRecipient, address(transmitter), address(usdcToken));
        CCTPBridgeAdapter dest = CCTPBridgeAdapter(destDiamond);

        // Append a synthetic Lattice envelope to Circle's REAL 376-byte header+body.
        bytes memory payload = bytes("grounding-payload");
        bytes memory grounded = abi.encodePacked(realMsg, HOOK_MAGIC, bytes20(address(hookReceiver)), payload);

        // The nonce grounding (@12) is asserted via HookExecuted (nonce is not an onCCTPHook arg).
        vm.expectEmit(true, true, false, true, destDiamond);
        emit ICCTPBridgeAdapter.HookExecuted(realNonce, address(hookReceiver), true);
        vm.prank(relayer);
        dest.relayMessageWithHook(grounded, hex"01");

        assertEq(hookReceiver.calls(), 1, "hook executed against Circle's real bytes");
        assertEq(hookReceiver.lastSourceDomain(), realSourceDomain, "sourceDomain @4 grounded to Circle's value");
        assertEq(
            hookReceiver.lastMintRecipient(),
            bytes32(uint256(uint160(realRecipient))),
            "mintRecipient @184 grounded to Circle's value"
        );
        assertEq(hookReceiver.lastAmount(), realAmount - realFee, "minted amount (@216 - @312) grounded");
        assertEq(hookReceiver.lastPayload(), payload, "payload from the appended envelope");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          INBOUND MESSAGE BUILDERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev A Lattice hook envelope: `HOOK_MAGIC ‖ target(20) ‖ payload`.
    function _latticeHookData(address target, bytes memory payload) internal pure returns (bytes memory) {
        return abi.encodePacked(HOOK_MAGIC, bytes20(target), payload);
    }

    /// @dev A valid 376+ byte CCTP v2 BurnMessageV2 toward this adapter's TokenMessenger carrying `hookData`.
    function _validHookedMessage(address target, bytes memory payload) internal view returns (bytes memory) {
        return _buildMessage(
            1,
            SRC_DOMAIN,
            NONCE,
            address(messenger),
            1,
            bytes32(uint256(uint160(evmRecipient))),
            HOOK_AMOUNT,
            SENDER,
            _latticeHookData(target, payload)
        );
    }

    /// @dev A valid BurnMessageV2 with a NONZERO `feeExecuted` — the minted amount is `amount - feeExecuted`.
    function _validHookedMessageWithFee(address target, bytes memory payload, uint256 feeExecuted)
        internal
        view
        returns (bytes memory)
    {
        return _buildMessageWithFee(
            1,
            SRC_DOMAIN,
            NONCE,
            address(messenger),
            1,
            bytes32(uint256(uint160(evmRecipient))),
            HOOK_AMOUNT,
            SENDER,
            feeExecuted,
            _latticeHookData(target, payload)
        );
    }

    /// @dev Assembles a MessageV2 header + BurnMessageV2 body with `hookData` at the exact 376-byte offset. Every
    ///      field lands at its Circle byte offset (header 148 B, body-before-hookData 228 B). `feeExecuted` is 0.
    function _buildMessage(
        uint32 headerVersion,
        uint32 sourceDomain,
        bytes32 nonce,
        address headerRecipient,
        uint32 bodyVersion,
        bytes32 mintRecipient,
        uint256 amount,
        bytes32 messageSender,
        bytes memory hookData
    ) internal pure returns (bytes memory) {
        return _buildMessageWithFee(
            headerVersion,
            sourceDomain,
            nonce,
            headerRecipient,
            bodyVersion,
            mintRecipient,
            amount,
            messageSender,
            0,
            hookData
        );
    }

    /// @dev As {_buildMessage} but with an explicit `feeExecuted` at body @164 (abs @312).
    function _buildMessageWithFee(
        uint32 headerVersion,
        uint32 sourceDomain,
        bytes32 nonce,
        address headerRecipient,
        uint32 bodyVersion,
        bytes32 mintRecipient,
        uint256 amount,
        bytes32 messageSender,
        uint256 feeExecuted,
        bytes memory hookData
    ) internal pure returns (bytes memory) {
        bytes memory header = abi.encodePacked(
            headerVersion, // version                   uint32  @0
            sourceDomain, // sourceDomain               uint32  @4
            uint32(0), // destinationDomain             uint32  @8
            nonce, // nonce                             bytes32 @12
            bytes32(0), // sender                       bytes32 @44
            bytes32(uint256(uint160(headerRecipient))), // recipient bytes32 @76
            bytes32(0), // destinationCaller            bytes32 @108
            uint32(0), // minFinalityThreshold          uint32  @140
            uint32(0) // finalityThresholdExecuted      uint32  @144
        );
        bytes memory body = abi.encodePacked(
            bodyVersion, // version                      uint32  @148 (body 0)
            bytes32(0), // burnToken                     bytes32 @152 (body 4)
            mintRecipient, // mintRecipient              bytes32 @184 (body 36)
            amount, // amount                            uint256 @216 (body 68)
            messageSender, // messageSender              bytes32 @248 (body 100)
            uint256(0), // maxFee                        uint256 @280 (body 132)
            feeExecuted, // feeExecuted                  uint256 @312 (body 164)
            uint256(0), // expirationBlock               uint256 @344 (body 196)
            hookData //                                          @376 (body 228)
        );
        return abi.encodePacked(header, body);
    }
}
