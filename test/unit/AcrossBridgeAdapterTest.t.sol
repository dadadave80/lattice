// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {AcrossBridgeAdapterTestBase} from "@lattice-test/base/AcrossBridgeAdapterTestBase.sol";
import {MockSpokePool} from "@lattice-test/mocks/MockSpokePool.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {AcrossBridgeAdapter} from "@lattice/crosschain/across/AcrossBridgeAdapter.sol";
import {NonEvmAddress} from "@lattice/crosschain/libraries/NonEvmAddress.sol";
import {IAcrossBridgeAdapter} from "@lattice/interfaces/crosschain/IAcrossBridgeAdapter.sol";
import {IReentrancyGuard} from "@lattice/interfaces/security/IReentrancyGuard.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

/// @notice Minimal ERC-20 (mint/approve/transfer/transferFrom) used as the Across input token.
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

/// @notice Reentrancy attacker: an input token whose `transferFrom` re-enters `deposit` on the diamond
///         mid-pull, REQUIRES the re-enter to revert with exactly {ReentrancyGuardReentrantCall} (recorded in
///         `sawGuardRevert`), then completes the transfer normally so the outer deposit succeeds.
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

contract AcrossBridgeAdapterTest is AcrossBridgeAdapterTestBase {
    MockSpokePool pool;
    MockToken token;

    address diamond;
    AcrossBridgeAdapter adapter;

    address user = address(0x2);
    address relayer = address(0x3);
    address evmRecipient = address(0xCAFE);

    uint256 constant DEST_CHAIN = 8453; // Base
    bytes32 constant OUTPUT_TOKEN = bytes32(uint256(uint160(address(0xBEEF))));
    uint256 constant INPUT_AMOUNT = 1 ether;
    uint256 constant OUTPUT_AMOUNT = 0.99 ether;
    bytes32 constant EXCLUSIVE_RELAYER = bytes32(uint256(uint160(address(0xE0))));
    uint32 constant QUOTE_TIMESTAMP = 1_700_000_000;
    uint32 constant FILL_DEADLINE = 1_700_010_000;
    uint32 constant EXCLUSIVITY_PARAM = 300;

    function setUp() public {
        pool = new MockSpokePool();
        token = new MockToken();

        diamond = _deployAcrossBridgeAdapter(address(pool));
        adapter = AcrossBridgeAdapter(diamond);
    }

    function _fund(address who, uint256 amount) internal {
        token.mint(who, amount);
        vm.prank(who);
        token.approve(diamond, amount);
    }

    /// @notice Fully-populated default params toward an EVM (Base) recipient.
    function _defaultParams() internal view returns (IAcrossBridgeAdapter.DepositParams memory p) {
        p = IAcrossBridgeAdapter.DepositParams({
            recipient: InteroperableAddress.formatEvmV1(DEST_CHAIN, evmRecipient),
            outputToken: OUTPUT_TOKEN,
            inputToken: address(token),
            inputAmount: INPUT_AMOUNT,
            outputAmount: OUTPUT_AMOUNT,
            destinationChainId: DEST_CHAIN,
            exclusiveRelayer: EXCLUSIVE_RELAYER,
            quoteTimestamp: QUOTE_TIMESTAMP,
            fillDeadline: FILL_DEADLINE,
            exclusivityParameter: EXCLUSIVITY_PARAM,
            message: hex"deadbeef"
        });
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   INIT
    //////////////////////////////////////////////////////////////////////////*//

    function test_InitWiresSpokePool() public view {
        assertEq(adapter.spokePool(), address(pool));
    }

    /// @dev Only `d.initialize` is wrapped in `expectRevert` (the `AcrossZeroAddress` revert bubbles up through
    ///      {Diamond.initialize}); `deployer` was created in `setUp`. An unconfigured module is impossible:
    ///      this zero-SpokePool init revert is the guarantee.
    function test_InitRejectsZeroSpokePool() public {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(address(0));
        Lattice d = new Lattice();
        vm.expectRevert(IAcrossBridgeAdapter.AcrossZeroAddress.selector);
        d.initialize(cuts, init, initCalldata);
    }

    function test_SupportsInterface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IAcrossBridgeAdapter).interfaceId));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  DEPOSIT
    //////////////////////////////////////////////////////////////////////////*//

    function test_DepositHappyPath() public {
        _fund(user, INPUT_AMOUNT);

        vm.prank(user);
        adapter.deposit(_defaultParams());

        // Every field recorded verbatim by the SpokePool mock.
        assertEq(pool.calls(), 1);
        assertEq(pool.lastDepositor(), bytes32(uint256(uint160(user))), "depositor == pranked user, right-aligned");
        assertEq(pool.lastRecipient(), bytes32(uint256(uint160(evmRecipient))), "recipient parsed from ERC-7930");
        assertEq(pool.lastInputToken(), bytes32(uint256(uint160(address(token)))));
        assertEq(pool.lastOutputToken(), OUTPUT_TOKEN);
        assertEq(pool.lastInputAmount(), INPUT_AMOUNT);
        assertEq(pool.lastOutputAmount(), OUTPUT_AMOUNT);
        assertEq(pool.lastDestinationChainId(), DEST_CHAIN);
        assertEq(pool.lastExclusiveRelayer(), EXCLUSIVE_RELAYER);
        assertEq(pool.lastQuoteTimestamp(), QUOTE_TIMESTAMP);
        assertEq(pool.lastFillDeadline(), FILL_DEADLINE);
        assertEq(pool.lastExclusivityParameter(), EXCLUSIVITY_PARAM, "exclusivityParameter passthrough");
        assertEq(pool.lastMessage(), hex"deadbeef");
    }

    /// @notice REFUND-STRANDING GUARD (regression): Across refunds an expired unfilled deposit ON THIS CHAIN to
    ///         the deposit's `depositor`. If the adapter ever passed `address(this)` (the diamond) instead of
    ///         the calling user, every expired-deposit refund would be stranded in the diamond. This test pins
    ///         `depositor == msg.sender` as bytes32 forever.
    function test_DepositRefundSemanticsDepositorIsUser() public {
        _fund(user, INPUT_AMOUNT);
        vm.prank(user);
        adapter.deposit(_defaultParams());
        assertEq(pool.lastDepositor(), bytes32(uint256(uint160(user))), "refund goes to the user, not the diamond");
        assertTrue(pool.lastDepositor() != bytes32(uint256(uint160(diamond))), "NEVER the diamond");
    }

    function test_DepositExactApprovalGrantedAndReset() public {
        _fund(user, INPUT_AMOUNT);
        vm.prank(user);
        adapter.deposit(_defaultParams());
        assertEq(pool.allowanceSeen(), INPUT_AMOUNT, "SpokePool granted EXACTLY inputAmount");
        assertEq(token.allowance(diamond, address(pool)), 0, "allowance reset to 0 (hygiene)");
    }

    /// @notice Approval hygiene holds even when the SpokePool does NOT consume the allowance.
    function test_DepositResetsAllowanceWhenPoolDoesNotPull() public {
        pool.setPullFunds(false);
        _fund(user, INPUT_AMOUNT);
        vm.prank(user);
        adapter.deposit(_defaultParams());
        assertEq(token.allowance(diamond, address(pool)), 0, "allowance reset to 0 (hygiene)");
    }

    function test_DepositPullsFromCallerNoStuck() public {
        _fund(user, INPUT_AMOUNT);
        vm.prank(user);
        adapter.deposit(_defaultParams());
        assertEq(token.balanceOf(user), 0, "user balance reduced by inputAmount");
        assertEq(token.balanceOf(diamond), 0, "no token stuck in the diamond");
        assertEq(token.balanceOf(address(pool)), INPUT_AMOUNT, "SpokePool escrowed the input");
    }

    function test_DepositEmitsEvent() public {
        _fund(user, INPUT_AMOUNT);
        vm.expectEmit(true, true, false, true, diamond);
        emit IAcrossBridgeAdapter.AcrossDepositSent(
            user,
            DEST_CHAIN,
            address(token),
            INPUT_AMOUNT,
            OUTPUT_TOKEN,
            OUTPUT_AMOUNT,
            bytes32(uint256(uint160(evmRecipient)))
        );
        vm.prank(user);
        adapter.deposit(_defaultParams());
    }

    /// @notice A solana-style non-EVM recipient (chainType 0x0002, 32-byte address) passes through verbatim
    ///         with the caller-supplied destinationChainId (no cross-check possible for non-EVM chainTypes).
    function test_DepositNonEvmRecipient() public {
        uint256 acrossSolanaChainId = 34268394551451; // Across's own numeric id for a non-EVM chain, raw
        bytes32 solanaKey = keccak256("solana-recipient");

        IAcrossBridgeAdapter.DepositParams memory p = _defaultParams();
        p.recipient = NonEvmAddress.formatV1(0x0002, abi.encodePacked(uint32(101)), solanaKey);
        p.destinationChainId = acrossSolanaChainId;

        _fund(user, INPUT_AMOUNT);
        vm.prank(user);
        adapter.deposit(p);

        assertEq(pool.lastRecipient(), solanaKey, "32-byte non-EVM recipient verbatim");
        assertEq(pool.lastDestinationChainId(), acrossSolanaChainId, "caller-supplied Across chain id trusted");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              DEPOSIT REVERTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_DepositRevertsZeroInputAmount() public {
        IAcrossBridgeAdapter.DepositParams memory p = _defaultParams();
        p.inputAmount = 0;
        vm.prank(user);
        vm.expectRevert(IAcrossBridgeAdapter.AcrossZeroAmount.selector);
        adapter.deposit(p);
    }

    function test_DepositRevertsZeroInputToken() public {
        IAcrossBridgeAdapter.DepositParams memory p = _defaultParams();
        p.inputToken = address(0);
        vm.prank(user);
        vm.expectRevert(IAcrossBridgeAdapter.AcrossZeroAddress.selector);
        adapter.deposit(p);
    }

    function test_DepositRevertsZeroOutputToken() public {
        IAcrossBridgeAdapter.DepositParams memory p = _defaultParams();
        p.outputToken = bytes32(0);
        vm.prank(user);
        vm.expectRevert(IAcrossBridgeAdapter.AcrossZeroOutputToken.selector);
        adapter.deposit(p);
    }

    function test_DepositRevertsSameChainDestination() public {
        IAcrossBridgeAdapter.DepositParams memory p = _defaultParams();
        p.destinationChainId = block.chainid;
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IAcrossBridgeAdapter.AcrossSameChainDeposit.selector, block.chainid));
        adapter.deposit(p);
    }

    /// @notice FAIL-CLOSED cross-check: an eip-155 recipient whose ERC-7930 chain reference differs from the
    ///         raw `destinationChainId` is rejected (mirrors the ZetaChain `SourceChainMismatch` precedent).
    function test_DepositRevertsEip155DestinationMismatch() public {
        IAcrossBridgeAdapter.DepositParams memory p = _defaultParams();
        p.recipient = InteroperableAddress.formatEvmV1(10, evmRecipient); // declares Optimism...
        p.destinationChainId = DEST_CHAIN; // ...but claims Base
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IAcrossBridgeAdapter.AcrossDestinationMismatch.selector, 10, DEST_CHAIN));
        adapter.deposit(p);
    }

    function test_DepositRevertsEmptyRecipientBytes() public {
        IAcrossBridgeAdapter.DepositParams memory p = _defaultParams();
        p.recipient = hex"";
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(InteroperableAddress.InteroperableAddressParsingError.selector, hex""));
        adapter.deposit(p);
    }

    function test_DepositRevertsEmptyAddressField() public {
        IAcrossBridgeAdapter.DepositParams memory p = _defaultParams();
        p.recipient = InteroperableAddress.formatEvmV1(DEST_CHAIN); // chain-only, empty address field
        vm.prank(user);
        vm.expectRevert(NonEvmAddress.NonEvmAddressEmpty.selector);
        adapter.deposit(p);
    }

    function test_DepositRevertsMalformedEvmWidth() public {
        IAcrossBridgeAdapter.DepositParams memory p = _defaultParams();
        // eip-155 chainType with a 19-byte address field: rejected instead of right-aligning into a WRONG bytes32.
        p.recipient =
            InteroperableAddress.formatV1(bytes2(0x0000), abi.encodePacked(uint16(uint256(DEST_CHAIN))), new bytes(19));
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NonEvmAddress.NonEvmAddressInvalidEvmWidth.selector, 19));
        adapter.deposit(p);
    }

    function test_DepositRevertsOversizedAddressField() public {
        IAcrossBridgeAdapter.DepositParams memory p = _defaultParams();
        p.recipient = InteroperableAddress.formatV1(bytes2(0x0002), abi.encodePacked(uint32(101)), new bytes(33));
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NonEvmAddress.NonEvmAddressTooLong.selector, 33));
        adapter.deposit(p);
    }

    /// @notice REENTRANCY REGRESSION: a malicious input token re-entering `deposit` mid-`transferFrom` must be
    ///         stopped by the diamond-global guard with {ReentrancyGuardReentrantCall}. The evil token records
    ///         that exact inner revert and then completes, so this test fails if the guard is ever dropped or
    ///         moved after the pull.
    function test_DepositNonReentrantViaMaliciousToken() public {
        MockReentrantToken evil = new MockReentrantToken();

        IAcrossBridgeAdapter.DepositParams memory p = _defaultParams();
        p.inputToken = address(evil);
        evil.setReenter(diamond, abi.encodeCall(IAcrossBridgeAdapter.deposit, (p)));

        evil.mint(user, INPUT_AMOUNT);
        vm.prank(user);
        evil.approve(diamond, INPUT_AMOUNT);

        vm.prank(user);
        adapter.deposit(p);

        assertTrue(evil.sawGuardRevert(), "inner re-enter reverted with ReentrancyGuardReentrantCall");
        assertEq(pool.calls(), 1, "outer deposit completed exactly once");
    }

    /// @notice FAIL-CLOSED width guard: an eip-155 recipient whose ERC-7930 chain reference exceeds 32 bytes
    ///         reverts {AcrossChainReferenceTooLong} instead of silently truncating into a wrong chainId.
    function test_DepositRevertsChainReferenceTooLong() public {
        IAcrossBridgeAdapter.DepositParams memory p = _defaultParams();
        p.recipient = InteroperableAddress.formatV1(bytes2(0x0000), new bytes(33), abi.encodePacked(evmRecipient));
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IAcrossBridgeAdapter.AcrossChainReferenceTooLong.selector, 33));
        adapter.deposit(p);
    }

    function test_DepositRevertsNoApproval() public {
        token.mint(user, INPUT_AMOUNT); // minted, not approved to the diamond
        vm.prank(user);
        vm.expectRevert(); // pullExact transferFrom underflows without allowance
        adapter.deposit(_defaultParams());
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   FUZZ
    //////////////////////////////////////////////////////////////////////////*//

    function testFuzz_DepositAmount(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        IAcrossBridgeAdapter.DepositParams memory p = _defaultParams();
        p.inputAmount = amount;

        _fund(user, amount);
        vm.prank(user);
        adapter.deposit(p);

        assertEq(pool.lastInputAmount(), amount);
        assertEq(pool.lastDepositor(), bytes32(uint256(uint160(user))));
        assertEq(token.balanceOf(diamond), 0);
        assertEq(token.allowance(diamond, address(pool)), 0);
    }

    function testFuzz_DepositChainId(uint64 destChainId) public {
        vm.assume(destChainId != 0 && destChainId != block.chainid);
        IAcrossBridgeAdapter.DepositParams memory p = _defaultParams();
        p.recipient = InteroperableAddress.formatEvmV1(destChainId, evmRecipient);
        p.destinationChainId = destChainId;

        _fund(user, INPUT_AMOUNT);
        vm.prank(user);
        adapter.deposit(p);

        assertEq(pool.lastDestinationChainId(), destChainId);
        assertEq(pool.lastRecipient(), bytes32(uint256(uint160(evmRecipient))));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          HANDLE V3 ACROSS MESSAGE
    //////////////////////////////////////////////////////////////////////////*//

    function test_HandleV3AcrossMessageFromSpokePool() public {
        vm.expectEmit(true, true, false, true, diamond);
        emit IAcrossBridgeAdapter.AcrossMessageReceived(address(token), OUTPUT_AMOUNT, relayer, hex"deadbeef");
        vm.prank(address(pool));
        adapter.handleV3AcrossMessage(address(token), OUTPUT_AMOUNT, relayer, hex"deadbeef");
    }

    function test_HandleV3AcrossMessageRevertsNotSpokePool() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IAcrossBridgeAdapter.AcrossNotSpokePool.selector, user));
        adapter.handleV3AcrossMessage(address(token), 1, relayer, hex"");
    }

    function test_HandleV3AcrossMessageRevertsForRelayer() public {
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(IAcrossBridgeAdapter.AcrossNotSpokePool.selector, relayer));
        adapter.handleV3AcrossMessage(address(token), 1, relayer, hex"");
    }

    function test_HandleV3AcrossMessageRevertsForDiamondItself() public {
        vm.prank(diamond);
        vm.expectRevert(abi.encodeWithSelector(IAcrossBridgeAdapter.AcrossNotSpokePool.selector, diamond));
        adapter.handleV3AcrossMessage(address(token), 1, relayer, hex"");
    }
}
