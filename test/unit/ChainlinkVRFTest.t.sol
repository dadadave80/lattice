// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ChainlinkVRFTestBase} from "@lattice-test/base/ChainlinkVRFTestBase.sol";
import {IVRFCoordinatorV2Plus} from "@lattice/interfaces/external/IVRFCoordinatorV2Plus.sol";
import {IChainlinkVRF} from "@lattice/interfaces/oracles/IChainlinkVRF.sol";
import {ChainlinkVRF} from "@lattice/oracles/ChainlinkVRF.sol";

// ---------------------------------------------------------------------------
//                          EXTERNAL FIXTURE (coordinator)
// ---------------------------------------------------------------------------

/// @notice Mock VRF coordinator that returns incrementing request IDs. This is the EXTERNAL Chainlink
///         coordinator the facet talks to (NOT the facet under test) — kept as a test fixture that drives the
///         `rawFulfillRandomWords` callback into the diamond.
contract MockVRFCoordinator is IVRFCoordinatorV2Plus {
    uint256 private _nextRequestId = 1;

    struct Request {
        bytes32 keyHash;
        uint256 subId;
        uint16 requestConfirmations;
        uint32 callbackGasLimit;
        uint32 numWords;
    }

    mapping(uint256 => Request) public requests;

    function requestRandomWords(RandomWordsRequest calldata req) external returns (uint256 requestId) {
        requestId = _nextRequestId++;
        requests[requestId] = Request({
            keyHash: req.keyHash,
            subId: req.subId,
            requestConfirmations: req.requestConfirmations,
            callbackGasLimit: req.callbackGasLimit,
            numWords: req.numWords
        });
    }

    /// @notice Simulate coordinator fulfillment by calling back on the consumer.
    function fulfillRandomWords(address consumer, uint256 requestId, uint256[] calldata randomWords) external {
        IChainlinkVRF(consumer).rawFulfillRandomWords(requestId, randomWords);
    }
}

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

