// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {RawCode} from "@lattice-test/helpers/LatticeCoreMocks.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {ILatticeRegistry} from "@lattice/interfaces/ILatticeRegistry.sol";
import {Test} from "forge-std/Test.sol";

/// @title LatticeRegistryFuzz
/// @notice #176: stateless fuzz properties of {LatticeRegistry}: string/hash overload parity, record
///         immutability, the exact acceptance rule for selector blobs and for raw return data, version 0, and the
///         two-step ownership handover.
contract LatticeRegistryFuzz is Test {
    LatticeRegistry internal registry;
    address internal owner = makeAddr("registryOwner");

    uint256 internal constant MAX_BLOB = 256;

    function setUp() public {
        registry = new LatticeRegistry(owner);
    }

    /// @dev External so a test can `try` it: reverts exactly when `abi.decode(ret, (bytes))` would.
    function decodeBytes(bytes calldata ret) external pure returns (bytes memory) {
        return abi.decode(ret, (bytes));
    }

    /// @dev The ERC-8153 acceptance rule the registry documents: non-empty, 4-aligned, no duplicates, and no
    ///      `exportSelectors()` self-selector.
    function _acceptable(bytes memory blob) internal pure returns (bool) {
        if (blob.length == 0 || blob.length % 4 != 0) return false;
        bytes4[] memory s = RawCode.unpack(blob);
        for (uint256 i; i < s.length; ++i) {
            if (s[i] == 0x0ef22643) return false;
            for (uint256 j = i + 1; j < s.length; ++j) {
                if (s[i] == s[j]) return false;
            }
        }
        return true;
    }

    /// @notice Every string overload resolves exactly what its `bytes32` twin resolves for `keccak256(name)`.
    function testFuzz_StringAndHashOverloadsAgree(string calldata name, uint64 version, bytes32 tag, uint8 n) public {
        version = uint64(bound(version, 1, type(uint64).max));
        n = uint8(bound(n, 1, 16));
        bytes32 h = keccak256(bytes(name));
        assertEq(registry.nameHash(name), h, "nameHash is the raw keccak");

        address facet = RawCode.exporter(RawCode.selectorBlob(tag, n));
        vm.startPrank(owner);
        registry.register(name, version, facet);
        registry.setLatest(h, version);
        vm.stopPrank();

        assertEq(keccak256(abi.encode(registry.get(name, version))), keccak256(abi.encode(registry.get(h, version))));
        assertEq(keccak256(abi.encode(registry.latest(name))), keccak256(abi.encode(registry.latest(h))));
        assertEq(
            keccak256(abi.encode(registry.getSelectors(name, version))),
            keccak256(abi.encode(registry.getSelectors(h, version)))
        );
        FacetCut memory a = registry.getCut(name, version);
        FacetCut memory b = registry.getCut(h, version);
        assertEq(keccak256(abi.encode(a)), keccak256(abi.encode(b)), "getCut parity");
    }

    /// @notice A record never changes after it is written, whatever is registered or moved afterwards (I1).
    function testFuzz_RecordIsImmutable(bytes32 nameHash, uint64 version, uint64 other, uint32 warp) public {
        version = uint64(bound(version, 1, type(uint64).max));
        other = uint64(bound(other, 1, type(uint64).max));
        vm.assume(other != version);

        address first = RawCode.exporter(abi.encodePacked(bytes4(0x01020304)));
        address second = RawCode.exporter(abi.encodePacked(bytes4(0x05060708)));
        address replacement = RawCode.exporter(abi.encodePacked(bytes4(0x0a0b0c0d)));

        vm.prank(owner);
        registry.register(nameHash, version, first);
        bytes32 before = keccak256(abi.encode(registry.get(nameHash, version)));

        vm.warp(block.timestamp + warp);
        vm.startPrank(owner);
        registry.register(nameHash, other, second);
        registry.setLatest(nameHash, other);
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__RecordExists.selector, nameHash, version)
        );
        vm.prank(owner);
        registry.register(nameHash, version, replacement);

        assertEq(keccak256(abi.encode(registry.get(nameHash, version))), before, "record changed");
    }

    /// @notice A canonically encoded blob registers EXACTLY when it satisfies the documented rule, and then the
    ///         pin is its hash.
    function testFuzz_BlobAcceptanceMatchesTheRule(bytes memory blob) public {
        if (blob.length > MAX_BLOB) {
            assembly ("memory-safe") {
                mstore(blob, 256)
            }
        }
        address facet = RawCode.exporter(blob);
        if (_acceptable(blob)) {
            vm.prank(owner);
            registry.register(bytes32(0), 1, facet);
            assertEq(registry.get(bytes32(0), 1).selectorsHash, keccak256(blob), "pin is the blob hash");
        } else {
            vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__NotERC8153.selector, facet));
            vm.prank(owner);
            registry.register(bytes32(0), 1, facet);
        }
    }

    /// @notice For ARBITRARY raw return data, registration never accepts anything but a decodable, valid blob,
    ///         and the pin is always the hash of the decoded blob. Failures are {LatticeRegistry__NotERC8153}, or
    ///         (finding R-1) an empty revert or `Panic(0x41)` from the decoder.
    function testFuzz_RawReturnNeverRegistersAnythingButTheDecodedBlob(bytes memory ret) public {
        if (ret.length > MAX_BLOB) {
            assembly ("memory-safe") {
                mstore(ret, 256)
            }
        }
        _checkRawReturn(ret);
    }

    /// @notice The same property over STRUCTURED encodings (offset word, padding, declared length, body), which
    ///         reach the decoder's offset and length checks far more often than unstructured bytes.
    function testFuzz_StructuredReturnNeverRegistersAnythingButTheDecodedBlob(
        uint8 offsetWords,
        uint16 declaredLength,
        bytes memory body
    ) public {
        offsetWords = uint8(bound(offsetWords, 0, 3));
        declaredLength = uint16(bound(declaredLength, 0, 80));
        if (body.length > 96) {
            assembly ("memory-safe") {
                mstore(body, 96)
            }
        }
        bytes memory head = abi.encode(uint256(offsetWords) * 32 + 32);
        for (uint256 i; i < offsetWords; ++i) {
            head = abi.encodePacked(head, bytes32(0));
        }
        _checkRawReturn(abi.encodePacked(head, uint256(declaredLength), body));
    }

    function _checkRawReturn(bytes memory ret) internal {
        address facet = RawCode.deploy(ret);

        bool decodes;
        bytes memory decoded;
        if (ret.length >= 64) {
            try this.decodeBytes(ret) returns (bytes memory d) {
                decodes = true;
                decoded = d;
            } catch {}
        }

        vm.prank(owner);
        try registry.register(bytes32(0), 1, facet) {
            assertTrue(decodes && _acceptable(decoded), "accepted an invalid return");
            assertEq(registry.get(bytes32(0), 1).selectorsHash, keccak256(decoded), "pin != decoded blob");
        } catch (bytes memory err) {
            assertFalse(decodes && _acceptable(decoded), "rejected a valid return");
            bool documented = keccak256(err)
                == keccak256(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__NotERC8153.selector, facet));
            bool bare = err.length == 0;
            bool panic = keccak256(err) == keccak256(abi.encodeWithSignature("Panic(uint256)", uint256(0x41)));
            assertTrue(documented || bare || panic, "unexpected revert shape");
            if (!decodes && ret.length >= 64) assertFalse(documented, "decoder failures are not NotERC8153 (R-1)");
        }
    }

    /// @notice Version 0 never registers, for any name and any valid facet (I3 sentinel).
    function testFuzz_VersionZeroNeverRegisters(bytes32 nameHash, bytes32 tag) public {
        address facet = RawCode.exporter(RawCode.selectorBlob(tag, 1));
        vm.expectRevert(ILatticeRegistry.LatticeRegistry__InvalidVersion.selector);
        vm.prank(owner);
        registry.register(nameHash, 0, facet);
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__RecordNotFound.selector, nameHash, 0));
        registry.get(nameHash, 0);
    }

    /// @notice The handover completes only for the nominated account, and only once. (`transferOwnership(0)`
    ///         "cancels" by nominating address 0, which no transaction can send from; see
    ///         {test_Finding_CancelledHandoverIsAcceptableOnlyByAddressZero}.)
    function testFuzz_OwnershipHandover(address nominee, address caller) public {
        vm.prank(owner);
        registry.transferOwnership(nominee);

        if (caller != nominee) {
            vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__NotPendingOwner.selector, caller));
            vm.prank(caller);
            registry.acceptOwnership();
            assertEq(registry.owner(), owner, "owner unchanged");
            return;
        }
        vm.prank(caller);
        registry.acceptOwnership();
        assertEq(registry.owner(), nominee, "handover");
        assertEq(registry.pendingOwner(), address(0), "pending cleared");

        if (caller == address(0)) return;
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__NotPendingOwner.selector, caller));
        vm.prank(caller);
        registry.acceptOwnership();
    }

    /// @notice FINDING (R-4, informational): cancelling stores `pendingOwner = 0`, and `acceptOwnership` does not
    ///         reject a zero pending owner, so a call FROM address 0 would complete the cancelled handover and
    ///         set `owner = 0`, contradicting the constructor's non-zero rule. No EVM transaction is sent from
    ///         address 0, so this is reachable only under a cheatcode; an explicit check would make R4
    ///         (`owner != 0`) hold by construction.
    function test_Finding_CancelledHandoverIsAcceptableOnlyByAddressZero() public {
        vm.startPrank(owner);
        registry.transferOwnership(makeAddr("nominee"));
        registry.transferOwnership(address(0));
        vm.stopPrank();

        vm.prank(address(0));
        registry.acceptOwnership();
        assertEq(registry.owner(), address(0), "owner zeroed by a call from address 0");
    }
}
