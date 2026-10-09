// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {ArchiveFork} from "@lattice-test/helpers/ArchiveFork.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IChronicle} from "@lattice/interfaces/external/chronicle/IChronicle.sol";
import {IChronicleAdapter} from "@lattice/interfaces/oracles/IChronicleAdapter.sol";
import {ChronicleAdapter} from "@lattice/oracles/chronicle/ChronicleAdapter.sol";
import {ChronicleAdapterLib} from "@lattice/oracles/chronicle/ChronicleAdapterLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Mock diamond combining AccessControl + ChronicleAdapter.
contract MockChronicleAdapterForkContract is AccessControl, ChronicleAdapter, Initializable {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(AccessControl, ChronicleAdapter) returns (bytes memory) {}

    function initialize(address _admin) external initializer {
        AccessControlLib.__AccessControl_init(_admin);
        ChronicleAdapterLib.__ChronicleAdapter_init();
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title ChronicleAdapterFork
/// @notice Fork test against Chronicle's ETH/USD oracle on Ethereum mainnet.
///
/// Enabling this test:
///   export MAINNET_RPC_URL=<your-archive-rpc-url>
///   forge test --match-path "test/fork/ChronicleAdapterFork.t.sol"
///
/// Without MAINNET_RPC_URL set, all tests here are skipped. The fork is pinned (CHRONICLE_FORK_BLOCK overrides
/// it), so it needs an archive endpoint. The default oracle is `Chronicle_ETH_USD_3`; CHRONICLE_ETH_USD
/// overrides it.
///
/// Chronicle oracles are toll-gated: only addresses the oracle's wards whitelist with `kiss` can read them. As
/// a consumer's diamond would be, the adapter is kissed in setUp, here by pranking one of the oracle's own
/// wards (`authed()`), so every read below runs against the live oracle state.
contract ChronicleAdapterFork is Test {
    /// @notice Pinned mainnet block (December 2024), shared with the other mainnet oracle suites.
    uint256 constant DEFAULT_FORK_BLOCK = 21_500_000;

    /// @notice `Chronicle_ETH_USD_3` on Ethereum mainnet, as Chronicle's challenger guide lists it
    ///         (https://github.com/chronicleprotocol/documentation/blob/d0149f46e0ae1636f72980cada76071623fdb72f/docs/Developers/Guides/runChallengerK8s.md#L73-L75).
    address constant CHRONICLE_ETH_USD_3 = 0x46ef0071b1E2fF6B42d36e5A177EA43Ae5917f4E;

    bytes32 constant KEY_ETH_USD = keccak256("ETH/USD");

    MockChronicleAdapterForkContract adapter;
    address chronicle;
    address admin = address(0x1);

    function setUp() public {
        if (bytes(vm.envOr("MAINNET_RPC_URL", string(""))).length == 0) {
            vm.skip(true);
            return;
        }
        chronicle = vm.envOr("CHRONICLE_ETH_USD", CHRONICLE_ETH_USD_3);
        if (!ArchiveFork.select("mainnet", vm.envOr("CHRONICLE_FORK_BLOCK", DEFAULT_FORK_BLOCK))) return;
        // The pin postdates the oracle, so missing code means a wrong address or pin: skip locally, fail on the
        // strict weekly lane.
        if (chronicle.code.length == 0) {
            ArchiveFork.skipOrFail(ArchiveFork.strict(), "Chronicle ETH/USD oracle has no code at the fork block");
            return;
        }
        assertEq(_staticcall(abi.encodeWithSignature("wat()")), bytes32("ETH/USD"), "oracle is not ETH/USD");
        assertEq(uint256(_staticcall(abi.encodeWithSignature("decimals()"))), 18, "oracle is not 18 decimals");

        adapter = new MockChronicleAdapterForkContract();
        adapter.initialize(admin);

        (bool ok, bytes memory ret) = chronicle.staticcall(abi.encodeWithSignature("authed()"));
        assertTrue(ok, "authed() reverted");
        address[] memory wards = abi.decode(ret, (address[]));
        assertGt(wards.length, 0, "oracle has no wards");
        vm.prank(wards[0]);
        (ok,) = chronicle.call(abi.encodeWithSignature("kiss(address)", address(adapter)));
        assertTrue(ok, "kiss reverted");
        assertEq(
            uint256(_staticcall(abi.encodeWithSignature("tolled(address)", address(adapter)))), 1, "adapter not tolled"
        );
    }

    /// @dev Registers ETH/USD with a staleness window covering the forked block's on-chain value age.
    function _registerEthUsd() internal {
        vm.prank(address(adapter));
        (, uint256 age) = IChronicle(chronicle).readWithAge();
        uint256 elapsed = block.timestamp > age ? block.timestamp - age : 0;
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, chronicle, uint48(elapsed + 1 hours));
    }

    /// @dev The single word a view call on the oracle returns.
    function _staticcall(bytes memory data) internal view returns (bytes32 word) {
        (bool ok, bytes memory ret) = chronicle.staticcall(data);
        assertTrue(ok && ret.length == 32, "oracle view call failed");
        word = bytes32(ret);
    }

    function test_Fork_RegistrationAndConfig() public {
        _registerEthUsd();

        (address storedChronicle, uint48 maxStaleness) = adapter.getFeed(KEY_ETH_USD);
        assertEq(storedChronicle, chronicle, "chronicle address mismatch");
        assertGt(maxStaleness, 0, "staleness must be set");
    }

    function test_Fork_ETHUSDReadsLatestPrice() public {
        _registerEthUsd();

        (uint256 value, uint256 age) = adapter.readWithAge(KEY_ETH_USD);
        // ETH/USD should be between $500 and $10,000 at any reasonable mainnet block.
        assertTrue(value >= 500e18 && value <= 10_000e18, "ETH/USD out of expected range");
        assertGt(age, 0, "age must be non-zero");
        assertLe(age, block.timestamp, "age is in the future");
    }

    function test_Fork_LatestAnswerMatchesRawWiden() public {
        _registerEthUsd();

        // Chronicle values are already 18-decimals; WAD answer is exactly the cast native value.
        (uint256 value,) = adapter.readWithAge(KEY_ETH_USD);
        assertEq(adapter.latestAnswer(KEY_ETH_USD), int256(value), "WAD cast mismatch");
    }

    /// @notice The toll gate is live: a caller the wards never kissed cannot read the oracle.
    function test_Fork_UnkissedCallerCannotRead() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSignature("NotTolled(address)", address(0xBEEF)));
        IChronicle(chronicle).readWithAge();
    }
}
