// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAPI3QRNGAdapter} from "@lattice/interfaces/IAPI3QRNGAdapter.sol";
import {IAirnodeRrpV0} from "@lattice/interfaces/external/IAirnodeRrpV0.sol";
import {API3QRNGAdapter} from "@lattice/oracles/API3QRNGAdapter.sol";
import {API3QRNGAdapterLib} from "@lattice/oracles/libraries/API3QRNGAdapterLib.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCKS
// ---------------------------------------------------------------------------

/// @notice Mock Airnode RRP that records calls and returns deterministic request IDs.
contract MockAirnodeRrp is IAirnodeRrpV0 {
    uint256 private _nonce;

    struct Sponsorship {
        address sponsor;
        address requester;
        bool status;
    }

    struct FullRequest {
        address airnode;
        bytes32 endpointId;
        address sponsor;
        address sponsorWallet;
        address fulfillAddress;
        bytes4 fulfillFunctionId;
        bytes parameters;
    }

    Sponsorship public lastSponsorship;
    mapping(bytes32 => FullRequest) public requests;

    function setSponsorshipStatus(address requester, bool sponsorshipStatus) external {
        lastSponsorship = Sponsorship({sponsor: msg.sender, requester: requester, status: sponsorshipStatus});
    }

    function makeFullRequest(
        address airnode,
        bytes32 endpointId,
        address sponsor,
        address sponsorWallet,
        address fulfillAddress,
        bytes4 fulfillFunctionId,
        bytes calldata parameters
    ) external returns (bytes32 requestId) {
        requestId = keccak256(abi.encodePacked(++_nonce));
        requests[requestId] = FullRequest({
            airnode: airnode,
            endpointId: endpointId,
            sponsor: sponsor,
            sponsorWallet: sponsorWallet,
            fulfillAddress: fulfillAddress,
            fulfillFunctionId: fulfillFunctionId,
            parameters: parameters
        });
    }

    /// @notice Simulate Airnode fulfillment by calling back on the consumer.
    function fulfill(address consumer, bytes32 requestId, bytes calldata data) external {
        IAPI3QRNGAdapter(consumer).fulfillRandomNumber(requestId, data);
    }
}

