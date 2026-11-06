// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployRelease} from "@lattice-script/deploy/DeployRelease.s.sol";
import {AccountReleaseInventory} from "@lattice-script/lib/AccountReleaseInventory.sol";
import {FacetInventory} from "@lattice-script/lib/FacetInventory.sol";
import {InitInventory} from "@lattice-script/lib/InitInventory.sol";
import {LibraryInventory} from "@lattice-script/lib/LibraryInventory.sol";
import {ArachnidProxy} from "@lattice-test/helpers/ArachnidProxy.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {IERC8153} from "@lattice/interfaces/external/ercs/IERC8153.sol";
import {Script} from "forge-std/Script.sol";

/// @title GenerateManifest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Offline release identities. Constructors run only in Forge's local EVM; never broadcast this script.
/// @dev Use script/release-manifest.sh to bind the output to clean source and compiler input witnesses.
contract GenerateManifest is DeployRelease {
    /// @notice Alphabetical field order matches Forge JSON decoding.
    struct ContractIdentity {
        address at;
        string artifact;
        bytes32 codehash;
        bytes constructorArgs;
        bytes32 initCodeHash;
        string kind;
        string name;
        bytes32 nameHash;
        bytes32 salt;
        bytes32 selectorsHash;
    }

    /// @notice Generate identities without RPC, wall-clock time, chain ID or broadcaster-dependent state.
    function generate(string memory version, address owner, string memory destination) external {
        vm.writeJson(snapshot(version, owner), destination);
    }

    /// @notice Execute constructors locally to include immutable-adjusted runtime hashes (not artifact placeholders).
    function snapshot(string memory version, address owner) public returns (string memory json) {
        require(owner != address(0), "manifest: explicit nonzero initial owner required");
        vm.etch(ArachnidProxy.PROXY, ArachnidProxy.RUNTIME);
        ReleaseOutput memory out = release(version, owner);
        JsonRecordWriter writer = new JsonRecordWriter();
        string[] memory records =
            new string[](2 + out.facets.length + out.inits.length + out.libraries.length + 2 * out.accountInits.length);
        records[0] = writer.record(
            "registry",
            "LatticeRegistry",
            "src/LatticeRegistry.sol:LatticeRegistry",
            out.registry,
            REGISTRY_SALT,
            abi.encode(owner)
        );
        records[1] = writer.record(
            "factory",
            "LatticeFactory",
            "src/LatticeFactory.sol:LatticeFactory",
            out.factory,
            FACTORY_SALT,
            abi.encode(out.registry, address(0), address(0))
        );
        {
            (string[] memory names, string[] memory artifacts) = FacetInventory.inventory();
            for (uint256 i; i < names.length; ++i) {
                records[2 + i] =
                    writer.record("facet", names[i], artifacts[i], out.facets[i], facetSalt(names[i], version), "");
            }
        }
        {
            (string[] memory names, string[] memory artifacts) = InitInventory.inventory();
            for (uint256 i; i < names.length; ++i) {
                records[2 + out.facets.length + i] =
                    writer.record("init", names[i], artifacts[i], out.inits[i], facetSalt(names[i], version), "");
            }
        }
        {
            (string[] memory names, string[] memory artifacts,) = LibraryInventory.inventory();
            for (uint256 i; i < names.length; ++i) {
                records[2 + out.facets.length + out.inits.length + i] =
                    writer.record("library", names[i], artifacts[i], out.libraries[i], LibraryInventory.SALT, "");
            }
        }
        string memory accountBindings = _accountRecords(version, out, writer, records);
        vm.serializeString("identity:proxy", "name", "Lattice");
        string memory proxy =
            vm.serializeBytes32("identity:proxy", "initCodeHash", keccak256(vm.getCode("src/Lattice.sol:Lattice")));
        json = string.concat(
            '{"proxy":', proxy, ',"contracts":', writer.join(records), ',"accounts":', accountBindings, "}"
        );
    }

    function _accountRecords(
        string memory version,
        ReleaseOutput memory out,
        JsonRecordWriter writer,
        string[] memory records
    ) private returns (string memory) {
        AccountReleaseInventory.Entry[] memory accounts = AccountReleaseInventory.inventory();
        string[] memory accountBindings = new string[](accounts.length);
        for (uint256 i; i < accounts.length; ++i) {
            AccountReleaseInventory.Entry memory entry = accounts[i];
            FacetCut[] memory cuts = _accountCuts(entry.modular, version);
            uint256 offset = 2 + out.facets.length + out.inits.length + out.libraries.length + 2 * i;
            records[offset] = writer.accountInitializer(entry, out.accountInits[i], version);
            records[offset + 1] =
                writer.accountFactory(entry, out.accountFactories[i], version, abi.encode(cuts, out.accountInits[i]));
            accountBindings[i] = writer.account(entry, keccak256(abi.encode(cuts)));
        }
        return writer.join(accountBindings);
    }
}

/// @title JsonRecordWriter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Small offline helper: each artifact serialization has its own memory frame.
contract JsonRecordWriter is Script {
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
        return vm.serializeBytes32(key, "selectorsHash", facet ? keccak256(IERC8153(at).exportSelectors()) : bytes32(0));
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
