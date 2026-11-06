// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccountReleaseInventory} from "@lattice-script/lib/AccountReleaseInventory.sol";
import {IERC8153} from "@lattice/interfaces/external/ercs/IERC8153.sol";
import {Script} from "forge-std/Script.sol";

/// @title JsonRecordWriter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Small offline helper: each artifact serialization has its own memory frame.
contract JsonRecordWriter is Script {
    /// @dev Preserve the legacy five-field facet plan shape in an independent serialization frame.
    function planFacet(string memory name, address at, bytes32 salt) external returns (string memory) {
        string memory key = string.concat("plan:", name);
        vm.serializeString(key, "name", name);
        vm.serializeAddress(key, "address", at);
        vm.serializeBytes32(key, "codehash", at.codehash);
        vm.serializeBytes32(key, "selectorsHash", keccak256(IERC8153(at).exportSelectors()));
        return vm.serializeBytes32(key, "salt", salt);
    }

    /// @dev Stateless initializer/library records retain their existing five-field plan shape.
    function planArtifact(string memory name, string memory artifact, address at, bytes32 salt)
        external
        returns (string memory)
    {
        string memory key = string.concat("plan:", name);
        vm.serializeString(key, "name", name);
        vm.serializeAddress(key, "address", at);
        vm.serializeBytes32(key, "codehash", at.codehash);
        vm.serializeBytes32(key, "initCodeHash", keccak256(vm.getCode(artifact)));
        return vm.serializeBytes32(key, "salt", salt);
    }

    function accountPlan(
        AccountReleaseInventory.Entry memory entry,
        bool factory,
        address at,
        string memory version,
        bytes memory args
    ) external returns (string memory) {
        string memory name = factory ? entry.factory : entry.initializer;
        string memory artifact = factory ? entry.factoryArtifact : entry.initializerArtifact;
        string memory key = string.concat("account:", name);
        vm.serializeString(key, "name", name);
        vm.serializeString(key, "artifact", artifact);
        vm.serializeAddress(key, "entryPoint", entry.entryPoint);
        vm.serializeString(key, "entryPointVersion", entry.entryPointVersion);
        vm.serializeString(key, "proxyKind", entry.proxyKind);
        vm.serializeBytes32(key, "proxyInitCodeHash", keccak256(vm.getCode(entry.proxyArtifact)));
        vm.serializeAddress(key, "address", at);
        vm.serializeBytes32(key, "codehash", at.codehash);
        vm.serializeBytes(key, "constructorArgs", args);
        vm.serializeBytes32(key, "initCodeHash", keccak256(abi.encodePacked(vm.getCode(artifact), args)));
        return vm.serializeBytes32(key, "salt", keccak256(abi.encodePacked("lattice.", name, ".", version)));
    }

    /// @dev Inventory names are Solidity identifiers. Construct the map in one allocation, without cumulative
    ///      VM.serializeString copies in the caller's shared EVM memory frame.
    function joinObject(string[] memory names, string[] memory records) external pure returns (string memory) {
        require(names.length == records.length, "plan: mismatched names and records");
        string[] memory entries = new string[](names.length);
        for (uint256 i; i < names.length; ++i) {
            entries[i] = string.concat('"', names[i], '":', records[i]);
        }
        bytes memory encoded = bytes(join(entries));
        encoded[0] = "{";
        encoded[encoded.length - 1] = "}";
        return string(encoded);
    }

    function accountInitializer(AccountReleaseInventory.Entry memory entry, address at, string memory version)
        external
        returns (string memory)
    {
        return this.record(
            "account-init",
            entry.initializer,
            entry.initializerArtifact,
            at,
            keccak256(abi.encodePacked("lattice.", entry.initializer, ".", version)),
            abi.encode(entry.entryPoint)
        );
    }

    function accountFactory(
        AccountReleaseInventory.Entry memory entry,
        address at,
        string memory version,
        bytes memory args
    ) external returns (string memory) {
        return this.record(
            "account-factory",
            entry.factory,
            entry.factoryArtifact,
            at,
            keccak256(abi.encodePacked("lattice.", entry.factory, ".", version)),
            args
        );
    }

    /// @dev Account bindings supplement, rather than replace, the definitive contract constructor arguments.
    function account(AccountReleaseInventory.Entry memory entry, bytes32 blueprintHash)
        external
        returns (string memory)
    {
        string memory key = string.concat("binding:", entry.factory);
        vm.serializeAddress(key, "entryPoint", entry.entryPoint);
        vm.serializeString(key, "entryPointVersion", entry.entryPointVersion);
        vm.serializeString(key, "proxyKind", entry.proxyKind);
        vm.serializeBytes32(key, "proxyInitCodeHash", keccak256(vm.getCode(entry.proxyArtifact)));
        vm.serializeString(key, "initializer", entry.initializer);
        vm.serializeString(key, "factory", entry.factory);
        return vm.serializeBytes32(key, "blueprintHash", blueprintHash);
    }

    /// @dev External helper bounds artifact/serialization memory to one record.
    function record(
        string memory kind,
        string memory name,
        string memory artifact,
        address at,
        bytes32 salt,
        bytes memory args
    ) external returns (string memory) {
        string memory key = string.concat("identity:", name);
        vm.serializeAddress(key, "address", at);
        vm.serializeString(key, "artifact", artifact);
        vm.serializeBytes32(key, "codehash", at.codehash);
        vm.serializeBytes(key, "constructorArgs", args);
        vm.serializeBytes32(key, "initCodeHash", keccak256(abi.encodePacked(vm.getCode(artifact), args)));
        vm.serializeString(key, "kind", kind);
        vm.serializeString(key, "name", name);
        bool facet = keccak256(bytes(kind)) == keccak256("facet");
        vm.serializeBytes32(key, "nameHash", facet ? keccak256(abi.encodePacked("lattice.", name)) : bytes32(0));
        vm.serializeBytes32(key, "salt", salt);
        bytes memory selectors = facet ? IERC8153(at).exportSelectors() : bytes("");
        vm.serializeBytes(key, "selectors", selectors);
        return vm.serializeBytes32(key, "selectorsHash", facet ? keccak256(selectors) : bytes32(0));
    }

    /// @dev One allocation prevents quadratic string concatenation across the full release catalog.
    function join(string[] memory values) public pure returns (string memory) {
        uint256 length = 2 + (values.length == 0 ? 0 : values.length - 1);
        for (uint256 i; i < values.length; ++i) {
            length += bytes(values[i]).length;
        }
        bytes memory joined = new bytes(length);
        joined[0] = "[";
        uint256 cursor = 1;
        for (uint256 i; i < values.length; ++i) {
            bytes memory value = bytes(values[i]);
            assembly ("memory-safe") {
                mcopy(add(add(joined, 32), cursor), add(value, 32), mload(value))
            }
            cursor += value.length;
            if (i + 1 < values.length) joined[cursor++] = ",";
        }
        joined[cursor] = "]";
        return string(joined);
    }
}
