// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {CCTPBridgeAdapterTestBase} from "@lattice-test/base/CCTPBridgeAdapterTestBase.sol";
import {CCTPBridgeAdapter} from "@lattice/crosschain/CCTPBridgeAdapter.sol";
import {NonEvmAddress} from "@lattice/crosschain/libraries/NonEvmAddress.sol";
import {ICCTPBridgeAdapter} from "@lattice/interfaces/crosschain/ICCTPBridgeAdapter.sol";
import {IReceiverV2} from "@lattice/interfaces/external/IReceiverV2.sol";
import {ITokenMessengerV2} from "@lattice/interfaces/external/ITokenMessengerV2.sol";
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

    function setUp() public {
        messenger = new MockTokenMessenger();
        transmitter = new MockMessageTransmitter();
        usdcToken = new MockUSDC();

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
}
