// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {ArchiveFork} from "@lattice-test/helpers/ArchiveFork.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IApi3Proxy} from "@lattice/interfaces/external/api3/IApi3Proxy.sol";
import {IAPI3Adapter} from "@lattice/interfaces/oracles/IAPI3Adapter.sol";
import {API3Adapter} from "@lattice/oracles/api3/API3Adapter.sol";
import {API3AdapterLib} from "@lattice/oracles/api3/API3AdapterLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Mock diamond combining AccessControl + API3Adapter.
contract MockAPI3AdapterForkContract is AccessControl, API3Adapter, Initializable {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(AccessControl, API3Adapter) returns (bytes memory) {}

    function initialize(address _admin) external initializer {
        AccessControlLib.__AccessControl_init(_admin);
        API3AdapterLib.__API3Adapter_init();
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title API3AdapterFork
/// @notice Fork test against API3's ETH/USD dAPI proxy on Ethereum mainnet.
///
/// Enabling this test:
///   export MAINNET_RPC_URL=<your-archive-rpc-url>
///   forge test --match-path "test/fork/API3AdapterFork.t.sol"
///
/// Without MAINNET_RPC_URL set, all tests here are skipped. The fork is pinned (API3_FORK_BLOCK overrides it),
/// so it needs an archive endpoint. The default proxy is the ETH/USD `DapiProxy` that API3's ProxyFactory
/// deploys deterministically from the dAPI name alone (no per-dApp metadata). API3_ETH_USD_PROXY overrides it,
/// for example with a per-dApp `Api3ReaderProxyV1` from the API3 Market.
contract API3AdapterFork is Test {
    /// @notice Pinned mainnet block (2026), shared with the EntryPoint suites. The ETH/USD dAPI is not yet
    ///         initialized at the 21_500_000 pin of the other oracle suites: its proxy reverts
    ///         "Data feed not initialized" until block 22_473_379.
    uint256 constant DEFAULT_FORK_BLOCK = 25_000_000;

    /// @notice API3 ProxyFactory on Ethereum mainnet:
    ///         https://github.com/api3dao/airnode-protocol-v1/blob/4816d45e66e985ad2cc848695e52435467768e2f/deployments/ethereum/ProxyFactory.json
    address constant PROXY_FACTORY = 0x9EB9798Dc1b602067DFe5A57c3bfc914B965acFD;
    /// @notice API3's Api3ServerV1 on Ethereum mainnet, which every dAPI proxy reads (same deployments directory;
    ///         also chain 1 of `deployments/addresses.json` in api3dao/contracts).
    address constant API3_SERVER_V1 = 0x709944a48cAf83535e43471680fDA4905FB3920a;
    /// @notice The ETH/USD DapiProxy: `PROXY_FACTORY.computeDapiProxyAddress(bytes32("ETH/USD"), "")`.
    address constant ETH_USD_DAPI_PROXY = 0x009E9B1eec955E9Fe7FE64f80aE868e661cb4729;

    bytes32 constant KEY_ETH_USD = keccak256("ETH/USD");

    MockAPI3AdapterForkContract adapter;
    address proxy;
    address admin = address(0x1);

    function setUp() public {
        if (bytes(vm.envOr("MAINNET_RPC_URL", string(""))).length == 0) {
            vm.skip(true);
            return;
        }
        proxy = vm.envOr("API3_ETH_USD_PROXY", ETH_USD_DAPI_PROXY);
        if (!ArchiveFork.select("mainnet", vm.envOr("API3_FORK_BLOCK", DEFAULT_FORK_BLOCK))) return;
        // The pin postdates the proxy, so missing code means a wrong address or pin: skip locally, fail on the
        // strict weekly lane.
        if (proxy.code.length == 0) {
            ArchiveFork.skipOrFail(ArchiveFork.strict(), "API3 ETH/USD proxy has no code at the fork block");
            return;
        }

        adapter = new MockAPI3AdapterForkContract();
        adapter.initialize(admin);
    }

    /// @notice The default proxy is the one API3's ProxyFactory derives for "ETH/USD", and it reads Api3ServerV1.
    function test_Fork_DefaultProxyIsFactoryEthUsdDapiProxy() public view {
        (bool ok, bytes memory ret) = PROXY_FACTORY.staticcall(
            abi.encodeWithSignature("computeDapiProxyAddress(bytes32,bytes)", bytes32("ETH/USD"), bytes(""))
        );
        assertTrue(ok, "computeDapiProxyAddress reverted");
        assertEq(abi.decode(ret, (address)), ETH_USD_DAPI_PROXY, "factory derives another ETH/USD proxy");

        (ok, ret) = ETH_USD_DAPI_PROXY.staticcall(abi.encodeWithSignature("dapiNameHash()"));
        assertTrue(ok, "dapiNameHash() reverted");
        assertEq(abi.decode(ret, (bytes32)), keccak256(abi.encodePacked(bytes32("ETH/USD"))), "not the ETH/USD dAPI");

        (ok, ret) = ETH_USD_DAPI_PROXY.staticcall(abi.encodeWithSignature("api3ServerV1()"));
        assertTrue(ok, "api3ServerV1() reverted");
        assertEq(abi.decode(ret, (address)), API3_SERVER_V1, "proxy reads another Api3ServerV1");
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
