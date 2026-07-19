// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AcrossBridgeAdapterTestBase} from "@lattice-test/base/AcrossBridgeAdapterTestBase.sol";
import {AcrossBridgeAdapter} from "@lattice/crosschain/across/AcrossBridgeAdapter.sol";
import {IAcrossBridgeAdapter} from "@lattice/interfaces/crosschain/IAcrossBridgeAdapter.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev Live-SpokePool view getters the fork test needs that are NOT part of the deliberately minimal vendored
///      {V3SpokePoolInterface} subset (upstream: https://github.com/across-protocol/contracts).
interface ISpokePoolForkViews {
    function fillDeadlineBuffer() external view returns (uint32);
    function numberOfDeposits() external view returns (uint32);
}

/// @title AcrossBridgeAdapterFork
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Fork smoke test for the intent/optimistic settlement family: the production Across adapter diamond
///         (built from the {DeployAcrossBridgeAdapter} recipe) escrows LIVE USDC in the Ethereum mainnet
///         SpokePool as a deposit intent toward a Base recipient. The deposit's time fields are built from the
///         live pool's own bounds (`quoteTimestamp = block.timestamp`, `fillDeadline` within
///         `fillDeadlineBuffer()`), and the observable asserted is the SpokePool's deposit accounting: escrowed
///         balance, `numberOfDeposits`, and the bytes32 `FundsDeposited` event with `depositor == user`.
///
/// Enabling:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   forge test --match-path "test/fork/AcrossBridgeAdapterFork.t.sol"
///
/// Without MAINNET_RPC_URL set, all tests here are skipped.
contract AcrossBridgeAdapterFork is AcrossBridgeAdapterTestBase {
    // Across v3 Ethereum SpokePool (verified `ERC1967Proxy` -> `Ethereum_SpokePool`).
    address constant SPOKE_POOL = 0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5;
    // Circle USDC on Ethereum mainnet (verified `FiatTokenProxy` -> `FiatTokenV2_2`).
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // Circle USDC on Base (verified on Base, chain 8453) — the token the relayer fronts on the destination.
    bytes32 constant BASE_USDC = bytes32(uint256(uint160(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)));

    /// @dev topic0 of the live SpokePool's bytes32 `FundsDeposited` event (Across v3.5+ layout).
    bytes32 constant FUNDS_DEPOSITED_TOPIC = keccak256(
        "FundsDeposited(bytes32,bytes32,uint256,uint256,uint256,uint256,uint32,uint32,uint32,bytes32,bytes32,bytes32,bytes)"
    );

    uint256 constant BASE_CHAIN = 8453;
    uint256 constant AMOUNT = 1_000e6; // 1,000 USDC

    /// @notice Pinned mainnet block (2026-06-26; fillDeadlineBuffer 21600s, depositQuoteTimeBuffer 3600s,
    ///         deposits unpaused).
    uint256 constant FORK_BLOCK = 25_400_000;

    address diamond;
    AcrossBridgeAdapter adapter;

    address user = address(0xAC5);
    address baseRecipient = address(0xCAFE);

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", FORK_BLOCK);

        diamond = _deployAcrossBridgeAdapter(SPOKE_POOL);
        adapter = AcrossBridgeAdapter(diamond);
    }

    /// @notice Happy path: pull exactly `AMOUNT` from the user, escrow it in the live SpokePool as an intent
    ///         toward Base (depositor = the user, so an unfilled expiry refunds the user, not the diamond),
    ///         and leave no allowance or balance behind on the diamond.
    function test_Fork_DepositUSDCTowardBase() public {
        deal(USDC, user, AMOUNT);
        vm.prank(user);
        IERC20(USDC).approve(diamond, AMOUNT);

        // Build the time fields from the LIVE pool's own bounds so the params are valid by construction.
        uint32 fillBuffer = ISpokePoolForkViews(SPOKE_POOL).fillDeadlineBuffer();
        IAcrossBridgeAdapter.DepositParams memory p = IAcrossBridgeAdapter.DepositParams({
            recipient: InteroperableAddress.formatEvmV1(BASE_CHAIN, baseRecipient),
            outputToken: BASE_USDC,
            inputToken: USDC,
            inputAmount: AMOUNT,
            outputAmount: (AMOUNT * 99) / 100, // quote-derived in production; any value < input is accepted
            destinationChainId: BASE_CHAIN,
            exclusiveRelayer: bytes32(0),
            quoteTimestamp: uint32(block.timestamp),
            fillDeadline: uint32(block.timestamp) + fillBuffer / 2, // safely inside the pool's buffer
            exclusivityParameter: 0,
            message: ""
        });

        uint256 poolBefore = IERC20(USDC).balanceOf(SPOKE_POOL);
        uint32 depositsBefore = ISpokePoolForkViews(SPOKE_POOL).numberOfDeposits();

        vm.recordLogs();
        vm.prank(user);
        adapter.deposit(p);

        assertEq(IERC20(USDC).balanceOf(user), 0, "user debited exactly inputAmount");
        assertEq(IERC20(USDC).balanceOf(SPOKE_POOL) - poolBefore, AMOUNT, "SpokePool escrowed the input");
        assertEq(ISpokePoolForkViews(SPOKE_POOL).numberOfDeposits(), depositsBefore + 1, "deposit counted");
        assertEq(IERC20(USDC).allowance(diamond, SPOKE_POOL), 0, "SpokePool allowance reset to 0");
        assertEq(IERC20(USDC).balanceOf(diamond), 0, "no USDC stuck in the diamond");

        // The live pool emitted FundsDeposited toward Base with the USER as the refundable depositor.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == SPOKE_POOL && logs[i].topics[0] == FUNDS_DEPOSITED_TOPIC
                    && logs[i].topics[1] == bytes32(BASE_CHAIN) && logs[i].topics[3] == bytes32(uint256(uint160(user)))
            ) {
                seen = true;
                break;
            }
        }
        assertTrue(seen, "FundsDeposited(destinationChainId=Base, depositor=user) emitted by the SpokePool");
    }
}
