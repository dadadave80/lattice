// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Vm} from "forge-std/Vm.sol";
import {PoseidonT3} from "poseidon-solidity/PoseidonT3.sol";

/// @title LibraryInventory
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice External release libraries. Referencing the linked address anchors Foundry's native CREATE2 linker.
/// @dev The explicit Foundry library salt/deployer are checked by check-release-build.sh; solc libraries stays empty.
library LibraryInventory {
    bytes32 internal constant SALT = bytes32(0);

    function inventory()
        internal
        pure
        returns (string[] memory names, string[] memory artifacts, address[] memory linked)
    {
        names = new string[](1);
        artifacts = new string[](1);
        linked = new address[](1);
        names[0] = "PoseidonT3";
        artifacts[0] = "lib/poseidon-solidity/PoseidonT3.sol:PoseidonT3";
        linked[0] = address(PoseidonT3);
    }

    /// @notice Trusted artifact runtime with Solidity's PUSH20 self-address patched exactly as its constructor does.
    /// @dev Reject an unexpected artifact convention; never derive the expected hash from remote code.
    function runtimeHash(Vm vm, string memory artifact, address deployed) internal view returns (bytes32) {
        bytes memory runtime = vm.getDeployedCode(artifact);
        require(runtime.length > 21 && runtime[0] == bytes1(0x73), "release library: unsupported runtime prefix");
        bytes20 self = bytes20(deployed);
        for (uint256 i; i < 20; ++i) {
            require(runtime[i + 1] == 0, "release library: expected zero self-address placeholder");
            runtime[i + 1] = self[i];
        }
        return keccak256(runtime);
    }
}
