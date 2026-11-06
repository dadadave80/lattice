// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitInventory} from "@lattice-script/lib/InitInventory.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract ConstructorBoundFixtureInit {
    address public immutable dependency;

    constructor(address dependency_) {
        dependency = dependency_;
    }
}

contract InitInventoryParityTest is Test {
    function test_NewSharedInitializerArtifactsExist() public {
        string[9] memory names = [
            "CircuitBreakerInit",
            "EmergencyStopInit",
            "InvariantCheckerInit",
            "PausableInit",
            "RateLimiterInit",
            "GovernorInit",
            "TimelockControllerInit",
            "VotesInit",
            "ReinitMultiInit"
        ];
        for (uint256 i; i < names.length; ++i) {
            assertGt(vm.getCode(string.concat(names[i], ".sol:", names[i])).length, 0, names[i]);
        }
    }

    function test_InventoryMatchesEveryStatelessSourceInitializer() public view {
        (string[] memory names, string[] memory paths) = InitInventory.inventory();
        this.checkInventory(names, paths);
    }

    function test_RejectsMissingEntry() public {
        (string[] memory names, string[] memory paths) = InitInventory.inventory();
        string memory missing = names[names.length - 1];
        assembly ("memory-safe") {
            mstore(names, sub(mload(names), 1))
            mstore(paths, sub(mload(paths), 1))
        }
        vm.expectRevert(bytes(string.concat("Missing initializer: ", missing)));
        this.checkInventory(names, paths);
    }

    function test_RejectsDuplicateEntry() public {
        (string[] memory names, string[] memory paths) = InitInventory.inventory();
        names[1] = names[0];
        paths[1] = paths[0];
        vm.expectRevert(bytes("Duplicate initializer"));
        this.checkInventory(names, paths);
    }

    function test_RejectsExtraEntry() public {
        (string[] memory names, string[] memory paths) = InitInventory.inventory();
        names[0] = "Initializable";
        paths[0] = "src/utils/Initializable.sol:Initializable";
        vm.expectRevert(bytes("Not an initializer artifact"));
        this.checkInventory(names, paths);
    }

    function test_ConstructorBoundAccountsHaveExplicitExclusions() public pure {
        assertGt(bytes(InitInventory.exclusionReason("AccountInit")).length, 0);
        assertGt(bytes(InitInventory.exclusionReason("AccountInit6900")).length, 0);
        assertEq(InitInventory.exclusionReason("ERC20Init"), "");
    }

    function test_RejectsConstructorArguments() public {
        vm.expectRevert(bytes("Initializer requires constructor arguments"));
        this.checkArtifact(
            "ConstructorBoundFixtureInit", "test/unit/InitInventoryParityTest.t.sol:ConstructorBoundFixtureInit"
        );
    }

    function checkInventory(string[] memory names, string[] memory paths) external view {
        require(names.length == paths.length && names.length != 0, "Invalid inventory lengths");
        bool[] memory found = new bool[](names.length);
        for (uint256 i; i < names.length; ++i) {
            require(_endsWith(names[i], "Init"), "Not an initializer artifact");
            require(bytes(InitInventory.exclusionReason(names[i])).length == 0, "Excluded initializer");
            for (uint256 j; j < i; ++j) {
                require(keccak256(bytes(names[i])) != keccak256(bytes(names[j])), "Duplicate initializer");
            }
            this.checkArtifact(names[i], paths[i]);
            if (keccak256(bytes(names[i])) == keccak256("MultiInit")) {
                require(keccak256(bytes(paths[i])) == keccak256("MultiInit.sol:MultiInit"), "Wrong MultiInit artifact");
                found[i] = true;
            }
        }
        Vm.DirEntry[] memory entries = vm.readDir("src", 20);
        for (uint256 i; i < entries.length; ++i) {
            if (
                entries[i].isDir
                    || (!_endsWith(entries[i].path, "Init.sol") && !_endsWith(entries[i].path, "Init6900.sol"))
            ) continue;
            string memory filename = _basename(entries[i].path);
            bytes memory nameBytes = new bytes(bytes(filename).length - 4);
            for (uint256 j; j < nameBytes.length; ++j) {
                nameBytes[j] = bytes(filename)[j];
            }
            string memory name = string(nameBytes);
            if (bytes(InitInventory.exclusionReason(name)).length != 0) continue;
            bool listed;
            for (uint256 j; j < names.length; ++j) {
                if (keccak256(bytes(names[j])) != keccak256(bytes(name))) continue;
                string memory file = _sourceFile(paths[j], names[j]);
                require(
                    keccak256(bytes(file)) == keccak256(bytes(entries[i].path))
                        || keccak256(bytes(string.concat(vm.projectRoot(), "/", file)))
                            == keccak256(bytes(entries[i].path)),
                    "Initializer name/path mismatch"
                );
                found[j] = true;
                listed = true;
                break;
            }
            require(listed, string.concat("Missing initializer: ", name));
        }
        for (uint256 i; i < found.length; ++i) {
            require(found[i], string.concat("Extra initializer: ", names[i]));
        }
    }

    /// @dev A separate frame bounds artifact JSON allocations across the whole inventory.
    function checkArtifact(string memory name, string memory artifact) external view {
        string memory filename = _basename(_sourceFile(artifact, name));
        string memory json = vm.readFile(string.concat("out/", filename, "/", name, ".json"));
        // solc emits a constructor first when one exists; only zero-argument builds can be shared here.
        if (keccak256(bytes(vm.parseJsonString(json, ".abi[0].type"))) == keccak256("constructor")) {
            require(!vm.keyExistsJson(json, ".abi[0].inputs[0]"), "Initializer requires constructor arguments");
        }
        require(vm.getCode(artifact).length != 0, "Empty initializer bytecode");
    }

    function _sourceFile(string memory artifact, string memory name) internal pure returns (string memory) {
        require(_endsWith(artifact, string.concat(":", name)), "Initializer artifact name mismatch");
        bytes memory result = new bytes(bytes(artifact).length - bytes(name).length - 1);
        for (uint256 i; i < result.length; ++i) {
            result[i] = bytes(artifact)[i];
        }
        return string(result);
    }

    function _basename(string memory path) internal pure returns (string memory) {
        bytes memory data = bytes(path);
        uint256 start;
        for (uint256 i; i < data.length; ++i) {
            if (data[i] == "/") start = i + 1;
        }
        bytes memory result = new bytes(data.length - start);
        for (uint256 i; i < result.length; ++i) {
            result[i] = data[start + i];
        }
        return string(result);
    }

    function _endsWith(string memory value, string memory suffix) internal pure returns (bool) {
        bytes memory data = bytes(value);
        bytes memory end = bytes(suffix);
        if (data.length < end.length) return false;
        for (uint256 i; i < end.length; ++i) {
            if (data[data.length - end.length + i] != end[i]) return false;
        }
        return true;
    }
}
