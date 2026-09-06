// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {DeployGovernedVault} from "@lattice-script/base/defi/DeployGovernedVault.s.sol";
import {TestnetAsset} from "@lattice-script/base/defi/DeployGovernedVaultENS.s.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {console} from "forge-std/console.sol";

/// @title GrantUpgradeProbe
/// @notice A stateless facet whose new selector proves the governed upgrade executed.
contract GrantUpgradeProbe {
    function grantVersion() external pure returns (uint256) {
        return 2;
    }
}

/// @title GrantExample
/// @notice Self-contained testnet example using the production recipe and atomic factory deployment.
contract GrantExample is DeployGovernedVault {
    function run() external returns (address vault, address asset, address probe) {
        vm.startBroadcast();
        asset = address(new TestnetAsset("Grant example asset", "TEST"));
        LatticeFactory factory = new LatticeFactory(new LatticeRegistry(msg.sender));
        GovernedVaultParams memory p = GovernedVaultParams(asset, "Grant vault", "gVLT", 0, 300, 60, 600, 0, 4);
        vault = deployAtomic(p, factory, bytes32(0));
        probe = address(new GrantUpgradeProbe());
        vm.stopBroadcast();
        console.log("VAULT", vault);
        console.log("ASSET", asset);
        console.log("PROBE", probe);
    }
}