/// @notice Combines AccessControl + API3QRNGAdapter for testing.
contract MockAPI3QRNGAdapterContract is AccessControl, API3QRNGAdapter {
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        API3QRNGAdapterLib.__API3QRNGAdapter_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

contract API3QRNGAdapterTester is Test {
    MockAPI3QRNGAdapterContract qrng;
    MockAirnodeRrp rrp;

    address admin = address(0x1);
    address user = address(0x2);

    address airnode = address(0xA1);
    bytes32 constant ENDPOINT_ID = keccak256("QRNG_ENDPOINT");
    address sponsorWallet = address(0xB1);
    bytes32 constant USER_KEY = keccak256("USER_REQUEST_KEY");

    IAPI3QRNGAdapter.QRNGConfig validConfig;

    function setUp() public {
        qrng = new MockAPI3QRNGAdapterContract();
        qrng.initialize(admin);

        rrp = new MockAirnodeRrp();

        validConfig = IAPI3QRNGAdapter.QRNGConfig({
            airnodeRrp: address(rrp), airnode: airnode, endpointId: ENDPOINT_ID, sponsorWallet: sponsorWallet
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
        qrng.setConfig(validConfig);
    }

    /// @notice setConfig with zero airnodeRrp reverts QRNGInvalidConfig.
    function test_SetConfigRevertsOnZeroAirnodeRrp() public {
        IAPI3QRNGAdapter.QRNGConfig memory cfg = validConfig;
        cfg.airnodeRrp = address(0);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAPI3QRNGAdapter.QRNGInvalidConfig.selector));
        qrng.setConfig(cfg);
    }

    /// @notice setConfig with zero airnode reverts QRNGInvalidConfig.
    function test_SetConfigRevertsOnZeroAirnode() public {
        IAPI3QRNGAdapter.QRNGConfig memory cfg = validConfig;
        cfg.airnode = address(0);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAPI3QRNGAdapter.QRNGInvalidConfig.selector));
        qrng.setConfig(cfg);
    }

    /// @notice setConfig with zero endpointId reverts QRNGInvalidConfig.
    function test_SetConfigRevertsOnZeroEndpointId() public {
        IAPI3QRNGAdapter.QRNGConfig memory cfg = validConfig;
        cfg.endpointId = bytes32(0);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAPI3QRNGAdapter.QRNGInvalidConfig.selector));
        qrng.setConfig(cfg);
    }

    /// @notice setConfig with zero sponsorWallet reverts QRNGInvalidConfig.
    function test_SetConfigRevertsOnZeroSponsorWallet() public {
        IAPI3QRNGAdapter.QRNGConfig memory cfg = validConfig;
        cfg.sponsorWallet = address(0);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAPI3QRNGAdapter.QRNGInvalidConfig.selector));
        qrng.setConfig(cfg);
    }

    /// @notice Admin can set config and it is stored correctly.
    function test_SetConfigByAdmin() public {
        vm.prank(admin);
        qrng.setConfig(validConfig);

        IAPI3QRNGAdapter.QRNGConfig memory stored = qrng.getConfig();
        assertEq(stored.airnodeRrp, address(rrp));
        assertEq(stored.airnode, airnode);
        assertEq(stored.endpointId, ENDPOINT_ID);
        assertEq(stored.sponsorWallet, sponsorWallet);
    }

    /// @notice setConfig emits QRNGConfigSet event.
    function test_SetConfigEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit IAPI3QRNGAdapter.QRNGConfigSet(address(rrp), airnode, ENDPOINT_ID, sponsorWallet);
        qrng.setConfig(validConfig);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       SELF SPONSORSHIP TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice setSelfSponsorship registers this contract with the RRP.
    function test_SetSelfSponsorshipCallsRrp() public {
        vm.startPrank(admin);
        qrng.setConfig(validConfig);

        vm.expectEmit(false, false, false, true);
        emit IAPI3QRNGAdapter.QRNGSelfSponsorshipSet(true);
        qrng.setSelfSponsorship(true);
        vm.stopPrank();

        (address sponsor, address requester, bool status) = rrp.lastSponsorship();
        assertEq(sponsor, address(qrng), "sponsor should be the adapter");
        assertEq(requester, address(qrng), "requester should be the adapter");
        assertTrue(status, "status should be true");
    }

    /// @notice setSelfSponsorship can revoke (status false).
    function test_SetSelfSponsorshipRevoke() public {
        vm.startPrank(admin);
        qrng.setConfig(validConfig);
        qrng.setSelfSponsorship(false);
        vm.stopPrank();

        (,, bool status) = rrp.lastSponsorship();
        assertFalse(status, "status should be false");
    }

    /// @notice Non-admin cannot call setSelfSponsorship.
    function test_SetSelfSponsorshipRevertsForNonAdmin() public {
        vm.prank(admin);
        qrng.setConfig(validConfig);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        qrng.setSelfSponsorship(true);
    }

    /// @notice setSelfSponsorship without config reverts QRNGNotConfigured.
    function test_SetSelfSponsorshipRevertsWhenNotConfigured() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAPI3QRNGAdapter.QRNGNotConfigured.selector));
        qrng.setSelfSponsorship(true);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      REQUEST RANDOM NUMBER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice requestRandomNumber stores userKey, returns ID, emits event, passes correct args.
    function test_RequestRandomNumberStoresAndEmits() public {
        vm.startPrank(admin);
        qrng.setConfig(validConfig);

        bytes32 expectedId = keccak256(abi.encodePacked(uint256(1)));

        vm.expectEmit(true, true, false, true);
        emit IAPI3QRNGAdapter.RandomNumberRequested(expectedId, USER_KEY);
        bytes32 requestId = qrng.requestRandomNumber(USER_KEY);
        vm.stopPrank();

        assertEq(requestId, expectedId);
        assertEq(qrng.getUserKey(requestId), USER_KEY);

        (
            address reqAirnode,
            bytes32 reqEndpoint,
            address reqSponsor,
            address reqSponsorWallet,
            address reqFulfillAddress,
            bytes4 reqFulfillFunctionId,
        ) = rrp.requests(requestId);
        assertEq(reqAirnode, airnode, "airnode mismatch");
        assertEq(reqEndpoint, ENDPOINT_ID, "endpoint mismatch");
        assertEq(reqSponsor, address(qrng), "sponsor should be the adapter");
        assertEq(reqSponsorWallet, sponsorWallet, "sponsorWallet mismatch");
        assertEq(reqFulfillAddress, address(qrng), "fulfillAddress should be the adapter");
        assertEq(
            reqFulfillFunctionId,
            IAPI3QRNGAdapter.fulfillRandomNumber.selector,
            "fulfillFunctionId should be fulfillRandomNumber selector"
        );
    }

    /// @notice requestRandomNumber with bytes32(0) userKey reverts QRNGInvalidUserKey.
    function test_RequestRandomNumberRejectsZeroUserKey() public {
        vm.startPrank(admin);
        qrng.setConfig(validConfig);

        vm.expectRevert(abi.encodeWithSelector(IAPI3QRNGAdapter.QRNGInvalidUserKey.selector));
        qrng.requestRandomNumber(bytes32(0));
        vm.stopPrank();
    }

    /// @notice requestRandomNumber without config reverts QRNGNotConfigured.
    function test_RequestRandomNumberRevertsWhenNotConfigured() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAPI3QRNGAdapter.QRNGNotConfigured.selector));
        qrng.requestRandomNumber(USER_KEY);
    }

    /// @notice Non-admin cannot call requestRandomNumber.
    function test_RequestRandomNumberRevertsForNonAdmin() public {
        vm.prank(admin);
        qrng.setConfig(validConfig);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        qrng.requestRandomNumber(USER_KEY);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      FULFILL RANDOM NUMBER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice fulfillRandomNumber from a non-RRP caller reverts QRNGOnlyAirnodeRrp.
    function test_FulfillRevertsFromNonRrp() public {
        vm.startPrank(admin);
        qrng.setConfig(validConfig);
        bytes32 requestId = qrng.requestRandomNumber(USER_KEY);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IAPI3QRNGAdapter.QRNGOnlyAirnodeRrp.selector, user));
        qrng.fulfillRandomNumber(requestId, abi.encode(uint256(777)));
    }

    /// @notice fulfillRandomNumber for unknown requestId reverts QRNGRequestNotFound.
    function test_FulfillRevertsOnUnknownRequestId() public {
        vm.prank(admin);
        qrng.setConfig(validConfig);

        bytes32 unknownId = keccak256("UNKNOWN");
        vm.expectRevert(abi.encodeWithSelector(IAPI3QRNGAdapter.QRNGRequestNotFound.selector, unknownId));
        rrp.fulfill(address(qrng), unknownId, abi.encode(uint256(777)));
    }

    /// @notice RRP fulfillment decodes the random number, clears the entry, and emits.
    function test_FulfillFromRrpClearsAndEmits() public {
        vm.startPrank(admin);
        qrng.setConfig(validConfig);
        bytes32 requestId = qrng.requestRandomNumber(USER_KEY);
        vm.stopPrank();

        // Verify pending entry exists.
        assertEq(qrng.getUserKey(requestId), USER_KEY);

        uint256 rand = 0xC0FFEE;

        vm.expectEmit(true, true, false, true);
        emit IAPI3QRNGAdapter.RandomNumberFulfilled(requestId, USER_KEY, rand);
        rrp.fulfill(address(qrng), requestId, abi.encode(rand));

        // Pending entry should be cleared.
        assertEq(qrng.getUserKey(requestId), bytes32(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice supportsInterface returns true for IAPI3QRNGAdapter after init.
    function test_SupportsInterfaceAPI3QRNGAdapter() public view {
        assertTrue(qrng.supportsInterface(type(IAPI3QRNGAdapter).interfaceId));
    }
}
