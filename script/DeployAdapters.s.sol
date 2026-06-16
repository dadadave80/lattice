// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CreateXDeployer} from "@lattice-script/lib/CreateXDeployer.sol";
import {Script, console} from "forge-std/Script.sol";

/// @title DeployAdapters
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Deterministically deploys Lattice DeFi protocol adapters (Aave v3 / Compound v3 /
///         ERC4626-wrap) through the SAME {CreateXDeployer} helper used to deploy the Diamond +
///         facets in the governed-diamond-upgrade plan. Each adapter lands at the same address on
///         every chain because CreateX CREATE3 derives the address from `(CreateX, guardedSalt)` and
///         NOT from the adapter's initcode.
/// @dev Reuses `script/lib/CreateXDeployer.sol` and `src/interfaces/external/ICreateX.sol` from the
///      upgrade plan (Task 1). If running this DeFi plan standalone, vendor those two files first
///      (see the cross-plan dependency note in Task 15). `_guardedSalt` pins the salt to the
///      broadcasting deployer (first 20 bytes) and enables cross-chain redeploy protection (21st
///      byte == 0x01).
///
/// Usage (predict an adapter's cross-chain address):
///   forge script script/DeployAdapters.s.sol --sig "predictAdapter(bytes11)" <ENTROPY>
///
/// Usage (deploy one adapter; add --broadcast + --sender):
///   forge script script/DeployAdapters.s.sol \
///     --sig "deployAdapter(bytes11,bytes)" <ENTROPY> <INITCODE> --broadcast
contract DeployAdapters is Script {
    /// @notice Pre-computes the deterministic CREATE3 address an adapter will occupy on every chain.
    /// @param entropy 11 bytes distinguishing this adapter from others by the same deployer.
    /// @return adapter The deterministic adapter address (broadcast by `msg.sender`).
    function predictAdapter(bytes11 entropy) external view returns (address adapter) {
        bytes32 salt = CreateXDeployer._guardedSalt(msg.sender, entropy);
        adapter = CreateXDeployer.predict(salt);
        console.log("Predicted adapter (all chains):", adapter);
    }

    /// @notice Deploys one adapter deterministically via CreateX CREATE3 at its predicted address.
    /// @param entropy  11 bytes of per-adapter entropy (distinct per adapter to avoid salt collisions).
    /// @param initCode The adapter facet's full creation bytecode incl. ABI-encoded constructor args
    ///        (e.g. `abi.encodePacked(type(AaveV3Adapter).creationCode, abi.encode(...))`).
    /// @return adapter The deterministic adapter address (== {predictAdapter}).
    function deployAdapter(bytes11 entropy, bytes memory initCode) public returns (address adapter) {
        bytes32 salt = CreateXDeployer._guardedSalt(msg.sender, entropy);
        address predicted = CreateXDeployer.predict(salt);
        adapter = CreateXDeployer.deploy(salt, initCode);
        require(adapter == predicted, "DeployAdapters: deployed != predicted");
        console.log("Deployed adapter (deterministic, all chains):", adapter);
    }

    /// @notice Convenience: deterministically deploy all three adapters in one broadcast.
    /// @dev Pass each adapter's full initcode (creationCode ++ encoded args) and a DISTINCT entropy.
    /// @return aave The Aave v3 adapter address.
    /// @return compound The Compound v3 adapter address.
    /// @return erc4626 The ERC4626-wrap adapter address.
    function deployAll(
        bytes11 aaveEntropy,
        bytes memory aaveInitCode,
        bytes11 compoundEntropy,
        bytes memory compoundInitCode,
        bytes11 erc4626Entropy,
        bytes memory erc4626InitCode
    ) external returns (address aave, address compound, address erc4626) {
        vm.startBroadcast();
        aave = deployAdapter(aaveEntropy, aaveInitCode);
        compound = deployAdapter(compoundEntropy, compoundInitCode);
        erc4626 = deployAdapter(erc4626Entropy, erc4626InitCode);
        vm.stopBroadcast();
        console.log("Aave v3 adapter:", aave);
        console.log("Compound v3 adapter:", compound);
        console.log("ERC4626 adapter:", erc4626);
    }
}
