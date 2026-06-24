// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IChronicleAdapter} from "@lattice/interfaces/IChronicleAdapter.sol";
import {IChronicle} from "@lattice/interfaces/external/IChronicle.sol";
import {ChronicleAdapter} from "@lattice/oracles/ChronicleAdapter.sol";
import {ChronicleAdapterLib} from "@lattice/oracles/libraries/ChronicleAdapterLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Mock diamond combining AccessControl + ChronicleAdapter.
contract MockChronicleAdapterForkContract is AccessControl, ChronicleAdapter {
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        ChronicleAdapterLib.__ChronicleAdapter_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title ChronicleAdapterFork
/// @notice Fork test against a real Chronicle oracle feed on Ethereum mainnet.
///
/// Enabling this test:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   export CHRONICLE_ETH_USD=<chronicle ETH/USD oracle address>
///   forge test --match-path "test/fork/ChronicleAdapterFork.t.sol"
///
/// TOLL-GATING CAVEAT: Chronicle oracles are Schnorr-signed and access-controlled. The adapter contract
/// that calls `readWithAge()` on the Chronicle oracle must be whitelisted ("`kiss`ed") by the oracle
/// operator. In a fork test the freshly deployed `MockChronicleAdapterForkContract` will NOT be
/// whitelisted, so live `readWithAge()` calls may revert unless the forked oracle happens to be
/// publicly readable (some test/community feeds waive toll-gating). If reads revert, the test catches
/// the revert and skips the value-range assertion, logging the toll-gate caveat. The configuration
/// and registration paths are verified unconditionally.
///
/// The Chronicle ETH/USD oracle address is supplied via the CHRONICLE_ETH_USD env var. The test is
/// skipped unless both MAINNET_RPC_URL and CHRONICLE_ETH_USD are set.
contract ChronicleAdapterFork is Test {
    /// @notice A recent mainnet block; overridable via CHRONICLE_FORK_BLOCK for a fresher value.
    uint256 constant DEFAULT_FORK_BLOCK = 21_500_000;

    bytes32 constant KEY_ETH_USD = keccak256("ETH/USD");

    MockChronicleAdapterForkContract adapter;
    address chronicle;
    address admin = address(0x1);

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        chronicle = vm.envOr("CHRONICLE_ETH_USD", address(0));
        if (bytes(rpc).length == 0 || chronicle == address(0)) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", vm.envOr("CHRONICLE_FORK_BLOCK", DEFAULT_FORK_BLOCK));

        adapter = new MockChronicleAdapterForkContract();
        adapter.initialize(admin);
    }

    /// @dev Registers ETH/USD. We cannot inspect `age` from outside without being kiss-ed, so we use a
    ///      generous maxStaleness (30 days) to cover any reasonable fork block age.
    function _registerEthUsd() internal {
        vm.prank(admin);
        adapter.registerFeed(KEY_ETH_USD, chronicle, uint48(30 days));
    }

    function test_Fork_RegistrationAndConfig() public {
        _registerEthUsd();

        (address storedChronicle, uint48 maxStaleness) = adapter.getFeed(KEY_ETH_USD);
        assertEq(storedChronicle, chronicle, "chronicle address mismatch");
        assertGt(maxStaleness, 0, "staleness must be set");
    }

    function test_Fork_ETHUSDReadsLatestPrice() public {
        _registerEthUsd();

        // Chronicle feeds are toll-gated: reads may revert if this contract is not kiss-ed.
        // We attempt the read and only assert the range if it succeeds.
        try adapter.readWithAge(KEY_ETH_USD) returns (uint256 value, uint256 age) {
            // ETH/USD should be between $500 and $10,000 at any reasonable mainnet block.
            assertTrue(
                int256(value) >= int256(500e18) && int256(value) <= int256(10_000e18), "ETH/USD out of expected range"
            );
            assertGt(age, 0, "age must be non-zero");
        } catch {
            // Toll-gate revert: the mock adapter contract is not kiss-ed on the forked state.
            // This is expected behaviour — register and config paths are already verified above.
            emit log("Chronicle toll-gate active: readWithAge reverted (adapter not kiss-ed). Skipping range check.");
        }
    }

    function test_Fork_LatestAnswerMatchesRawWiden() public {
        _registerEthUsd();

        // Chronicle values are already 18-decimals; WAD answer is exactly the cast native value.
        try adapter.readWithAge(KEY_ETH_USD) returns (uint256 value, uint256) {
            assertEq(adapter.latestAnswer(KEY_ETH_USD), int256(value), "WAD cast mismatch");
        } catch {
            emit log("Chronicle toll-gate active: readWithAge reverted (adapter not kiss-ed). Skipping widen check.");
        }
    }
}
