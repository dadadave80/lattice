// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DeployAdapters} from "@lattice-script/DeployAdapters.s.sol";
import {CreateXDeployer} from "@lattice-script/lib/CreateXDeployer.sol";
import {Test} from "forge-std/Test.sol";

// Reuse the faithful CreateX mock from the CreateXDeployer test (same canonical-address etch trick).
import {MockCreateX} from "@lattice-test/unit/CreateXDeployerTest.t.sol";

/// @notice A stand-in "adapter" with a constructor arg, to prove initcode-with-args deploys and that
///         the address is independent of those args (CREATE3).
contract FakeAdapter {
    address public immutable provider;

    constructor(address provider_) {
        provider = provider_;
    }
}

/// @notice Exercises {DeployAdapters}' deterministic CreateX CREATE3 deploy helpers with a faithful
///         MockCreateX etched at the canonical singleton address (no fork, no `--broadcast`). The
///         load-bearing assertion is that an adapter deployed via the script equals the address
///         {DeployAdapters.predictAdapter} pre-computes — i.e. the same cross-chain-stable address on
///         every chain, independent of initcode.
contract DeployAdaptersTest is Test {
    address internal constant CANONICAL = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    DeployAdapters internal script;

    function setUp() public {
        MockCreateX impl = new MockCreateX();
        vm.etch(CANONICAL, address(impl).code);
        script = new DeployAdapters();
    }

    /// @notice The script deploys an adapter at exactly the address it predicts (cross-chain-stable).
    /// @dev CreateX pins the deterministic address to ITS OWN `msg.sender`. When the script forwards a
    ///      deploy, the nested call into CreateX has `msg.sender == address(script)`; under real
    ///      `forge script --broadcast`, Foundry rewrites each broadcasted call to originate from the
    ///      deployer EOA as a standalone tx, so CreateX sees that EOA. To reproduce that alignment in a
    ///      plain unit test (no script runtime), we prank the script call FROM `address(script)` so the
    ///      salt the script mints (pinned to its `msg.sender`) matches the deployer CreateX observes —
    ///      exactly the approach `UpgradeDiamondScriptTest` uses.
    function test_DeployAdapterMatchesPrediction() public {
        bytes11 entropy = bytes11(uint88(0xAA00BB11CC22DD33EE44FF));
        bytes memory initCode = abi.encodePacked(type(FakeAdapter).creationCode, abi.encode(address(0xCAFE)));
        address deployer = address(script);

        vm.prank(deployer);
        address predicted = script.predictAdapter(entropy);

        vm.prank(deployer);
        address deployed = script.deployAdapter(entropy, initCode);

        assertEq(deployed, predicted, "adapter predicted != deployed");
        assertEq(FakeAdapter(deployed).provider(), address(0xCAFE), "constructor arg lost");
    }

    /// @notice Different entropy ⇒ different deterministic address (no salt collision across adapters).
    function test_DistinctEntropyDistinctAddress() public {
        address deployer = address(script);

        vm.prank(deployer);
        address a = script.predictAdapter(bytes11(uint88(1)));
        vm.prank(deployer);
        address b = script.predictAdapter(bytes11(uint88(2)));
        assertTrue(a != b, "distinct adapters must get distinct addresses");
    }
}
