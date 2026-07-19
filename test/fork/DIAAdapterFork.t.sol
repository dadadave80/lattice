// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IDIAOracleV2} from "@lattice/interfaces/external/dia/IDIAOracleV2.sol";
import {IDIAAdapter} from "@lattice/interfaces/oracles/IDIAAdapter.sol";
import {DIAAdapter} from "@lattice/oracles/dia/DIAAdapter.sol";
import {DIAAdapterLib} from "@lattice/oracles/dia/DIAAdapterLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Mock diamond combining AccessControl + DIAAdapter.
contract MockDIAAdapterForkContract is AccessControl, DIAAdapter {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(AccessControl, DIAAdapter) returns (bytes memory) {}

    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        s = InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        DIAAdapterLib.__DIAAdapter_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title DIAAdapterFork
/// @notice Fork test against a real DIA OracleV2 contract on Ethereum mainnet.
///
/// Enabling this test:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   forge test --match-path "test/fork/DIAAdapterFork.t.sol"
///
/// The DIA OracleV2 contract address on Ethereum mainnet is the well-known stable deployment at
/// 0xa93546947f3015c986695750b8bbEa8e26D65856 (source: github.com/diadata-org/DIA-integration-sample).
/// It can be overridden via DIA_ORACLE env var. The DIA key string defaults to "ETH/USD" but can be
/// overridden via DIA_KEY env var. The test is skipped unless MAINNET_RPC_URL is set.
contract DIAAdapterFork is Test {
    /// @notice A recent mainnet block; overridable via DIA_FORK_BLOCK for a fresher value.
    uint256 constant DEFAULT_FORK_BLOCK = 21_500_000;

    /// @notice The stable Ethereum mainnet DIA OracleV2 deployment.
    /// @dev Source: https://github.com/diadata-org/DIA-integration-sample
    address constant DEFAULT_DIA_ORACLE = 0xa93546947f3015c986695750b8bbEa8e26D65856;

    bytes32 constant KEY_ETH_USD = keccak256("ETH/USD");

    MockDIAAdapterForkContract adapter;
    address diaOracle;
    string diaKey;
    address admin = address(0x1);

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", vm.envOr("DIA_FORK_BLOCK", DEFAULT_FORK_BLOCK));

        diaOracle = vm.envOr("DIA_ORACLE", DEFAULT_DIA_ORACLE);
        diaKey = vm.envOr("DIA_KEY", string("ETH/USD"));

        adapter = new MockDIAAdapterForkContract();
        adapter.initialize(admin);
    }

    /// @dev Registers the feed with a staleness window covering the forked block's on-chain value age.
    function _registerFeed() internal {
        (, uint128 timestamp) = IDIAOracleV2(diaOracle).getValue(diaKey);
        uint256 age = block.timestamp > timestamp ? block.timestamp - timestamp : 0;
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, diaOracle, diaKey, uint48(age + 1 hours));
    }

    function test_Fork_ETHUSDReadsLatestPrice() public {
        _registerFeed();

        (address storedOracle, string memory storedKey, uint48 maxStaleness) = adapter.getFeed(KEY_ETH_USD);
        assertEq(storedOracle, diaOracle, "oracle mismatch");
        assertEq(storedKey, diaKey, "diaKey mismatch");
        assertGt(maxStaleness, 0, "staleness set");

        int256 priceWad = adapter.latestAnswer(KEY_ETH_USD);
        // ETH/USD should be between $500 and $10,000 at any reasonable mainnet block.
        assertTrue(priceWad >= int256(500e18) && priceWad <= int256(10_000e18), "ETH/USD out of expected range");
    }

    function test_Fork_LatestAnswerMatchesRawScaling() public {
        _registerFeed();

        (uint128 value,) = adapter.getValue(KEY_ETH_USD);
        // DIA values have 8 decimals; WAD answer is value * 1e10.
        assertEq(adapter.latestAnswer(KEY_ETH_USD), int256(uint256(value)) * 1e10, "WAD scaling mismatch");
    }
}
