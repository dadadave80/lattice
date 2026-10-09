// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {ArchiveFork} from "@lattice-test/helpers/ArchiveFork.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IPythEntropyAdapter} from "@lattice/interfaces/oracles/IPythEntropyAdapter.sol";
import {PythEntropyAdapter} from "@lattice/oracles/pyth/PythEntropyAdapter.sol";
import {PythEntropyAdapterLib} from "@lattice/oracles/pyth/PythEntropyAdapterLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCK CONTRACT
// ---------------------------------------------------------------------------

/// @notice Mock Diamond that combines AccessControl + PythEntropyAdapter for fork testing.
contract MockPythEntropyAdapterForkContract is AccessControl, PythEntropyAdapter, Initializable {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(AccessControl, PythEntropyAdapter)
        returns (bytes memory)
    {}

    function initialize(address _admin) external initializer {
        AccessControlLib.__AccessControl_init(_admin);
        PythEntropyAdapterLib.__PythEntropyAdapter_init();
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

// ---------------------------------------------------------------------------
//                              FORK TESTS
// ---------------------------------------------------------------------------

/// @title PythEntropyAdapterFork
/// @notice Fork tests that exercise PythEntropyAdapter against the live Pyth Entropy
///         contract on Base Sepolia. Pyth has no Entropy deployment on Ethereum
///         mainnet, so this suite runs in the Base Sepolia lane.
///
/// Enabling fork tests:
///   export BASE_SEPOLIA_RPC_URL=<your-rpc-url>
///   forge test --match-path "test/fork/PythEntropyAdapterFork.t.sol"
///
/// Without BASE_SEPOLIA_RPC_URL set, all tests in this contract are skipped. The
/// fork is pinned (PYTH_ENTROPY_FORK_BLOCK overrides it); an RPC that pruned the
/// pin skips with a reason (see {ArchiveFork}). PYTH_ENTROPY overrides the
/// Entropy address for a fork of another chain.
contract PythEntropyAdapterFork is Test {
    /// @notice Pinned Base Sepolia block (October 2026), inside the public endpoint's retention window.
    uint256 constant DEFAULT_FORK_BLOCK = 47_800_000;
    /// @notice Pyth Entropy on Base Sepolia (pyth-crosschain contract_manager store, EvmEntropyContracts.json).
    address constant BASE_SEPOLIA_ENTROPY = 0x41c9e39574F40Ad34c79f1C99B66A45eFB830d4c;

    MockPythEntropyAdapterForkContract adapter;
    address admin = address(0x1);
    address entropy;

    function setUp() public {
        if (bytes(vm.envOr("BASE_SEPOLIA_RPC_URL", string(""))).length == 0) {
            vm.skip(true);
            return;
        }
        entropy = vm.envOr("PYTH_ENTROPY", BASE_SEPOLIA_ENTROPY);
        if (!ArchiveFork.select("base-sepolia", vm.envOr("PYTH_ENTROPY_FORK_BLOCK", DEFAULT_FORK_BLOCK))) return;

        adapter = new MockPythEntropyAdapterForkContract();
        adapter.initialize(admin);
    }

    /// @notice Configure the live Entropy contract with the default provider and
    ///         verify the quoted fee is positive.
    function test_Fork_GetFeeReturnsPositiveFee() public {
        IPythEntropyAdapter.EntropyConfig memory cfg =
            IPythEntropyAdapter.EntropyConfig({entropy: entropy, provider: address(0)});
        vm.prank(admin);
        adapter.setConfig(cfg);

        assertGt(adapter.getFee(), 0, "default provider fee should be positive");
    }
}
