// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CCTPBridgeAdapterTestBase} from "@lattice-test/base/CCTPBridgeAdapterTestBase.sol";
import {HOOK_MAGIC} from "@lattice/crosschain/libraries/CCTPBridgeAdapterLib.sol";
import {CCTPHookVault} from "@lattice/examples/crosschain/CCTPHookVault.sol";
import {ICCTPBridgeAdapter} from "@lattice/interfaces/crosschain/ICCTPBridgeAdapter.sol";
import {IReceiverV2} from "@lattice/interfaces/external/circle/IReceiverV2.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";

/// @notice Minimal USDC-like ERC-20 (mint/approve/transfer/transferFrom) for the vault tests.
contract MockUSDC is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function name() external pure returns (string memory) {
        return "USDC";
    }

    function symbol() external pure returns (string memory) {
        return "USDC";
    }

    function decimals() external pure returns (uint8) {
        return 6;
    }
}

/// @notice Passthrough transmitter: relayMessageWithHook calls receiveMessage, which we accept (mint is modelled
///         by dealing/minting USDC to the vault directly in the integration test).
contract MockTransmitter is IReceiverV2 {
    function receiveMessage(bytes calldata, bytes calldata) external pure returns (bool) {
        return true;
    }

    function localDomain() external pure returns (uint32) {
        return 6;
    }
}

/// @notice Hostile USDC-like token whose `transfer` re-enters the paying vault mid-withdraw to read the
///         recipient's remaining credit. Standalone (MockUSDC's methods are not virtual) — it lets a test prove
///         withdraw follows checks-effects-interactions: the caller's credit is already zeroed BEFORE the USDC
///         leaves the vault, so a re-entrant read sees 0. A mutant that moves the debit after the transfer would
///         instead expose the pre-debit credit here.
contract ReentrantObserverUSDC is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    CCTPHookVault public vault;
    uint256 public observedCredit; // creditOf(recipient) seen DURING the transfer
    bool public reentered;

    function setVault(CCTPHookVault vault_) external {
        vault = vault_;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (address(vault) != address(0)) {
            reentered = true;
            observedCredit = vault.creditOf(to); // re-entrant read while the vault is mid-payout
        }
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function name() external pure returns (string memory) {
        return "rUSDC";
    }

    function symbol() external pure returns (string memory) {
        return "rUSDC";
    }

    function decimals() external pure returns (uint8) {
        return 6;
    }
}

