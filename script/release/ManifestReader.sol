// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GenerateManifest} from "./GenerateManifest.s.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title ManifestReader
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Explicit JSON coercion avoids treating a 32-byte constructor argument as a fixed bytes32 field.
library ManifestReader {
    function identities(Vm vm, string memory json) internal pure returns (GenerateManifest.ContractIdentity[] memory) {
        return abi.decode(
            vm.parseJsonTypeArray(
                json,
                ".contracts",
                "Identity(address address,string artifact,bytes32 codehash,bytes constructorArgs,bytes32 initCodeHash,string kind,string name,bytes32 nameHash,bytes32 salt,bytes32 selectorsHash)"
            ),
            (GenerateManifest.ContractIdentity[])
        );
    }
}
