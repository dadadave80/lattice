// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAPI3QRNGAdapter} from "@lattice/interfaces/oracles/IAPI3QRNGAdapter.sol";
import {API3QRNGAdapter} from "@lattice/oracles/api3/API3QRNGAdapter.sol";
import {API3QRNGAdapterLib} from "@lattice/oracles/libraries/API3QRNGAdapterLib.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCK CONTRACT
// ---------------------------------------------------------------------------

/// @notice Mock Diamond that combines AccessControl + API3QRNGAdapter, matching
///         the pattern from API3QRNGAdapterTest.t.sol.
contract MockAPI3QRNGAdapterForkContract is AccessControl, API3QRNGAdapter {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(AccessControl, API3QRNGAdapter) returns (bytes memory) {}

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
//                              FORK TESTS
// ---------------------------------------------------------------------------

/// @title API3QRNGAdapterFork
/// @notice Fork tests that exercise API3QRNGAdapter against a real Airnode RRP
///         contract on Ethereum mainnet.
///
/// Enabling fork tests:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   export API3_AIRNODE_RRP=<airnode-rrp-address>
///   forge test --match-path "test/fork/*"
///
/// Without API3_AIRNODE_RRP set, all tests in this contract are skipped. A live
/// request needs a funded sponsorWallet, which is out of scope here — these
/// tests cover the on-chain config round-trip only.
contract API3QRNGAdapterFork is Test {
    // -------------------------------------------------------------------------
    //                              State
    // -------------------------------------------------------------------------

    MockAPI3QRNGAdapterForkContract qrng;
    address admin = address(0x1);

    address airnodeRrp;

    address constant DUMMY_AIRNODE = address(0xA1);
    bytes32 constant DUMMY_ENDPOINT_ID = keccak256("QRNG_ENDPOINT");
    address constant DUMMY_SPONSOR_WALLET = address(0xB1);

    // -------------------------------------------------------------------------
    //                              Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        airnodeRrp = vm.envOr("API3_AIRNODE_RRP", address(0));
        if (airnodeRrp == address(0)) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet");

        qrng = new MockAPI3QRNGAdapterForkContract();
        qrng.initialize(admin);
    }

    // -------------------------------------------------------------------------
    //                              Tests
    // -------------------------------------------------------------------------

    /// @notice Configure the adapter with the live Airnode RRP and dummy fields,
    ///         then verify the config round-trips through getConfig.
    function test_Fork_ConfigRoundTrip() public {
        IAPI3QRNGAdapter.QRNGConfig memory cfg = IAPI3QRNGAdapter.QRNGConfig({
            airnodeRrp: airnodeRrp,
            airnode: DUMMY_AIRNODE,
            endpointId: DUMMY_ENDPOINT_ID,
            sponsorWallet: DUMMY_SPONSOR_WALLET
        });

        vm.prank(admin);
        qrng.setConfig(cfg);

        IAPI3QRNGAdapter.QRNGConfig memory stored = qrng.getConfig();
        assertEq(stored.airnodeRrp, airnodeRrp, "airnodeRrp mismatch");
        assertEq(stored.airnode, DUMMY_AIRNODE, "airnode mismatch");
        assertEq(stored.endpointId, DUMMY_ENDPOINT_ID, "endpointId mismatch");
        assertEq(stored.sponsorWallet, DUMMY_SPONSOR_WALLET, "sponsorWallet mismatch");
    }
}
