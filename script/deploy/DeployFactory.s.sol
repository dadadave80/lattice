// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {ILatticeRegistry} from "@lattice/interfaces/ILatticeRegistry.sol";
import {Script, console} from "forge-std/Script.sol";

/// @title DeployFactory
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Deploys one replacement {LatticeFactory} against an existing registry and assigns ownership of
///         the factory's constructor-claimed ENS reverse record.
///
/// Usage:
///   forge script script/deploy/DeployFactory.s.sol:DeployFactory \
///     --sig "run(address,address,address)" <REGISTRY> <REVERSE_REGISTRAR> <REVERSE_RECORD_OWNER> \
///     --rpc-url <CHAIN> --account <KEYSTORE> --broadcast --verify --verifier sourcify
contract DeployFactory is Script {
    /// @notice Broadcasts a single factory deployment.
    function run(address registry, address reverseRegistrar, address reverseRecordOwner)
        external
        returns (address factory)
    {
        vm.startBroadcast();
        factory = deploy(registry, reverseRegistrar, reverseRecordOwner);
        vm.stopBroadcast();
        console.log("LatticeFactory deployed:", factory);
        console.log("Registry:", registry);
        console.log("Reverse registrar:", reverseRegistrar);
        console.log("Reverse record owner:", reverseRecordOwner);
    }

    /// @notice Deploys without broadcast cheatcodes so tests exercise the same constructor path.
    function deploy(address registry, address reverseRegistrar, address reverseRecordOwner)
        public
        returns (address factory)
    {
        factory = address(new LatticeFactory(ILatticeRegistry(registry), reverseRegistrar, reverseRecordOwner));
        require(address(LatticeFactory(factory).registry()) == registry, "DeployFactory: registry mismatch");
    }
}