/// @notice Exercises the Chainlink VRF facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployChainlinkVRF} script (see {ChainlinkVRFTestBase}) — every call below routes through the
///         diamond's `delegatecall` dispatch, not a flattened inheritance mock. Admin gating is enforced by the
///         cut-in `AccessControl` facet; `supportsInterface` by the cut-in `ERC165Facet`.
contract ChainlinkVRFTest is ChainlinkVRFTestBase {
    MockVRFCoordinator coordinator;

    address admin = address(0x1);
    address user = address(0x2);

    bytes32 constant KEY_HASH = keccak256("VRF_KEY_HASH");
    bytes32 constant USER_KEY = keccak256("USER_REQUEST_KEY");
    uint256 constant SUB_ID = 42;
    uint16 constant REQUEST_CONFIRMATIONS = 3;
    uint32 constant CALLBACK_GAS_LIMIT = 100_000;

    IChainlinkVRF.VRFConfig validConfig;

    function setUp() public {
        diamond = _deployChainlinkVRF(admin);
        vrf = ChainlinkVRF(diamond);

        coordinator = new MockVRFCoordinator();

        validConfig = IChainlinkVRF.VRFConfig({
            coordinator: address(coordinator),
            subscriptionId: SUB_ID,
            keyHash: KEY_HASH,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: CALLBACK_GAS_LIMIT
        });
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           SET CONFIG TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Non-admin cannot set config.
    function test_SetConfigRevertsForNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        vrf.setConfig(validConfig);
    }

    /// @notice setConfig with zero coordinator reverts VRFInvalidConfig.
    function test_SetConfigRevertsOnZeroCoordinator() public {
        IChainlinkVRF.VRFConfig memory cfg = validConfig;
        cfg.coordinator = address(0);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IChainlinkVRF.VRFInvalidConfig.selector));
        vrf.setConfig(cfg);
    }

    /// @notice setConfig with zero subscriptionId reverts VRFInvalidConfig.
    function test_SetConfigRevertsOnZeroSubscriptionId() public {
        IChainlinkVRF.VRFConfig memory cfg = validConfig;
        cfg.subscriptionId = 0;
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IChainlinkVRF.VRFInvalidConfig.selector));
        vrf.setConfig(cfg);
    }

    /// @notice setConfig with zero keyHash reverts VRFInvalidConfig.
    function test_SetConfigRevertsOnZeroKeyHash() public {
        IChainlinkVRF.VRFConfig memory cfg = validConfig;
        cfg.keyHash = bytes32(0);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IChainlinkVRF.VRFInvalidConfig.selector));
        vrf.setConfig(cfg);
    }

    /// @notice Admin can set config and it is stored correctly.
    function test_SetConfigByAdmin() public {
        vm.prank(admin);
        vrf.setConfig(validConfig);

        IChainlinkVRF.VRFConfig memory stored = vrf.getConfig();
        assertEq(stored.coordinator, address(coordinator));
        assertEq(stored.subscriptionId, SUB_ID);
        assertEq(stored.keyHash, KEY_HASH);
        assertEq(stored.requestConfirmations, REQUEST_CONFIRMATIONS);
        assertEq(stored.callbackGasLimit, CALLBACK_GAS_LIMIT);
    }

    /// @notice setConfig emits VRFConfigSet event.
    function test_SetConfigEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit IChainlinkVRF.VRFConfigSet(address(coordinator), SUB_ID, KEY_HASH);
        vrf.setConfig(validConfig);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        REQUEST RANDOM WORDS TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice requestRandomWords stores userKey, returns ID, emits event.
    function test_RequestRandomWordsStoresAndEmits() public {
        vm.startPrank(admin);
        vrf.setConfig(validConfig);

        vm.expectEmit(true, true, false, true);
        emit IChainlinkVRF.RandomWordsRequested(1, USER_KEY, 1);
        uint256 requestId = vrf.requestRandomWords(USER_KEY, 1);
        vm.stopPrank();

        assertEq(requestId, 1);
        assertEq(vrf.getUserKey(requestId), USER_KEY);
    }

    /// @notice requestRandomWords without config reverts VRFNotConfigured.
    function test_RequestRandomWordsRevertsWhenNotConfigured() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IChainlinkVRF.VRFNotConfigured.selector));
        vrf.requestRandomWords(USER_KEY, 1);
    }

    /// @notice Non-admin cannot call requestRandomWords.
    function test_RequestRandomWordsRevertsForNonAdmin() public {
        vm.prank(admin);
        vrf.setConfig(validConfig);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        vrf.requestRandomWords(USER_KEY, 1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       RAW FULFILL RANDOM WORDS TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice rawFulfillRandomWords from a non-coordinator reverts VRFOnlyCoordinator.
    function test_RawFulfillRevertsFromNonCoordinator() public {
        vm.prank(admin);
        vrf.setConfig(validConfig);

        uint256[] memory words = new uint256[](1);
        words[0] = 12345;

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IChainlinkVRF.VRFOnlyCoordinator.selector, user));
        vrf.rawFulfillRandomWords(1, words);
    }

    /// @notice rawFulfillRandomWords for unknown requestId reverts VRFRequestNotFound.
    function test_RawFulfillRevertsOnUnknownRequestId() public {
        vm.prank(admin);
        vrf.setConfig(validConfig);

        uint256[] memory words = new uint256[](1);
        words[0] = 12345;

        vm.prank(address(coordinator));
        vm.expectRevert(abi.encodeWithSelector(IChainlinkVRF.VRFRequestNotFound.selector, uint256(999)));
        vrf.rawFulfillRandomWords(999, words);
    }

    /// @notice Coordinator fulfillment clears pending entry and emits event.
    function test_RawFulfillFromCoordinatorClearsAndEmits() public {
        vm.startPrank(admin);
        vrf.setConfig(validConfig);
        uint256 requestId = vrf.requestRandomWords(USER_KEY, 1);
        vm.stopPrank();

        // Verify pending entry exists
        assertEq(vrf.getUserKey(requestId), USER_KEY);

        uint256[] memory words = new uint256[](1);
        words[0] = 777;

        vm.expectEmit(true, true, false, false);
        emit IChainlinkVRF.RandomWordsFulfilled(requestId, USER_KEY);
        coordinator.fulfillRandomWords(diamond, requestId, words);

        // Pending entry should be cleared
        assertEq(vrf.getUserKey(requestId), bytes32(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         ZERO USERKEY TESTS (T2 / H1)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice requestRandomWords with bytes32(0) userKey reverts VRFInvalidUserKey.
    /// @dev Prevents silent sentinel collision: bytes32(0) is used by
    ///      rawFulfillRandomWords to detect a missing pending request.
    function test_RequestRandomWordsRejectsZeroUserKey() public {
        vm.prank(admin);
        vrf.setConfig(validConfig);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IChainlinkVRF.VRFInvalidUserKey.selector));
        vrf.requestRandomWords(bytes32(0), 1);
    }

    /// @notice Fulfilling a request with a non-zero userKey still works after
    ///         the zero-userKey guard is in place (regression test).
    function test_FulfillmentUnaffectedByZeroKeyGuard() public {
        vm.startPrank(admin);
        vrf.setConfig(validConfig);
        uint256 requestId = vrf.requestRandomWords(USER_KEY, 1);
        vm.stopPrank();

        uint256[] memory words = new uint256[](1);
        words[0] = 42;
        coordinator.fulfillRandomWords(diamond, requestId, words);

        assertEq(vrf.getUserKey(requestId), bytes32(0), "pending entry should be cleared");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice supportsInterface returns true for IChainlinkVRF after init.
    function test_SupportsInterfaceChainlinkVRF() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IChainlinkVRF).interfaceId));
    }
}
