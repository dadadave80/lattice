// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {PythEntropyAdapterTestBase} from "@lattice-test/base/PythEntropyAdapterTestBase.sol";
import {IEntropy} from "@lattice/interfaces/external/pyth/IEntropy.sol";
import {IPythEntropyAdapter} from "@lattice/interfaces/oracles/IPythEntropyAdapter.sol";
import {PythEntropyAdapter} from "@lattice/oracles/pyth/PythEntropyAdapter.sol";

// ---------------------------------------------------------------------------
//                          EXTERNAL FIXTURE (Pyth Entropy)
// ---------------------------------------------------------------------------

/// @notice Mock Pyth Entropy contract that returns incrementing sequence numbers. This is the EXTERNAL Pyth
///         Entropy protocol the facet talks to (NOT the facet under test) — kept as a test fixture that drives
///         the `entropyCallback` callback into the diamond.
contract MockEntropy is IEntropy {
    address public defaultProvider;
    uint128 public fee;
    uint64 private _nextSequence = 1;

    mapping(uint64 => uint256) public valueForwarded;

    constructor(address _defaultProvider, uint128 _fee) {
        defaultProvider = _defaultProvider;
        fee = _fee;
    }

    function setFee(uint128 _fee) external {
        fee = _fee;
    }

    function getDefaultProvider() external view returns (address provider) {
        return defaultProvider;
    }

    function getFee(address) external view returns (uint128 feeAmount) {
        return fee;
    }

    function requestWithCallback(address, bytes32) external payable returns (uint64 assignedSequenceNumber) {
        assignedSequenceNumber = _nextSequence++;
        valueForwarded[assignedSequenceNumber] = msg.value;
    }

    /// @notice Simulate Entropy fulfillment by calling back on the consumer.
    function fulfill(address consumer, uint64 seq, address provider, bytes32 rand) external {
        IPythEntropyAdapter(consumer).entropyCallback(seq, provider, rand);
    }
}

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

