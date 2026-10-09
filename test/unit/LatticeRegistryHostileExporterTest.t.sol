// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {
    CoreFlippingExporter,
    CoreLoopExporter,
    CoreReentrantAttestExporter,
    CoreReturnBombExporter,
    CoreSwitchableRawExporter,
    RawCode
} from "@lattice-test/helpers/LatticeCoreMocks.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {ILatticeRegistry} from "@lattice/interfaces/ILatticeRegistry.sol";
import {Test} from "forge-std/Test.sol";

/// @title LatticeRegistryHostileExporterTest
/// @notice #176: how {LatticeRegistry} treats hostile ERC-8153 selector exporters. Each case pins the exact
///         outcome today, at registration and on the live read path that {LatticeRegistry.getCut} and the factory
///         use: reverting and gas-burning calls, short, malformed and non-canonical ABI encodings, trailing bytes,
///         huge returns and the return-size and gas bounds, duplicates and the forbidden self-selector deep in a
///         long blob, mutable exports, code drift, and an exporter that tries to write to the registry from inside
///         its staticcall.
/// @dev Findings R-1 (malformed returns reported as empty reverts or Panics) and R-2 (unbounded gas and return
///      size) are fixed; the tests below pin the fixed behaviour. R-3 (Tier A is a code-identity lookup) is
///      documented in {ILatticeRegistry}. See docs/security/registry-factory-threat-model.md.
contract LatticeRegistryHostileExporterTest is Test {
    LatticeRegistry internal registry;
    address internal owner = makeAddr("registryOwner");

    bytes32 internal constant NAME = keccak256("lattice.Hostile");
    uint64 internal constant V1 = 1 << 48;

    bytes4 internal constant SEL_A = 0x11111111;

    /// @dev The registry's cap on an `exportSelectors()` return, in bytes.
    uint256 internal constant MAX_EXPORT_SIZE = 8192;
    bytes32 internal constant SEL_A_WORD = bytes32(SEL_A);

    function setUp() public {
        registry = new LatticeRegistry(owner);
    }

    function _register(address facet) internal {
        vm.prank(owner);
        registry.register(NAME, V1, facet);
    }

    function _expectNotERC8153(address facet) internal {
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__NotERC8153.selector, facet));
        _register(facet);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                 REGISTRATION — return-data shape and size
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The canonical encoding registers, and the pin is the hash of the DECODED blob.
    function test_CanonicalRawExporterPinsDecodedBlob() public {
        address facet = RawCode.exporter(abi.encodePacked(SEL_A));
        _register(facet);
        assertEq(registry.get(NAME, V1).selectorsHash, keccak256(abi.encodePacked(SEL_A)), "pin = decoded blob");
        assertEq(registry.getSelectors(NAME, V1)[0], SEL_A, "live read");
    }

    /// @notice A 32-byte return is shorter than any ABI `bytes` encoding: refused with the documented error.
    function test_RegisterRevertsNotERC8153OnShortReturn() public {
        _expectNotERC8153(RawCode.deploy(abi.encode(uint256(0x20))));
    }

    /// @notice A bare 4-byte return (packed, not ABI-wrapped) is refused with the documented error.
    function test_RegisterRevertsNotERC8153OnUnwrappedReturn() public {
        _expectNotERC8153(RawCode.deploy(abi.encodePacked(SEL_A)));
    }

    /// @notice R-1 (fixed): a return of 64 bytes or more whose offset points past the end is refused with the
    ///         documented error (it used to revert with empty data from inside `abi.decode`).
    function test_RegisterRevertsNotERC8153OnOffsetPastEnd() public {
        _expectNotERC8153(RawCode.deploy(abi.encode(uint256(0x1000), uint256(4), SEL_A_WORD)));
    }

    /// @notice R-1 (fixed): the same for an offset of `2**256 - 1`.
    function test_RegisterRevertsNotERC8153OnHugeOffset() public {
        _expectNotERC8153(RawCode.deploy(abi.encode(type(uint256).max, uint256(4), SEL_A_WORD)));
    }

    /// @notice R-1 (fixed): an offset that leaves no room for the length word (offset + 32 > size).
    function test_RegisterRevertsNotERC8153OnOffsetWithoutLengthWord() public {
        _expectNotERC8153(RawCode.deploy(abi.encode(uint256(0x41), uint256(4), SEL_A_WORD)));
    }

    /// @notice R-1 (fixed): a declared length larger than the data that follows.
    function test_RegisterRevertsNotERC8153OnLengthPastEnd() public {
        _expectNotERC8153(RawCode.deploy(abi.encode(uint256(0x20), uint256(0x100), SEL_A_WORD)));
    }

    /// @notice R-1 (fixed): truncated data (8 bytes declared, 4 present, no padding).
    function test_RegisterRevertsNotERC8153OnTruncatedData() public {
        _expectNotERC8153(RawCode.deploy(abi.encodePacked(uint256(0x20), uint256(8), SEL_A)));
    }

    /// @notice R-1 (fixed): a declared length of `2**256 - 1` is refused with the documented error (it used to
    ///         overflow the decoder's allocation with `Panic(0x41)`).
    function test_RegisterRevertsNotERC8153OnHugeDeclaredLength() public {
        _expectNotERC8153(RawCode.deploy(abi.encode(uint256(0x20), type(uint256).max, SEL_A_WORD)));
    }

    /// @notice Unpadded data that exactly fills the return is accepted, as `abi.decode` accepts it.
    function test_UnpaddedDataEndingAtTheReturnEndRegisters() public {
        _register(RawCode.deploy(abi.encodePacked(uint256(0x20), uint256(4), SEL_A)));
        assertEq(registry.get(NAME, V1).selectorsHash, keccak256(abi.encodePacked(SEL_A)), "pin = decoded blob");
    }

    /// @notice A non-canonical encoding (offset 0x40, one padding word) decodes to the same blob, so it pins the
    ///         SAME selectorsHash as the canonical exporter: the pin covers the decoded selectors, not the raw
    ///         return data, and two facets with different codehashes can share a selectorsHash.
    function test_NonCanonicalOffsetPinsSameHashAsCanonical() public {
        address canonical = RawCode.exporter(abi.encodePacked(SEL_A));
        address shifted = RawCode.deploy(abi.encode(uint256(0x40), uint256(0), uint256(4), SEL_A_WORD));
        vm.startPrank(owner);
        registry.register(NAME, V1, canonical);
        registry.register(NAME, V1 + 1, shifted);
        vm.stopPrank();
        assertEq(registry.get(NAME, V1).selectorsHash, registry.get(NAME, V1 + 1).selectorsHash, "same pin");
        assertTrue(registry.get(NAME, V1).codehash != registry.get(NAME, V1 + 1).codehash, "different code");
    }

    /// @notice Bytes after a valid encoding are ignored: the facet registers and the pin is the decoded blob.
    function test_TrailingBytesAfterValidEncodingAreIgnored() public {
        address facet = RawCode.deploy(abi.encodePacked(abi.encode(abi.encodePacked(SEL_A)), hex"deadbeef"));
        _register(facet);
        assertEq(registry.get(NAME, V1).selectorsHash, keccak256(abi.encodePacked(SEL_A)), "trailing bytes ignored");
    }

    /// @notice Non-zero padding after the last selector is ignored by the decoder.
    function test_DirtyPaddingIsIgnored() public {
        address facet = RawCode.deploy(abi.encode(uint256(0x20), uint256(4), bytes32(hex"11111111ffff")));
        _register(facet);
        assertEq(registry.getSelectors(NAME, V1)[0], SEL_A, "padding ignored");
    }

    /// @notice R-2 (fixed): an exporter that loops forever burns only the 100,000 gas the registry forwards,
    ///         however much the caller has, and registration fails with the documented error.
    function test_LoopingExporterBurnsAtMostTheExportGasThenRevertsNotERC8153() public {
        address facet = address(new CoreLoopExporter());
        bytes memory expected = abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__NotERC8153.selector, facet);
        uint256 before = gasleft();
        vm.prank(owner);
        try registry.register{gas: 10_000_000}(NAME, V1, facet) {
            revert("looping exporter registered");
        } catch (bytes memory err) {
            assertEq(err, expected, "documented error");
        }
        assertLt(before - gasleft(), 200_000, "the exporter call is capped at 100,000 gas");
    }

    /// @notice R-2 (fixed): a valid one-selector encoding followed by ~1 MB of zeros is refused at registration,
    ///         and refusing it is cheap: the registry never copies a return over its size cap.
    function test_ReturnBombIsRefusedAtRegistration() public {
        address bomb = address(new CoreReturnBombExporter(1_000_000));
        uint256 before = gasleft();
        _expectNotERC8153(bomb);
        assertLt(before - gasleft(), 300_000, "the bomb is never copied");
    }

    /// @notice R-2 boundary: a return of exactly the cap (a valid encoding padded with trailing bytes) registers;
    ///         one byte more is refused.
    function test_ReturnSizeCapBoundary() public {
        bytes memory head = abi.encode(abi.encodePacked(SEL_A));
        address atCap = RawCode.deploy(abi.encodePacked(head, new bytes(MAX_EXPORT_SIZE - head.length)));
        address overCap = RawCode.deploy(abi.encodePacked(head, new bytes(MAX_EXPORT_SIZE + 1 - head.length)));
        _register(atCap);
        assertEq(registry.getSelectors(NAME, V1)[0], SEL_A, "at the cap registers and reads");

        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__NotERC8153.selector, overCap));
        vm.prank(owner);
        registry.register(NAME, V1 + 1, overCap);
    }

    /// @notice The registry scans the whole blob: a duplicate in last position of a 128-selector blob is caught.
    function test_DuplicateAtEndOfLongBlobIsRejected() public {
        bytes memory blob = RawCode.selectorBlob(keccak256("long"), 128);
        bytes memory withDup = abi.encodePacked(blob, bytes4(RawCode.unpack(blob)[0]));
        _expectNotERC8153(RawCode.exporter(withDup));
    }

    /// @notice The self-selector `exportSelectors()` in last position of a 128-selector blob is caught.
    function test_SelfSelectorAtEndOfLongBlobIsRejected() public {
        bytes memory blob = abi.encodePacked(RawCode.selectorBlob(keccak256("long"), 128), bytes4(0x0ef22643));
        _expectNotERC8153(RawCode.exporter(blob));
    }

    /// @notice The zero selector is legal: {Receive} exports `0x00000000` so a diamond can route bare ETH sends.
    function test_ZeroSelectorIsRegistrable() public {
        _register(RawCode.exporter(abi.encodePacked(bytes4(0))));
        assertEq(registry.getSelectors(NAME, V1)[0], bytes4(0), "zero selector pinned");
    }

    /// @notice An exporter that calls `attest` on the registry from inside the registry's staticcall: the
    ///         first write fails in the static context, so registration is refused. Once anyone has attested
    ///         that codehash, the inner `attest` is a read-only no-op and the SAME facet registers: the
    ///         exporter's answer depends on registry state, which the selector pin then freezes.
    function test_ReentrantAttestInsideStaticcallDependsOnRegistryState() public {
        CoreReentrantAttestExporter facet = new CoreReentrantAttestExporter(registry);
        _expectNotERC8153(address(facet));

        registry.attest(address(facet));
        _register(address(facet));
        assertEq(registry.getSelectors(NAME, V1)[0], bytes4(0x13131313), "registers once the write is a no-op");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                 LIVE READS — mutable exports and code drift
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Selector drift is evaluated per read: flipping the export breaks `getCut`, flipping it back
    ///         restores it. The record never changes (I1); only the live answer does.
    function test_SelectorDriftIsTransient() public {
        CoreFlippingExporter facet = new CoreFlippingExporter();
        _register(address(facet));
        ILatticeRegistry.Record memory pinned = registry.get(NAME, V1);

        facet.flip();
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__SelectorDrift.selector, facet));
        registry.getCut(NAME, V1);

        facet.flip();
        assertEq(registry.getCut(NAME, V1).functionSelectors[0], SEL_A, "drift cleared");
        assertEq(keccak256(abi.encode(registry.get(NAME, V1))), keccak256(abi.encode(pinned)), "record unchanged");
    }

    /// @notice A live answer switched to a SHORT return (no decode) is caught by the selector pin.
    function test_LiveShortReturnIsSelectorDrift() public {
        CoreSwitchableRawExporter facet = new CoreSwitchableRawExporter();
        facet.set(abi.encode(abi.encodePacked(SEL_A)));
        _register(address(facet));

        facet.set(abi.encode(uint256(0x20)));
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__SelectorDrift.selector, facet));
        registry.getCut(NAME, V1);
    }

    /// @notice R-1 (fixed, live path): a live answer switched to a malformed encoding of 64 bytes or more is
    ///         reported as {LatticeRegistry__SelectorDrift} (it used to revert with empty data).
    function test_LiveMalformedReturnIsSelectorDrift() public {
        CoreSwitchableRawExporter facet = new CoreSwitchableRawExporter();
        facet.set(abi.encode(abi.encodePacked(SEL_A)));
        _register(address(facet));

        facet.set(abi.encode(uint256(0x1000), uint256(4), SEL_A_WORD));
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__SelectorDrift.selector, facet));
        registry.getCut(NAME, V1);
    }

    /// @notice R-2 (fixed, live path): a registered exporter that later answers with more than the cap is
    ///         drift, and the read never copies the oversized return.
    function test_LiveOversizedReturnIsSelectorDrift() public {
        CoreSwitchableRawExporter facet = new CoreSwitchableRawExporter();
        bytes memory head = abi.encode(abi.encodePacked(SEL_A));
        facet.set(head);
        _register(address(facet));

        facet.set(abi.encodePacked(head, new bytes(MAX_EXPORT_SIZE + 1 - head.length)));
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__SelectorDrift.selector, facet));
        registry.getCut(NAME, V1);
    }

    /// @notice Code removed from a registered address (the end state of a metamorphic swap) is code drift.
    function test_EmptiedCodeIsCodeDrift() public {
        address facet = RawCode.exporter(abi.encodePacked(SEL_A));
        _register(facet);
        vm.etch(facet, "");
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__CodeDrift.selector, facet));
        registry.getCut(NAME, V1);
    }

    /// @notice Code swapped for code that exports the SAME blob still trips the code pin first.
    function test_SwappedCodeWithSameExportIsCodeDrift() public {
        address facet = RawCode.exporter(abi.encodePacked(SEL_A));
        _register(facet);
        address twin = RawCode.deploy(abi.encodePacked(abi.encode(abi.encodePacked(SEL_A)), hex"00"));
        vm.etch(facet, twin.code);
        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__CodeDrift.selector, facet));
        registry.getCut(NAME, V1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                 TIER A — code identity is not export identity
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice R-3 (documented in the {ILatticeRegistry} Tier A NatSpec): two same-codehash instances in different
    ///         states export different selectors, yet `resolve` returns whichever was attested first. `resolve` is
    ///         a code identity lookup; it says nothing about selectors or about direct (non-delegatecall)
    ///         behaviour.
    function test_ResolveReturnsFirstAttesterWhileExportsDiffer() public {
        CoreFlippingExporter first = new CoreFlippingExporter();
        CoreFlippingExporter second = new CoreFlippingExporter();
        second.flip();
        assertEq(address(first).codehash, address(second).codehash, "same code");
        assertTrue(keccak256(first.exportSelectors()) != keccak256(second.exportSelectors()), "exports differ");

        registry.attest(address(first));
        registry.attest(address(second));
        assertEq(registry.resolve(address(second).codehash), address(first), "first attester wins");
    }

    /// @notice `register`'s auto-attest never overwrites Tier A: a curated record can point at a different
    ///         address than `resolve` returns for the same codehash.
    function test_RegisterAutoAttestNeverOverwritesResolver() public {
        CoreFlippingExporter early = new CoreFlippingExporter();
        CoreFlippingExporter curated = new CoreFlippingExporter();
        early.flip();
        registry.attest(address(early));

        _register(address(curated));
        assertEq(registry.get(NAME, V1).facet, address(curated), "record keeps the curated address");
        assertEq(registry.resolve(address(curated).codehash), address(early), "resolver keeps the first attester");
    }
}
