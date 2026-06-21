// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ITellorAdapter} from "@lattice/interfaces/ITellorAdapter.sol";
import {ITellor} from "@lattice/interfaces/external/ITellor.sol";
import {TellorAdapter} from "@lattice/oracles/TellorAdapter.sol";
import {TellorAdapterLib} from "@lattice/oracles/libraries/TellorAdapterLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Mock diamond combining AccessControl + TellorAdapter.
contract MockTellorAdapterForkContract is AccessControl, TellorAdapter {
    function initialize(address _admin, address _tellor) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        TellorAdapterLib.__TellorAdapter_init(_tellor);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title TellorAdapterFork
/// @notice Fork tests against the real Tellor oracle (TellorFlex) on Ethereum mainnet.
///
/// Enabling fork tests:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   forge test --match-path "test/fork/TellorAdapterFork.t.sol"
///
/// The Tellor oracle address and ETH/USD query id default to the mainnet constants below, but can be
/// overridden via TELLOR_ORACLE / TELLOR_QUERY_ID. Without MAINNET_RPC_URL set, all tests are skipped.
contract TellorAdapterFork is Test {
    /// @notice Pinned mainnet block for deterministic results (December 2024).
    uint256 constant FORK_BLOCK = 21_500_000;

    /// @notice Tellor oracle (TellorFlex) on Ethereum mainnet.
    address constant TELLOR = 0xB3B662644F8d3138df63D2F43068ea621e2981f9;

    /// @notice Tellor ETH/USD SpotPrice query id:
    /// `keccak256(abi.encode("SpotPrice", abi.encode("eth", "usd")))`.
    bytes32 constant TELLOR_ETH_USD = 0x83a7f3d48786ac2667503a61e8c415438ed2922eb86a2906e4ee66d9a2ce4992;

    bytes32 constant KEY_ETH_USD = keccak256("ETH/USD");

    /// @notice Dispute buffer: read data at least this old so disputed values are removed first.
    uint48 constant DISPUTE_BUFFER = 900; // 15 minutes

    MockTellorAdapterForkContract adapter;
    address oracle;
    bytes32 queryId;
    address admin = address(0x1);

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        oracle = vm.envOr("TELLOR_ORACLE", TELLOR);
        queryId = vm.envOr("TELLOR_QUERY_ID", TELLOR_ETH_USD);
        vm.createSelectFork("mainnet", FORK_BLOCK);

        adapter = new MockTellorAdapterForkContract();
        adapter.initialize(admin, oracle);
    }

    /// @dev Registers ETH/USD with a staleness window covering the forked block's on-chain value age.
    function _registerEthUsd() internal {
        (,, uint256 timestamp) = ITellor(oracle).getDataBefore(queryId, block.timestamp - DISPUTE_BUFFER);
        // The retrieved value at a pinned block may be minutes/hours old; size the window to it.
        uint256 age = block.timestamp > timestamp ? block.timestamp - timestamp : 0;
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, queryId, DISPUTE_BUFFER, uint48(age + 1 hours));
    }

    function test_Fork_ETHUSDReadsLatestPrice() public {
        _registerEthUsd();

        (bytes32 storedQueryId, uint48 disputeBuffer, uint48 maxStaleness) = adapter.getFeed(KEY_ETH_USD);
        assertEq(storedQueryId, queryId, "queryId mismatch");
        assertEq(disputeBuffer, DISPUTE_BUFFER, "dispute buffer mismatch");
        assertGt(maxStaleness, 0, "staleness set");

        int256 priceWad = adapter.latestAnswer(KEY_ETH_USD);
        // ETH/USD should be between $500 and $10,000 at any reasonable mainnet block.
        assertTrue(priceWad >= int256(500e18) && priceWad <= int256(10_000e18), "ETH/USD out of expected range");
    }

    function test_Fork_LatestAnswerMatchesRawDecode() public {
        _registerEthUsd();

        (bytes memory value,) = adapter.getDataBefore(KEY_ETH_USD);
        // Tellor SpotPrice values are already 18-decimals; WAD answer is the decoded value widened.
        assertEq(adapter.latestAnswer(KEY_ETH_USD), int256(abi.decode(value, (uint256))), "WAD decode mismatch");
    }
}
