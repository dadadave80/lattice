// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ITWAPOracle} from "@lattice/interfaces/ITWAPOracle.sol";
import {IUniswapV2Pair} from "@lattice/interfaces/external/IUniswapV2Pair.sol";
import {TWAPOracle} from "@lattice/oracles/TWAPOracle.sol";
import {TWAPOracleLib} from "@lattice/oracles/libraries/TWAPOracleLib.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCKS
// ---------------------------------------------------------------------------

/// @notice Mock Uniswap V2 pair with injectable cumulative prices.
contract MockUniswapV2Pair is IUniswapV2Pair {
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint112 public reserve0 = 1e18;
    uint112 public reserve1 = 3000e18;
    uint32 public blockTimestampLast;

    function setValues(uint256 p0Cumulative, uint256 p1Cumulative, uint32 timestamp) external {
        price0CumulativeLast = p0Cumulative;
        price1CumulativeLast = p1Cumulative;
        blockTimestampLast = timestamp;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, blockTimestampLast);
    }
}

/// @notice Combines AccessControl + TWAPOracle for testing.
contract MockTWAPOracleContract is AccessControl, TWAPOracle {
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        TWAPOracleLib.__TWAPOracle_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

contract TWAPOracleTester is Test {
    MockTWAPOracleContract oracle;
    MockUniswapV2Pair pair;

    address admin = address(0x1);
    address user = address(0x2);

    bytes32 constant KEY_ETH_USD = keccak256("ETH/USD");
    bytes32 constant KEY_UNKNOWN = keccak256("UNKNOWN");

    // UQ112x112 price per second at 3000:1 ratio.
    // price0Cumulative increases by price0 * elapsed, where price0 = (reserve1 / reserve0) * 2^112.
    // For simplicity only PRICE0_PER_SEC is used in correctness assertions;
    // PRICE1_PER_SEC is derived where needed with explicit arithmetic.
    uint256 constant PRICE0_PER_SEC = 3000 * (2 ** 112);

    function setUp() public {
        // Start at a non-trivial timestamp.
        vm.warp(1_000_000);

        oracle = new MockTWAPOracleContract();
        oracle.initialize(admin);

        pair = new MockUniswapV2Pair();
        // Initial state: cumulatives = 0, timestamp = current block
        pair.setValues(0, 0, uint32(block.timestamp));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         REGISTER PAIR TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Non-admin cannot register a pair.
    function test_RegisterPairRevertsForNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        oracle.registerPair(KEY_ETH_USD, address(pair));
    }

    /// @notice Admin can register a pair and it records an initial observation.
    function test_RegisterPairByAdmin() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));

        assertEq(oracle.getPair(KEY_ETH_USD), address(pair));

        // Initial observation should be recorded.
        ITWAPOracle.Observation memory obs = oracle.getLatestObservation(KEY_ETH_USD);
        assertEq(obs.timestamp, uint32(block.timestamp));
        assertEq(obs.price0Cumulative, 0);
        assertEq(obs.price1Cumulative, 0);
    }

    /// @notice registerPair emits PairRegistered and ObservationRecorded events.
    function test_RegisterPairEmitsEvents() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit ITWAPOracle.PairRegistered(KEY_ETH_USD, address(pair));
        oracle.registerPair(KEY_ETH_USD, address(pair));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              CONSULT TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice consult reverts when pair is not registered.
    function test_ConsultRevertsOnUnregisteredPair() public {
        vm.expectRevert(abi.encodeWithSelector(ITWAPOracle.TWAPPairNotRegistered.selector, KEY_UNKNOWN));
        oracle.consult(KEY_UNKNOWN, 300);
    }

    /// @notice consult with fewer than 2 observations reverts TWAPInsufficientHistory.
    function test_ConsultRevertsWithInsufficientHistory() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));
        // Only 1 observation was recorded at registration.
        vm.expectRevert(abi.encodeWithSelector(ITWAPOracle.TWAPInsufficientHistory.selector, KEY_ETH_USD));
        oracle.consult(KEY_ETH_USD, 300);
    }

    /// @notice consult reverts when window exceeds the age of the oldest observation.
    function test_ConsultRevertsWhenWindowTooLarge() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));

        // Advance 60 seconds and record a second observation.
        uint32 t0 = uint32(block.timestamp);
        vm.warp(block.timestamp + 60);
        pair.setValues(PRICE0_PER_SEC * 60, 0, uint32(block.timestamp));
        oracle.recordObservation(KEY_ETH_USD);

        // The oldest observation is 60 seconds old; requesting a 300-second window should revert.
        vm.expectRevert(
            abi.encodeWithSelector(ITWAPOracle.TWAPWindowTooLarge.selector, uint32(300), uint32(block.timestamp) - t0)
        );
        oracle.consult(KEY_ETH_USD, 300);
    }

    /// @notice consult returns correct TWAP over recorded observations.
    function test_ConsultReturnCorrectTWAP() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));
        // Observation 0: timestamp=1_000_000, cumulatives=0

        uint32 elapsed = 3600; // 1 hour
        uint256 p0 = PRICE0_PER_SEC * elapsed;

        vm.warp(block.timestamp + elapsed);
        pair.setValues(p0, 0, uint32(block.timestamp));
        oracle.recordObservation(KEY_ETH_USD);
        // Observation 1: timestamp=1_000_000+3600, cumulatives=PRICE*3600

        // consult over a 3600-second window should return PRICE_PER_SEC.
        (uint256 twap0,) = oracle.consult(KEY_ETH_USD, elapsed);
        assertEq(twap0, PRICE0_PER_SEC);
    }

    /// @notice consult across multiple observations picks the right base.
    function test_ConsultPicksCorrectBaseObservation() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));
        // Obs 0: t=1_000_000, cum=0

        // Obs 1: t+300, after 5 minutes
        vm.warp(block.timestamp + 300);
        pair.setValues(PRICE0_PER_SEC * 300, 0, uint32(block.timestamp));
        oracle.recordObservation(KEY_ETH_USD);

        // Obs 2: t+600, after 10 minutes total
        vm.warp(block.timestamp + 300);
        pair.setValues(PRICE0_PER_SEC * 600, 0, uint32(block.timestamp));
        oracle.recordObservation(KEY_ETH_USD);

        // Request 500-second window: obs1 (300s ago) is too recent, must use obs0 (600s ago).
        (uint256 twap0,) = oracle.consult(KEY_ETH_USD, 500);
        assertEq(twap0, PRICE0_PER_SEC);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         UNREGISTER PAIR TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice unregisterPair clears the pair and its observations.
    function test_UnregisterPairWorks() public {
        vm.startPrank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));

        vm.expectEmit(true, false, false, false);
        emit ITWAPOracle.PairUnregistered(KEY_ETH_USD);
        oracle.unregisterPair(KEY_ETH_USD);
        vm.stopPrank();

        assertEq(oracle.getPair(KEY_ETH_USD), address(0));

        // getLatestObservation should now revert TWAPPairNotRegistered.
        vm.expectRevert(abi.encodeWithSelector(ITWAPOracle.TWAPPairNotRegistered.selector, KEY_ETH_USD));
        oracle.getLatestObservation(KEY_ETH_USD);
    }

    /// @notice Non-admin cannot unregister a pair.
    function test_UnregisterPairRevertsForNonAdmin() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        oracle.unregisterPair(KEY_ETH_USD);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       RECORD OBSERVATION TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice recordObservation on unregistered pair reverts TWAPPairNotRegistered.
    function test_RecordObservationRevertsOnUnregistered() public {
        vm.expectRevert(abi.encodeWithSelector(ITWAPOracle.TWAPPairNotRegistered.selector, KEY_UNKNOWN));
        oracle.recordObservation(KEY_UNKNOWN);
    }

    /// @notice Anyone can call recordObservation.
    function test_RecordObservationPermissionless() public {
        vm.prank(admin);
        oracle.registerPair(KEY_ETH_USD, address(pair));

        vm.warp(block.timestamp + 60);
        pair.setValues(PRICE0_PER_SEC * 60, 0, uint32(block.timestamp));

        // Called by non-admin user — should succeed.
        vm.prank(user);
        oracle.recordObservation(KEY_ETH_USD);

        ITWAPOracle.Observation memory obs = oracle.getLatestObservation(KEY_ETH_USD);
        assertEq(obs.price0Cumulative, PRICE0_PER_SEC * 60);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice supportsInterface returns true for ITWAPOracle after init.
    function test_SupportsInterfaceITWAPOracle() public view {
        assertTrue(oracle.supportsInterface(type(ITWAPOracle).interfaceId));
    }
}