/// @title CCTPHookVaultTest
/// @notice Unit + integration coverage for {CCTPHookVault}: the executor-only + mint-recipient-backed credit
///         invariants, the withdraw CEI path, and the full real-diamond inbound path
///         (relayMessageWithHook -> CCTPHookExecutor -> onCCTPHook -> credit).
contract CCTPHookVaultTest is CCTPBridgeAdapterTestBase {
    MockUSDC internal usdc;

    address internal constant EXECUTOR = address(0xE0E0);
    address internal constant BENEFICIARY = address(0xBEEF);
    uint32 internal constant SRC_DOMAIN = 26; // Arc, the showcase source
    bytes32 internal constant SENDER = bytes32(uint256(0x50271CE)); // burner on the source domain
    uint256 internal constant AMOUNT = 1_000_000; // 1 USDC (6dp)

    function setUp() public {
        usdc = new MockUSDC();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           UNIT: constructor + guards
    //////////////////////////////////////////////////////////////////////////*//

    function test_ConstructorRejectsZeroExecutor() public {
        vm.expectRevert(CCTPHookVault.CCTPHookVault__ZeroAddress.selector);
        new CCTPHookVault(address(0), address(usdc));
    }

    function test_ConstructorRejectsZeroUsdc() public {
        vm.expectRevert(CCTPHookVault.CCTPHookVault__ZeroAddress.selector);
        new CCTPHookVault(EXECUTOR, address(0));
    }

    function test_OnCCTPHookRevertsNonExecutor() public {
        CCTPHookVault vault = new CCTPHookVault(EXECUTOR, address(usdc));
        vm.expectRevert(CCTPHookVault.CCTPHookVault__NotExecutor.selector);
        vault.onCCTPHook(SRC_DOMAIN, SENDER, _b32(address(vault)), AMOUNT, abi.encodePacked(BENEFICIARY));
    }

    function test_OnCCTPHookRevertsWrongMintRecipient() public {
        CCTPHookVault vault = new CCTPHookVault(EXECUTOR, address(usdc));
        // mintRecipient is someone else -> the credit would be unbacked -> reject.
        vm.prank(EXECUTOR);
        vm.expectRevert(CCTPHookVault.CCTPHookVault__NotMintRecipient.selector);
        vault.onCCTPHook(SRC_DOMAIN, SENDER, _b32(address(0xDEAD)), AMOUNT, abi.encodePacked(BENEFICIARY));
    }

    function test_OnCCTPHookRevertsBadPayload() public {
        CCTPHookVault vault = new CCTPHookVault(EXECUTOR, address(usdc));
        vm.prank(EXECUTOR);
        vm.expectRevert(CCTPHookVault.CCTPHookVault__BadPayload.selector);
        vault.onCCTPHook(SRC_DOMAIN, SENDER, _b32(address(vault)), AMOUNT, hex"deadbeef"); // < 20 bytes
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           UNIT: credit + withdraw
    //////////////////////////////////////////////////////////////////////////*//

    function test_OnCCTPHookCreditsBeneficiary() public {
        CCTPHookVault vault = new CCTPHookVault(EXECUTOR, address(usdc));
        vm.expectEmit(true, false, false, true, address(vault));
        emit CCTPHookVault.Credited(BENEFICIARY, AMOUNT, SRC_DOMAIN, SENDER);
        vm.prank(EXECUTOR);
        vault.onCCTPHook(SRC_DOMAIN, SENDER, _b32(address(vault)), AMOUNT, abi.encodePacked(BENEFICIARY));

        assertEq(vault.creditOf(BENEFICIARY), AMOUNT, "beneficiary credited");
        assertEq(vault.totalCredited(), AMOUNT, "total credited");
    }

    function test_OnCCTPHookIgnoresPayloadTail() public {
        // Only the first 20 bytes select the beneficiary; a longer payload is fine.
        CCTPHookVault vault = new CCTPHookVault(EXECUTOR, address(usdc));
        vm.prank(EXECUTOR);
        vault.onCCTPHook(SRC_DOMAIN, SENDER, _b32(address(vault)), AMOUNT, abi.encodePacked(BENEFICIARY, uint256(42)));
        assertEq(vault.creditOf(BENEFICIARY), AMOUNT, "credited despite trailing payload bytes");
    }

    function test_OnCCTPHookAccumulatesRepeatedCredits() public {
        // Two hooks to the same beneficiary must ADD (not overwrite): a beneficiary can be bridged to twice.
        CCTPHookVault vault = new CCTPHookVault(EXECUTOR, address(usdc));
        vm.startPrank(EXECUTOR);
        vault.onCCTPHook(SRC_DOMAIN, SENDER, _b32(address(vault)), AMOUNT, abi.encodePacked(BENEFICIARY));
        vault.onCCTPHook(SRC_DOMAIN, SENDER, _b32(address(vault)), AMOUNT, abi.encodePacked(BENEFICIARY));
        vm.stopPrank();

        assertEq(vault.creditOf(BENEFICIARY), 2 * AMOUNT, "credits accumulate across hooks");
        assertEq(vault.totalCredited(), 2 * AMOUNT, "total accumulates across hooks");
    }

    function test_WithdrawTransfersAndClearsCredit() public {
        CCTPHookVault vault = new CCTPHookVault(EXECUTOR, address(usdc));
        // Credit the beneficiary and fund the vault with the corresponding USDC (models the CCTP mint).
        vm.prank(EXECUTOR);
        vault.onCCTPHook(SRC_DOMAIN, SENDER, _b32(address(vault)), AMOUNT, abi.encodePacked(BENEFICIARY));
        usdc.mint(address(vault), AMOUNT);

        vm.expectEmit(true, false, false, true, address(vault));
        emit CCTPHookVault.Withdrawn(BENEFICIARY, AMOUNT);
        vm.prank(BENEFICIARY);
        vault.withdraw(AMOUNT);

        assertEq(usdc.balanceOf(BENEFICIARY), AMOUNT, "USDC delivered to beneficiary");
        assertEq(vault.creditOf(BENEFICIARY), 0, "credit cleared");
        assertEq(vault.totalCredited(), 0, "total cleared");
    }

    function test_WithdrawRevertsInsufficientCredit() public {
        CCTPHookVault vault = new CCTPHookVault(EXECUTOR, address(usdc));
        vm.prank(EXECUTOR);
        vault.onCCTPHook(SRC_DOMAIN, SENDER, _b32(address(vault)), AMOUNT, abi.encodePacked(BENEFICIARY));
        usdc.mint(address(vault), AMOUNT);

        vm.prank(BENEFICIARY);
        vm.expectRevert(CCTPHookVault.CCTPHookVault__InsufficientCredit.selector);
        vault.withdraw(AMOUNT + 1);
    }

    function test_WithdrawTwiceFailsSecondTime() public {
        CCTPHookVault vault = new CCTPHookVault(EXECUTOR, address(usdc));
        vm.prank(EXECUTOR);
        vault.onCCTPHook(SRC_DOMAIN, SENDER, _b32(address(vault)), AMOUNT, abi.encodePacked(BENEFICIARY));
        usdc.mint(address(vault), AMOUNT);

        vm.prank(BENEFICIARY);
        vault.withdraw(AMOUNT);
        vm.prank(BENEFICIARY);
        vm.expectRevert(CCTPHookVault.CCTPHookVault__InsufficientCredit.selector);
        vault.withdraw(1);
    }

    function test_WithdrawPartialKeepsRemainder() public {
        // A partial withdraw must debit ONLY the withdrawn amount and keep the rest withdrawable.
        CCTPHookVault vault = new CCTPHookVault(EXECUTOR, address(usdc));
        vm.prank(EXECUTOR);
        vault.onCCTPHook(SRC_DOMAIN, SENDER, _b32(address(vault)), AMOUNT, abi.encodePacked(BENEFICIARY));
        usdc.mint(address(vault), AMOUNT);

        uint256 part = AMOUNT / 3;
        vm.prank(BENEFICIARY);
        vault.withdraw(part);

        assertEq(usdc.balanceOf(BENEFICIARY), part, "only the partial amount delivered");
        assertEq(vault.creditOf(BENEFICIARY), AMOUNT - part, "remaining credit kept, not zeroed");
        assertEq(vault.totalCredited(), AMOUNT - part, "total reduced by exactly the withdrawn amount");
        assertEq(usdc.balanceOf(address(vault)), AMOUNT - part, "vault still backs the remaining credit");

        // The remainder stays withdrawable.
        vm.prank(BENEFICIARY);
        vault.withdraw(AMOUNT - part);
        assertEq(usdc.balanceOf(BENEFICIARY), AMOUNT, "full amount withdrawn across two calls");
        assertEq(vault.creditOf(BENEFICIARY), 0, "credit fully drained");
    }

    /// @notice withdraw follows checks-effects-interactions: the caller's credit is zeroed BEFORE the USDC
    ///         leaves the vault. Proven with a hostile token that re-enters the vault during the payout and reads
    ///         the recipient's credit — it must observe 0, not the pre-debit balance.
    function test_WithdrawDebitsCreditBeforeTransfer_CEI() public {
        ReentrantObserverUSDC hostile = new ReentrantObserverUSDC();
        CCTPHookVault vault = new CCTPHookVault(EXECUTOR, address(hostile));
        hostile.setVault(vault);

        vm.prank(EXECUTOR);
        vault.onCCTPHook(SRC_DOMAIN, SENDER, _b32(address(vault)), AMOUNT, abi.encodePacked(BENEFICIARY));
        hostile.mint(address(vault), AMOUNT);

        vm.prank(BENEFICIARY);
        vault.withdraw(AMOUNT);

        assertTrue(hostile.reentered(), "token re-entered the vault during the payout");
        assertEq(hostile.observedCredit(), 0, "credit zeroed BEFORE the transfer (checks-effects-interactions)");
        assertEq(hostile.balanceOf(BENEFICIARY), AMOUNT, "beneficiary paid exactly once");
        assertEq(vault.creditOf(BENEFICIARY), 0, "credit cleared");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    INTEGRATION: real diamond -> executor -> vault
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Drives a synthetic Lattice-hook message through a REAL CCTP diamond's relayMessageWithHook: the
    ///         diamond's own {CCTPHookExecutor} (not the diamond) must call the vault's onCCTPHook and credit
    ///         the beneficiary. Proves the vault is a correct hook target end-to-end (mock transmitter only).
    function test_Integration_RelayWithHookCreditsVault() public {
        address messenger = makeAddr("tokenMessenger"); // header-recipient anchor for a burn message
        MockTransmitter transmitter = new MockTransmitter();
        address diamond = _deployCCTPBridgeAdapter(address(this), messenger, address(transmitter), address(usdc));
        address executor = ICCTPBridgeAdapter(diamond).hookExecutor();

        CCTPHookVault vault = new CCTPHookVault(executor, address(usdc));

        // Envelope targets the vault; payload = beneficiary. mintRecipient (body) = the vault.
        bytes memory hookData = abi.encodePacked(HOOK_MAGIC, bytes20(address(vault)), bytes20(BENEFICIARY));
        bytes memory message = _hookMessage(messenger, _b32(address(vault)), AMOUNT, hookData);

        ICCTPBridgeAdapter(diamond).relayMessageWithHook(message, hex"01");

        assertEq(vault.creditOf(BENEFICIARY), AMOUNT, "vault credited beneficiary via the real executor");
        assertEq(vault.totalCredited(), AMOUNT, "vault total credited");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    function _b32(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }

    /// @dev Minimal valid CCTP v2 MessageV2 + BurnMessageV2 with a hook body. Byte offsets per the CCTP v2
    ///      spec: header version 1 at 0, recipient at 76; body version 1 at 148, mintRecipient at 184, amount at
    ///      216, messageSender at 248, feeExecuted 0 at 312, hookData at 376.
    function _hookMessage(address headerRecipient, bytes32 mintRecipient, uint256 amount, bytes memory hookData)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory header = abi.encodePacked(
            uint32(1), // version @0
            SRC_DOMAIN, // sourceDomain @4
            uint32(0), // destinationDomain @8
            bytes32(uint256(0x1234)), // nonce @12
            bytes32(0), // sender @44
            bytes32(uint256(uint160(headerRecipient))), // recipient @76
            bytes32(0), // destinationCaller @108
            uint32(0), // minFinalityThreshold @140
            uint32(0) // finalityThresholdExecuted @144
        );
        bytes memory body = abi.encodePacked(
            uint32(1), // version @148
            bytes32(0), // burnToken @152
            mintRecipient, // mintRecipient @184
            amount, // amount @216
            SENDER, // messageSender @248
            uint256(0), // maxFee @280
            uint256(0), // feeExecuted @312
            uint256(0), // expirationBlock @344
            hookData // @376
        );
        return abi.encodePacked(header, body);
    }
}
