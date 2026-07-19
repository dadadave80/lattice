// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IApi3Proxy} from "@lattice/interfaces/external/api3/IApi3Proxy.sol";
import {IAPI3Adapter} from "@lattice/interfaces/oracles/IAPI3Adapter.sol";
import {API3Adapter} from "@lattice/oracles/api3/API3Adapter.sol";
import {API3AdapterLib} from "@lattice/oracles/api3/API3AdapterLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Mock diamond combining AccessControl + API3Adapter.
contract MockAPI3AdapterForkContract is AccessControl, API3Adapter {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(AccessControl, API3Adapter) returns (bytes memory) {}

    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        API3AdapterLib.__API3Adapter_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title API3AdapterFork
/// @notice Fork test against a real API3 dAPI reader proxy on Ethereum mainnet.
///
/// Enabling this test:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   export API3_ETH_USD_PROXY=<dAPI reader proxy address from the API3 Market>
///   forge test --match-path "test/fork/API3AdapterFork.t.sol"
///
/// The dAPI reader proxy is deployed per-dApp via the API3 Market factory rather than being a stable
/// published constant, so the proxy address is supplied via the API3_ETH_USD_PROXY env var. The test is
/// skipped unless both MAINNET_RPC_URL and API3_ETH_USD_PROXY are set.
contract API3AdapterFork is Test {
    /// @notice A recent mainnet block; overridable via API3_FORK_BLOCK for a fresher dAPI value.
    uint256 constant DEFAULT_FORK_BLOCK = 21_500_000;

    bytes32 constant KEY_ETH_USD = keccak256("ETH/USD");

    MockAPI3AdapterForkContract adapter;
    address proxy;
    address admin = address(0x1);

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        proxy = vm.envOr("API3_ETH_USD_PROXY", address(0));
        if (bytes(rpc).length == 0 || proxy == address(0)) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", vm.envOr("API3_FORK_BLOCK", DEFAULT_FORK_BLOCK));

        adapter = new MockAPI3AdapterForkContract();
        adapter.initialize(admin);
    }

    /// @dev Registers ETH/USD with a staleness window covering the forked block's on-chain value age.
    function _registerEthUsd() internal {
        (, uint32 timestamp) = IApi3Proxy(proxy).read();
        uint256 age = block.timestamp > timestamp ? block.timestamp - timestamp : 0;
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, proxy, uint48(age + 1 hours));
    }

    function test_Fork_ETHUSDReadsLatestPrice() public {
        _registerEthUsd();

        (address storedProxy, uint48 maxStaleness) = adapter.getFeed(KEY_ETH_USD);
        assertEq(storedProxy, proxy, "proxy mismatch");
        assertGt(maxStaleness, 0, "staleness set");

        int256 priceWad = adapter.latestAnswer(KEY_ETH_USD);
        // ETH/USD should be between $500 and $10,000 at any reasonable mainnet block.
        assertTrue(priceWad >= int256(500e18) && priceWad <= int256(10_000e18), "ETH/USD out of expected range");
    }

    function test_Fork_LatestAnswerMatchesRawWiden() public {
        _registerEthUsd();

        (int224 value,) = adapter.read(KEY_ETH_USD);
        // dAPI values are already 18-decimals; WAD answer is exactly the widened native value.
        assertEq(adapter.latestAnswer(KEY_ETH_USD), int256(value), "WAD widen mismatch");
    }
}
