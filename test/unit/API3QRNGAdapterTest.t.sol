// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {API3QRNGAdapterTestBase} from "@lattice-test/base/API3QRNGAdapterTestBase.sol";
import {IAirnodeRrpV0} from "@lattice/interfaces/external/api3/IAirnodeRrpV0.sol";
import {IAPI3QRNGAdapter} from "@lattice/interfaces/oracles/IAPI3QRNGAdapter.sol";
import {API3QRNGAdapter} from "@lattice/oracles/api3/API3QRNGAdapter.sol";

// ---------------------------------------------------------------------------
//                          EXTERNAL FIXTURE (Airnode RRP)
// ---------------------------------------------------------------------------

/// @notice Mock Airnode RRP that records calls and returns deterministic request IDs. This is the EXTERNAL API3
///         Airnode protocol the facet talks to (NOT the facet under test) — kept as a test fixture that drives
///         the `fulfillRandomNumber` callback into the diamond.
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

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

/// @notice Exercises the API3 QRNG facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployAPI3QRNGAdapter} script (see {API3QRNGAdapterTestBase}) — every call below routes through the
///         diamond's `delegatecall` dispatch, not a flattened inheritance mock. Admin gating is enforced by the
///         cut-in `AccessControl` facet; `supportsInterface` by the cut-in `ERC165Facet`.
contract API3QRNGAdapterTest is API3QRNGAdapterTestBase {
    MockAirnodeRrp rrp;

    address admin = address(0x1);
    address user = address(0x2);

    address airnode = address(0xA1);
    bytes32 constant ENDPOINT_ID = keccak256("QRNG_ENDPOINT");
    address sponsorWallet = address(0xB1);
    bytes32 constant USER_KEY = keccak256("USER_REQUEST_KEY");

    IAPI3QRNGAdapter.QRNGConfig validConfig;

    function setUp() public {
        diamond = _deployAPI3QRNGAdapter(admin);
        qrng = API3QRNGAdapter(diamond);

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
        assertEq(sponsor, diamond, "sponsor should be the adapter");
        assertEq(requester, diamond, "requester should be the adapter");
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
        assertEq(reqSponsor, diamond, "sponsor should be the adapter");
        assertEq(reqSponsorWallet, sponsorWallet, "sponsorWallet mismatch");
        assertEq(reqFulfillAddress, diamond, "fulfillAddress should be the adapter");
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
        rrp.fulfill(diamond, unknownId, abi.encode(uint256(777)));
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
        rrp.fulfill(diamond, requestId, abi.encode(rand));

        // Pending entry should be cleared.
        assertEq(qrng.getUserKey(requestId), bytes32(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice supportsInterface returns true for IAPI3QRNGAdapter after init.
    function test_SupportsInterfaceAPI3QRNGAdapter() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IAPI3QRNGAdapter).interfaceId));
    }
}
