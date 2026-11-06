// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../fixtures/composition/MetadataFixtures.sol";
import {CoreCompositionMetadata} from "@lattice-script/lib/CoreCompositionMetadata.sol";
import {FacetInventory} from "@lattice-script/lib/FacetInventory.sol";
import {InitInventory} from "@lattice-script/lib/InitInventory.sol";
import {ERC20_TEMPORARY_APPROVAL_STORAGE_SLOT} from "@lattice/tokens/ERC20/libraries/ERC20TemporaryApprovalLib.sol";
import {Test} from "forge-std/Test.sol";

/// @title CompositionMetadataTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Compiled NatSpec completeness and reference gate; semantic truth still requires source review.
contract CompositionMetadataTest is Test {
    string private constant TEMPORARY_NAMESPACE = "transient:lattice.storage.ERC20TemporaryApproval";

    error MissingTag(string artifact, string tag);
    error InvalidTag(string artifact, string tag, string value);
    error DanglingReference(string artifact, string referenceName);
    error InvalidInitializerReference(string artifact, string initializerName);

    function test_CompilerPreservesRawTagsAndConcatenatesRepeatedRecords() public view {
        string memory artifact = _artifact("MetadataFixtures.sol", "MetadataFoldFixture");
        string memory raw = vm.parseJsonString(artifact, ".rawMetadata");
        assertFalse(vm.keyExistsJson(artifact, ".metadata.output.devdoc['custom:lattice-family']"));
        assertEq(vm.parseJsonString(raw, ".output.devdoc['custom:lattice-family']"), "none");
        assertEq(
            vm.parseJsonString(raw, ".output.devdoc['custom:lattice-requires']"),
            "ERC20 hard first record;AccessControl convention second record;"
        );
        string memory method = ".output.devdoc.methods['init(uint256,address)']";
        assertEq(vm.parseJsonString(raw, string.concat(method, "['custom:lattice-kind']")), "step");
        assertEq(
            vm.parseJsonString(raw, string.concat(method, "['custom:lattice-param']")),
            "delay unit=seconds rule=nonzero;admin authority;"
        );
        assertTrue(vm.keyExistsJson(raw, string.concat(method, "['custom:lattice-registers-interfaces']")));
        assertEq(vm.parseJsonString(raw, string.concat(method, "['custom:lattice-registers-interfaces']")), "");
    }

    function test_AllReleaseFacetsHaveCompositionMetadata() public {
        (string[] memory names, string[] memory paths) = FacetInventory.inventory();
        for (uint256 i; i < names.length; ++i) {
            this.validateFacet(names[i], paths[i]);
        }
    }

    function test_AllReleasedInitializersHaveCompositionMetadata() public {
        (string[] memory names, string[] memory paths) = InitInventory.inventory();
        for (uint256 i; i < names.length; ++i) {
            this.validateInitializer(names[i], paths[i]);
        }
    }

    function test_MissingTagMutationIsRejected() public {
        vm.expectRevert(abi.encodeWithSelector(MissingTag.selector, "MetadataMissingFixture", "init"));
        this.validateFacet("MetadataMissingFixture", "MetadataFixtures.sol:MetadataMissingFixture");
    }

    function test_DanglingReferenceMutationIsRejected() public {
        vm.expectRevert(abi.encodeWithSelector(DanglingReference.selector, "MetadataDanglingFixture", "DoesNotExist"));
        this.validateFacet("MetadataDanglingFixture", "MetadataFixtures.sol:MetadataDanglingFixture");
    }

    function test_BareMarkerConsumesFollowingTagUnlessLast() public view {
        string memory raw = vm.parseJsonString(_artifact("MetadataFixtures.sol", "MetadataFoldFixture"), ".rawMetadata");
        string memory method = ".output.devdoc.methods['misordered(address)']";
        assertFalse(vm.keyExistsJson(raw, string.concat(method, "['custom:lattice-param']")));
        assertEq(
            vm.parseJsonString(raw, string.concat(method, "['custom:lattice-registers-interfaces']")),
            "@custom:lattice-param admin authority;"
        );
    }

    function test_DanglingInitializerModuleMutationIsRejected() public {
        vm.expectRevert(
            abi.encodeWithSelector(DanglingReference.selector, "MetadataDanglingInitializerFixture", "DoesNotExist")
        );
        this.validateInitializer(
            "MetadataDanglingInitializerFixture", "MetadataFixtures.sol:MetadataDanglingInitializerFixture"
        );
    }

    function test_MissingInitializerParameterMutationIsRejected() public {
        vm.expectRevert(abi.encodeWithSelector(MissingTag.selector, "MetadataMissingParameterFixture", "param"));
        this.validateInitializer(
            "MetadataMissingParameterFixture", "MetadataFixtures.sol:MetadataMissingParameterFixture"
        );
    }

    function test_CoreOverlayDoesNotExemptNewFirstPartyEntries() public pure {
        assertEq(CoreCompositionMetadata.devdoc("ERC20TemporaryApproval"), "");
        assertEq(CoreCompositionMetadata.devdoc("HSSAdapterRecoveryInit"), "");
    }

    function test_NonInitializerContractReferenceMutationIsRejected() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidInitializerReference.selector, "MetadataNonInitializerContractFixture", "ERC20"
            )
        );
        this.validateFacet(
            "MetadataNonInitializerContractFixture", "MetadataFixtures.sol:MetadataNonInitializerContractFixture"
        );
    }

    function test_NonInitializerLibraryReferenceMutationIsRejected() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidInitializerReference.selector, "MetadataNonInitializerLibraryFixture", "ERC20Lib"
            )
        );
        this.validateFacet(
            "MetadataNonInitializerLibraryFixture", "MetadataFixtures.sol:MetadataNonInitializerLibraryFixture"
        );
    }

    function test_TransientNamespaceIsAccepted() public view {
        this.validateFacet(
            "MetadataTransientNamespaceFixture", "MetadataFixtures.sol:MetadataTransientNamespaceFixture"
        );
    }

    function test_WrongTransientRootMutationIsRejected() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DanglingReference.selector, "MetadataWrongTransientRootFixture", "transient:lattice.storage.ERC20"
            )
        );
        this.validateFacet(
            "MetadataWrongTransientRootFixture", "MetadataFixtures.sol:MetadataWrongTransientRootFixture"
        );
    }

    function test_TransientRootMatchesSourceAndIsNotPersistentLayout() public view {
        _assertTemporaryRoot();
        string[] memory persistent = abi.decode(
            vm.parseJson(vm.readFile("script/upgrades/storage-registry.json"), ".layouts[*].namespace"), (string[])
        );
        for (uint256 i; i < persistent.length; ++i) {
            assertFalse(
                _eq(persistent[i], "lattice.storage.ERC20TemporaryApproval"),
                "transient root is not a persistent struct"
            );
        }
    }

    /// @dev Curated against actual exported entrypoints: _spendAllowance consumers and direct temporaryApprove.
    function test_TransientWriteUnionCoversSpendersAndExcludesApproveOnlyFacets() public view {
        string[10] memory writers = [
            "ERC20",
            "ERC20Burnable",
            "ERC20FlashMint",
            "ERC20Pausable",
            "ERC20Votes",
            "ERC1363",
            "ERC4626",
            "VaultCore",
            "GovernedVault",
            "ERC20TemporaryApproval"
        ];
        for (uint256 i; i < writers.length; ++i) {
            assertTrue(
                _declaresTemporaryWrites(writers[i]),
                string.concat(writers[i], ": missing conditional transient writes")
            );
        }
        string[5] memory others = ["ERC20Permit", "ERC20Capped", "ERC20Wrapper", "ERC20Crosschain", "ERC7802"];
        for (uint256 i; i < others.length; ++i) {
            assertFalse(_declaresTemporaryWrites(others[i]), string.concat(others[i], ": no local transient writes"));
        }
    }

    function _assertTemporaryRoot() private pure {
        bytes32 derived = keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC20TemporaryApproval")) - 1))
            & ~bytes32(uint256(0xff));
        assertEq(ERC20_TEMPORARY_APPROVAL_STORAGE_SLOT, derived, "temporary namespace must match the source root");
    }

    function _declaresTemporaryWrites(string memory name) private view returns (bool) {
        string memory raw = vm.parseJsonString(_artifact(string.concat(name, ".sol"), name), ".rawMetadata");
        string[] memory namespaces = _split(_tag(raw, ".output.devdoc", name, "touches"), bytes1(";"));
        for (uint256 i; i < namespaces.length; ++i) {
            if (_eq(namespaces[i], TEMPORARY_NAMESPACE)) return true;
        }
        return false;
    }

    /// @dev A fresh external frame bounds allocations while scanning all release artifacts.
    function validateFacet(string memory name, string memory path) external view {
        string memory artifact = _readArtifact(path, name);
        string memory raw = _devdoc(name, path, artifact);
        string memory prefix = ".output.devdoc";
        string memory requires_ = _tag(raw, prefix, name, "requires");
        _tag(raw, prefix, name, "family");
        string memory owns = _tag(raw, prefix, name, "owns");
        string memory touches = _tag(raw, prefix, name, "touches");
        string memory init = _tag(raw, prefix, name, "init");
        string memory seams = _tag(raw, prefix, name, "seam");
        _references(name, requires_, true, true);
        _initializerReference(name, init);
        _signatures(name, artifact, owns);
        _namespaces(name, touches);
        _seams(name, artifact, seams);
    }

    function validateInitializer(string memory name, string memory path) external view {
        string memory artifact = _readArtifact(path, name);
        string memory raw = _devdoc(name, path, artifact);
        string memory kind = _tag(raw, ".output.devdoc", name, "kind");
        if (!_eq(kind, "step") && !_eq(kind, "bundle")) revert InvalidTag(name, "kind", kind);
        string[] memory signatures = vm.parseJsonKeys(artifact, ".methodIdentifiers");
        if (signatures.length == 0) revert InvalidTag(name, "initializer", "no entrypoint");
        for (uint256 i; i < signatures.length; ++i) {
            string memory prefix = string.concat(".output.devdoc.methods['", signatures[i], "']");
            _references(name, _tag(raw, prefix, name, "initializes"), false, false);
            _references(name, _tag(raw, prefix, name, "after"), false, true);
            _references(name, _tag(raw, prefix, name, "same-call"), false, true);
            if (_eq(kind, "bundle")) _references(name, _tag(raw, prefix, name, "sequence"), false, false);
            _parameters(name, artifact, raw, prefix, signatures[i]);
            string memory registration = string.concat(prefix, "['custom:lattice-registers-interfaces']");
            if (vm.keyExistsJson(raw, registration) && bytes(vm.parseJsonString(raw, registration)).length != 0) {
                revert InvalidTag(name, "registers-interfaces", "bare marker must be last");
            }
        }
    }

    function _parameters(
        string memory name,
        string memory artifact,
        string memory raw,
        string memory prefix,
        string memory signature
    ) private view {
        string memory records = _tag(raw, prefix, name, "param");
        string[] memory entries = _split(records, bytes1(";"));
        string[] memory parameters = _parameterNames(artifact, signature);
        if (parameters.length == 0) {
            if (!_eq(records, "none;")) revert InvalidTag(name, "param", records);
            return;
        }
        if (entries.length != parameters.length) revert InvalidTag(name, "param count", records);
        for (uint256 i; i < parameters.length; ++i) {
            bool found;
            for (uint256 j; j < entries.length; ++j) {
                if (_parameterEntry(name, parameters[i], entries[j])) found = true;
            }
            if (!found) revert MissingTag(name, string.concat("param ", parameters[i]));
        }
    }

    function _parameterEntry(string memory name, string memory parameter, string memory entry)
        private
        pure
        returns (bool)
    {
        string[] memory words = _split(entry, bytes1(" "));
        if (!_eq(words[0], parameter)) return false;
        for (uint256 i = 1; i < words.length; ++i) {
            if (
                _starts(words[i], "unit=") && !_eq(words[i], "unit=seconds") && !_eq(words[i], "unit=percent")
                    && !_eq(words[i], "unit=wei")
            ) revert InvalidTag(name, "param unit", words[i]);
        }
        return true;
    }

    function _parameterNames(string memory artifact, string memory signature) private view returns (string[] memory) {
        bytes memory sig = bytes(signature);
        uint256 open;
        while (sig[open] != "(") ++open;
        string memory functionName = _slice(sig, 0, open);
        for (uint256 i; vm.keyExistsJson(artifact, string.concat(".abi[", vm.toString(i), "]")); ++i) {
            string memory key = string.concat(".abi[", vm.toString(i), "]");
            if (!vm.keyExistsJson(artifact, string.concat(key, ".name"))) continue;
            if (
                _eq(vm.parseJsonString(artifact, string.concat(key, ".name")), functionName)
                    && _eq(_abiSignature(artifact, key, functionName), signature)
            ) {
                uint256 length;
                while (vm.keyExistsJson(artifact, string.concat(key, ".inputs[", vm.toString(length), "]"))) ++length;
                string[] memory names = new string[](length);
                for (uint256 j; j < length; ++j) {
                    names[j] = vm.parseJsonString(artifact, string.concat(key, ".inputs[", vm.toString(j), "].name"));
                }
                return names;
            }
        }
        revert InvalidTag(functionName, "method ABI", signature);
    }

    function _abiSignature(string memory artifact, string memory key, string memory name)
        private
        view
        returns (string memory signature)
    {
        signature = string.concat(name, "(");
        for (uint256 i; vm.keyExistsJson(artifact, string.concat(key, ".inputs[", vm.toString(i), "]")); ++i) {
            if (i != 0) signature = string.concat(signature, ",");
            signature =
                string.concat(signature, _abiType(artifact, string.concat(key, ".inputs[", vm.toString(i), "]")));
        }
        return string.concat(signature, ")");
    }

    function _abiType(string memory artifact, string memory key) private view returns (string memory canonical) {
        string memory type_ = vm.parseJsonString(artifact, string.concat(key, ".type"));
        if (!_starts(type_, "tuple")) return type_;
        canonical = "(";
        for (uint256 i; vm.keyExistsJson(artifact, string.concat(key, ".components[", vm.toString(i), "]")); ++i) {
            if (i != 0) canonical = string.concat(canonical, ",");
            canonical =
                string.concat(canonical, _abiType(artifact, string.concat(key, ".components[", vm.toString(i), "]")));
        }
        return string.concat(canonical, ")", _slice(bytes(type_), 5, bytes(type_).length));
    }

    function _tag(string memory raw, string memory prefix, string memory name, string memory tag)
        private
        view
        returns (string memory value)
    {
        string memory key = string.concat(prefix, "['custom:lattice-", tag, "']");
        if (!vm.keyExistsJson(raw, key)) revert MissingTag(name, tag);
        value = vm.parseJsonString(raw, key);
        if (bytes(value).length == 0) revert InvalidTag(name, tag, value);
        if (!_eq(tag, "family") && !_eq(tag, "init") && !_eq(tag, "kind")) {
            bytes memory record = bytes(value);
            if (record[record.length - 1] != ";") revert InvalidTag(name, tag, value);
        }
    }

    function _references(string memory name, string memory records, bool facetsOnly, bool qualified) private view {
        if (bytes(records).length == 0) revert InvalidTag(name, "reference", records);
        string[] memory entries = _split(records, bytes1(";"));
        for (uint256 i; i < entries.length; ++i) {
            string memory entry = entries[i];
            if (
                _eq(entry, "none")
                    || ((_eq(name, "MultiInit") || _eq(name, "ReinitMultiInit")) && _eq(entry, "caller-defined"))
            ) continue;
            string[] memory words = _split(entry, bytes1(" "));
            if (qualified && (words.length < 3 || (!_eq(words[1], "hard") && !_eq(words[1], "convention")))) {
                revert InvalidTag(name, "requirement", entry);
            }
            string[] memory alternatives = _split(words[0], bytes1("|"));
            for (uint256 j; j < alternatives.length; ++j) {
                if (!_known(alternatives[j], facetsOnly)) revert DanglingReference(name, alternatives[j]);
            }
        }
    }

    function _initializerReference(string memory artifact, string memory initializer) private view {
        if (_eq(initializer, "none")) return;
        bool listed;
        (string[] memory names,) = InitInventory.inventory();
        for (uint256 i; i < names.length; ++i) {
            if (_eq(initializer, names[i])) {
                listed = true;
                break;
            }
        }
        // These two constructor-bound initializers are deliberately released by their account factories.
        // InitInventory.exclusionReason documents the same narrow exception; ordinary artifacts are not inits.
        if (_eq(initializer, "AccountInit") || _eq(initializer, "AccountInit6900")) {
            listed = bytes(InitInventory.exclusionReason(initializer)).length != 0;
        }
        if (!listed || !_known(initializer, false)) revert InvalidInitializerReference(artifact, initializer);
    }

    function _known(string memory name, bool facetsOnly) private view returns (bool) {
        if (facetsOnly) {
            (string[] memory names,) = FacetInventory.inventory();
            for (uint256 i; i < names.length; ++i) {
                if (_eq(name, names[i])) return true;
            }
            return false;
        }
        return vm.exists(string.concat(vm.projectRoot(), "/out/", name, ".sol/", name, ".json"))
            || vm.exists(string.concat(vm.projectRoot(), "/out/", name, "Lib.sol/", name, "Lib.json"));
    }

    function _signatures(string memory name, string memory artifact, string memory records) private view {
        string[] memory signatures = _split(records, bytes1(";"));
        for (uint256 i; i < signatures.length; ++i) {
            if (_eq(signatures[i], "none")) continue;
            if (_eq(signatures[i], "receive()") && _eq(name, "Receive")) continue;
            if (!vm.keyExistsJson(artifact, string.concat(".methodIdentifiers['", signatures[i], "']"))) {
                revert InvalidTag(name, "owns", signatures[i]);
            }
            if (_eq(signatures[i], "exportSelectors()")) revert InvalidTag(name, "owns", signatures[i]);
        }
    }

    function _namespaces(string memory name, string memory records) private view {
        string[] memory namespaces = _split(records, bytes1(";"));
        string[] memory known = abi.decode(
            vm.parseJson(
                vm.readFile(string.concat(vm.projectRoot(), "/script/upgrades/storage-registry.json")),
                ".layouts[*].namespace"
            ),
            (string[])
        );
        for (uint256 i; i < namespaces.length; ++i) {
            if (_eq(namespaces[i], "none")) continue;
            if (_eq(namespaces[i], TEMPORARY_NAMESPACE)) {
                _assertTemporaryRoot();
                continue;
            }
            if (_eq(namespaces[i], "diamond.lib.storage") || _eq(namespaces[i], "diamond.lib.storage.ERC165")) {
                continue; // Pinned upstream roots.
            }
            if (_eq(namespaces[i], "slot:0x8000000000ab143c06")) continue; // ReentrancyGuardLib's shared lock.
            if (
                _eq(name, "OwnableFacet")
                    && (_eq(namespaces[i], "slot:0xffffffffffffffffffffffffffffffffffffffffffffffffffffffff74873927")
                        || _eq(namespaces[i], "derived:OwnableHandover"))
            ) continue;
            bool found;
            for (uint256 j; j < known.length; ++j) {
                if (_eq(known[j], namespaces[i])) found = true;
            }
            if (!found) revert DanglingReference(name, namespaces[i]);
        }
    }

    function _seams(string memory name, string memory artifact, string memory records) private view {
        string[] memory entries = _split(records, bytes1(";"));
        for (uint256 i; i < entries.length; ++i) {
            if (_eq(entries[i], "none")) continue;
            string[] memory words = _split(entries[i], bytes1(" "));
            _signatures(name, artifact, words[0]);
            bool hasWhen;
            bool hasOwners;
            for (uint256 j = 1; j < words.length; ++j) {
                bytes memory word = bytes(words[j]);
                uint256 start;
                if (_starts(words[j], "when=")) {
                    start = 5;
                    hasWhen = true;
                } else if (_starts(words[j], "anyOf=")) {
                    start = 6;
                    hasOwners = true;
                } else {
                    continue;
                }
                _references(name, _slice(word, start, word.length), true, false);
            }
            if (!hasWhen || !hasOwners || words.length < 4) revert InvalidTag(name, "seam", entries[i]);
        }
    }

    function _devdoc(string memory name, string memory path, string memory artifact)
        private
        pure
        returns (string memory)
    {
        string memory overlay = CoreCompositionMetadata.devdoc(name);
        return bytes(overlay).length != 0 && _eq(path, string.concat(name, ".sol:", name))
            ? overlay
            : vm.parseJsonString(artifact, ".rawMetadata");
    }

    function _readArtifact(string memory path, string memory name) private view returns (string memory) {
        bytes memory source = bytes(path);
        uint256 end = source.length;
        uint256 start;
        for (uint256 i; i < source.length; ++i) {
            if (source[i] == ":") {
                end = i;
                break;
            }
            if (source[i] == "/") start = i + 1;
        }
        return _artifact(_slice(source, start, end), name);
    }

    function _artifact(string memory file, string memory name) private view returns (string memory) {
        return vm.readFile(string.concat(vm.projectRoot(), "/out/", file, "/", name, ".json"));
    }

    function _split(string memory input, bytes1 delimiter) private pure returns (string[] memory values) {
        bytes memory data = bytes(input);
        uint256 count;
        for (uint256 i; i < data.length; ++i) {
            if (data[i] == delimiter) ++count;
        }
        if (data.length != 0 && data[data.length - 1] != delimiter) ++count;
        values = new string[](count);
        uint256 start;
        uint256 index;
        for (uint256 i; i <= data.length; ++i) {
            if (i == data.length || data[i] == delimiter) {
                if (i != start) values[index++] = _slice(data, start, i);
                start = i + 1;
            }
        }
    }

    function _slice(bytes memory data, uint256 start, uint256 end) private pure returns (string memory) {
        bytes memory result = new bytes(end - start);
        for (uint256 i; i < result.length; ++i) {
            result[i] = data[start + i];
        }
        return string(result);
    }

    function _eq(string memory a, string memory b) private pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _starts(string memory a, string memory b) private pure returns (bool) {
        bytes memory aa = bytes(a);
        bytes memory bb = bytes(b);
        if (aa.length < bb.length) return false;
        for (uint256 i; i < bb.length; ++i) {
            if (aa[i] != bb[i]) return false;
        }
        return true;
    }
}
