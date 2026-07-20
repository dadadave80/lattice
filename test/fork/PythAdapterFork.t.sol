// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IPyth} from "@lattice/interfaces/external/pyth/IPyth.sol";
import {IPythAdapter} from "@lattice/interfaces/oracles/IPythAdapter.sol";
import {PythAdapter} from "@lattice/oracles/pyth/PythAdapter.sol";
import {PythAdapterLib} from "@lattice/oracles/pyth/PythAdapterLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Mock diamond combining AccessControl + PythAdapter.
contract MockPythAdapterForkContract is AccessControl, PythAdapter, Initializable {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(AccessControl, PythAdapter) returns (bytes memory) {}

    function initialize(address _admin, address _pyth) external initializer {
        AccessControlLib.__AccessControl_init(_admin);
        PythAdapterLib.__PythAdapter_init(_pyth);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title PythAdapterFork
/// @notice Fork tests against the real Pyth contract on Ethereum mainnet.
///
/// Enabling fork tests:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   forge test --match-path "test/fork/*"
///
/// Without MAINNET_RPC_URL set, all tests in this contract are skipped.
contract PythAdapterFork is Test {
    /// @notice Pinned mainnet block for deterministic results (December 2024).
    uint256 constant FORK_BLOCK = 21_500_000;

    /// @notice Pyth contract on Ethereum mainnet.
    address constant PYTH = 0x4305FB66699C3B2702D4d05CF36551390A4c69C6;

    /// @notice Pyth ETH/USD price-feed id.
    bytes32 constant PYTH_ETH_USD = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;

    bytes32 constant KEY_ETH_USD = keccak256("ETH/USD");

    MockPythAdapterForkContract adapter;
    address admin = address(0x1);

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", FORK_BLOCK);

        adapter = new MockPythAdapterForkContract();
        adapter.initialize(admin, PYTH);
    }

    /// @dev Registers ETH/USD with a staleness window covering the forked block's on-chain price age.
    function _registerEthUsd(uint64 maxConfBps) internal {
        IPyth.Price memory p = IPyth(PYTH).getPriceUnsafe(PYTH_ETH_USD);
        // The on-chain Pyth price at a pinned block may be minutes/hours old; size the window to it.
        uint256 age = block.timestamp > p.publishTime ? block.timestamp - p.publishTime : 0;
        uint48 staleness = uint48(age + 1 hours);
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, PYTH_ETH_USD, staleness, maxConfBps);
    }

    function test_Fork_ETHUSDReadsLatestPrice() public {
        _registerEthUsd(0);

        (bytes32 priceId, uint48 maxStaleness,) = adapter.getFeed(KEY_ETH_USD);
        assertEq(priceId, PYTH_ETH_USD, "priceId mismatch");
        assertGt(maxStaleness, 0, "staleness set");

        int256 priceWad = adapter.latestAnswer(KEY_ETH_USD);
        // ETH/USD should be between $500 and $10,000 at any reasonable mainnet block.
        assertTrue(priceWad >= int256(500e18) && priceWad <= int256(10_000e18), "ETH/USD out of expected range");
    }

    function test_Fork_WadNormalizationMatchesRaw() public {
        _registerEthUsd(0);

        (int64 price, int32 expo,,) = adapter.latestAnswerRaw(KEY_ETH_USD);
        int256 priceWad = adapter.latestAnswer(KEY_ETH_USD);

        // Pyth ETH/USD uses a negative exponent (typically -8); recompute WAD = price * 10^(18 + expo).
        int256 e = int256(18) + int256(expo);
        int256 expected = e >= 0 ? int256(price) * int256(10 ** uint256(e)) : int256(price) / int256(10 ** uint256(-e));
        assertEq(priceWad, expected, "WAD normalization mismatch");
    }

    function test_Fork_ConfidenceCheckCanReject() public {
        // A 1-bps confidence cap is almost certainly tighter than Pyth's live conf/price ratio,
        // so the read should revert PythConfidenceTooWide.
        _registerEthUsd(1);
        vm.expectRevert();
        adapter.latestAnswer(KEY_ETH_USD);
    }
}
