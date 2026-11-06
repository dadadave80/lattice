// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GenerateManifest, JsonRecordWriter} from "./GenerateManifest.s.sol";
import {ManifestReader} from "./ManifestReader.sol";
import {ReleaseVersion} from "@lattice-script/lib/ReleaseVersion.sol";
import {ILatticeRegistry} from "@lattice/interfaces/ILatticeRegistry.sol";
import {Script} from "forge-std/Script.sol";

/// @title ObserveManifest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Read-only status at a pinned RPC block. Use release-status.sh; never broadcast this script.
contract ObserveManifest is Script {
    /// @notice Record code and registry observations; verification starts unknown, never inferred from code presence.
    function run(string memory releasePath, bytes32 observedHash, string memory destination) external {
        vm.writeJson(observe(vm.readFile(releasePath), observedHash), destination);
    }

    function observe(string memory releaseJson, bytes32 observedHash) public returns (string memory json) {
        require(observedHash != bytes32(0), "manifest: observed block hash required");
        GenerateManifest.ContractIdentity[] memory records = ManifestReader.identities(vm, releaseJson);
        ILatticeRegistry registry = ILatticeRegistry(records[0].at);
        uint64 version = ReleaseVersion.packVersion(vm.parseJsonString(releaseJson, ".lattice.version"));
        address owner;
        if (records[0].at.codehash == records[0].codehash) {
            try registry.owner() returns (address value) {
                owner = value;
            } catch {}
        }
        StatusRecordWriter writer = new StatusRecordWriter();
        string[] memory statuses = new string[](records.length);
        for (uint256 i; i < records.length; ++i) {
            statuses[i] = writer.status(records[i], registry, version);
        }
        vm.serializeString("observed:lattice", "version", vm.parseJsonString(releaseJson, ".lattice.version"));
        vm.serializeString("observed:lattice", "tag", vm.parseJsonString(releaseJson, ".lattice.tag"));
        string memory lattice =
            vm.serializeString("observed:lattice", "commit", vm.parseJsonString(releaseJson, ".lattice.commit"));
        vm.serializeUint("observed:chain", "id", block.chainid);
        vm.serializeUint("observed:chain", "blockNumber", block.number);
        string memory chain = vm.serializeBytes32("observed:chain", "blockHash", observedHash);
        vm.serializeAddress("observed:root", "registryOwner", owner);
        string memory root =
            vm.serializeString("observed:root", "publication", vm.parseJsonString(releaseJson, ".publication"));
        // The Bash wrapper sets the canonical JSON hash after Forge returns.
        json = string.concat(
            _trim(root),
            ',"schemaVersion":1,"lattice":',
            lattice,
            ',"chain":',
            chain,
            ',"contracts":',
            writer.join(statuses),
            ',"nonCanonicalFactories":[]}'
        );
    }

    function _trim(string memory value) private pure returns (string memory) {
        bytes memory source = bytes(value);
        bytes memory result = new bytes(source.length - 1);
        for (uint256 i; i < result.length; ++i) {
            result[i] = source[i];
        }
        return string(result);
    }
}

/// @title StatusRecordWriter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Small offline helper for one block-pinned contract observation per memory frame.
contract StatusRecordWriter is JsonRecordWriter {
    /// @dev One read/serialization frame per contract, as for offline identities.
    function status(GenerateManifest.ContractIdentity memory record, ILatticeRegistry registry, uint64 version)
        external
        returns (string memory)
    {
        bool present = record.at.code.length > 0;
        bool matches = present && record.at.codehash == record.codehash;
        bool registered;
        bool latest;
        if (matches && keccak256(bytes(record.kind)) == keccak256("facet")) {
            try registry.get(record.nameHash, version) returns (ILatticeRegistry.Record memory value) {
                registered = _matches(record, value, version);
            } catch {}
            if (registered) {
                try registry.latest(record.nameHash) returns (ILatticeRegistry.Record memory value) {
                    latest = _matches(record, value, version);
                } catch {}
            }
        }
        string memory key = string.concat("status:", record.name);
        vm.serializeString(key, "name", record.name);
        vm.serializeAddress(key, "address", record.at);
        vm.serializeBool(key, "codeMatches", matches);
        vm.serializeBool(key, "registered", registered);
        string memory item = vm.serializeBool(key, "latest", latest);
        // Null is an explicit unknown; "pre-existing" means code observed at this block, not a fabricated tx.
        item = string.concat(
            _trim(item), ',"deployed":', present ? '"pre-existing"' : "null", ',"verified":false,"verifier":null}'
        );
        return item;
    }

    function _trim(string memory value) private pure returns (string memory) {
        bytes memory source = bytes(value);
        bytes memory result = new bytes(source.length - 1);
        for (uint256 i; i < result.length; ++i) {
            result[i] = source[i];
        }
        return string(result);
    }

    function _matches(
        GenerateManifest.ContractIdentity memory identity,
        ILatticeRegistry.Record memory value,
        uint64 version
    ) private pure returns (bool) {
        return value.facet == identity.at && value.version == version && value.codehash == identity.codehash
            && value.selectorsHash == identity.selectorsHash;
    }
}
