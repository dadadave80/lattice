// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {JsonRecordWriter} from "./JsonRecordWriter.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployRelease} from "@lattice-script/deploy/DeployRelease.s.sol";
import {AccountReleaseInventory} from "@lattice-script/lib/AccountReleaseInventory.sol";
import {FacetInventory} from "@lattice-script/lib/FacetInventory.sol";
import {InitInventory} from "@lattice-script/lib/InitInventory.sol";
import {LibraryInventory} from "@lattice-script/lib/LibraryInventory.sol";
import {ArachnidProxy} from "@lattice-test/helpers/ArachnidProxy.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";

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
