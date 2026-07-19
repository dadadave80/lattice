// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IStdReference} from "@lattice/interfaces/external/band/IStdReference.sol";
import {IBandAdapter} from "@lattice/interfaces/oracles/IBandAdapter.sol";
import {BandAdapter} from "@lattice/oracles/BandAdapter.sol";
import {BandAdapterLib} from "@lattice/oracles/libraries/BandAdapterLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Mock diamond combining AccessControl + BandAdapter.
contract MockBandAdapterForkContract is AccessControl, BandAdapter {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(AccessControl, BandAdapter) returns (bytes memory) {}

    function initialize(address _admin, address _reference) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        BandAdapterLib.__BandAdapter_init(_reference);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title BandAdapterFork
/// @notice Fork test against a real Band StdReference contract on Ethereum mainnet.
///
/// Enabling this test:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   export BAND_STD_REFERENCE=<StdReference contract address>
///   forge test --match-path "test/fork/BandAdapterFork.t.sol"
///
/// Band publishes a SINGLE global StdReference contract per chain via a deterministic CREATE2 address
/// (`0xDA7a001b254CD22e46d3eAB04d937489c93174C3` on most supported EVM chains). Ethereum mainnet is not
/// in Band's officially supported-blockchains list, and the contract at that canonical address on mainnet
/// is only sparsely maintained, so the StdReference address is supplied via the BAND_STD_REFERENCE env var
/// rather than hard-coded. The test is skipped unless both MAINNET_RPC_URL and BAND_STD_REFERENCE are set.
contract BandAdapterFork is Test {
    /// @notice A recent mainnet block; overridable via BAND_FORK_BLOCK for a fresher reference value.
    uint256 constant DEFAULT_FORK_BLOCK = 21_500_000;

    bytes32 constant KEY_ETH_USD = keccak256("ETH/USD");

    string constant BASE = "ETH";
    string constant QUOTE = "USD";

    MockBandAdapterForkContract adapter;
    address stdRef;
    address admin = address(0x1);

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        stdRef = vm.envOr("BAND_STD_REFERENCE", address(0));
        if (bytes(rpc).length == 0 || stdRef == address(0)) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", vm.envOr("BAND_FORK_BLOCK", DEFAULT_FORK_BLOCK));

        adapter = new MockBandAdapterForkContract();
        adapter.initialize(admin, stdRef);
    }

    /// @dev Registers ETH/USD with a staleness window covering the forked block's on-chain value age.
    function _registerEthUsd() internal {
        IStdReference.ReferenceData memory rd = IStdReference(stdRef).getReferenceData(BASE, QUOTE);
        uint256 lastUpdated = rd.lastUpdatedBase < rd.lastUpdatedQuote ? rd.lastUpdatedBase : rd.lastUpdatedQuote;
        uint256 age = block.timestamp > lastUpdated ? block.timestamp - lastUpdated : 0;
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, BASE, QUOTE, uint48(age + 1 hours));
    }

    function test_Fork_ETHUSDReadsLatestPrice() public {
        _registerEthUsd();

        (string memory base, string memory quote, uint48 maxStaleness) = adapter.getFeed(KEY_ETH_USD);
        assertEq(base, BASE, "base mismatch");
        assertEq(quote, QUOTE, "quote mismatch");
        assertGt(maxStaleness, 0, "staleness set");

        int256 priceWad = adapter.latestAnswer(KEY_ETH_USD);
        // ETH/USD should be between $500 and $10,000 at any reasonable mainnet block.
        assertTrue(priceWad >= int256(500e18) && priceWad <= int256(10_000e18), "ETH/USD out of expected range");
    }

    function test_Fork_LatestAnswerMatchesRawWiden() public {
        _registerEthUsd();

        (uint256 rate,,) = adapter.getReferenceData(KEY_ETH_USD);
        // Band rates are already 18-decimals; WAD answer is exactly the widened native rate.
        assertEq(adapter.latestAnswer(KEY_ETH_USD), int256(rate), "WAD widen mismatch");
    }
}