/// @notice Exercises the Pyth Entropy facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployPythEntropyAdapter} script (see {PythEntropyAdapterTestBase}) — every call below routes
///         through the diamond's `delegatecall` dispatch, not a flattened inheritance mock. Admin gating is
///         enforced by the cut-in `AccessControl` facet; `supportsInterface` by the cut-in `ERC165Facet`.
contract PythEntropyAdapterTest is PythEntropyAdapterTestBase {
    MockEntropy entropy;

    address admin = address(0x1);
    address user = address(0x2);
    address defaultProvider = address(0xDEF);
    address customProvider = address(0xCAFE);

    bytes32 constant USER_KEY = keccak256("USER_REQUEST_KEY");
    bytes32 constant USER_RANDOM = keccak256("USER_RANDOM_NUMBER");

    uint128 constant FEE = 1 ether;

    IPythEntropyAdapter.EntropyConfig validConfig;

    function setUp() public {
        diamond = _deployPythEntropyAdapter(admin);
        entropyContract = PythEntropyAdapter(diamond);

        entropy = new MockEntropy(defaultProvider, FEE);

        // provider == address(0) => resolve to default provider.
        validConfig = IPythEntropyAdapter.EntropyConfig({entropy: address(entropy), provider: address(0)});
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
        entropyContract.setConfig(validConfig);
    }

    /// @notice setConfig with zero entropy reverts EntropyInvalidConfig.
    function test_SetConfigRevertsOnZeroEntropy() public {
        IPythEntropyAdapter.EntropyConfig memory cfg = validConfig;
        cfg.entropy = address(0);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IPythEntropyAdapter.EntropyInvalidConfig.selector));
        entropyContract.setConfig(cfg);
    }

    /// @notice Admin can set config and it is stored correctly.
    function test_SetConfigByAdmin() public {
        IPythEntropyAdapter.EntropyConfig memory cfg =
            IPythEntropyAdapter.EntropyConfig({entropy: address(entropy), provider: customProvider});
        vm.prank(admin);
        entropyContract.setConfig(cfg);

        IPythEntropyAdapter.EntropyConfig memory stored = entropyContract.getConfig();
        assertEq(stored.entropy, address(entropy));
        assertEq(stored.provider, customProvider);
    }

    /// @notice setConfig emits EntropyConfigSet event.
    function test_SetConfigEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit IPythEntropyAdapter.EntropyConfigSet(address(entropy), address(0));
        entropyContract.setConfig(validConfig);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              GET FEE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice getFee with provider == address(0) resolves the default provider.
    function test_GetFeeResolvesDefaultProvider() public {
        vm.prank(admin);
        entropyContract.setConfig(validConfig);

        assertEq(entropyContract.getFee(), uint256(FEE));
    }

    /// @notice getFee without config reverts EntropyNotConfigured.
    function test_GetFeeRevertsWhenNotConfigured() public {
        vm.expectRevert(abi.encodeWithSelector(IPythEntropyAdapter.EntropyNotConfigured.selector));
        entropyContract.getFee();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        REQUEST RANDOM NUMBER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice requestRandomNumber stores userKey, emits event, forwards exact fee, refunds excess.
    function test_RequestRandomNumberStoresEmitsForwardsAndRefunds() public {
        vm.prank(admin);
        entropyContract.setConfig(validConfig);

        // Fund admin and send fee + 1 wei; the 1 wei should be refunded.
        vm.deal(admin, FEE + 1);
        uint256 balanceBefore = admin.balance;

        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit IPythEntropyAdapter.RandomNumberRequested(1, USER_KEY);
        uint64 seq = entropyContract.requestRandomNumber{value: FEE + 1}(USER_KEY, USER_RANDOM);

        assertEq(seq, 1);
        assertEq(entropyContract.getUserKey(seq), USER_KEY);
        // Exactly FEE forwarded to the Entropy contract.
        assertEq(entropy.valueForwarded(seq), uint256(FEE));
        // Caller refunded the 1 wei excess (net spend == FEE).
        assertEq(admin.balance, balanceBefore - uint256(FEE));
    }

    /// @notice requestRandomNumber with insufficient fee reverts EntropyInsufficientFee.
    function test_RequestRandomNumberRevertsOnInsufficientFee() public {
        vm.prank(admin);
        entropyContract.setConfig(validConfig);

        vm.deal(admin, FEE);
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IPythEntropyAdapter.EntropyInsufficientFee.selector, uint256(FEE) - 1, uint256(FEE))
        );
        entropyContract.requestRandomNumber{value: FEE - 1}(USER_KEY, USER_RANDOM);
    }

    /// @notice requestRandomNumber with zero userKey reverts EntropyInvalidUserKey.
    function test_RequestRandomNumberRejectsZeroUserKey() public {
        vm.prank(admin);
        entropyContract.setConfig(validConfig);

        vm.deal(admin, FEE);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IPythEntropyAdapter.EntropyInvalidUserKey.selector));
        entropyContract.requestRandomNumber{value: FEE}(bytes32(0), USER_RANDOM);
    }

    /// @notice requestRandomNumber without config reverts EntropyNotConfigured.
    function test_RequestRandomNumberRevertsWhenNotConfigured() public {
        vm.deal(admin, FEE);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IPythEntropyAdapter.EntropyNotConfigured.selector));
        entropyContract.requestRandomNumber{value: FEE}(USER_KEY, USER_RANDOM);
    }

    /// @notice Non-admin cannot call requestRandomNumber.
    function test_RequestRandomNumberRevertsForNonAdmin() public {
        vm.prank(admin);
        entropyContract.setConfig(validConfig);

        vm.deal(user, FEE);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        entropyContract.requestRandomNumber{value: FEE}(USER_KEY, USER_RANDOM);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          ENTROPY CALLBACK TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice entropyCallback from a non-entropy caller reverts EntropyOnlyEntropy.
    function test_EntropyCallbackRevertsFromNonEntropy() public {
        vm.prank(admin);
        entropyContract.setConfig(validConfig);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IPythEntropyAdapter.EntropyOnlyEntropy.selector, user));
        entropyContract.entropyCallback(1, defaultProvider, keccak256("RAND"));
    }

    /// @notice entropyCallback for an unknown sequence reverts EntropyRequestNotFound.
    function test_EntropyCallbackRevertsOnUnknownSequence() public {
        vm.prank(admin);
        entropyContract.setConfig(validConfig);

        vm.expectRevert(abi.encodeWithSelector(IPythEntropyAdapter.EntropyRequestNotFound.selector, uint64(999)));
        entropy.fulfill(diamond, 999, defaultProvider, keccak256("RAND"));
    }

    /// @notice Successful callback clears the pending entry and emits RandomNumberFulfilled.
    function test_EntropyCallbackClearsAndEmits() public {
        vm.prank(admin);
        entropyContract.setConfig(validConfig);

        vm.deal(admin, FEE);
        vm.prank(admin);
        uint64 seq = entropyContract.requestRandomNumber{value: FEE}(USER_KEY, USER_RANDOM);

        // Verify pending entry exists.
        assertEq(entropyContract.getUserKey(seq), USER_KEY);

        bytes32 rand = keccak256("DELIVERED_RANDOM");
        vm.expectEmit(true, true, false, true);
        emit IPythEntropyAdapter.RandomNumberFulfilled(seq, USER_KEY, rand);
        entropy.fulfill(diamond, seq, defaultProvider, rand);

        // Pending entry should be cleared.
        assertEq(entropyContract.getUserKey(seq), bytes32(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice supportsInterface returns true for IPythEntropyAdapter after init.
    function test_SupportsInterfacePythEntropyAdapter() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IPythEntropyAdapter).interfaceId));
    }
}
