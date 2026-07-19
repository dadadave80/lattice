// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {GelatoVRFAdapterTestBase} from "@lattice-test/base/GelatoVRFAdapterTestBase.sol";
import {IGelatoVRFConsumer} from "@lattice/interfaces/external/gelato/IGelatoVRFConsumer.sol";
import {IGelatoVRFAdapter} from "@lattice/interfaces/oracles/IGelatoVRFAdapter.sol";
import {GelatoVRFAdapter} from "@lattice/oracles/GelatoVRFAdapter.sol";

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

/// @notice Exercises the Gelato VRF facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployGelatoVRFAdapter} script (see {GelatoVRFAdapterTestBase}) — every call below routes through
///         the diamond's `delegatecall` dispatch, not a flattened inheritance mock. The Gelato `operator`
///         (an EOA in these tests) drives the `fulfillRandomness` callback into the diamond. Admin gating is
///         enforced by the cut-in `AccessControl` facet; `supportsInterface` by the cut-in `ERC165Facet`.
contract GelatoVRFAdapterTest is GelatoVRFAdapterTestBase {
    address admin = address(0x1);
    address user = address(0x2);
    address operator = address(0xBEEF);

    bytes32 constant USER_KEY = keccak256("USER_REQUEST_KEY");

    // drand quicknet beacon genesis / period (mirrors the library constants).
    uint256 constant GENESIS = 1_692_803_367;
    uint256 constant PERIOD = 3;

    function setUp() public {
        diamond = _deployGelatoVRFAdapter(admin);
        adapter = GelatoVRFAdapter(diamond);

        // Warp to a realistic timestamp so _round() returns a realistic round.
        vm.warp(1_700_000_000);
    }

    /// @notice Computes the expected drand round the way the library does.
    function _expectedRound() internal view returns (uint256) {
        uint256 elapsed = block.timestamp > GENESIS ? block.timestamp - GENESIS : 0;
        return elapsed / PERIOD + 1;
    }

    /// @notice Builds the `dataWithRound` payload exactly like the library.
    function _dataWithRound(uint256 round, uint256 requestId, bytes32 userKey) internal pure returns (bytes memory) {
        return abi.encode(round, abi.encode(requestId, userKey));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           SET OPERATOR TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Non-admin cannot set the operator.
    function test_SetOperatorRevertsForNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        adapter.setOperator(operator);
    }

    /// @notice setOperator with zero address reverts GelatoVRFInvalidOperator.
    function test_SetOperatorRevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IGelatoVRFAdapter.GelatoVRFInvalidOperator.selector));
        adapter.setOperator(address(0));
    }

    /// @notice Admin can set the operator and it is stored.
    function test_SetOperatorByAdmin() public {
        vm.prank(admin);
        adapter.setOperator(operator);
        assertEq(adapter.getOperator(), operator);
    }

    /// @notice setOperator emits GelatoVRFOperatorSet.
    function test_SetOperatorEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit IGelatoVRFAdapter.GelatoVRFOperatorSet(operator);
        adapter.setOperator(operator);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         REQUEST RANDOMNESS TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice requestRandomness with bytes32(0) userKey reverts GelatoVRFInvalidUserKey.
    function test_RequestRandomnessRejectsZeroUserKey() public {
        vm.prank(admin);
        adapter.setOperator(operator);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IGelatoVRFAdapter.GelatoVRFInvalidUserKey.selector));
        adapter.requestRandomness(bytes32(0));
    }

    /// @notice requestRandomness without an operator reverts GelatoVRFNotConfigured.
    function test_RequestRandomnessRevertsWhenNotConfigured() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IGelatoVRFAdapter.GelatoVRFNotConfigured.selector));
        adapter.requestRandomness(USER_KEY);
    }

    /// @notice Non-admin cannot call requestRandomness.
    function test_RequestRandomnessRevertsForNonAdmin() public {
        vm.prank(admin);
        adapter.setOperator(operator);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        adapter.requestRandomness(USER_KEY);
    }

    /// @notice requestRandomness increments requestId from 0, stores the key,
    ///         and emits BOTH RandomnessRequested and RequestedRandomness.
    function test_RequestRandomnessStoresAndEmitsBoth() public {
        vm.prank(admin);
        adapter.setOperator(operator);

        uint256 round = _expectedRound();
        bytes memory dataWithRound = _dataWithRound(round, 0, USER_KEY);

        vm.expectEmit(true, true, false, true);
        emit IGelatoVRFAdapter.RandomnessRequested(0, USER_KEY, round);
        vm.expectEmit(false, false, false, true);
        emit IGelatoVRFConsumer.RequestedRandomness(round, dataWithRound);

        vm.prank(admin);
        uint256 requestId = adapter.requestRandomness(USER_KEY);

        assertEq(requestId, 0, "first request id should be 0");
        assertEq(adapter.getUserKey(requestId), USER_KEY, "user key not stored");

        // A second request increments the ID.
        vm.prank(admin);
        uint256 requestId2 = adapter.requestRandomness(USER_KEY);
        assertEq(requestId2, 1, "second request id should be 1");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         FULFILL RANDOMNESS TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice fulfillRandomness from a non-operator reverts GelatoVRFOnlyOperator.
    function test_FulfillRevertsFromNonOperator() public {
        vm.prank(admin);
        adapter.setOperator(operator);

        vm.prank(admin);
        uint256 requestId = adapter.requestRandomness(USER_KEY);

        uint256 round = _expectedRound();
        bytes memory dataWithRound = _dataWithRound(round, requestId, USER_KEY);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IGelatoVRFAdapter.GelatoVRFOnlyOperator.selector, user));
        adapter.fulfillRandomness(12345, dataWithRound);
    }

    /// @notice fulfillRandomness for an unknown requestId reverts GelatoVRFRequestNotFound.
    function test_FulfillRevertsOnUnknownRequestId() public {
        vm.prank(admin);
        adapter.setOperator(operator);

        uint256 round = _expectedRound();
        bytes memory dataWithRound = _dataWithRound(round, 999, USER_KEY);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IGelatoVRFAdapter.GelatoVRFRequestNotFound.selector, uint256(999)));
        adapter.fulfillRandomness(12345, dataWithRound);
    }

    /// @notice fulfillRandomness with a mismatched userKey reverts GelatoVRFRequestNotFound.
    function test_FulfillRevertsOnMismatchedUserKey() public {
        vm.prank(admin);
        adapter.setOperator(operator);

        vm.prank(admin);
        uint256 requestId = adapter.requestRandomness(USER_KEY);

        uint256 round = _expectedRound();
        bytes memory dataWithRound = _dataWithRound(round, requestId, keccak256("WRONG_KEY"));

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IGelatoVRFAdapter.GelatoVRFRequestNotFound.selector, requestId));
        adapter.fulfillRandomness(12345, dataWithRound);
    }

    /// @notice Operator fulfillment clears the pending entry and emits RandomnessFulfilled.
    function test_FulfillFromOperatorClearsAndEmits() public {
        vm.prank(admin);
        adapter.setOperator(operator);

        vm.prank(admin);
        uint256 requestId = adapter.requestRandomness(USER_KEY);

        assertEq(adapter.getUserKey(requestId), USER_KEY, "pending entry should exist");

        uint256 round = _expectedRound();
        bytes memory dataWithRound = _dataWithRound(round, requestId, USER_KEY);

        uint256 randomness = 777;
        uint256 expectedDerived = uint256(keccak256(abi.encode(randomness, address(adapter), block.chainid, requestId)));

        vm.expectEmit(true, true, false, true);
        emit IGelatoVRFAdapter.RandomnessFulfilled(requestId, USER_KEY, expectedDerived);

        vm.prank(operator);
        adapter.fulfillRandomness(randomness, dataWithRound);

        // Pending entry should be cleared.
        assertEq(adapter.getUserKey(requestId), bytes32(0), "pending entry should be cleared");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice supportsInterface returns true for IGelatoVRFAdapter after init.
    function test_SupportsInterfaceGelatoVRFAdapter() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IGelatoVRFAdapter).interfaceId));
    }
}
