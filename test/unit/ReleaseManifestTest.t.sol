// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {AccountReleaseInventory} from "@lattice-script/lib/AccountReleaseInventory.sol";
import {ArachnidDeployer} from "@lattice-script/lib/ArachnidDeployer.sol";
import {FacetInventory} from "@lattice-script/lib/FacetInventory.sol";
import {InitInventory} from "@lattice-script/lib/InitInventory.sol";
import {LibraryInventory} from "@lattice-script/lib/LibraryInventory.sol";
import {GenerateManifest} from "@lattice-script/release/GenerateManifest.s.sol";
import {ManifestReader} from "@lattice-script/release/ManifestReader.sol";
import {ObserveManifest} from "@lattice-script/release/ObserveManifest.s.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {ILatticeRegistry} from "@lattice/interfaces/ILatticeRegistry.sol";
import {IERC8153} from "@lattice/interfaces/external/ercs/IERC8153.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract ReleaseManifestTest is Test, GenerateManifest {
    function test_ReleaseIncludesEveryCanonicalAccountIdentity() public {
        ContractIdentity[] memory records = ManifestReader.identities(vm, snapshot("99.0.0", address(this)));
        AccountReleaseInventory.Entry[] memory entries = AccountReleaseInventory.inventory();
        for (uint256 i; i < entries.length; ++i) {
            bool foundInit;
            bool foundFactory;
            for (uint256 k; k < records.length; ++k) {
                if (keccak256(bytes(records[k].name)) == keccak256(bytes(entries[i].initializer))) {
                    foundInit = true;
                    assertEq(records[k].kind, "account-init");
                    assertEq(records[k].artifact, entries[i].initializerArtifact);
                    assertEq(abi.decode(records[k].constructorArgs, (address)), entries[i].entryPoint);
                }
                if (keccak256(bytes(records[k].name)) == keccak256(bytes(entries[i].factory))) {
                    foundFactory = true;
                    assertEq(records[k].kind, "account-factory");
                    assertEq(records[k].artifact, entries[i].factoryArtifact);
                }
            }
            assertTrue(foundInit, "canonical account initializer missing");
            assertTrue(foundFactory, "canonical account factory missing");
        }
    }

    function test_AccountBindingsMatchExactBlueprintConstructorsAndSourceProxyHashes() public {
        string memory json = snapshot("99.0.0", address(this));
        ContractIdentity[] memory records = ManifestReader.identities(vm, json);
        AccountReleaseInventory.Entry[] memory entries = AccountReleaseInventory.inventory();
        assertEq(abi.decode(vm.parseJson(json, ".accounts[*].factory"), (string[])).length, entries.length);
        for (uint256 i; i < entries.length; ++i) {
            AccountReleaseInventory.Entry memory entry = entries[i];
            ContractIdentity memory initializer = _identity(records, entry.initializer);
            ContractIdentity memory factory = _identity(records, entry.factory);
            (FacetCut[] memory cuts, address init) = abi.decode(factory.constructorArgs, (FacetCut[], address));
            assertEq(init, initializer.at);
            string[] memory wanted = AccountReleaseInventory.facetNames(entry.modular);
            assertEq(cuts.length, wanted.length);
            for (uint256 k; k < wanted.length; ++k) {
                ContractIdentity memory facet = _identity(records, wanted[k]);
                assertEq(cuts[k].facetAddress, facet.at);
                assertEq(uint256(cuts[k].action), 0);
                bytes memory packed;
                for (uint256 s; s < cuts[k].functionSelectors.length; ++s) {
                    packed = abi.encodePacked(packed, cuts[k].functionSelectors[s]);
                }
                assertEq(packed, IERC8153(facet.at).exportSelectors());
            }
            string memory path = string.concat(".accounts[", vm.toString(i), "]");
            assertEq(vm.parseJsonString(json, string.concat(path, ".initializer")), initializer.name);
            assertEq(vm.parseJsonString(json, string.concat(path, ".factory")), factory.name);
            assertEq(vm.parseJsonString(json, string.concat(path, ".proxyKind")), entry.proxyKind);
            assertEq(vm.parseJsonAddress(json, string.concat(path, ".entryPoint")), entry.entryPoint);
            assertEq(vm.parseJsonString(json, string.concat(path, ".entryPointVersion")), entry.entryPointVersion);
            assertEq(vm.parseJsonBytes32(json, string.concat(path, ".blueprintHash")), keccak256(abi.encode(cuts)));
            assertEq(
                vm.parseJsonBytes32(json, string.concat(path, ".proxyInitCodeHash")),
                keccak256(vm.getCode(entry.proxyArtifact))
            );
        }
    }

    function test_AccountManifestNativeBindingMutations() public {
        string memory root = "deployments/.account-manifest-fixture";
        vm.createDir(root, true);
        string memory path = string.concat(root, "/release.json");
        vm.writeJson(_envelope(this.snapshot("99.0.0", address(0xBEEF))), path);
        string[] memory command = new string[](3);
        command[0] = "bash";
        command[1] = "script/test-account-release-manifest.sh";
        command[2] = path;
        vm.ffi(command);
        vm.removeDir(root, true);
    }

    function _identity(ContractIdentity[] memory records, string memory name)
        private
        pure
        returns (ContractIdentity memory)
    {
        for (uint256 i; i < records.length; ++i) {
            if (keccak256(bytes(records[i].name)) == keccak256(bytes(name))) return records[i];
        }
        revert("missing manifest identity");
    }

    function test_ReleaseIdentityHasSchemaAndCreationCommitments() public {
        string memory json = snapshot("99.0.0", address(0xBEEF));
        ContractIdentity[] memory records = ManifestReader.identities(vm, json);
        (string[] memory facets, string[] memory facetPaths) = FacetInventory.inventory();
        (string[] memory inits, string[] memory initPaths) = InitInventory.inventory();
        (string[] memory libraries, string[] memory libraryPaths, address[] memory linked) =
            LibraryInventory.inventory();
        assertEq(
            records.length,
            2 + facets.length + inits.length + libraries.length + 2 * AccountReleaseInventory.inventory().length
        );
        assertEq(abi.decode(records[0].constructorArgs, (address)), address(0xBEEF));
        (address registry, address registrar, address reverseOwner) =
            abi.decode(records[1].constructorArgs, (address, address, address));
        assertEq(registry, records[0].at);
        assertEq(registrar, address(0));
        assertEq(reverseOwner, address(0));
        // Factory's immutable registry address means a zero-filled artifact runtime is not its codehash.
        assertEq(address(LatticeFactory(records[1].at).registry()), records[0].at);
        for (uint256 i; i < records.length; ++i) {
            ContractIdentity memory record = records[i];
            assertEq(record.at, ArachnidDeployer.predict(record.salt, record.initCodeHash));
            assertEq(record.codehash, record.at.codehash);
            assertEq(
                record.initCodeHash, keccak256(abi.encodePacked(vm.getCode(record.artifact), record.constructorArgs))
            );
            if (i >= 2 && i < 2 + facets.length) {
                assertEq(record.name, facets[i - 2]);
                assertEq(record.artifact, facetPaths[i - 2]);
                assertEq(record.nameHash, keccak256(abi.encodePacked("lattice.", record.name)));
                assertTrue(record.selectorsHash != bytes32(0));
                assertEq(record.selectors, IERC8153(record.at).exportSelectors());
                assertEq(record.selectorsHash, keccak256(record.selectors));
            } else if (i >= 2 + facets.length && i < 2 + facets.length + inits.length) {
                assertEq(record.name, inits[i - 2 - facets.length]);
                assertEq(record.artifact, initPaths[i - 2 - facets.length]);
                assertEq(record.nameHash, bytes32(0));
                assertEq(record.selectorsHash, bytes32(0));
                assertEq(record.selectors.length, 0);
            } else if (i >= 2 + facets.length + inits.length && i < 2 + facets.length + inits.length + libraries.length)
            {
                uint256 at = i - 2 - facets.length - inits.length;
                assertEq(record.name, libraries[at]);
                assertEq(record.artifact, libraryPaths[at]);
                assertEq(record.at, linked[at]);
                assertEq(record.codehash, LibraryInventory.runtimeHash(vm, record.artifact, record.at));
                assertEq(ILatticeRegistry(records[0].at).resolve(record.codehash), record.at);
            } else if (i >= 2 + facets.length + inits.length + libraries.length) {
                assertEq(record.nameHash, bytes32(0));
                assertEq(record.selectorsHash, bytes32(0));
            }
        }
        assertEq(vm.parseJsonBytes32(json, ".proxy.initCodeHash"), keccak256(vm.getCode("src/Lattice.sol:Lattice")));
    }

    function test_InitialOwnerIsExplicitAndChangesCorePredictions() public {
        vm.expectRevert("manifest: explicit nonzero initial owner required");
        this.snapshot("99.0.0", address(0));
        bytes32 hashA = keccak256(
            abi.encodePacked(vm.getCode("src/LatticeRegistry.sol:LatticeRegistry"), abi.encode(address(0xBEEF)))
        );
        bytes32 hashB = keccak256(
            abi.encodePacked(vm.getCode("src/LatticeRegistry.sol:LatticeRegistry"), abi.encode(address(0xCAFE)))
        );
        assertTrue(ArachnidDeployer.predict(REGISTRY_SALT, hashA) != ArachnidDeployer.predict(REGISTRY_SALT, hashB));
    }

    function test_AllCommittedManifestsHaveSchemaAndPredictions() public {
        Vm.DirEntry[] memory entries = vm.readDir("deployments", 3);
        string memory fixtureRelease = "test/fixtures/release-manifests/release.json";
        string memory fixtureChain = "test/fixtures/release-manifests/chain.json";
        _requiredKeys(vm.readFile(fixtureRelease), "deployments/schema/release.schema.json");
        _requiredKeys(vm.readFile(fixtureChain), "deployments/schema/chain.schema.json");
        string[] memory fixtureCommand = new string[](4);
        fixtureCommand[0] = "bash";
        fixtureCommand[1] = "script/release/validate-manifest.sh";
        fixtureCommand[2] = fixtureRelease;
        fixtureCommand[3] = fixtureChain;
        vm.ffi(fixtureCommand);
        for (uint256 i; i < entries.length; ++i) {
            if (entries[i].isDir || !_endsWith(entries[i].path, ".json") || !_contains(entries[i].path, "/release-")) {
                continue;
            }
            string memory json = vm.readFile(entries[i].path);
            assertEq(vm.parseJsonUint(json, ".schemaVersion"), 1);
            if (vm.keyExistsJson(json, ".chain")) {
                _validateCommittedChain(entries[i].path, json, entries);
                continue;
            }
            _requiredKeys(json, "deployments/schema/release.schema.json");
            string[] memory command = new string[](3);
            command[0] = "bash";
            command[1] = "script/release/validate-manifest.sh";
            command[2] = entries[i].path;
            vm.ffi(command);
            ContractIdentity[] memory records = ManifestReader.identities(vm, json);
            for (uint256 j; j < records.length; ++j) {
                assertEq(records[j].at, ArachnidDeployer.predict(records[j].salt, records[j].initCodeHash));
            }
        }
        // Published release goldens are added only after an already-merged source freeze and owner decision.
        // Synthetic schema fixtures never stand in for a public release or an archived source commit.
    }

    function _validateCommittedChain(string memory statusPath, string memory statusJson, Vm.DirEntry[] memory entries)
        private
    {
        _requiredKeys(statusJson, "deployments/schema/chain.schema.json");
        bool matched;
        for (uint256 i; i < entries.length; ++i) {
            if (entries[i].isDir || !_endsWith(entries[i].path, ".json") || !_contains(entries[i].path, "/release-")) {
                continue;
            }
            string memory candidate = vm.readFile(entries[i].path);
            if (vm.keyExistsJson(candidate, ".chain")) continue;
            if (
                keccak256(bytes(vm.parseJsonString(candidate, ".lattice.commit")))
                    != keccak256(bytes(vm.parseJsonString(statusJson, ".lattice.commit")))
            ) continue;
            if (
                keccak256(bytes(vm.parseJsonString(candidate, ".lattice.version")))
                    != keccak256(bytes(vm.parseJsonString(statusJson, ".lattice.version")))
            ) continue;
            string[] memory command = new string[](4);
            command[0] = "bash";
            command[1] = "script/release/validate-manifest.sh";
            command[2] = entries[i].path;
            command[3] = statusPath;
            vm.ffi(command);
            matched = true;
        }
        assertTrue(matched, "chain manifest must reference an offline manifest");
    }

    function _requiredKeys(string memory json, string memory schemaPath) private view {
        string[] memory required = vm.parseJsonStringArray(vm.readFile(schemaPath), ".required");
        for (uint256 i; i < required.length; ++i) {
            assertTrue(vm.keyExistsJson(json, string.concat(".", required[i])));
        }
        string[] memory keys = vm.parseJsonKeys(json, ".");
        string memory schema = vm.readFile(schemaPath);
        for (uint256 i; i < keys.length; ++i) {
            assertTrue(vm.keyExistsJson(schema, string.concat(".properties.", keys[i])), "unknown manifest field");
        }
    }

    function test_ObserverHasNoLinkedLibraryDependencies() public view {
        assertEq(
            vm.parseJsonKeys(vm.readFile("out/ObserveManifest.s.sol/ObserveManifest.json"), ".bytecode.linkReferences")
            .length,
            0
        );
        assertEq(
            vm.parseJsonKeys(
                vm.readFile("out/ObserveManifest.s.sol/StatusRecordWriter.json"), ".bytecode.linkReferences"
            )
            .length,
            0
        );
    }

    function test_ObservedStatusSeparatesPresenceCurationAndVerification() public {
        string memory releaseJson = _envelope(this.snapshot("99.0.0", address(this)));
        vm.serializeJson("test:owner", releaseJson);
        releaseJson = vm.serializeAddress("test:owner", "initialOwner", address(this));
        ContractIdentity[] memory records = ManifestReader.identities(vm, releaseJson);
        // A missing factory and wrong-code facet must not be promoted to ready, even with old registry records.
        vm.etch(records[1].at, "");
        vm.etch(records[2].at, hex"00");
        string memory statusJson = new ObserveManifest().observe(releaseJson, keccak256("local fixture block"));
        bool[] memory matches = abi.decode(vm.parseJson(statusJson, ".contracts[*].codeMatches"), (bool[]));
        bool[] memory registered = abi.decode(vm.parseJson(statusJson, ".contracts[*].registered"), (bool[]));
        bool[] memory latest = abi.decode(vm.parseJson(statusJson, ".contracts[*].latest"), (bool[]));
        bool[] memory verified = abi.decode(vm.parseJson(statusJson, ".contracts[*].verified"), (bool[]));
        assertEq(matches.length, records.length);
        assertEq(vm.parseJsonAddress(statusJson, ".registryOwner"), address(this));
        assertFalse(matches[1]);
        assertFalse(matches[2]);
        for (uint256 i; i < records.length; ++i) {
            assertFalse(verified[i]);
            bool curated = i > 2 && keccak256(bytes(records[i].kind)) == keccak256("facet");
            assertEq(registered[i], curated);
            assertEq(latest[i], curated);
        }
        string memory root = "deployments/.manifest-fixtures";
        vm.createDir(root, true);
        vm.writeJson(releaseJson, string.concat(root, "/release.json"));
        // Canonical JSON hashing belongs to the Bash wrapper; it is tested through the fixture driver.
        vm.writeJson(statusJson, string.concat(root, "/chain-unhashed.json"));
        string[] memory command = new string[](5);
        command[0] = "bash";
        command[1] = "script/test-release-manifest.sh";
        command[2] = string.concat(root, "/release.json");
        command[3] = string.concat(root, "/chain-unhashed.json");
        command[4] = "--hash-local-fixture";
        vm.ffi(command);
        vm.removeDir(root, true);
    }

    function _envelope(string memory identities) private pure returns (string memory) {
        bytes memory original = bytes(identities);
        original[original.length - 1] = " ";
        return string.concat(
            string(original),
            ',"schemaVersion":1,"publication":"fixture","initialOwner":"0x000000000000000000000000000000000000bEEF","lattice":{"version":"99.0.0","tag":"fixture/unit-test","commit":"1111111111111111111111111111111111111111"},"deployer":{"kind":"arachnid","address":"0x4e59b44847b379578588920cA78FbF26c0B4956C","librarySalt":"0x0000000000000000000000000000000000000000000000000000000000000000"},"compiler":{"foundry":"v1.9.0","solc":"0.8.36","evmVersion":"cancun","optimizerRuns":1000000,"viaIR":false,"bytecodeHash":"ipfs","libraries":{},"inputHash":"0x1111111111111111111111111111111111111111111111111111111111111111"}}'
        );
    }

    function _endsWith(string memory value, string memory suffix) private pure returns (bool) {
        bytes memory v = bytes(value);
        bytes memory s = bytes(suffix);
        if (v.length < s.length) return false;
        for (uint256 i; i < s.length; ++i) {
            if (v[v.length - s.length + i] != s[i]) return false;
        }
        return true;
    }

    function _contains(string memory value, string memory needle) private pure returns (bool) {
        bytes memory v = bytes(value);
        bytes memory n = bytes(needle);
        for (uint256 i; i + n.length <= v.length; ++i) {
            bool match_ = true;
            for (uint256 j; j < n.length; ++j) {
                if (v[i + j] != n[j]) {
                    match_ = false;
                    break;
                }
            }
            if (match_) return true;
        }
        return false;
    }
}
