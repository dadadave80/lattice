// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DeployGovernedVault} from "@lattice-script/base/defi/DeployGovernedVault.s.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {Test} from "forge-std/Test.sol";

/// @title GovernedVaultTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for {GovernedVault} tests that assembles the PRODUCTION self-governed vault diamond via the
///         {DeployGovernedVault} recipe (13 cuts: ERC165 + AccessControl + the vault/governance facets + loupe +
///         EmergencyStop + GovernedDiamondCut, initialized by {GovernedVaultInit}), so every
///         deposit / vote / proposal routes through the real diamond `delegatecall` dispatch.
abstract contract GovernedVaultTestBase is Test {
    DeployGovernedVault internal deployer;

    /// @notice Assembles the self-governed vault diamond over `asset` with the given governance parameters.
    function _deployGovernedVault(address asset, GovernedVaultParams memory p) internal returns (address vault) {
        p.asset = asset;
        deployer = new DeployGovernedVault();
        LatticeFactory factory = new LatticeFactory(new LatticeRegistry(address(this)));
        vault = deployer.deployAtomic(p, factory, bytes32(0));
    }
}
