// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAPI3QRNGAdapter} from "@lattice/interfaces/oracles/IAPI3QRNGAdapter.sol";
import {API3QRNGAdapter} from "@lattice/oracles/api3/API3QRNGAdapter.sol";
import {API3QRNGAdapterLib} from "@lattice/oracles/api3/API3QRNGAdapterLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCK CONTRACT
// ---------------------------------------------------------------------------

/// @notice Mock Diamond that combines AccessControl + API3QRNGAdapter, matching
///         the pattern from API3QRNGAdapterTest.t.sol.
contract MockAPI3QRNGAdapterForkContract is AccessControl, API3QRNGAdapter, Initializable {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(AccessControl, API3QRNGAdapter) returns (bytes memory) {}

    function initialize(address _admin) external initializer {
        AccessControlLib.__AccessControl_init(_admin);
        API3QRNGAdapterLib.__API3QRNGAdapter_init();
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

// ---------------------------------------------------------------------------
//                              FORK TESTS
// ---------------------------------------------------------------------------

/// @title API3QRNGAdapterFork
/// @notice Fork tests that exercise API3QRNGAdapter against the real AirnodeRrpV0
///         contract on Ethereum mainnet.
///
/// Enabling fork tests:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   forge test --match-path "test/fork/API3QRNGAdapterFork.t.sol"
///
/// Without MAINNET_RPC_URL set, all tests in this contract are skipped. The fork
/// is pinned (API3_QRNG_FORK_BLOCK overrides it), and API3_AIRNODE_RRP overrides
/// the canonical AirnodeRrpV0 address. A live request needs a funded
/// sponsorWallet, which is out of scope here: these tests cover the on-chain
/// config round-trip only.
contract API3QRNGAdapterFork is Test {
    // -------------------------------------------------------------------------
    //                              State
    // -------------------------------------------------------------------------

    MockAPI3QRNGAdapterForkContract qrng;
    address admin = address(0x1);

    address airnodeRrp;

    /// @notice Pinned mainnet block (December 2024), shared with the other mainnet oracle suites.
    uint256 constant DEFAULT_FORK_BLOCK = 21_500_000;
    /// @notice API3's AirnodeRrpV0, deployed at the same address on every chain API3 supports.
    address constant AIRNODE_RRP_V0 = 0xa0AD79D995DdeeB18a14eAef56A549A04e3Aa1Bd;

    address constant DUMMY_AIRNODE = address(0xA1);
    bytes32 constant DUMMY_ENDPOINT_ID = keccak256("QRNG_ENDPOINT");
    address constant DUMMY_SPONSOR_WALLET = address(0xB1);

    // -------------------------------------------------------------------------
    //                              Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        if (bytes(vm.envOr("MAINNET_RPC_URL", string(""))).length == 0) {
            vm.skip(true);
            return;
        }
        airnodeRrp = vm.envOr("API3_AIRNODE_RRP", AIRNODE_RRP_V0);
        vm.createSelectFork("mainnet", vm.envOr("API3_QRNG_FORK_BLOCK", DEFAULT_FORK_BLOCK));

        qrng = new MockAPI3QRNGAdapterForkContract();
        qrng.initialize(admin);
    }

    // -------------------------------------------------------------------------
    //                              Tests
    // -------------------------------------------------------------------------

    /// @notice Configure the adapter with the live Airnode RRP and dummy fields,
    ///         then verify the config round-trips through getConfig.
    function test_Fork_ConfigRoundTrip() public {
        assertGt(airnodeRrp.code.length, 0, "no AirnodeRrp code at the fork block");
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
