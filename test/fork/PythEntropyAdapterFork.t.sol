// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IPythEntropyAdapter} from "@lattice/interfaces/oracles/IPythEntropyAdapter.sol";
import {PythEntropyAdapterLib} from "@lattice/oracles/libraries/PythEntropyAdapterLib.sol";
import {PythEntropyAdapter} from "@lattice/oracles/pyth/PythEntropyAdapter.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCK CONTRACT
// ---------------------------------------------------------------------------

/// @notice Mock Diamond that combines AccessControl + PythEntropyAdapter for fork testing.
contract MockPythEntropyAdapterForkContract is AccessControl, PythEntropyAdapter {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(AccessControl, PythEntropyAdapter)
        returns (bytes memory)
    {}

    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        PythEntropyAdapterLib.__PythEntropyAdapter_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

// ---------------------------------------------------------------------------
//                              FORK TESTS
// ---------------------------------------------------------------------------

/// @title PythEntropyAdapterFork
/// @notice Fork tests that exercise PythEntropyAdapter against a live Pyth Entropy
///         contract on Ethereum mainnet.
///
/// Enabling fork tests:
///   export PYTH_ENTROPY=<live-entropy-address>
///   forge test --match-path "test/fork/*"
///
/// Without PYTH_ENTROPY set, all tests in this contract are skipped.
contract PythEntropyAdapterFork is Test {
    MockPythEntropyAdapterForkContract adapter;
    address admin = address(0x1);
    address entropy;

    function setUp() public {
        entropy = vm.envOr("PYTH_ENTROPY", address(0));
        if (entropy == address(0)) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet");

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
